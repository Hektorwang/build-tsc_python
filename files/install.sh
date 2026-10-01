#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2154
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
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
    target_arch="$(echo "${system_info}" | jq -r '.machine_architecture')"
    if [[ "${target_arch}" == "${build_arch}" ]]; then
        LOGSUCCESS "${FUNCNAME[0]}"
        return 0
    fi
    LOGERROR "${FUNCNAME[0]}: 架构不匹配 (安装包: ${build_arch}, 目标机: ${target_arch})"
    exit 1
}

_install() {
    LOGINFO "${FUNCNAME[0]}"
    install --mode=0755 "${WORK_DIR}/tsc_python_profile" /home/tsc/
    backup_dir_with_rotation "${DST_DIR}"
    mkdir -p /home/tsc/tsc_tools
    LOGINFO "Installation in progress, This will take about 1-5 minutes."
    tar xzf "${WORK_DIR}"/micromamba.tar.gz -C /home/tsc/tsc_tools/
    \cp "${WORK_DIR}"/release-note.md \
        "${WORK_DIR}"/readme.md \
        "${WORK_DIR}"/install.sh \
        "${WORK_DIR}"/smoke_test.sh \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.zh_CN.md \
        "${DST_DIR}"/
    mkdir -p /home/tsc/tsc_tools/modules/
    \cp -r "${WORK_DIR}"/ansible /home/tsc/tsc_tools/
    \cp -r "${WORK_DIR}"/modules/* /home/tsc/tsc_tools/modules/
    if [[ -f /home/tsc/tsc_profile ]]; then
        sed -i '/tsc_python_profile/d' /home/tsc/tsc_profile
    fi
    source /home/tsc/tsc_python_profile
    _patch_ansible
    LOGSUCCESS "${FUNCNAME[0]}"
    echo 'source /home/tsc/tsc_python_profile' >>/home/tsc/tsc_profile
    echo "################################################################################
Usage: 
    # activate micromamba environment
    source /home/tsc/tsc_python_profile
    # or
    # activate full tsc environment
    source /home/tsc/tsc_profile
################################################################################"
}

_patch_ansible() {
	# add more python3 interpreter path to ansible default interpreter fallback path list
	source /home/tsc/tsc_python_profile
	# 补丁失败不阻断安装, 仅告警 (ansible 改动 base.yml 结构时可能失败)
	python3 "${WORK_DIR}"/patch_ansible.py ||
		LOGWARNING "_patch_ansible: 解释器补丁失败, ansible 可能无法自动发现 tsc_python, 不影响安装完成"
}

check_env
_install
