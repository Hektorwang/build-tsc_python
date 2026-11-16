#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 构建入口脚本：在本机架构的容器中构建并打包
# 产物与发行版无关: 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中创建,
# 兼容所有 glibc >= 2.17 的 Linux 发行版 (CentOS/RHEL 7+, openEuler, HCE, Kylin V10, FitOS 等)
set -o errexit
set -o nounset
set -o pipefail
set +o posix
shopt -s nullglob
# 固定 umask: 产物文件权限 = 源文件 mode & umask, 收紧的构建机 umask(如 0077)
# 会静默削掉权限, 这里统一保证常规权限可预期 (与 tsc_tools/build.sh 一致)
umask 022

WORK_DIR="$(dirname "$(readlink -f "$0")")"
OUTPUT_DIR="${WORK_DIR}/output"
LOG_DIR="${WORK_DIR}/log"
TMP_DIR="${WORK_DIR}/files/tmp"
PACKAGING_DIR="${WORK_DIR}/packaging/rpm"
RELEASE_DIR="${WORK_DIR}/release"
STAGE_DIR="${WORK_DIR}/stage"
ARCH="$(arch)"
D14="$(date +%Y%m%d%H%M%S)"
DOCKERFILE="Dockerfile"

# 函数库唯一副本在 files/func (容器内由 Dockerfile COPY 到工作目录, pack.sh 源同一份)
source "${WORK_DIR}/files/func"

# 同机互斥: 并发 build.sh 会互踩 stage/ 与 release/ 的清理 (清空 output/<arch>、
# 回收旧产物), 第二个实例直接退出。锁文件零字节, 已入 .gitignore;
# flock 属 util-linux, 缺失时显式报错而不是静默失去互斥
BUILD_LOCK="${WORK_DIR}/.build.lock"
if ! command -v flock &>/dev/null; then
    LOGERROR "缺少 flock (util-linux), 无法保证构建互斥"
    exit 1
fi
exec 9>"${BUILD_LOCK}"
if ! flock -n 9; then
    LOGERROR "已有构建正在运行 (锁: ${BUILD_LOCK}), 同机只允许一个 build.sh 实例"
    exit 1
fi

trap gracefully_abort INT

# 默认参数
no_cache=""
micromamba_version=""
repo_local=""
python_version=""
pypi_index=""
conda_forge=""

_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build TSC Python distribution using local Docker containers (same architecture).

Options:
  -n, --no-cache              Disable Docker build cache
  -m, --micromamba-ver V      Micromamba version (overrides build.conf)
  -r, --repo-local URL        Internal yum repo URL (overrides build.conf)
  -p, --python-version V      Override Python version in environment.yml (overrides build.conf)
      --pypi-index URL        PyPI index URL (overrides build.conf)
      --conda-forge URL       conda-forge channel URL (overrides build.conf)
  -h, --help                  Show this help

Config file:
  build.conf (INI format, [build] section) is read when a parameter is not specified on the command line.
  Keys: micromamba_ver, repo_local, python_version, pypi_index, conda_forge

Note:
  This script builds for the CURRENT machine architecture: ${ARCH}
  To build for another architecture, run this script on that machine.
  The build container is CentOS 7.9 (glibc 2.17 baseline), artifacts are distro-independent.
  files/pack.sh prepares the install tree inside the container; this script then packages
  it into an RPM with nfpm on the build host.
EOF
    exit 0
}

_parsed=$(getopt \
    --options hnm:r:p: \
    --longoptions help,no-cache,micromamba-ver:,repo-local:,python-version:,pypi-index:,conda-forge: \
    --name "$0" \
    -- "$@") || { LOGERROR "Invalid arguments, try -h for help"; exit 1; }

eval set -- "${_parsed}"
while true; do
    case "$1" in
        -h|--help)            _usage ;;
        -n|--no-cache)        no_cache="--no-cache";     shift ;;
        -m|--micromamba-ver)  micromamba_version="$2";   shift 2 ;;
        -r|--repo-local)      repo_local="$2";           shift 2 ;;
        -p|--python-version)  python_version="$2";       shift 2 ;;
        --pypi-index)         pypi_index="$2";           shift 2 ;;
        --conda-forge)        conda_forge="$2";          shift 2 ;;
        --)                   shift; break ;;
        *)                    LOGERROR "Unknown argument: $1"; exit 1 ;;
    esac
done

