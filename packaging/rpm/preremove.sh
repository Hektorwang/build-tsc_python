#!/bin/bash
#
# tsc_python RPM ---- %preun (卸载前回收)
#
#   $1 == 0  真卸载 (rpm -e):     执行回收
#   $1 >= 1  升级 (rpm -U / 重装): 直接跳过, 由新包的 %post 重建
#
# 回收范围 (本包在包文件清单之外的衍生文件):
#   1. 本包 drop-in /home/tsc/tsc_profile.d/01-tsc_python-profile.sh
#      (按 .installed_manifest 记录的 sha256 校验, 用户改过则不删)
#
# 保留 (不回收):
#   /home/tsc/tsc_profile        公共入口, 其他工具可能仍在用
#   /home/tsc/tsc_profile.d 目录  其他工具的 drop-in 可能还在
#   /var/log/tsc 及运行期日志
#   %pre 轮转出的旧安装备份 (micromamba.bak.<ts> / tsc_python_profile.pre-rpm.<ts>)
#
# 包内文件 (环境本体、模块、ansible 配置) 由 rpm 自行删除;
# 空目录壳由新增的 %postun 清理。
#
# 本脚本只使用 POSIX 语法且任何情况下都返回 0: %preun 非零会导致 rpm 拒绝卸载,
# 让机器卡在"卸不掉"的状态比留下几个文件更糟。
##################################################

# shellcheck disable=SC1090,SC1091,SC2034,SC2181
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

TSC_HOME_DIR="/home/tsc"
ENV_ROOT="${TSC_HOME_DIR}/tsc_python"
TSC_PROFILE_D_DIR="${TSC_HOME_DIR}/tsc_profile.d"
DROPIN_FILE="${TSC_PROFILE_D_DIR}/01-tsc_python-profile.sh"
MANIFEST_FILE="${ENV_ROOT}/.installed_manifest"

# $1 为卸载后剩余的本包实例数: 0=真卸载, >=1=升级
if [ "${1:-0}" != "0" ]; then
    echo "tsc_python: upgrade detected, skip cleanup (handled by new package %post)"
    exit 0
fi

LOG() {
    printf '%s | %-8s | tsc_python-preun - %s\n' "$(date "+%F %T")" "$1" "$2" >&2
}

LOG "INFO" "cleanup start"

# ---------- 1. 按 manifest 回收本包部署的衍生文件 ----------
# 每行: FILE:<path>:<sha256>; hash 一致才删, 防止删掉被用户/其他包改过的同名文件
if [ -f "${MANIFEST_FILE}" ]; then
    while IFS= read -r entry; do
        [ -n "${entry}" ] || continue
        kind="${entry%%:*}"
        rest="${entry#*:}"
        [ "${kind}" = "FILE" ] || continue

        path="${rest%%:*}"
        sum="${rest#*:}"
        [ -f "${path}" ] || continue
        if [ -z "${sum}" ]; then
            LOG "WARNING" "${path} has no recorded hash, skip"
            continue
        fi
        cur_sum="$(sha256sum <"${path}" 2>/dev/null | awk '{print $1}')"
        if [ "${cur_sum}" = "${sum}" ]; then
            rm -f "${path}" && LOG "SUCCESS" "removed ${path}"
        else
            LOG "WARNING" "${path} modified (hash mismatch), kept"
        fi
    done <"${MANIFEST_FILE}"
else
    LOG "WARNING" "manifest ${MANIFEST_FILE} not found, skip drop-in cleanup"
    # 兜底: 清单丢失时按名字删, 仍是只删本包的 drop-in
    if [ -f "${DROPIN_FILE}" ]; then
        rm -f "${DROPIN_FILE}" && LOG "SUCCESS" "removed drop-in ${DROPIN_FILE}"
    fi
fi

rm -f "${MANIFEST_FILE}"

LOG "INFO" "cleanup done (tsc_profile, tsc_profile.d, /var/log/tsc are kept)"
exit 0
