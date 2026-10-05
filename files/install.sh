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
    # 模块 run.sh 补可执行位 (防打包/拷贝过程丢失), 保证 tsc 入口可调用
    chmod 0755 /home/tsc/tsc_tools/modules/*/run.sh
    # 模块合并后重建 rag.md (生成器由 tsc_tools >= 2.1.7 随包提供), 使 tsc 命令帮助与 RAG 文档覆盖本包模块
    if [[ -x /home/tsc/tsc_tools/gen_rag.sh ]]; then
        /home/tsc/tsc_tools/gen_rag.sh || LOGWARNING "gen_rag.sh 执行失败, rag.md 未更新"
    else
        LOGWARNING "未找到 /home/tsc/tsc_tools/gen_rag.sh, 跳过 rag.md 更新 (需升级 tsc_tools)"
    fi
    # 创建 ansible 日志目录 (ansible.cfg: log_path=/var/log/tsc/ansible.log)
    mkdir -p /var/log/tsc
    chmod 0755 /var/log/tsc
    if id tsc &>/dev/null; then
        chown tsc: /var/log/tsc || LOGWARNING "chown tsc /var/log/tsc 失败, 以 tsc 用户运行 ansible 时日志可能不可写"
    fi
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
