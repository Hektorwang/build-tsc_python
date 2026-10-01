#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 构建入口脚本：在本机架构的容器中构建并打包
# 产物与发行版无关: 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中创建,
# 兼容所有 glibc >= 2.17 的 Linux 发行版 (CentOS/RHEL 7+, openEuler, HCE, Kylin V10, FitOS 等)
set -o errexit
set -o nounset
set -o pipefail
set +o posix
shopt -s nullglob

WORK_DIR="$(dirname "$(readlink -f "$0")")"
OUTPUT_DIR="${WORK_DIR}/output"
LOG_DIR="${WORK_DIR}/log"
TMP_DIR="${WORK_DIR}/files/tmp"
ARCH="$(arch)"
D14="$(date +%Y%m%d%H%M%S)"
DOCKERFILE="Dockerfile"

source "${WORK_DIR}/func"

trap gracefully_abort INT

# 默认参数
no_cache=""
micromamba_version=""
repo_local=""
python_version=""
pypi_index=""
conda_forge=""

_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build TSC Python distribution using local Docker containers (same architecture).

Options:
  -n, --no-cache              Disable Docker build cache
  -m, --micromamba-ver V      Micromamba version (overrides build.conf)
  -r, --repo-local URL        Internal yum repo URL (overrides build.conf)
  -p, --python-version V      Override Python version in environment.yml (overrides build.conf)
      --pypi-index URL        PyPI index URL (overrides build.conf)
      --conda-forge URL       conda-forge channel URL (overrides build.conf)
  -h, --help                  Show this help

Config file:
  build.conf (INI format, [build] section) is read when a parameter is not specified on the command line.
  Keys: micromamba_ver, repo_local, python_version, pypi_index, conda_forge

Note:
  This script builds for the CURRENT machine architecture: ${ARCH}
  To build for another architecture, run this script on that machine.
  The build container is CentOS 7.9 (glibc 2.17 baseline), artifacts are distro-independent.
  makeself packaging is performed inside the container by files/build.sh.
EOF
    exit 0
}

_parsed=$(getopt \
    --options hnm:r:p: \
    --longoptions help,no-cache,micromamba-ver:,repo-local:,python-version:,pypi-index:,conda-forge: \
    --name "$0" \
    -- "$@") || { LOGERROR "Invalid arguments, try -h for help"; exit 1; }

eval set -- "${_parsed}"
while true; do
    case "$1" in
        -h|--help)            _usage ;;
        -n|--no-cache)        no_cache="--no-cache";     shift ;;
        -m|--micromamba-ver)  micromamba_version="$2";   shift 2 ;;
        -r|--repo-local)      repo_local="$2";           shift 2 ;;
        -p|--python-version)  python_version="$2";       shift 2 ;;
        --pypi-index)         pypi_index="$2";           shift 2 ;;
        --conda-forge)        conda_forge="$2";          shift 2 ;;
        --)                   shift; break ;;
        *)                    LOGERROR "Unknown argument: $1"; exit 1 ;;
    esac
done

# 读取配置文件，仅在参数未通过命令行指定时生效
build_conf="${WORK_DIR}/build.conf"
if [[ -f "${build_conf}" ]]; then
    [[ -z "${micromamba_version}" ]] && micromamba_version="$(get_ini_value "${build_conf}" build micromamba_ver 2>/dev/null || true)"
    [[ -z "${repo_local}" ]]         && repo_local="$(get_ini_value "${build_conf}" build repo_local 2>/dev/null || true)"
    [[ -z "${python_version}" ]]     && python_version="$(get_ini_value "${build_conf}" build python_version 2>/dev/null || true)"
    [[ -z "${pypi_index}" ]]         && pypi_index="$(get_ini_value "${build_conf}" build pypi_index 2>/dev/null || true)"
    [[ -z "${conda_forge}" ]]        && conda_forge="$(get_ini_value "${build_conf}" build conda_forge 2>/dev/null || true)"
else
    LOGWARNING "build.conf not found, using built-in defaults"
fi

# 最终兜底默认值
micromamba_version="${micromamba_version:-2.5.0}"
repo_local="${repo_local:-}"
pypi_index="${pypi_index:-https://mirrors.cernet.edu.cn/pypi/web/simple}"
conda_forge="${conda_forge:-https://mirrors.cernet.edu.cn/anaconda/cloud/conda-forge}"

if [[ -z "${repo_local}" ]]; then
    LOGERROR "yum 源地址未配置: 请通过 --repo-local 参数或 build.conf 的 repo_local 键提供"
    exit 1
