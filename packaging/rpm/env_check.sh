##################################################
# 运行环境检测与准入校验 (tsc_python)
#
# 由 build.sh 内联进 RPM %pre 脚本: 彼时包内文件尚未落盘, 脚本必须自包含,
# 因此本文件只使用 lib_min.sh 提供的函数, 不依赖包内任何文件。
#
# 与 tsc_tools 的差异: 本包不做发行版家族门禁——环境在 glibc 2.17 基线容器中
# 构建, 凡 glibc >= 基线的发行版均可运行, 因此只校验 root / 架构 / glibc。
#
# 前置条件 (调用方保证):
#   - 已提供 LOG*/is_element_in_array/version_ge (lib_min.sh)
#   - 已 source packaging/rpm/supported_env.conf (SUPPORTED_ARCHITECTURES / GLIBC_BASELINE)
#   - 已设置 PACKAGE_ARCH (本包的构建架构, 由 build.sh 渲染)
#   - 已声明 declare -A system_info
##################################################

##################################################
# 检测系统信息 (架构 / 发行版 / glibc)
# 输出:
#   key=value 形式的系统信息 (每行一对, 输出到 stdout)
# 返回:
#   0 - 成功
##################################################
detect_system_info() {
    local machine_architecture distribution distribution_version glibc_version getconf_out
    machine_architecture="$(uname -m)"
    distribution="unknown"
    distribution_version="unknown"

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        distribution="${NAME:-unknown}"
        distribution_version="${VERSION_ID:-unknown}"
    fi

    # 不经 awk: 门禁脚本不隐式依赖 gawk (nfpm depends 未声明它, awk 缺失时这里会在
    # errexit 下以 127 中止且报错误导)。"glibc 2.17" 剥掉首个空格前缀即版本号;
    # getconf 缺失/无输出时为空串, detect_system_info 按未知回填, check_env 按拒绝处理
    getconf_out="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
    glibc_version="${getconf_out#* }"

    echo "machine_architecture=${machine_architecture}"
    echo "os_distribution=${distribution}"
    echo "os_distribution_version=${distribution_version}"
    echo "glibc_version=${glibc_version:-unknown}"
    return 0
}

##################################################
# 校验本机环境是否满足安装要求
# 全局变量:
#   system_info (关联数组, 由本函数填充)
#   SUPPORTED_ARCHITECTURES / GLIBC_BASELINE (来自 packaging/rpm/supported_env.conf)
#   PACKAGE_ARCH (本包构建架构)
# 返回:
#   0   - 校验通过
#   127 - 校验未通过
##################################################
check_env() {
    LOGINFO "${FUNCNAME[0]}"
    local ret=0

    if [[ "$EUID" != "0" ]]; then
        LOGERROR "Insufficient privileges: Script must be run with root privilege."
        ret=127
    fi

    while IFS='=' read -r key value; do
        system_info["$key"]="$value"
    done < <(detect_system_info)

    local current_arch="${system_info[machine_architecture]:-unknown}"
    local current_glibc="${system_info[glibc_version]:-unknown}"

    LOGINFO "Target: ${system_info[os_distribution]:-unknown} ${system_info[os_distribution_version]:-unknown} | arch: ${current_arch} | glibc: ${current_glibc}"

    IFS=',' read -r -a supported_archs_array <<<"$SUPPORTED_ARCHITECTURES"
    if ! is_element_in_array "${current_arch}" "${supported_archs_array[@]}"; then
        LOGERROR "Architecture incompatible: '${current_arch}' is not in the supported list '${SUPPORTED_ARCHITECTURES}'."
        ret=127
    fi

    # 环境内含本地编译的二进制, 装错架构会直接不可用。
    # rpm 本身也会拦跨架构安装, 此处是 --ignorearch 等绕过场景的最后一道闸
    if [[ "${current_arch}" != "${PACKAGE_ARCH}" ]]; then
        LOGERROR "Architecture mismatch: package is built for '${PACKAGE_ARCH}', target machine is '${current_arch}'."
        ret=127
    fi

    if [[ "${current_glibc}" == "unknown" ]]; then
        # fail-close: 检测不到即拒装。musl 系 (Alpine) 的 getconf GNU_LIBC_VERSION 无输出,
        # 旧行为 (WARNING + 跳过) 会放行安装、到运行期才以 `version GLIBC_2.xx not found`
        # 暴露, 与 README "musl 系不适用"的口径不符; getconf 属 glibc 自带, glibc 系必有,
        # 检测不到即拒装不会误伤受支持环境
        LOGERROR "glibc version not detected (getconf GNU_LIBC_VERSION unavailable), cannot verify baseline ${GLIBC_BASELINE}, aborting"
        ret=127
    elif ! version_ge "${current_glibc}" "${GLIBC_BASELINE}"; then
        LOGERROR "glibc too old: '${current_glibc}' < baseline '${GLIBC_BASELINE}'; the environment is built on glibc ${GLIBC_BASELINE} (CentOS 7.9)."
        ret=127
    fi

    if [[ "${ret}" -ne 0 ]]; then
        LOGERROR "${FUNCNAME[0]}"
    else
        LOGSUCCESS "${FUNCNAME[0]}"
    fi
    return "${ret}"
}