# 读取配置文件，仅在参数未通过命令行指定时生效
build_conf="${WORK_DIR}/build.conf"
if [[ -f "${build_conf}" ]]; then
    [[ -z "${micromamba_version}" ]] && micromamba_version="$(get_ini_value "${build_conf}" build micromamba_ver 2>/dev/null || true)"
    [[ -z "${repo_local}" ]]         && repo_local="$(get_ini_value "${build_conf}" build repo_local 2>/dev/null || true)"
    [[ -z "${python_version}" ]]     && python_version="$(get_ini_value "${build_conf}" build python_version 2>/dev/null || true)"
    [[ -z "${pypi_index}" ]]         && pypi_index="$(get_ini_value "${build_conf}" build pypi_index 2>/dev/null || true)"
    [[ -z "${conda_forge}" ]]        && conda_forge="$(get_ini_value "${build_conf}" build conda_forge 2>/dev/null || true)"
else
    LOGWARNING "build.conf not found, using built-in defaults"
fi

# 最终兜底默认值 (与 build.conf.example 保持一致)
micromamba_version="${micromamba_version:-2.9.0}"
repo_local="${repo_local:-}"
pypi_index="${pypi_index:-https://mirrors.cernet.edu.cn/pypi/web/simple}"
conda_forge="${conda_forge:-https://mirrors.cernet.edu.cn/anaconda/cloud/conda-forge}"

# python 版本号格式校验: 形如 3.13 或 3.13.12; 非法值到容器内才会被 conda 拒绝, 入口提前拦下
if [[ -n "${python_version}" && ! "${python_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    LOGERROR "python_version 格式非法: '${python_version}' (期望 3.13 / 3.13.12 形式)"
    exit 1
fi

if [[ -z "${repo_local}" ]]; then
    LOGERROR "yum 源地址未配置: 请通过 --repo-local 参数或 build.conf 的 repo_local 键提供"
    exit 1
fi

LOGINFO "Config | micromamba: ${micromamba_version} | repo_local: ${repo_local} | python_version: ${python_version:-<from environment.yml>}"
LOGINFO "Config | pypi_index: ${pypi_index} | conda_forge: ${conda_forge}"

# 检查 Docker 是否可用
if ! command -v docker &>/dev/null; then
    LOGERROR "Docker is not installed or not in PATH"
    exit 1
fi
if ! docker info &>/dev/null; then
    LOGERROR "Docker daemon is not running or current user has no permission"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${TMP_DIR}"

# ─────────────────────────────────────────────
# 生成构建期配置: environment.yml / condarc / pip.conf
# 每次从原始文件与参数重新生成, 支持源地址自定义
# ─────────────────────────────────────────────
env_yml_src="${WORK_DIR}/files/environment.yml"
env_yml_tmp="${TMP_DIR}/environment.yml"
condarc_tmp="${TMP_DIR}/condarc"
pip_conf_tmp="${TMP_DIR}/pip.conf"

# 临时构建期配置 + stage/ 一并回收: package_rpm 的 RETURN trap 只在函数正常返回时
# 触发, 构建中途 Ctrl-C (gracefully_abort -> exit) 时不会触发, 会留下 GB 级 payload 拷贝。
# 注意: 同一信号只能有一个 trap, 后注册会覆盖前者, 故此处合并为一条
trap 'rm -f "${env_yml_tmp}" "${condarc_tmp}" "${pip_conf_tmp}"; rm -rf "${STAGE_DIR}"' EXIT

if [[ -n "${python_version}" ]]; then
    sed "s/- python=.*/- python=${python_version}/" "${env_yml_src}" > "${env_yml_tmp}"
    LOGINFO "Python version override: ${python_version}"
else
    cp "${env_yml_src}" "${env_yml_tmp}"
fi

# condarc: 仅使用 conda-forge 社区通道 (default_channels 置空, 不含 anaconda defaults 商业源)
cat > "${condarc_tmp}" <<EOF
# generated by build.sh -- do not edit
channels:
  - conda-forge
show_channel_urls: true
default_channels: []
custom_channels:
  conda-forge: ${conda_forge}
EOF

cat > "${pip_conf_tmp}" <<EOF
# generated by build.sh -- do not edit
[global]
timeout=30
index-url = ${pypi_index}
EOF

LOGINFO "Generated: ${condarc_tmp} / ${pip_conf_tmp}"

# python 主.次版本 (产物自检 need_file 里 base.yml 等条目锚定 lib/python<MM> 路径)
# 用 sed -n '1p' 而非 head -n1: head 提前退出会让上游 grep 收到 SIGPIPE 返回 141,
# 在 pipefail + errexit 下脚本无任何提示直接中断
py_mm="$(grep -oE 'python=[0-9]+\.[0-9]+' "${env_yml_tmp}" | sed -n '1p' | sed 's/^python=//')" || py_mm=""
py_mm="${py_mm:-3.13}"

# ─────────────────────────────────────────────
# 架构映射与支持白名单一致性断言
# packaging/rpm/supported_env.conf 是支持条件的唯一事实源 (架构白名单 + glibc 基线),
# %pre 注入的是同一份。这里把架构 → 第三方组件下载标识收敛为单一映射 (原先
# micromamba 与 jq 各写一个 case, 可漂移), 并断言:
#   1. 本机架构在白名单内;
#   2. 白名单每一项都有下载映射与 jq sha256——白名单加了架构而映射/sha 漏改时,
#      会打出 %pre 拒装自己目标架构的包, 在此提前拦下 (checklist 见 conf 头注释)
# ─────────────────────────────────────────────
arch_download_tags() {
    # 输出 "<micromamba-tag> <jq-arch>", 未知架构返回 1
    case "$1" in
        x86_64)  echo "linux-64 amd64" ;;
        aarch64) echo "linux-aarch64 arm64" ;;
        *)       return 1 ;;
    esac
}

