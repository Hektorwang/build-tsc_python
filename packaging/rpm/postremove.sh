#!/bin/bash
#
# tsc_python RPM ---- %postun (卸载后清理目录壳)
#
#   $1 == 0  真卸载 (rpm -e):     清理空目录壳
#   $1 >= 1  升级 (rpm -U / 重装): 跳过, 新包 %post 会重建
#
# 执行时机: RPM 已删除包内文件清单的所有文件之后
#   环境本体 (/home/tsc/tsc_python)、模块 (tsc_python/modules/tsc_python_*)、
#   ansible 配置 (tsc_python/ansible) 均已删除, 此时仅剩空目录壳
# 本步自底向上只删空目录; 有残留文件的目录不会被删, 安全
#
# 不清理 (保留):
#   /home/tsc/tsc_profile        公共入口
#   /home/tsc/tsc_profile.d      目录 (其他工具的 drop-in 可能还在)
#   /home/tsc/tsc_tools          目录壳本身属 tsc_tools, 即使空也不由本包删
#   /var/log/tsc                 运行期日志
#   %pre 轮转出的旧安装备份
##################################################
# shellcheck disable=SC2034
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

TSC_HOME_DIR="/home/tsc"
ENV_ROOT="${TSC_HOME_DIR}/tsc_python"
TSC_TOOLS_DIR="${TSC_HOME_DIR}/tsc_tools"

if [ "${1:-0}" != "0" ]; then
    # 升级: 不清理, 新包 %post 会重建
    exit 0
fi

# 自底向上清理本包自己的空目录壳 (-depth 先子后父, -empty 只删空目录)
# 注意: 只列本包独占的路径, 不碰 ${TSC_TOOLS_DIR} 本身以免误删别人的目录
for _dir in ${ENV_ROOT} \
    ${ENV_ROOT}/ansible \
    ${ENV_ROOT}/modules/tsc_python_*; do
    [ -d "${_dir}" ] || continue
    find "${_dir}" -depth -type d -empty -delete 2>/dev/null
done

exit 0
