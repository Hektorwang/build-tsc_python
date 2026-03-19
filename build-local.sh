#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# 本地构建脚本：在本机架构的容器中执行打包
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

source "${WORK_DIR}/func"

trap gracefully_abort INT

# 默认参数
target="all"
no_cache=""
micromamba_version="2.5.0"
repo_local="http://192.168.19.22"
python_version=""

_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build TSC Python distribution using local Docker containers (same architecture).

Options:
  -t, --target TARGET         Build target: euler, redhat, all (default: all)
  -n, --no-cache              Disable Docker build cache
  -m, --micromamba-ver V      Micromamba version (default: 2.5.0)
  -r, --repo-local URL        Internal yum repo URL for RedHat (default: http://192.168.19.22)
  -p, --python-version V      Override Python version in environment.yml (e.g. 3.11.15)
  -h, --help                  Show this help

Note:
  This script builds for the CURRENT machine architecture: ${ARCH}
  To build for another architecture, run this script on that machine.
  makeself packaging is performed inside the container by files/build.sh.
EOF
    exit 0
}

_parsed=$(getopt \
    --options ht:nm:r:p: \
    --longoptions help,target:,no-cache,micromamba-ver:,repo-local:,python-version: \
    --name "$0" \
    -- "$@") || { LOGERROR "Invalid arguments, try -h for help"; exit 1; }

eval set -- "${_parsed}"
while true; do
    case "$1" in
        -h|--help)            _usage ;;
        -t|--target)          target="$2";               shift 2 ;;
        -n|--no-cache)        no_cache="--no-cache";     shift ;;
        -m|--micromamba-ver)  micromamba_version="$2";   shift 2 ;;
        -r|--repo-local)      repo_local="$2";           shift 2 ;;
        -p|--python-version)  python_version="$2";       shift 2 ;;
        --)                   shift; break ;;
        *)                    LOGERROR "Unknown argument: $1"; exit 1 ;;
    esac
done

case "${target}" in
    euler|redhat|all) ;;
    *) LOGERROR "Invalid target: '${target}'. Must be euler, redhat, or all"; exit 1 ;;
esac

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
# 准备 files/tmp/environment.yml
# 每次从原始文件生成，支持 --python-version 覆盖
# ─────────────────────────────────────────────
env_yml_src="${WORK_DIR}/files/environment.yml"
env_yml_tmp="${TMP_DIR}/environment.yml"

trap 'rm -f "${env_yml_tmp}"' EXIT

if [[ -n "${python_version}" ]]; then
    sed "s/- python=.*/- python=${python_version}/" "${env_yml_src}" > "${env_yml_tmp}"
    LOGINFO "Python version override: ${python_version}"
else
    cp "${env_yml_src}" "${env_yml_tmp}"
fi

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
# 构建单个目标
# ─────────────────────────────────────────────
build_target() {
    local dist="$1"
    local dockerfile output_dir image_tag
    log_file=""

    case "${dist}" in
        euler)
            dockerfile="Euler.dockerfile"
            output_dir="${OUTPUT_DIR}/euler-${ARCH}"
            image_tag="tsc-python-builder-euler-${ARCH}"
            log_file="${LOG_DIR}/build-euler-${ARCH}-${D14}.log"
            ;;
        redhat)
            dockerfile="RedHat.dockerfile"
            output_dir="${OUTPUT_DIR}/redhat-${ARCH}"
            image_tag="tsc-python-builder-redhat-${ARCH}"
            log_file="${LOG_DIR}/build-redhat-${ARCH}-${D14}.log"
            ;;
        *)
            LOGERROR "Unknown target: ${dist}"
            return 1
            ;;
    esac

    mkdir -p "${output_dir}"

    LOGINFO "Building: ${dist} / ${ARCH}"
    LOGINFO "Dockerfile: ${dockerfile} | Output: ${output_dir}"
    LOGINFO "Log: ${log_file}"

    local build_ok=0
    docker build \
        ${no_cache} \
        --pull=false \
        --progress plain \
        --target builder \
        --tag "${image_tag}" \
        --build-arg MICROMAMBA_VERSION="${micromamba_version}" \
        --build-arg REPO_LOCAL="${repo_local}" \
        --file "${dockerfile}" \
        "${WORK_DIR}" \
        2>&1 | tee "${log_file}" || build_ok=1

    if [[ ${build_ok} -ne 0 ]]; then
        LOGERROR "Docker build failed: ${dist}, see log: ${log_file}"
        return 1
    fi
    LOGSUCCESS "Docker build succeeded: ${dist}"

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

    LOGSUCCESS "Build completed: ${dist} / ${ARCH}"
}

# ─────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────
LOGINFO "TSC Python Local Build | Target: ${target} | Arch: ${ARCH} | Micromamba: ${micromamba_version}"
[[ -n "${python_version}" ]] && LOGINFO "Python version override: ${python_version}"

build_failed=()

case "${target}" in
    euler)
        build_target euler  || build_failed+=("euler")
        ;;
    redhat)
        build_target redhat || build_failed+=("redhat")
        ;;
    all)
        build_target euler  || build_failed+=("euler")
        build_target redhat || build_failed+=("redhat")
        ;;
esac

if [[ ${#build_failed[@]} -gt 0 ]]; then
    LOGERROR "Failed builds: ${build_failed[*]}"
    exit 1
else
    LOGSUCCESS "All builds completed successfully"
    LOGINFO "Output directory: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}"/*/  2>/dev/null || true
fi
