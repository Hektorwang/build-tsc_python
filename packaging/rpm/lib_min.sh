##################################################
# 最小运行时库 (供 RPM scriptlet 内联使用)
#
# 由 build.sh 通过 `# >>> INJECT <file>` 标记内联进 %pre / %post, 不单独发布:
#   - %pre 执行时包内文件尚未落盘, 无法 source 包内文件
#   - 目标机未必安装了 tsc_tools, 其 func 库未必存在
# 因此 scriptlet 只依赖这里提供的几个函数 (与 func 同名同签名)。
#
# 调用方需先设置 __LOG_TAG (如 tsc_python-pre / tsc_python-post)
##################################################

# scriptlet 输出统一写 stderr: rpm 会把 scriptlet 输出回显给安装者,
# 写 stdout 会与 rpm 自身的进度输出混淆
__log_min() {
    printf '%s | %-8s | %s - %s\n' \
        "$(date "+%F %T")" "$1" "${__LOG_TAG:-tsc_python}" "${*:2}" >&2
    return 0
}

LOGDEBUG() { __log_min "DEBUG" "$@"; }
LOGINFO() { __log_min "INFO" "$@"; }
LOGSUCCESS() { __log_min "SUCCESS" "$@"; }
LOGWARNING() { __log_min "WARNING" "$@"; }
LOGERROR() { __log_min "ERROR" "$@"; }

##################################################
# 判断元素是否在列表中 (与 func 同名函数实现一致)
# 参数:
#   $1      - 待查元素
#   $2...$# - 列表元素
# 返回:
#   0 - 命中
#   1 - 未命中
##################################################
is_element_in_array() {
    local element_to_check="$1"
    shift

    local item
    for item in "$@"; do
        if [[ "${element_to_check}" == "${item}" ]]; then
            return 0
        fi
    done
    return 1
}

##################################################
# 版本号比较: $1 >= $2 ?
# 返回:
#   0 - $1 >= $2
#   1 - $1 < $2
##################################################
version_ge() {
    [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$1" ]] || [[ "$1" == "$2" ]]
}
