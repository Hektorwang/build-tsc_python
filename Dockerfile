# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 唯一构建容器: CentOS 7.9 (glibc 2.17 基线), 产物与发行版无关
# REPO_LOCAL 必须经 --build-arg 或 build.conf 的 repo_local 键提供 (EL7 yum 源, 见 README)
FROM centos:7.9.2009 AS builder

ARG MICROMAMBA_DIR=/home/tsc/tsc_python
ARG ENV_NAME=tsc_python
ARG REPO_LOCAL=
ARG MAMBA_ROOT_PREFIX=/home/tsc/tsc_python

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

# jq 使用 build.sh 按需下载并缓存的静态二进制 (files/tmp/), 不依赖 EPEL
# 注意: 两个架构的 jq 文件都必须存在 (build.sh 的 ensure_jq 会同时下载 x86_64 与 aarch64),
# 请始终通过 build.sh 触发构建; 直接 `docker build` 而 files/tmp 未备齐时会因 COPY 源缺失而失败。
COPY ./files/tmp/jq-x86_64 ./files/tmp/jq-aarch64 /tmp/
RUN case $(arch) in \
        x86_64)  install -m 0755 /tmp/jq-x86_64  /usr/local/bin/jq ;; \
        aarch64) install -m 0755 /tmp/jq-aarch64 /usr/local/bin/jq ;; \
    esac && rm -f /tmp/jq-* && jq --version

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
RUN export MAMBA_ROOT_PREFIX && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba activate "${ENV_NAME}" && \
    [[ $(arch) == "aarch64" ]] && export CFLAGS="-D__ARM_ARCH=8" || true && \
    grep -vE '^(cffi|cryptography|packaging|pycparser|typing-extensions)==' /tmp/requirements.txt > /tmp/requirements.pip.txt && \
    uv pip install -r /tmp/requirements.pip.txt

# 工作目录只放打包必需的源文件: files/tmp/ 下的 micromamba/jq 缓存与构建期配置
# (condarc/pip.conf/environment.yml) 已由上方专用 COPY 直接进 /tmp, 不在此重复,
# 避免把二进制缓存带进工作目录层
# 注意: files/ 下新增随包文件时同步补充此列表 (漏掉不报错, 只会静默不随包)
# 注意: COPY 目录源时内容会落入目标目录 (COPY dir dest → dest/<dir 的内容>),
# 因此 ansible/ 与 modules/ 必须各自带目标路径, 不能与其他源共用一行
COPY ./files/centos7.repo ./files/environment.yml ./files/func ./files/pack.sh \
    ./files/patch_ansible.py ./files/profile ./files/readme.md ./files/requirements.in \
    ./files/requirements.txt ./files/smoke_test.sh ./files/tsc_profile \
    /home/tsc/build_micromamba/
COPY ./files/ansible /home/tsc/build_micromamba/ansible
COPY ./files/modules /home/tsc/build_micromamba/modules

# 仓库根目录的文档也进入容器工作目录, 由 build.sh 打入安装包
COPY ./release-note.md ./THIRD_PARTY_NOTICES.md ./THIRD_PARTY_NOTICES.zh_CN.md /home/tsc/build_micromamba/

RUN sh /home/tsc/build_micromamba/pack.sh


# exporter 阶段仅供 buildx --target exporter 使用
# 本地构建使用 build.sh，直接从 builder 容器中 docker cp 取出产物
FROM scratch AS exporter
COPY --from=builder /home/tsc/build_micromamba/output/* /export/