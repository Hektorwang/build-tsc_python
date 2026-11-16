# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 唯一构建容器: CentOS 7.9 (glibc 2.17 基线), 产物与发行版无关
# REPO_LOCAL 必须经 --build-arg 或 build.conf 的 repo_local 键提供 (EL7 yum 源, 见 README)
FROM centos:7.9.2009 AS builder

ARG MICROMAMBA_DIR=/home/tsc/tsc_python
ARG ENV_NAME=tsc_python
ARG REPO_LOCAL=
ARG MAMBA_ROOT_PREFIX=/home/tsc/tsc_python
# 本包架构 (决定 COPY 哪个 jq 静态二进制) 与 pip 层索引地址, 均由 build.sh 注入
ARG ARCH=
ARG PYPI_INDEX=

# 将构建参数导出为环境变量，供容器内 build.sh 使用
ENV MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX}

WORKDIR /home/tsc/build_micromamba

COPY ./files/centos7.repo /etc/yum.repos.d/

RUN case $(arch) in \
        x86_64) baseurl="${REPO_LOCAL}"/centos/7.9.2009/os/x86_64/ ;; \
        aarch64) baseurl="${REPO_LOCAL}"/centos-altarch/7.9.2009/os/aarch64/ ;; \
    esac && \
    sed -i "s#base_local_url#${baseurl}#g" /etc/yum.repos.d/centos7.repo && \
    yum install -y --disablerepo='*' --enablerepo='base-local' \
        curl \
        tar \
        findutils \
        coreutils \
        tzdata \
        "@Development Tools" \
    && yum clean all && rm -rf /var/cache/yum \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone

# jq 使用 build.sh 按需下载并缓存的静态二进制 (files/tmp/, 仅当前架构), 不依赖 EPEL
# COPY 源路径引用 ARG 需要 BuildKit (build.sh 的 docker build 即 BuildKit)。
# 请始终通过 build.sh 触发构建 (会传入 --build-arg ARCH); 直接 `docker build` 而
# files/tmp 未备齐时会因 COPY 源缺失而失败。
COPY ./files/tmp/jq-${ARCH} /tmp/jq-bin
RUN install -m 0755 /tmp/jq-bin /usr/local/bin/jq && rm -f /tmp/jq-bin && jq --version

# micromamba 由 build.sh 预下载到 files/tmp/，此处直接 COPY 进容器
COPY ./files/tmp/micromamba /tmp/micromamba
RUN rm -rf "${MICROMAMBA_DIR}" && mkdir -p "${MICROMAMBA_DIR}" && \
    tar -xf /tmp/micromamba -C "${MICROMAMBA_DIR}"

# condarc / pip.conf / environment.yml 均由 build.sh 生成到 files/tmp/ (源地址可配置)
COPY ./files/tmp/condarc ./files/tmp/pip.conf ./files/tmp/environment.yml /tmp/

RUN \cp /tmp/condarc /root/.condarc && \
    mkdir -p /root/.config/pip && \cp /tmp/pip.conf /root/.config/pip/pip.conf && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba env create -f "/tmp/environment.yml" --yes --no-pyc -c conda-forge --use-uv --name "${ENV_NAME}"

COPY ./files/requirements.txt /tmp/
# pip 层只装 conda 没有的包: 过滤掉 conda 已提供的全部条目 (原生库 cryptography/cffi/pycparser,
# 以及 conda 同样提供的纯 python 包 packaging/typing-extensions)。
# 不过滤的后果: 锁文件与 conda 解析漂移时, pip wheel 会覆盖 conda 构建版 (openssl ABI 风险);
# 过滤后 ansible-core/asyncssh 仍声明这些依赖, 但 pip 发现环境里已满足, 直接沿用 conda 版本。
# pack.sh 的 check_pip_conda_overlap 会在构建期兜底断言这条边界。
# 注意: && / || 左结合。原先写成 `... && [[ $(arch) == aarch64 ]] && export CFLAGS=... || true && ...`,
# 一旦 micromamba activate 失败, `|| true` 会把整条链救成真, uv pip install 继续在未激活的
# 环境 (EL7 上是系统 python 2.7) 里执行——装出的包根本不在 payload 中, 而构建仍标记成功。
# 因此: `|| true` 只兜住 arch 判断本身, activate 结果在下一条 RUN 语句内显式断言。
# uv 不读取 pip.conf (官方兼容性约定: 亦不读 PIP_INDEX_URL 等 pip 专属配置),
# pip 层源地址必须经 --index-url 显式传入 (build.sh 经 --build-arg PYPI_INDEX 注入),
# 空值在此显式断言拦下, 不让 uv 静默回落到默认 pypi.org。
RUN export MAMBA_ROOT_PREFIX && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba activate "${ENV_NAME}" && \
    { [[ $(arch) == "aarch64" ]] && export CFLAGS="-D__ARM_ARCH=8" || true; } && \
    test -n "${CONDA_PREFIX}" && \
    test "${CONDA_PREFIX}" = "${MICROMAMBA_DIR}/envs/${ENV_NAME}" && \
    grep -vE '^(cffi|cryptography|packaging|pycparser|typing-extensions)==' /tmp/requirements.txt > /tmp/requirements.pip.txt && \
    test -n "${PYPI_INDEX}" && \
    uv pip install --index-url "${PYPI_INDEX}" -r /tmp/requirements.pip.txt

# 工作目录只放打包必需的源文件: files/tmp/ 下的 micromamba/jq 缓存与构建期配置
# (condarc/pip.conf/environment.yml) 已由上方专用 COPY 直接进 /tmp, 不在此重复,
# 避免把二进制缓存带进工作目录层
# 注意: files/ 下新增随包文件时同步补充此列表 (漏掉不报错, 只会静默不随包)
# 注意: COPY 目录源时内容会落入目标目录 (COPY dir dest → dest/<dir 的内容>),
# 因此 ansible/ 与 modules/ 必须各自带目标路径, 不能与其他源共用一行
COPY ./files/centos7.repo ./files/environment.yml ./files/func ./files/pack.sh \
    ./files/patch_ansible.py ./files/tsc_python_profile ./files/README.md ./files/requirements.in \
    ./files/requirements.txt ./files/smoke_test.sh ./files/tsc_profile \
    /home/tsc/build_micromamba/
COPY ./files/ansible /home/tsc/build_micromamba/ansible
COPY ./files/modules /home/tsc/build_micromamba/modules

# 仓库根目录的文档也进入容器工作目录, 由 build.sh 打入安装包
COPY ./release-note.md ./THIRD_PARTY_NOTICES.md ./THIRD_PARTY_NOTICES.zh_CN.md /home/tsc/build_micromamba/

# pack.sh 是 bash 脚本 ([[ ]]/nullglob/局部关联数组), 此前以 sh 调用依赖 CentOS 的
# sh->bash; 显式 bash 调用, 基础镜像更换 (sh=dash) 时不再碎
RUN bash /home/tsc/build_micromamba/pack.sh


# exporter 阶段仅供 buildx --target exporter 使用
# 本地构建使用 build.sh，直接从 builder 容器中 docker cp 取出产物
FROM scratch AS exporter
COPY --from=builder /home/tsc/build_micromamba/output/* /export/
