#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2154
set -o errexit
set -o nounset
set -o pipefail
set +o posix
shopt -s nullglob
shopt -s dotglob

WORK_DIR="$(dirname "$(readlink -f "$0")")"
source "${WORK_DIR}/func"
source "${WORK_DIR}/.profile"
DST_DIR=/home/tsc/tsc_tools/micromamba

check_env() {
    LOGINFO "${FUNCNAME[0]}"
    system_info="$(detect_system_info)"
    if echo "${system_info}" |
        grep -q "${build_arch}"; then
        if echo "${system_info}" |
            grep -q "${build_os_distribution_file_variety}"; then
            LOGSUCCESS "${FUNCNAME[0]}"
            return 0
        fi
    fi
    LOGERROR "${FUNCNAME[0]}: Unsupported OS distribution"
    exit 1
}

_install() {
    LOGINFO "${FUNCNAME[0]}"
    install --mode=0755 "${WORK_DIR}/tsc_python_profile" /home/tsc/
    backup_dir_with_rotation "${DST_DIR}"
    mkdir -p /home/tsc/tsc_tools
    LOGINFO "Installation in progress, This will take about 1-5 minutes."
    mkdir -p /home/tsc/tsc_tools/
    tar xzf "${WORK_DIR}"/micromamba.tar.gz -C /home/tsc/tsc_tools/
    \cp "${WORK_DIR}"/release-note.md \
        "${WORK_DIR}"/readme.md \
        "${WORK_DIR}"/install.sh \
        "${DST_DIR}"/
    mkdir -p /home/tsc/tsc_tools/modules/
    \cp -r "${WORK_DIR}"/ansible /home/tsc/tsc_tools/
    \cp -r "${WORK_DIR}"/modules/* /home/tsc/tsc_tools/modules/
    if [[ -f /home/tsc/tsc_profile ]]; then
        sed -i '/tsc_python_profile/d' /home/tsc/tsc_profile
    fi
    LOGSUCCESS "${FUNCNAME[0]}"
    echo 'source /home/tsc/tsc_python_profile' >>/home/tsc/tsc_profile
    echo "################################################################################
Usage: 
    # activate micromamba environment
    source /home/tsc/tsc_python_profile
    # or
    # activate full tsc environment
    source /home/tsc/tsc_profile to
################################################################################"
}

check_env
_install
