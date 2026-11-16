#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
# 容器内打包脚本: 组装 RPM 打包源 (payload)、glibc 门限检查与构建元数据生成
#
# 本脚本只负责"产出安装树", 不打 RPM: RPM 由宿主机 build.sh 用 nfpm 打包
# (nfpm 不必进入构建容器, 且宿主机可直接对产物做 rpm -q 自检)。
# 产物:
#   output/payload/home/tsc/...  安装树 (相对 /home/tsc, 与 nfpm 的 dst 对应)
#   output/payload/home/tsc/tsc_python/build-info.json  构建元数据 (随包分发)
set -o errexit
set -o nounset
set -o pipefail
set +o posix
shopt -s nullglob

WORK_DIR="$(dirname "$(readlink -f "$0")")"
TSC_HOME_DIR="/home/tsc"
# 环境本体根目录: mamba root + envs/tsc_python, 同时也是随包文档/工具的落点
MICROMAMBA_DIR="${TSC_HOME_DIR}/tsc_python"
OUTPUT_DIR="${WORK_DIR}/output"
PAYLOAD_DIR="${OUTPUT_DIR}/payload"
export MAMBA_ROOT_PREFIX="${MICROMAMBA_DIR}"

source "${WORK_DIR}/func"

readonly GLIBC_BASELINE="2.17"

# glibc 符号门限: 包内所有 ELF 的最高 GLIBC_ 要求不得超过基线 (2.17 = CentOS 7)。
# 超标说明有产物在更新的容器中被源码编译, 将无法在 CentOS 7 上运行。
check_glibc_baseline() {
    local max_glibc
    if ! command -v objdump &>/dev/null; then
        # 基线不可判定时必须禁止出包: "跳过"会让超标产物静默流入现场, 而现场机器
        # 只会在运行期以 `version GLIBC_2.xx not found` 的形式暴露
        LOGERROR "check_glibc_baseline: 缺少 objdump, 无法校验 glibc 基线, 禁止出包"
        exit 1
    fi
    # ! -type d (而非 -type f): conda 环境里大量 .so 是软链 (libfoo.so -> libfoo.so.1),
    # 只扫常规文件会漏掉它们身上的 GLIBC_ 符号要求
    # -size +0c (而非 +10k): 体积小的 ELF 同样可能带高版本符号, 体积过滤不是安全筛子
    max_glibc="$(find "${MICROMAMBA_DIR}" ! -type d -size +0c \( -name '*.so*' -o -path '*/bin/*' \) |
        while read -r f; do
            head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
            objdump -T "$f" 2>/dev/null
        done |
        grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -n1)" || true
    if [[ -z "${max_glibc}" ]]; then
        LOGERROR "check_glibc_baseline: 未扫描到任何 ELF 符号, 无法判定基线, 禁止出包"
        exit 1
    fi
    LOGINFO "check_glibc_baseline: 环境最高 glibc 符号要求 = ${max_glibc} (基线 ${GLIBC_BASELINE})"
    # version_ge max baseline: max >= baseline 时为真; 与基线相等属正常, 超过才拦截
    if version_ge "${max_glibc}" "${GLIBC_BASELINE}" && [[ "${max_glibc}" != "${GLIBC_BASELINE}" ]]; then
        LOGERROR "check_glibc_baseline: 门限超标 (需要 glibc ${max_glibc} > 基线 ${GLIBC_BASELINE}), 禁止出包"
        exit 1
    fi
    LOGSUCCESS "check_glibc_baseline"
}