fi

LOGINFO "Config | micromamba: ${micromamba_version} | repo_local: ${repo_local} | python_version: ${python_version:-<from environment.yml>}"
LOGINFO "Config | pypi_index: ${pypi_index} | conda_forge: ${conda_forge}"

# 检查 Docker 是否可用
if ! command -v docker &>/dev/null; then
    LOGERROR "Docker is not installed or not in PATH"
    exit 1
fi
if ! docker info &>/dev/null; then
    LOGERROR "Docker daemon is not running or current user has no permission"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${TMP_DIR}"

# ─────────────────────────────────────────────
# 生成构建期配置: environment.yml / condarc / pip.conf
# 每次从原始文件与参数重新生成, 支持源地址自定义
# ─────────────────────────────────────────────
env_yml_src="${WORK_DIR}/files/environment.yml"
env_yml_tmp="${TMP_DIR}/environment.yml"
condarc_tmp="${TMP_DIR}/condarc"
pip_conf_tmp="${TMP_DIR}/pip.conf"

trap 'rm -f "${env_yml_tmp}" "${condarc_tmp}" "${pip_conf_tmp}"' EXIT

if [[ -n "${python_version}" ]]; then
    sed "s/- python=.*/- python=${python_version}/" "${env_yml_src}" > "${env_yml_tmp}"
    LOGINFO "Python version override: ${python_version}"
else
    cp "${env_yml_src}" "${env_yml_tmp}"
fi

# condarc: 仅使用 conda-forge 社区通道 (default_channels 置空, 不含 anaconda defaults 商业源)
cat > "${condarc_tmp}" <<EOF
# generated by build.sh -- do not edit
channels:
  - conda-forge
show_channel_urls: true
default_channels: []
custom_channels:
  conda-forge: ${conda_forge}
EOF

cat > "${pip_conf_tmp}" <<EOF
# generated by build.sh -- do not edit
[global]
timeout=30
index-url = ${pypi_index}
EOF

LOGINFO "Generated: ${condarc_tmp} / ${pip_conf_tmp}"

# ─────────────────────────────────────────────
# 预下载 micromamba 到 files/tmp/micromamba
# 若已存在且版本匹配则跳过，否则重新下载
# ─────────────────────────────────────────────
micromamba_cache="${TMP_DIR}/micromamba"
micromamba_cache_ver="${TMP_DIR}/micromamba.version"

case "${ARCH}" in
    x86_64)  micromamba_url_tag="linux-64" ;;
    aarch64) micromamba_url_tag="linux-aarch64" ;;
    *)
        LOGERROR "Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

_need_download=true
if [[ -f "${micromamba_cache}" && -f "${micromamba_cache_ver}" ]]; then
    cached_ver="$(cat "${micromamba_cache_ver}")"
    if [[ "${cached_ver}" == "${micromamba_version}-${ARCH}" ]]; then
        LOGINFO "micromamba cache hit: ${micromamba_version} (${ARCH}), skipping download"
        _need_download=false
    else
        LOGINFO "micromamba version changed (${cached_ver} -> ${micromamba_version}-${ARCH}), re-downloading"
    fi
fi

if [[ "${_need_download}" == true ]]; then
    LOGINFO "Downloading micromamba ${micromamba_version} for ${ARCH}..."
    curl --fail --insecure --location \
        --output "${micromamba_cache}" \
        "https://micro.mamba.pm/api/micromamba/${micromamba_url_tag}/${micromamba_version}"
    echo "${micromamba_version}-${ARCH}" > "${micromamba_cache_ver}"
    LOGSUCCESS "micromamba downloaded: ${micromamba_cache}"
fi

# ─────────────────────────────────────────────
# 第三方组件: 缓存优先, 缺失时按需下载 (与 micromamba 缓存同一模式)
# ─────────────────────────────────────────────
makeself_version="2.5.0"
jq_version="1.8.1"
jq_sha256_x86_64="020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d"
jq_sha256_aarch64="6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4"