jq_version="1.8.1"
jq_sha256_x86_64="020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d"
jq_sha256_aarch64="6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4"

supported_env_conf="${PACKAGING_DIR}/supported_env.conf"
supported_archs="$(sed -n 's/^SUPPORTED_ARCHITECTURES=//p' "${supported_env_conf}" | tr -d '"[:space:]')"
if [[ -z "${supported_archs}" ]]; then
    LOGERROR "未能从 ${supported_env_conf} 解析出 SUPPORTED_ARCHITECTURES"
    exit 1
fi
IFS=',' read -r -a whitelist_archs <<<"${supported_archs}"
for whitelist_arch in "${whitelist_archs[@]}"; do
    arch_download_tags "${whitelist_arch}" &>/dev/null || {
        LOGERROR "白名单架构 '${whitelist_arch}' 在 arch_download_tags() 缺少映射"
        LOGERROR "请补 case, 否则会打出 %pre 拒装自己目标架构的包 (checklist 见 conf 头注释)"
        exit 1
    }
    sha_var="jq_sha256_${whitelist_arch}"
    [[ -n "${!sha_var:-}" ]] || {
        LOGERROR "白名单架构 '${whitelist_arch}' 缺少 ${sha_var} 常量"
        exit 1
    }
done
is_element_in_array "${ARCH}" "${whitelist_archs[@]}" || {
    LOGERROR "本机架构 ${ARCH} 不在支持白名单 (${supported_archs})"
    exit 1
}
ARCH_TAGS="$(arch_download_tags "${ARCH}")"
micromamba_url_tag="${ARCH_TAGS%% *}"
jq_arch_tag="${ARCH_TAGS##* }"

# ─────────────────────────────────────────────
# 预下载 micromamba 到 files/tmp/micromamba
# 若已存在且版本匹配则跳过，否则重新下载
# ─────────────────────────────────────────────
micromamba_cache="${TMP_DIR}/micromamba"
micromamba_cache_ver="${TMP_DIR}/micromamba.version"

_need_download=true
if [[ -f "${micromamba_cache}" && -f "${micromamba_cache_ver}" ]]; then
    cached_ver="$(cat "${micromamba_cache_ver}")"
    if [[ "${cached_ver}" == "${micromamba_version}-${ARCH}" ]]; then
        LOGINFO "micromamba cache hit: ${micromamba_version} (${ARCH}), skipping download"
        _need_download=false
    else
        LOGINFO "micromamba version changed (${cached_ver} -> ${micromamba_version}-${ARCH}), re-downloading"
    fi
fi

if [[ "${_need_download}" == true ]]; then
    LOGINFO "Downloading micromamba ${micromamba_version} for ${ARCH}..."
    curl --fail --location \
        --output "${micromamba_cache}" \
        "https://micro.mamba.pm/api/micromamba/${micromamba_url_tag}/${micromamba_version}"
    echo "${micromamba_version}-${ARCH}" > "${micromamba_cache_ver}"
    LOGSUCCESS "micromamba downloaded: ${micromamba_cache}"
fi

