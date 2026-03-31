# FROM openeuler/openeuler:24.03-lts-sp1 AS builder
FROM openeuler/openeuler:22.03-lts-sp3 AS builder

ARG MICROMAMBA_VERSION=2.5.0   # 仅用于元数据记录，下载由 build-local.sh 完成
ARG PYTHON_VERSION=unknown
ARG MICROMAMBA_DIR=/home/tsc/tsc_tools/micromamba
ARG ENV_NAME=tsc_python
ARG MAMBA_ROOT_PREFIX=/home/tsc/tsc_tools/micromamba

# 将构建参数导出为环境变量，供容器内 build.sh 使用
ENV MICROMAMBA_VERSION=${MICROMAMBA_VERSION} \
    PYTHON_VERSION=${PYTHON_VERSION}

WORKDIR /home/tsc/build_micromamba

RUN yum install --assumeyes \
        curl \
        tar \
        jq \
        findutils \
        coreutils \
        tzdata \
        "@Development Tools" && \
    yum clean all && rm -rf /var/cache/yum && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone

# micromamba 由 build-local.sh 预下载到 files/tmp/，此处直接 COPY 进容器
COPY ./files/tmp/micromamba /tmp/micromamba
RUN rm -rf "${MICROMAMBA_DIR}" && mkdir -p "${MICROMAMBA_DIR}" && \
    tar -xf /tmp/micromamba -C "${MICROMAMBA_DIR}"

# environment.yml 由 build-local.sh 生成到 files/tmp/（支持 --python-version 覆盖）
COPY ./files/.condarc ./files/pip.conf ./files/tmp/environment.yml /tmp/

RUN \cp /tmp/.condarc  /root/.condarc && \
    mkdir -p /root/.config/pip && \cp /tmp/pip.conf /root/.config/pip/pip.conf && \
    export MAMBA_ROOT_PREFIX && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba env create -f "/tmp/environment.yml" --yes --no-pyc --use-uv -c conda-forge --name "${ENV_NAME}"

COPY ./files/requirements.txt /tmp/
RUN export MAMBA_ROOT_PREFIX && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba activate "${ENV_NAME}" && \
    [[ $(arch) == "aarch64" ]] && export CFLAGS="-D__ARM_ARCH=8" || true && \
    uv pip install -r /tmp/requirements.txt

COPY ./files/ /home/tsc/build_micromamba/
RUN sh /home/tsc/build_micromamba/build.sh

# exporter 阶段仅供 buildx --target exporter 使用
# 本地构建使用 build-local.sh，直接从 builder 容器中 docker cp 取出产物
FROM scratch AS exporter
COPY --from=builder /home/tsc/build_micromamba/output/* /export/
