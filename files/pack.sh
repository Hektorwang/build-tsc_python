#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 容器内打包脚本: makeself 自解压打包、checksum 与元数据生成
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

readonly GLIBC_BASELINE="2.17"

# glibc 符号门限: 包内所有 ELF 的最高 GLIBC_ 要求不得超过基线 (2.17 = CentOS 7)。
# 超标说明有产物在更新的容器中被源码编译, 将无法在 CentOS 7 上运行。
check_glibc_baseline() {
    local max_glibc
    if ! command -v objdump &>/dev/null; then
        LOGWARNING "check_glibc_baseline: 缺少 objdump, 跳过 ABI 门限检查"
        return 0
    fi
    max_glibc="$(find "${MICROMAMBA_DIR}" -type f \( -name '*.so*' -o -path '*/bin/*' \) -size +10k |
        while read -r f; do
            head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
            objdump -T "$f" 2>/dev/null
        done |
        grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -n1)" || true
    if [[ -z "${max_glibc}" ]]; then
        LOGWARNING "check_glibc_baseline: 未扫描到 ELF 符号, 跳过"
        return 0
    fi
    LOGINFO "check_glibc_baseline: 环境最高 glibc 符号要求 = ${max_glibc} (基线 ${GLIBC_BASELINE})"
    # version_ge max baseline: max >= baseline 时为真; 与基线相等属正常, 超过才拦截
    if version_ge "${max_glibc}" "${GLIBC_BASELINE}" && [[ "${max_glibc}" != "${GLIBC_BASELINE}" ]]; then
        LOGERROR "check_glibc_baseline: 门限超标 (需要 glibc ${max_glibc} > 基线 ${GLIBC_BASELINE}), 禁止出包"
        exit 1
    fi
    LOGSUCCESS "check_glibc_baseline"
}

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
build_date=${BUILD_DATE}
build_timestamp=${BUILD_TIMESTAMP}
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
        "${WORK_DIR}"/patch_ansible.py \
        "${WORK_DIR}"/smoke_test.sh \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.zh_CN.md \
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
    "build_date": "${BUILD_DATE}",
    "timestamp": ${BUILD_TIMESTAMP},
    "architecture": "${build_arch}",
    "glibc_baseline": "${GLIBC_BASELINE}"
  },
  "checksums": {
    "sha256": "$(sha256sum "${OUTPUT_BASENAME}" | awk '{print $1}')"
  },
  "size_bytes": $(stat -c%s "${OUTPUT_BASENAME}" 2>/dev/null || stat -f%z "${OUTPUT_BASENAME}"),
  "python_version": "${PYTHON_VERSION}",
  "micromamba_version": "${MICROMAMBA_VERSION}"
}
EOF
    LOGINFO "Generated metadata: ${OUTPUT_BASENAME}.json"
    
    LOGSUCCESS "Output file: ${OUTPUT_FILE}"
    LOGSUCCESS "Checksum: ${OUTPUT_FILE}.sha256"
    LOGSUCCESS "Metadata: ${OUTPUT_FILE}.json"
    LOGSUCCESS "${FUNCNAME[0]}"
}

BUILD_DATE="$(date +%Y%m%d)"
BUILD_TIMESTAMP="$(date +%s)"

ARCH="$(arch)"

version="$(grep -oP "^\s*(#+)?\s*Version=\s*?\K\S+$" "${WORK_DIR}"/release-note.md | head -n1)"

system_info="$(detect_system_info)"
build_arch="$(echo "${system_info}" | jq -r .machine_architecture)"

# 版本元数据取自真实安装产物 (而非构建参数自报), 保证元数据与包内容一致
PYTHON_VERSION="$("${MICROMAMBA_DIR}/envs/tsc_python/bin/python" --version 2>/dev/null | awk '{print $2}')"
MICROMAMBA_VERSION="$("${MICROMAMBA_DIR}/bin/micromamba" --version 2>/dev/null)" || true
PYTHON_VERSION="${PYTHON_VERSION:-unknown}"
MICROMAMBA_VERSION="${MICROMAMBA_VERSION:-unknown}"

OUTPUT_NAME="tsc_python-${version}-${ARCH}-${BUILD_DATE}"
OUTPUT_FILE="${OUTPUT_DIR}"/"${OUTPUT_NAME}".sh
# OUTPUT_FILE="${OUTPUT_DIR}"/"${OUTPUT_NAME}".tar.gz
mkdir -p "${OUTPUT_DIR}"

check_glibc_baseline
pack_installer