##################################################
# pip/conda 双层边界断言: pip 层不得安装 conda 已提供的包
#
# 边界规则: conda 已提供的一切 (原生库 + conda 也有的纯 python 包) 一律由 conda 层提供,
# pip 层只装 conda 没有的 (Dockerfile 在 uv pip install 前过滤)。本断言是兜底——
# 锁文件与 conda 解析各自演进, 一旦漂移, pip 会装上 conda 已有包并覆盖其构建版
# (典型风险: openssl ABI 不匹配), 此时禁止出包。
#
# 判定方法: site-packages 下每个 *.dist-info/INSTALLER 记录安装者——
# conda 装的写 "conda", pip/uv 装的写 "pip"/"uv"。若某包安装者是 pip/uv,
# 而同名包在 conda-meta 里有条目, 即视为越界。
##################################################
check_pip_conda_overlap() {
    local py="${MICROMAMBA_DIR}/envs/tsc_python/bin/python3"
    if [[ ! -x "${py}" ]]; then
        LOGWARNING "check_pip_conda_overlap: 找不到 ${py}, 跳过"
        return 0
    fi
    local overlap rc=0
    # 不做 `2>/dev/null || true`: 那会让解释器损坏 / heredoc 异常等任何失败都变成空串,
    # 使这条"构建期兜底断言"恒为通过 (fail-open)。扫描失败 = 边界未经验证 = 禁止出包
    overlap="$("${py}" - <<'PYEOF'
import json
import pathlib
import sys

env = pathlib.Path(sys.prefix)
site = env / "lib" / "python{}.{}".format(*sys.version_info[:2]) / "site-packages"

conda_names = set()
conda_meta = env / "conda-meta"
if conda_meta.is_dir():
    for meta in conda_meta.glob("*.json"):
        try:
            name = json.loads(meta.read_text()).get("name", "")
        except Exception:
            continue
        conda_names.add(name.lower().replace("-", "_"))

overlap = []
scanned = 0
if not site.is_dir():
    sys.stderr.write("site-packages not found: {}\n".format(site))
    sys.exit(2)
for dist_info in sorted(site.glob("*.dist-info")):
    installer = dist_info / "INSTALLER"
    if not installer.is_file():
        continue
    scanned += 1
    who = installer.read_text().strip().lower()
    if who not in ("pip", "uv"):
        continue
    name = dist_info.name.split("-")[0].lower().replace("-", "_")
    if name in conda_names:
        overlap.append("{} (installer={})".format(name, who))

if scanned == 0:
    # 一个都没扫到通常意味着判定方法失效 (如 uv 版本不再写 INSTALLER),
    # 此时"无重叠"是假阴性, 必须拦下而不是放行
    sys.stderr.write("no dist-info with INSTALLER found under {}\n".format(site))
    sys.exit(3)

sys.stderr.write("scanned {} dist-info\n".format(scanned))
print("\n".join(overlap))
PYEOF
)" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        LOGERROR "check_pip_conda_overlap: 扫描失败 (rc=${rc}), pip/conda 分层边界未经验证"
        exit 1
    fi
    if [[ -n "${overlap}" ]]; then
        LOGERROR "check_pip_conda_overlap: pip 层安装了 conda 已提供的包:"
        LOGERROR "${overlap//$'\n'/ }"
        LOGERROR "conda 已提供的一律由 conda 层提供, pip 只装 conda 没有的;"
        LOGERROR "请在 Dockerfile 的 pip 过滤列表补充该项, 或改由 environment.yml 提供"
        exit 1
    fi
    LOGSUCCESS "check_pip_conda_overlap"
}