ensure_jq() {
    local arch url file sum expected
    for arch in x86_64 aarch64; do
        file="${TMP_DIR}/jq-${arch}"
        case "${arch}" in
            x86_64)  url="https://github.com/jqlang/jq/releases/download/jq-${jq_version}/jq-linux-amd64" ;;
            aarch64) url="https://github.com/jqlang/jq/releases/download/jq-${jq_version}/jq-linux-arm64" ;;
        esac
        if [[ -f "${file}" ]]; then
            sum="$(sha256sum "${file}" | awk '{print $1}')"
            expected="${jq_sha256_x86_64}"
            [[ "${arch}" == "aarch64" ]] && expected="${jq_sha256_aarch64}"
            if [[ "${sum}" == "${expected}" ]]; then
                LOGINFO "jq cache hit: ${file}"
                continue
            fi
            LOGINFO "jq cache checksum mismatch (${arch}), re-downloading"
        fi
        LOGINFO "Downloading jq ${jq_version} for ${arch}..."
        curl --fail --insecure --location --output "${file}" "${url}"
        chmod +x "${file}"
    done
    LOGSUCCESS "jq ready: ${TMP_DIR}/jq-x86_64 / ${TMP_DIR}/jq-aarch64"
}

ensure_makeself() {
    if [[ -f "${WORK_DIR}/files/makeself.sh" && -f "${WORK_DIR}/files/makeself-header.sh" ]]; then
        LOGINFO "makeself cache hit: files/makeself.sh"
        return 0
    fi
    local run_file="${TMP_DIR}/makeself-${makeself_version}.run"
    local extract_dir="${TMP_DIR}/makeself-extract"
    LOGINFO "Downloading makeself ${makeself_version}..."
    curl --fail --insecure --location --output "${run_file}" \
        "https://github.com/megastep/makeself/releases/download/release-${makeself_version}/makeself-${makeself_version}.run"
    rm -rf "${extract_dir}" && mkdir -p "${extract_dir}"
    sh "${run_file}" --target "${extract_dir}" --noexec
    \cp -f "${extract_dir}/makeself.sh" "${extract_dir}/makeself-header.sh" "${WORK_DIR}/files/"
    chmod +x "${WORK_DIR}/files/makeself.sh" "${WORK_DIR}/files/makeself-header.sh"
    rm -rf "${extract_dir}"
    LOGSUCCESS "makeself ready: files/makeself.sh"
}

ensure_jq
ensure_makeself

# ─────────────────────────────────────────────
# 构建 (单架构单包, 容器为 CentOS 7.9 基线)
# ─────────────────────────────────────────────
build_target() {
    local output_dir image_tag
    log_file="${LOG_DIR}/build-${ARCH}-${D14}.log"
    output_dir="${OUTPUT_DIR}/${ARCH}"
    image_tag="tsc-python-builder-${ARCH}"

    mkdir -p "${output_dir}"

    LOGINFO "Building: ${ARCH} (container: CentOS 7.9 / glibc 2.17 baseline)"
    LOGINFO "Dockerfile: ${DOCKERFILE} | Output: ${output_dir}"
    LOGINFO "Log: ${log_file}"

    local build_ok=0
    docker build \
        ${no_cache} \
        --pull=false \
        --progress plain \
        --target builder \
        --tag "${image_tag}" \
        --build-arg REPO_LOCAL="${repo_local}" \
        --file "${DOCKERFILE}" \
        "${WORK_DIR}" \
        2>&1 | tee "${log_file}" || build_ok=1

    if [[ ${build_ok} -ne 0 ]]; then
        LOGERROR "Docker build failed, see log: ${log_file}"
        return 1
    fi
    LOGSUCCESS "Docker build succeeded"

    # 从容器取出产物（makeself 打包已在容器内 files/build.sh 完成）
    LOGINFO "Extracting build artifacts..."
    local container_id
    container_id=$(docker create "${image_tag}")

    if docker cp "${container_id}:/home/tsc/build_micromamba/output/." "${output_dir}/"; then
        LOGSUCCESS "Artifacts extracted to: ${output_dir}"
    else
        LOGERROR "Failed to extract artifacts from container"
        docker rm "${container_id}" &>/dev/null || true
        return 1
    fi

    docker rm "${container_id}" &>/dev/null || true

    LOGINFO "Build artifacts:"
    ls -lh "${output_dir}/"

    LOGSUCCESS "Build completed: ${ARCH}"
}

# ─────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────
LOGINFO "TSC Python Local Build | Arch: ${ARCH} | Micromamba: ${micromamba_version}"
[[ -n "${python_version}" ]] && LOGINFO "Python version override: ${python_version}"

build_target || { LOGERROR "Build failed"; exit 1; }

LOGSUCCESS "Build completed successfully"
LOGINFO "Output directory: ${OUTPUT_DIR}/${ARCH}"
ls -lh "${OUTPUT_DIR}/${ARCH}/" 2>/dev/null || true
