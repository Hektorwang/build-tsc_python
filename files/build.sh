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
    find "${MICROMAMBA_DIR}" -type d -name "__pycache__" -exec rm -rf {} +
    rm -rf "${MICROMAMBA_DIR}"/pkgs
    cat <<EOF >"${WORK_DIR}/.profile"
#!/usr/bin/env bash
build_arch=${build_arch}
build_os_distribution_file_variety=${build_os_distribution_file_variety}
EOF
    cd "${TSC_TOOLS_DIR}" || exit 99
    tar czf micromamba.tar.gz micromamba
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

    # tar czf "${OUTPUT_FILE}" "${OUTPUT_NAME}"
    "${WORK_DIR}"/makeself.sh --needroot --tar-quietly \
        --help-header README.md \
        "${OUTPUT_NAME}" "${OUTPUT_FILE}" \
        "TSC PYTHON" \
        ./install.sh
    chmod +x "${OUTPUT_FILE}"
    LOGSUCCESS "Output file: ${OUTPUT_FILE}"
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