##################################################
# 组装 RPM 打包源
#
# 目录布局与目标机一致 (相对 /home/tsc):
#   tsc_python/                         环境本体根目录 (mamba root + envs/tsc_python)
#   tsc_python/<docs>                   随包文档与工具
#   tsc_python/tsc_profile              tsc_profile 公共入口模板 (%post 在首次安装时部署)
#   tsc_python/tsc_python_profile      本包 drop-in 源 (%post 部署为 tsc_profile.d/01-tsc_python-profile.sh)
#   tsc_python/ansible/                ansible.cfg / hosts / roles
#   tsc_python/modules/tsc_python_*/   插件模块 (由本包独占目录, 与 tsc_tools 自有 modules 解耦)
##################################################
prepare_payload() {
    LOGINFO "${FUNCNAME[0]}"

    # 清理缓存
    find "${MICROMAMBA_DIR}" -type d -name "__pycache__" -exec rm -rf {} +
    rm -rf "${MICROMAMBA_DIR}"/pkgs

    # 创建 payload 根 (mv 目标父目录必须存在)
    mkdir -p "${PAYLOAD_DIR}/home/tsc"

    # 环境本体直接移动而非拷贝: 体积 1G+ 且多为硬链接, 拷贝既慢又容易翻倍
    mv "${MICROMAMBA_DIR}" "${PAYLOAD_DIR}/home/tsc/tsc_python"

    # 随包文档与工具
    \cp "${WORK_DIR}"/release-note.md \
        "${WORK_DIR}"/README.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.zh_CN.md \
        "${WORK_DIR}"/smoke_test.sh \
        "${WORK_DIR}"/patch_ansible.py \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/

    # profile 公共入口模板 + 本包 drop-in 源 (由 %post 部署到 /home/tsc 下)
    \cp "${WORK_DIR}"/tsc_profile "${WORK_DIR}"/tsc_python_profile "${PAYLOAD_DIR}"/home/tsc/tsc_python/
    chmod 0644 "${PAYLOAD_DIR}"/home/tsc/tsc_python/tsc_profile \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/tsc_python_profile

    # ansible 配置与 roles (随本包装在 tsc_python 树下, 与 tsc_tools 解耦)
    \cp -r "${WORK_DIR}"/ansible "${PAYLOAD_DIR}"/home/tsc/tsc_python/ansible

    # 插件模块 (本包独占目录, 避免与 tsc_tools 的 modules 命名空间冲突)
    mkdir -p "${PAYLOAD_DIR}"/home/tsc/tsc_python/modules
    \cp -r "${WORK_DIR}"/modules/* "${PAYLOAD_DIR}"/home/tsc/tsc_python/modules/

    # jq 静态二进制随包分发: yq 的硬依赖, 目标机未必自带 (EL7 无 jq 且 EPEL 已不可用)。
    # 放 envs/tsc_python/bin——激活后即在 PATH 上、与 yq 同目录; 不放 mamba root 的
    # bin/: micromamba activate 只把 root 的 condabin 挂上 PATH, root bin 并不在其中,
    # 放那里 yq 找不到。二进制为纯静态链接, 不引入额外 glibc 要求
    \cp /usr/local/bin/jq "${PAYLOAD_DIR}/home/tsc/tsc_python/envs/tsc_python/bin/jq"

    # 可执行位: 模块入口与冒烟测试 (防打包/拷贝过程丢失)
    # 同时把环境内二进制归一化到 0755: 构建容器 umask 002 会让它们带上组写位 (0775),
    # 共享目录 /home/tsc 下 root 所有的二进制保持 0755 更干净, 也让产物自检不依赖构建机 umask
    # find -exec 而非 glob 展开: nullglob 下 glob 无匹配时展开为空, chmod 无参数会报错退出
    find "${PAYLOAD_DIR}/home/tsc/tsc_python/bin" \
         "${PAYLOAD_DIR}/home/tsc/tsc_python/envs/tsc_python/bin" \
         -maxdepth 1 -type f -exec chmod 0755 {} +
    find "${PAYLOAD_DIR}/home/tsc/tsc_python/modules" \
         -name "run.sh" -exec chmod 0755 {} +
    chmod 0755 "${PAYLOAD_DIR}/home/tsc/tsc_python/smoke_test.sh"

    LOGINFO "Payload: ${PAYLOAD_DIR} ($(find "${PAYLOAD_DIR}" -type f | wc -l) files)"
}

##################################################
# 生成构建元数据 (随包分发, 便于现场核对包内容)
##################################################
write_build_info() {
    LOGINFO "${FUNCNAME[0]}"
    mkdir -p "${OUTPUT_DIR}"
    cat <<EOF >"${PAYLOAD_DIR}/home/tsc/tsc_python/build-info.json"
{
  "name": "tsc_python",
  "version": "${version}",
  "build": {
    "build_date": "${BUILD_DATE}",
    "timestamp": ${BUILD_TIMESTAMP},
    "architecture": "${build_arch}",
    "glibc_baseline": "${GLIBC_BASELINE}"
  },
  "python_version": "${PYTHON_VERSION}",
  "micromamba_version": "${MICROMAMBA_VERSION}"
}
EOF
    LOGSUCCESS "build-info.json: ${PAYLOAD_DIR}/home/tsc/tsc_python/build-info.json"
}

BUILD_DATE="$(date +%Y%m%d)"
BUILD_TIMESTAMP="$(date +%s)"

# 与宿主机 build.sh 的 RPM NVR 解析同一写法 (含同一锚定): 取 release-note.md 第一个
# "## Version=" 标题行并去空白。两处必须一致——build.sh 打包期会拿本文件产出的
# build-info.json 版本与 RPM 版本比对
version="$(awk '/^#+[[:space:]]*Version=/{sub(/^[^=]*=/, ""); print; exit}' "${WORK_DIR}"/release-note.md | tr -d '[:space:]')"

system_info="$(detect_system_info)"
build_arch="$(echo "${system_info}" | jq -r .machine_architecture)"

# 版本元数据取自真实安装产物 (而非构建参数自报), 保证元数据与包内容一致
# 两行都要 || true: python 缺失时管道在 pipefail 下返回非零, errexit 会在下一行
# 的 :-unknown 兜底生效之前就终止整个构建 (与 MICROMAMBA_VERSION 的写法保持一致)
PYTHON_VERSION="$("${MICROMAMBA_DIR}/envs/tsc_python/bin/python" --version 2>/dev/null | awk '{print $2}')" || true
MICROMAMBA_VERSION="$("${MICROMAMBA_DIR}/bin/micromamba" --version 2>/dev/null)" || true
PYTHON_VERSION="${PYTHON_VERSION:-unknown}"
MICROMAMBA_VERSION="${MICROMAMBA_VERSION:-unknown}"

mkdir -p "${OUTPUT_DIR}"

check_glibc_baseline
check_pip_conda_overlap
prepare_payload
write_build_info

LOGSUCCESS "Payload ready: ${PAYLOAD_DIR}"