# ─────────────────────────────────────────────
# 第三方组件: 缓存优先, 缺失时按需下载 (与 micromamba 缓存同一模式)
# jq 版本/sha256 常量与架构映射见上方"架构映射与支持白名单一致性断言"一节
# ─────────────────────────────────────────────
ensure_jq() {
    local url file sum expected sha_var
    # 只取当前架构: aarch64 的 jq 只在 ARM 机器构建时才用得上,
    # 强制双架构齐备会让 x86_64 构建机因 aarch64 下载失败而中断
    file="${TMP_DIR}/jq-${ARCH}"
    url="https://github.com/jqlang/jq/releases/download/jq-${jq_version}/jq-linux-${jq_arch_tag}"
    sha_var="jq_sha256_${ARCH}"
    expected="${!sha_var}"
    if [[ -f "${file}" ]]; then
        sum="$(sha256sum "${file}" | awk '{print $1}')"
        if [[ "${sum}" == "${expected}" ]]; then
            LOGINFO "jq cache hit: ${file}"
            return 0
        fi
        LOGINFO "jq cache checksum mismatch (${ARCH}), re-downloading"
    fi
    LOGINFO "Downloading jq ${jq_version} for ${ARCH}..."
    # 先落临时文件再校验: 直接 --output 到目标路径的话, 下载到损坏/被篡改的
    # 二进制会被原样用进容器, 只有下一次构建才发现不匹配
    if ! curl --fail --location --output "${file}.dl" "${url}"; then
        LOGERROR "jq 下载失败 (${ARCH}): ${url}"
        return 1
    fi
    sum="$(sha256sum "${file}.dl" | awk '{print $1}')"
    if [[ "${sum}" != "${expected}" ]]; then
        LOGERROR "jq 下载完整性校验失败 (${ARCH}): 期望 ${expected}, 实际 ${sum}"
        rm -f "${file}.dl"
        return 1
    fi
    mv -f "${file}.dl" "${file}"
    chmod +x "${file}"
    LOGSUCCESS "jq ${jq_version} (${ARCH}) downloaded and verified"
    LOGSUCCESS "jq ready: ${TMP_DIR}/jq-${ARCH}"
}

ensure_jq

# ─────────────────────────────────────────────
# 构建 (单架构单包, 容器为 CentOS 7.9 基线)
# ─────────────────────────────────────────────
build_target() {
    local output_dir image_tag
    log_file="${LOG_DIR}/build-${ARCH}-${D14}.log"
    output_dir="${OUTPUT_DIR}/${ARCH}"
    image_tag="tsc-python-builder-${ARCH}"

    mkdir -p "${output_dir}"

    LOGINFO "Building: ${ARCH} (container: CentOS 7.9 / glibc 2.17 baseline)"
    LOGINFO "Dockerfile: ${DOCKERFILE} | Output: ${output_dir}"
    LOGINFO "Log: ${log_file}"

    local build_ok=0
    docker build \
        ${no_cache} \
        --pull=false \
        --progress plain \
        --target builder \
        --tag "${image_tag}" \
        --build-arg REPO_LOCAL="${repo_local}" \
        --build-arg ARCH="${ARCH}" \
        --build-arg PYPI_INDEX="${pypi_index}" \
        --file "${DOCKERFILE}" \
        "${WORK_DIR}" \
        2>&1 | tee "${log_file}" || build_ok=1

    if [[ ${build_ok} -ne 0 ]]; then
        LOGERROR "Docker build failed, see log: ${log_file}"
        return 1
    fi
    LOGSUCCESS "Docker build succeeded"

    # 从容器取出产物（安装树已在容器内由 files/pack.sh 组装为 output/payload）
    # output/<arch> 先整体清空再取: docker cp 是目录合并语义而非替换,
    # 不清会把旧布局残留 (如重构前 tsc_tools/ 下的 ansible/modules) 合并进 payload,
    # 最终被打进 RPM —— 与 tsc_tools 命名空间冲突 (安装冲突/卸载误删)
    LOGINFO "Extracting build artifacts..."
    rm -rf "${output_dir}"
    mkdir -p "${output_dir}"
    local container_id
    container_id=$(docker create "${image_tag}")

    if docker cp "${container_id}:/home/tsc/build_micromamba/output/." "${output_dir}/"; then
        LOGSUCCESS "Artifacts extracted to: ${output_dir}"
    else
        LOGERROR "Failed to extract artifacts from container"
        docker rm "${container_id}" &>/dev/null || true
        return 1
    fi

    docker rm "${container_id}" &>/dev/null || true

    LOGINFO "Build artifacts:"
    ls -lh "${output_dir}/"

    LOGSUCCESS "Build completed: ${ARCH}"
}

# ─────────────────────────────────────────────
# RPM 打包 (nfpm, 在宿主机执行)
# ─────────────────────────────────────────────

