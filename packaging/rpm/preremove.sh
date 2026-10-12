#!/bin/bash
#
# tsc_python RPM ---- %preun (卸载前回收)
#
#   $1 == 0  真卸载 (rpm -e):     执行回收
#   $1 >= 1  升级 (rpm -U / 重装): 直接跳过, 由新包的 %post 重建
#
# 回收范围 (本包在包文件清单之外的衍生文件):
#   1. 本包 drop-in /home/tsc/tsc_profile.d/01-tsc_python-profile.sh
#      —— 该文件名归属本包独占: %post 每次安装/升级都用包内版本刷新,
#         此处无条件删除, 不保留本地修改 (现场自定义片段请另建文件)
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
TSC_PROFILE_D_DIR="${TSC_HOME_DIR}/tsc_profile.d"
DROPIN_FILE="${TSC_PROFILE_D_DIR}/01-tsc_python-profile.sh"

# $1 为卸载后剩余的本包实例数: 0=真卸载, >=1=升级
if [ "${1:-0}" != "0" ]; then
    echo "tsc_python: upgrade detected, skip cleanup (handled by new package %post)"
    exit 0
fi

LOG() {
    printf '%s | %-8s | tsc_python-preun - %s\n' "$(date "+%F %T")" "$1" "$2" >&2
}

LOG "INFO" "cleanup start"

# ---------- 1. 回收本包独占的 drop-in (无条件, 名字归属本包) ----------
if [ -f "${DROPIN_FILE}" ]; then
    if rm -f "${DROPIN_FILE}"; then
        LOG "SUCCESS" "removed ${DROPIN_FILE}"
    else
        LOG "WARNING" "failed to remove ${DROPIN_FILE}"
    fi
else
    LOG "INFO" "${DROPIN_FILE} not present, nothing to remove"
fi

LOG "INFO" "cleanup done (tsc_profile, tsc_profile.d, /var/log/tsc are kept)"
exit 0
