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
        LOGWARNING "check_glibc_baseline: 缺少 objdump, 跳过 ABI 门限检查"
        return 0
    fi
    max_glibc="$(find "${MICROMAMBA_DIR}" -type f \( -name '*.so*' -o -path '*/bin/*' \) -size +10k |
        while read -r f; do
            head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
            objdump -T "$f" 2>/dev/null
        done |
        grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -n1)" || true
    if [[ -z "${max_glibc}" ]]; then
        LOGWARNING "check_glibc_baseline: 未扫描到 ELF 符号, 跳过"
        return 0
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
    local overlap
    overlap="$("${py}" - <<'PYEOF' 2>/dev/null || true
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
if site.is_dir():
    for dist_info in sorted(site.glob("*.dist-info")):
        installer = dist_info / "INSTALLER"
        if not installer.is_file():
            continue
        who = installer.read_text().strip().lower()
        if who not in ("pip", "uv"):
            continue
        name = dist_info.name.split("-")[0].lower().replace("-", "_")
        if name in conda_names:
            overlap.append("{} (installer={})".format(name, who))

print("\n".join(overlap))
PYEOF
)"
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
#   tsc_python/profile                  本包 drop-in 源 (%post 部署为 tsc_profile.d/01-tsc_python-profile.sh)
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
        "${WORK_DIR}"/readme.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.md \
        "${WORK_DIR}"/THIRD_PARTY_NOTICES.zh_CN.md \
        "${WORK_DIR}"/smoke_test.sh \
        "${WORK_DIR}"/patch_ansible.py \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/

    # profile 公共入口模板 + 本包 drop-in 源 (由 %post 部署到 /home/tsc 下)
    \cp "${WORK_DIR}"/tsc_profile "${WORK_DIR}"/profile "${PAYLOAD_DIR}"/home/tsc/tsc_python/
    chmod 0644 "${PAYLOAD_DIR}"/home/tsc/tsc_python/tsc_profile \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/profile

    # ansible 配置与 roles (随本包装在 tsc_python 树下, 与 tsc_tools 解耦)
    \cp -r "${WORK_DIR}"/ansible "${PAYLOAD_DIR}"/home/tsc/tsc_python/ansible

    # 插件模块 (本包独占目录, 避免与 tsc_tools 的 modules 命名空间冲突)
    mkdir -p "${PAYLOAD_DIR}"/home/tsc/tsc_python/modules
    \cp -r "${WORK_DIR}"/modules/* "${PAYLOAD_DIR}"/home/tsc/tsc_python/modules/

    # 可执行位: 模块入口与冒烟测试 (防打包/拷贝过程丢失)
    # 同时把环境内二进制归一化到 0755: 构建容器 umask 002 会让它们带上组写位 (0775),
    # 共享目录 /home/tsc 下 root 所有的二进制保持 0755 更干净, 也让产物自检不依赖构建机 umask
    chmod 0755 "${PAYLOAD_DIR}"/home/tsc/tsc_python/bin/* \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/envs/tsc_python/bin/* \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/modules/*/run.sh \
        "${PAYLOAD_DIR}"/home/tsc/tsc_python/smoke_test.sh

    LOGINFO "Payload: ${PAYLOAD_DIR} ($(find "${PAYLOAD_DIR}" -type f | wc -l) files)"
}

##################################################
# 把 ansible 的 base.yml 移出安装树, 单独暂存
#
# patch_ansible.py (%post) 会改写该文件注入解释器回退列表; 若它随普通文件进包,
# 升级时会被包内原版覆盖, 丢失现场修补 (rpm -V 也会持续报差异, 虽属预期但扰民)。
# 改为在构建侧移出批量拷贝的安装树, 由 build.sh 以 %config(noreplace) 单独声明,
# 升级即保留现场已改写版本。
##################################################
stage_ansible_base() {
    local base_yml
    base_yml="$(find "${PAYLOAD_DIR}" -path '*/ansible/config/base.yml' -print -quit 2>/dev/null)"
    if [[ -z "${base_yml}" ]]; then
        LOGWARNING "stage_ansible_base: 未找到 ansible base.yml, 跳过"
        return 0
    fi
    mkdir -p "${OUTPUT_DIR}/staged"
    \cp -f "${base_yml}" "${OUTPUT_DIR}/staged/ansible_base.yml"
    \rm -f "${base_yml}"
    if [[ -e "${base_yml}" ]]; then
        LOGERROR "stage_ansible_base: 未能从安装树删除 ${base_yml}"
        exit 1
    fi
    LOGINFO "stage_ansible_base: ${base_yml} -> ${OUTPUT_DIR}/staged/ansible_base.yml"
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

version="$(grep -oP "^\s*(#+)?\s*Version=\s*?\K\S+$" "${WORK_DIR}"/release-note.md | head -n1)"

system_info="$(detect_system_info)"
build_arch="$(echo "${system_info}" | jq -r .machine_architecture)"

# 版本元数据取自真实安装产物 (而非构建参数自报), 保证元数据与包内容一致
PYTHON_VERSION="$("${MICROMAMBA_DIR}/envs/tsc_python/bin/python" --version 2>/dev/null | awk '{print $2}')"
MICROMAMBA_VERSION="$("${MICROMAMBA_DIR}/bin/micromamba" --version 2>/dev/null)" || true
PYTHON_VERSION="${PYTHON_VERSION:-unknown}"
MICROMAMBA_VERSION="${MICROMAMBA_VERSION:-unknown}"

mkdir -p "${OUTPUT_DIR}"

check_glibc_baseline
check_pip_conda_overlap
prepare_payload
stage_ansible_base
write_build_info

LOGSUCCESS "Payload ready: ${PAYLOAD_DIR}"
