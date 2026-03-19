#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -o errexit
set -o nounset
set -o pipefail
set +o posix
shopt -s nullglob

WORK_DIR="$(dirname "$(readlink -f "$0")")"
TSC_TOOLS_DIR="/home/tsc/tsc_tools"
MICROMAMBA_DIR="${TSC_TOOLS_DIR}/micromamba"
OUTPUT_DIR="${WORK_DIR}/output"
export MAMBA_ROOT_PREFIX="${MICROMAMBA_DIR}"

source "${WORK_DIR}/func"

pack_installer() {
    LOGINFO "${FUNCNAME[0]}"
    
    # 清理缓存
    find "${MICROMAMBA_DIR}" -type d -name "__pycache__" -exec rm -rf {} +
    rm -rf "${MICROMAMBA_DIR}"/pkgs
    
    # 创建详细的构建信息文件
    cat <<EOF >"${WORK_DIR}/.profile"
#!/usr/bin/env bash
# Build Configuration
build_arch=${build_arch}
build_os_distribution_file_variety=${build_os_distribution_file_variety}
build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
build_timestamp=${D14}
build_version=${version}

EOF
    
    # 打包 micromamba
    cd "${TSC_TOOLS_DIR}" || exit 99
    tar czf micromamba.tar.gz micromamba
    
    # 准备安装包目录
    mkdir -p "${OUTPUT_NAME}"
    \cp -r micromamba.tar.gz \
        "${WORK_DIR}"/release-note.md \
        "${WORK_DIR}"/readme.md \
        "${WORK_DIR}"/func \
        "${WORK_DIR}"/tsc_python_profile \
        "${WORK_DIR}"/install.sh \
        "${WORK_DIR}"/.profile \
        "${WORK_DIR}"/ansible \
        "${WORK_DIR}"/modules \
        "${OUTPUT_NAME}"/
    
    # 复制依赖清单文件（如果存在）
    if [[ -f "${WORK_DIR}"/conda-packages.json ]]; then
        mkdir -p "${OUTPUT_NAME}"/manifests
        \cp "${WORK_DIR}"/conda-packages.json "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        \cp "${WORK_DIR}"/conda-packages.txt "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        \cp "${WORK_DIR}"/pip-packages.json "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        \cp "${WORK_DIR}"/pip-freeze.txt "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        \cp "${WORK_DIR}"/environment-lock.yml "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        \cp "${WORK_DIR}"/build-info.txt "${OUTPUT_NAME}"/manifests/ 2>/dev/null || true
        LOGINFO "Dependency manifests copied to ${OUTPUT_NAME}/manifests/"
    fi
    
    # 创建 makeself 自解压安装包
    "${WORK_DIR}"/makeself.sh --needroot --tar-quietly \
        --help-header README.md \
        "${OUTPUT_NAME}" "${OUTPUT_FILE}" \
        "TSC PYTHON ${version}" \
        ./install.sh
    
    chmod +x "${OUTPUT_FILE}"
    
    # 生成 checksum 和元数据文件
    cd "${OUTPUT_DIR}" || exit 99
    OUTPUT_BASENAME=$(basename "${OUTPUT_FILE}")
    
    # SHA256 checksum
    sha256sum "${OUTPUT_BASENAME}" > "${OUTPUT_BASENAME}.sha256"
    LOGINFO "Generated checksum: ${OUTPUT_BASENAME}.sha256"
    
    # 创建元数据 JSON 文件
    cat <<EOF >"${OUTPUT_BASENAME}.json"
{
  "name": "tsc_python",
  "version": "${version}",
  "filename": "${OUTPUT_BASENAME}",
  "build": {
    "date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "timestamp": "${D14}",
    "architecture": "${build_arch}",
    "os_variant": "${build_os_distribution_file_variety}",
    "builder": "$(whoami)@$(hostname)"
  },
  "checksums": {
    "sha256": "$(sha256sum "${OUTPUT_BASENAME}" | awk '{print $1}')"
  },
  "size_bytes": $(stat -c%s "${OUTPUT_BASENAME}" 2>/dev/null || stat -f%z "${OUTPUT_BASENAME}"),
  "python_version": "3.11.15",
  "micromamba_version": "2.5.0"
}
EOF
    LOGINFO "Generated metadata: ${OUTPUT_BASENAME}.json"
    
    LOGSUCCESS "Output file: ${OUTPUT_FILE}"
    LOGSUCCESS "Checksum: ${OUTPUT_FILE}.sha256"
    LOGSUCCESS "Metadata: ${OUTPUT_FILE}.json"
    LOGSUCCESS "${FUNCNAME[0]}"
}

D14="$(date +%Y%m%d%H%M%S)"
ARCH="$(arch)"

version="$(grep -oP "^\s*(#+)?\s*Version=\s*?\K\S+$" "${WORK_DIR}"/release-note.md | head -n1)"

system_info="$(detect_system_info)"
build_arch="$(echo "${system_info}" | jq -r .machine_architecture)"
build_os_distribution_file_variety="$(echo "${system_info}" | jq -r .os_distribution_file_variety)"

OUTPUT_NAME="tsc_python-${version}-${build_os_distribution_file_variety}-${ARCH}-${D14}"
OUTPUT_FILE="${OUTPUT_DIR}"/"${OUTPUT_NAME}".sh
# OUTPUT_FILE="${OUTPUT_DIR}"/"${OUTPUT_NAME}".tar.gz
mkdir -p "${OUTPUT_DIR}"

pack_installer
