FROM centos:7.9.2009 AS builder
# FROM devtools/redhat:7.9-x86_64-20250713 AS builder

ARG MICROMAMBA_VERSION=2.3.0
ARG MICROMAMBA_DIR=/home/tsc/tsc_tools/micromamba
ARG ENV_NAME=tsc_python
ARG REPO_LOCAL=http://192.168.19.22
ARG MAMBA_ROOT_PREFIX=/home/tsc/tsc_tools/micromamba

WORKDIR /home/tsc/build_micromamba

COPY ./files/centos7.repo /etc/yum.repos.d/

RUN case $(arch) in \
        x86_64) baseurl="${REPO_LOCAL}"/centos/7.9.2009/os/x86_64/ ;; \
        aarch64) baseurl="${REPO_LOCAL}"/centos-altarch/7.9.2009/os/aarch64/ ;; \
    esac && \
    sed -i "s#base_local_url#${baseurl}#g" /etc/yum.repos.d/centos7.repo && \
    sed -i "s#REPO_LOCAL#${REPO_LOCAL}#g" /etc/yum.repos.d/centos7.repo && \
    yum install -y --disablerepo='*' --enablerepo='base-local,epel-local' \
        curl \
        tar \
        findutils \
        coreutils \
        jq \
        tzdata \
        "@Development Tools" \
    && yum clean all && rm -rf /var/cache/yum \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone

RUN case $(arch) in \
        x86_64) \
            URL_TAG=linux-64 \
            ;; \
        aarch64) \
            URL_TAG=linux-aarch64 \
            ;;\
    esac \
    && cd /tmp/ \
    && curl --fail --insecure --location --remote-header-name --remote-name \
        "https://micro.mamba.pm/api/micromamba/${URL_TAG}/${MICROMAMBA_VERSION}" \
    && rm -rf "${MICROMAMBA_DIR}" && mkdir -p "${MICROMAMBA_DIR}" \
    && find /tmp/ -type f -name "micromamba-*" -exec tar -xvf {} -C "${MICROMAMBA_DIR}" \;

COPY ./files/.condarc ./files/pip.conf ./files/environment.yml /tmp/

RUN \cp /tmp/.condarc  /root/.condarc && \
    mkdir -p /root/.config/pip && \cp /tmp/pip.conf /root/.config/pip/pip.conf && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba env create -f "/tmp/environment.yml" --yes --no-pyc --use-uv --name "${ENV_NAME}"

COPY ./files/requirements.txt ./files/.cargo_config /tmp/
RUN rm -rf /root/.cargo && mkdir -p /root/.cargo && \cp /tmp/.cargo_config /root/.cargo/config && \
    eval "$("${MICROMAMBA_DIR}/bin/micromamba" shell hook --shell bash)" && \
    micromamba activate "${ENV_NAME}" && \
    [[ $(arch) == "aarch64" ]] && export CFLAGS="-D__ARM_ARCH=8" || true && \
    uv pip install -r /tmp/requirements.txt

COPY ./files/ /home/tsc/build_micromamba/

RUN sh -x /home/tsc/build_micromamba/build.sh


FROM scratch AS exporter
COPY --from=builder /home/tsc/build_micromamba/output/* /export/

# ARG CACHE_BUSTER_GET_MICROMAMBA
# RUN echo "Cache buster for get_micromamba: ${CACHE_BUSTER_GET_MICROMAMBA}"