##################################################
# 将 `# >>> INJECT <file>` 标记替换为对应文件的内容
# (%pre 运行时包内文件尚未落盘, 脚本必须自包含)
# 参数:
#   $1 - 模板文件
#   $2 - 输出文件
##################################################
render_template() {
    local tmpl="$1" out="$2"
    awk -v work_dir="${WORK_DIR}" '
    /^# >>> INJECT / {
        f = work_dir "/" substr($0, index($0, "INJECT ") + 7)
        while ((getline line < f) > 0) print line
        close(f)
        next
    }
    { print }
    ' "${tmpl}" >"${out}"
}

package_rpm() {
    local payload_dir="${OUTPUT_DIR}/${ARCH}/payload"

    # stage/ 由 RETURN trap 回收所有 return 1 失败路径; 成功路径在函数尾部显式回收并
    # 复位 trap——不复位的话, 其后每个函数返回 (含 LOG*) 都会再触发一次 rm -rf。
    # RETURN trap 不被本函数调用的子函数继承 (未开 functrace), 只在本函数返回时触发
    trap 'rm -rf "${STAGE_DIR}"' RETURN

    if [[ ! -d "${payload_dir}/home/tsc" ]]; then
        LOGERROR "未找到打包源 ${payload_dir}/home/tsc, 容器内 pack.sh 可能未生成 payload"
        return 1
    fi

    # ---------- 1. 打包依赖检查 ----------
    # nfpm: 由打包机提供, 优先取 /bin/nfpm
    local nfpm_bin="${NFPM_BIN:-}"
    if [[ -z "${nfpm_bin}" && -x /bin/nfpm ]]; then
        nfpm_bin="/bin/nfpm"
    elif [[ -z "${nfpm_bin}" ]] && command -v nfpm &>/dev/null; then
        nfpm_bin="$(command -v nfpm)"
    fi
    if [[ -z "${nfpm_bin}" || ! -x "${nfpm_bin}" ]]; then
        LOGERROR "nfpm not found on this build host."
        LOGERROR "tsc_python 使用 nfpm 打 RPM 包, 请先在打包机安装 nfpm (期望路径 /bin/nfpm):"
        LOGERROR "  https://nfpm.goreleaser.com/install/"
        LOGERROR "也可放入 PATH, 或用 NFPM_BIN=/path/to/nfpm ./build.sh 显式指定。"
        return 1
    fi
    readonly NFPM_BIN="${nfpm_bin}"
    # || true: grep 匹配不到时 pipefail 会把非零传给 errexit, 脚本在打印 nfpm 版本
    # 这一行直接中断, ${NFPM_VERSION:-unknown} 的兜底永远到不了; 先赋值再 readonly,
    # 避免 local+赋值合一掩盖管道返回值 (SC2155)
    NFPM_VERSION="$("${NFPM_BIN}" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)" || true
    readonly NFPM_VERSION
    LOGINFO "Using packager: ${NFPM_BIN} (nfpm ${NFPM_VERSION:-unknown})"

    # ---------- 2. 版本号 ----------
    # version 取自 release-note.md 的 Version=; release 取构建时间戳 (YYYYMMDDHHMMSS):
    # 精确到秒, 保证同日多次构建的 NVR 可区分 (rpm 按字符串比较版本, 时间戳递增即可正常升级)
    local version release
    # 与 tsc_tools/build.sh 同一写法: 取首个 '=' 之后的整行 (值里再出现 '=' 不会被
    # -F '=' + $2 截断), 再去掉空白/CRLF
    version="$(awk '/Version=/{sub(/^[^=]*=/, ""); print; exit}' "${WORK_DIR}"/release-note.md | tr -d '[:space:]')"
    release="$(date "+%Y%m%d%H%M%S")"

    if [[ -z "${version}" ]]; then
        LOGERROR "未能从 release-note.md 解析出 Version="
        return 1
    fi
    # RPM 的 Version 不允许出现 '-', 提前拦下非法版本号
    if [[ "${version}" == *"-"* ]]; then
        LOGERROR "版本号 '${version}' 含 '-', RPM Version 不允许该字符"
        return 1
    fi

    local release_file="${RELEASE_DIR}/tsc_python-${version}-${release}.${ARCH}.rpm"

    # ---------- 3. 打包源 ----------
    rm -rf "${STAGE_DIR}"
    mkdir -p "${STAGE_DIR}/rpm-scripts" "${STAGE_DIR}/payload/home"
    \cp -a "${payload_dir}/home/tsc" "${STAGE_DIR}/payload/home/tsc"

    # 防御: payload/home/tsc 下只允许 tsc_python 一个顶层目录。
    # 出现其他目录说明构建残留混入 (docker cp 合并语义下旧布局文件会留在 output/<arch>),
    # 直接中止打包——这类文件打进包会与 tsc_tools 的路径冲突
    local stray_top
    stray_top="$(find "${STAGE_DIR}/payload/home/tsc" -mindepth 1 -maxdepth 1 \
        ! -name tsc_python -print -quit 2>/dev/null)"
    if [[ -n "${stray_top}" ]]; then
        LOGERROR "payload 含非预期顶层目录 '${stray_top}' (疑似旧构建残留), 已中止打包"
        LOGERROR "如确认要随包分发该目录, 请先修正其来源, 而非在此放行"
        return 1
    fi

    # ---------- 3.5 版本一致性断言 ----------
    # build-info.json 的 version 由容器内 pack.sh 按 release-note.md 独立解析,
    # 与 RPM NVR 各解一次; 两处漂移会让包内元数据与包版本不符, 在此显式比对
    local build_info="${STAGE_DIR}/payload/home/tsc/tsc_python/build-info.json"
    if [[ -f "${build_info}" ]]; then
        local info_version
        info_version="$(awk -F'"' '$2 == "version" {print $4; exit}' "${build_info}")"
        if [[ -n "${info_version}" && "${info_version}" != "${version}" ]]; then
            LOGERROR "build-info.json 版本 '${info_version}' 与 RPM 版本 '${version}' 不一致"
            return 1
        fi
        LOGINFO "build-info.json 版本一致: ${info_version}"
    else
        # pack.sh 无条件生成该文件, 缺失即容器侧构建异常; 放行会让包内元数据与包
        # 版本脱钩——与其余门禁 (glibc/占位符/PYTHON_MM) 的 fail-close 口径保持一致
        LOGERROR "未找到 ${build_info}, 容器内 pack.sh 未生成构建元数据"
        return 1
    fi

    # ---------- 4. 生成 RPM scriptlet ----------
    render_template "${PACKAGING_DIR}/preinstall.sh.tmpl" "${STAGE_DIR}/rpm-scripts/preinstall"
    render_template "${PACKAGING_DIR}/postinstall.sh.tmpl" "${STAGE_DIR}/rpm-scripts/postinstall"
    \cp "${PACKAGING_DIR}/preremove.sh" "${STAGE_DIR}/rpm-scripts/preremove"
    \cp "${PACKAGING_DIR}/postremove.sh" "${STAGE_DIR}/rpm-scripts/postremove"
    sed -i "s|@ARCH@|${ARCH}|g" "${STAGE_DIR}/rpm-scripts/preinstall"
    chmod 0755 "${STAGE_DIR}"/rpm-scripts/*

    # scriptlet 语法自检: 装到目标机上才发现语法错误代价太高
    local scriptlet
    for scriptlet in "${STAGE_DIR}"/rpm-scripts/*; do
        bash -n "${scriptlet}" || {
            LOGERROR "scriptlet 语法检查未通过: ${scriptlet}"
            return 1
        }
    done

    # 随包脚本语法自检: 模块 run.sh 一度因引号未闭合整份不可用, 而打包期只查了
    # 文件存在性与可执行位, 缺陷随包发布。这里对本包自带的 shell 脚本逐个 bash -n,
    # 把语法错误挡在出包之前
    # 范围限定为包自有脚本: conda 环境内还散落大量 *.sh (activate.d 等), 它们不由
    # 本仓维护, 纳入自检只会引入不可控的噪音
    local payload_script
    while IFS= read -r -d '' payload_script; do
        bash -n "${payload_script}" || {
            LOGERROR "随包脚本语法检查未通过: ${payload_script}"
            return 1
        }
    done < <(find "${STAGE_DIR}/payload/home/tsc/tsc_python" -maxdepth 3 -type f \
        \( -name 'smoke_test.sh' -o -path '*/modules/*/run.sh' \) -print0)

    # 注入/渲染完整性断言: render_template 读不到注入文件时会静默产出空内容,
    # bash -n 查不出这类运行期错误, 只能在打包期显式断言
    if ! grep -q 'SUPPORTED_ARCHITECTURES=' "${STAGE_DIR}/rpm-scripts/preinstall" ||
        ! grep -q 'check_env()' "${STAGE_DIR}/rpm-scripts/preinstall" ||
        grep -q '@ARCH@' "${STAGE_DIR}/rpm-scripts/preinstall"; then
        LOGERROR "%pre 渲染不完整: 注入文件缺失或 @ARCH@ 未替换"
        return 1
    fi
    if ! grep -q 'LOGINFO()' "${STAGE_DIR}/rpm-scripts/postinstall"; then
        LOGERROR "%post 渲染不完整: lib_min.sh 未注入"
        return 1
    fi

    # ---------- 4.5 python 主.次版本与真实环境的一致性断言 ----------
    # py_mm 由 environment.yml 文本正则抠出, 而真实目录名由 conda 解析结果决定,
    # 二者漂移会让产物自检 need_file 里锚定 python<MM> 的条目 (base.yml 等)
    # 指向不存在的路径
    local env_py_dir site_dir
    env_py_dir="$(find "${STAGE_DIR}/payload/home/tsc/tsc_python/envs/tsc_python/lib" \
        -maxdepth 1 -type d -name "python${py_mm}" -print -quit 2>/dev/null)"
    site_dir="${env_py_dir}/site-packages/ansible/config"
    if [[ -z "${env_py_dir}" || ! -d "${site_dir}" ]]; then
        LOGERROR "python 版本 (${py_mm}) 与真实环境不符: 未找到 ${site_dir}"
        LOGERROR "请核对 environment.yml 的 python 版本与 conda 解析结果"
        return 1
    fi
    LOGINFO "python 主.次版本校验通过: python${py_mm}"

    # ---------- 5. 生成 nfpm 配置并打包 ----------
    local nfpm_config="${STAGE_DIR}/nfpm.yaml"
    sed -e "s|@VERSION@|${version}|g" \
        -e "s|@RELEASE@|${release}|g" \
        -e "s|@ARCH@|${ARCH}|g" \
        -e "s|@STAGE_DIR@|${STAGE_DIR}|g" \
        "${PACKAGING_DIR}"/nfpm.yaml.tmpl >"${nfpm_config}"

    # 渲染完整性断言: 模板新增占位符而 build.sh 漏配 -e 时, 产物会带着字面量
    # @XXX@ 静默出包 (nfpm 侧只会报路径不存在, 与真实原因相距很远)
    if grep -qE '@[A-Z][A-Z_]*@' "${nfpm_config}"; then
        LOGERROR "nfpm.yaml 存在未替换的占位符:"
        grep -nE '@[A-Z][A-Z_]*@' "${nfpm_config}" >&2
        return 1
    fi

    mkdir -p "${RELEASE_DIR}"
    # 只清同 NVR 目标文件 (秒级时间戳下几乎不触发, 防覆盖不完整):
    # 不再打包前全删旧产物——nfpm 失败会把本机上一份可用 RPM 一并带走;
    # 旧产物改为打包成功后按 mtime 只保留最近 5 份 (见下方 section 7)
    rm -f "${release_file}" "${release_file}.sha256"

    LOGINFO "Build Start --> ${release_file}"
    "${NFPM_BIN}" package --packager rpm --config "${nfpm_config}" --target "${RELEASE_DIR}/"

    if [[ ! -f "${release_file}" ]]; then
        LOGERROR "未生成预期的产物 ${release_file}, release 目录现状:"
        ls -l "${RELEASE_DIR}" >&2
        return 1
    fi

    # ---------- 6. 产物自检 ----------
    if command -v rpm &>/dev/null; then
        local payload_files scripts_dump
        payload_files="$(rpm -qlp "${release_file}")"
        LOGINFO "Package info: $(rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}' "${release_file}")"
        LOGINFO "Requires: $(rpm -qp --qf '[%{REQUIRENAME} ]' "${release_file}")"
        LOGINFO "Payload:  $(wc -l <<<"${payload_files}") files"

        # 环境内含本地编译的二进制, 包架构必须与构建架构一致
        if [[ "$(rpm -qp --qf '%{ARCH}' "${release_file}")" != "${ARCH}" ]]; then
            LOGERROR "产物架构与构建架构不一致 (期望 ${ARCH})"
            return 1
        fi

        # 关键文件必须齐全
        # base.yml 以普通文件随批量安装树入包 (0.13.5 起放弃 %config(noreplace):
        # 升级由 rpm 覆盖为新版原版, %post 幂等重打解释器补丁);
        # patch_ansible.py 是 %post 改写 base.yml 的唯一手段;
        # build-info.json 是包内构建元数据; jq 随包供 yq 使用 (目标机未必自带)
        local need_file f
        need_file=(
            "/home/tsc/tsc_python/tsc_profile"
            "/home/tsc/tsc_python/tsc_python_profile"
            "/home/tsc/tsc_python/bin/micromamba"
            "/home/tsc/tsc_python/envs/tsc_python/bin/python3"
            "/home/tsc/tsc_python/envs/tsc_python/bin/ansible"
            "/home/tsc/tsc_python/envs/tsc_python/bin/jq"
            "/home/tsc/tsc_python/smoke_test.sh"
            "/home/tsc/tsc_python/patch_ansible.py"
            "/home/tsc/tsc_python/build-info.json"
            "/home/tsc/tsc_python/ansible/ansible.cfg"
            "/home/tsc/tsc_python/modules/tsc_python_changehostname/run.sh"
            "/home/tsc/tsc_python/envs/tsc_python/lib/python${py_mm}/site-packages/ansible/config/base.yml"
        )
        for f in "${need_file[@]}"; do
            if ! grep -qxF "${f}" <<<"${payload_files}"; then
                LOGERROR "产物缺少 ${f}"
                return 1
            fi
        done

        # 关键可执行文件必须带可执行位, 否则环境无法使用
        local need_exec
        need_exec=(
            "/home/tsc/tsc_python/bin/micromamba"
            "/home/tsc/tsc_python/envs/tsc_python/bin/jq"
            "/home/tsc/tsc_python/modules/tsc_python_changehostname/run.sh"
        )
        for f in "${need_exec[@]}"; do
            if ! rpm -qlpv "${release_file}" |
                awk -v p="${f}" '$NF == p && $1 == "-rwxr-xr-x" { found = 1 } END { exit !found }'; then
                LOGERROR "${f} 缺少可执行权限"
                return 1
            fi
        done

        # scriptlet 必须都写进包里 (nfpm 的 preremove/postremove 对应 rpm 的 %preun/%postun)
        scripts_dump="$(rpm -qp --scripts "${release_file}")"
        local needle
        for needle in "preinstall scriptlet" "postinstall scriptlet" \
            "preuninstall scriptlet" "postuninstall scriptlet"; do
            if ! grep -q "^${needle}" <<<"${scripts_dump}"; then
                LOGERROR "产物缺少 ${needle} 段"
                return 1
            fi
        done
    else
        LOGWARNING "打包机无 rpm 命令, 跳过产物自检"
    fi

    # ---------- 7. checksum 与清理 ----------
    (
        cd "${RELEASE_DIR}" || exit 99
        sha256sum "$(basename "${release_file}")" >"$(basename "${release_file}").sha256"
    )

    # 旧产物按 mtime 只保留最近 5 份 (含对应 .sha256): 打包失败路径不动旧产物,
    # 打包成功后在这里回收更旧的; 用 find 而非 glob 展开 (nullglob 下无匹配会
    # 令 ls 缺参转为列当前目录)。注意文件名里架构前是 '.' 不是 '-'
    # (tsc_python-<version>-<release>.<arch>.rpm)
    local keep=5 old_rpm
    while IFS= read -r old_rpm; do
        rm -f "${old_rpm}" "${old_rpm}.sha256"
        LOGINFO "回收旧产物 (超出保留 ${keep} 份): ${old_rpm}"
    done < <(find "${RELEASE_DIR}" -maxdepth 1 -type f -name "tsc_python-*.${ARCH}.rpm" \
        -printf '%T@\t%p\n' | sort -rn | tail -n +$((keep + 1)) | cut -f2-)

    LOGINFO "Size:    $(du -h "${release_file}" | cut -f1)"
    LOGINFO "SHA256:  $(sha256sum "${release_file}" | cut -d' ' -f1)"

    LOGSUCCESS "Build Over --> ${release_file}"

    # 成功路径: 显式回收 stage 并复位 RETURN trap (见函数头注释), 失败路径仍由 trap 覆盖
    rm -rf "${STAGE_DIR}"
    trap - RETURN
    return 0
}

# ─────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────
LOGINFO "TSC Python Local Build | Arch: ${ARCH} | Micromamba: ${micromamba_version}"
[[ -n "${python_version}" ]] && LOGINFO "Python version override: ${python_version}"

build_target || { LOGERROR "Build failed"; exit 1; }
package_rpm || { LOGERROR "RPM packaging failed"; exit 1; }

LOGSUCCESS "Build completed successfully"
LOGINFO "RPM directory: ${RELEASE_DIR}"
ls -lh "${RELEASE_DIR}/" 2>/dev/null || true
