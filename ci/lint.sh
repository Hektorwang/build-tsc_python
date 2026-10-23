#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
#
# 轻量静态检查 (CI 与本地通用): shellcheck + bash -n
#
# 覆盖范围:
#   - 一方 shell 脚本: build.sh / files/pack.sh / files/smoke_test.sh / files/modules/*/run.sh
#     (files/func 为 tsc_tools 同源的分发函数库, 不在本仓审查范围)
#   - 四段 RPM scriptlet: 模板先按 build.sh 的同一语义渲染 (INJECT 注入 + @ARCH@ 替换),
#     再 bash -n / shellcheck——渲染产物才是装到目标机上的东西
#
# 用法: bash ci/lint.sh
# 退出码: 0=全部通过, 1=存在失败项
# 注意: 本地无 shellcheck 时该项降级为跳过 (打印 WARN); CI 中为强制项
set -o pipefail

WORK_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
rc=0

fail() {
    echo "[lint] FAIL: $*" >&2
    rc=1
}

have_shellcheck=0
if command -v shellcheck &>/dev/null; then
    have_shellcheck=1
else
    echo "[lint] WARN: shellcheck 不可用, 跳过 shellcheck 检查 (CI 中为强制项)" >&2
fi

check_script() {
    local f="$1"
    bash -n "${f}" || fail "bash -n: ${f}"
    if ((have_shellcheck)); then
        # -S warning: 过滤 style 级噪音, 保留 warning 及以上
        shellcheck -S warning "${f}" || fail "shellcheck: ${f}"
    fi
}

# ---------- 1. 一方脚本 ----------
shopt -s nullglob
first_party=(
    "${WORK_DIR}/build.sh"
    "${WORK_DIR}/files/pack.sh"
    "${WORK_DIR}/files/smoke_test.sh"
    "${WORK_DIR}"/files/modules/*/run.sh
)

for f in "${first_party[@]}"; do
    check_script "${f}"
done

# ---------- 2. scriptlet (渲染后检查) ----------
tmp="$(mktemp -d)" || { echo "[lint] mktemp 失败" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT

# 与 build.sh 的 render_template 同一写法: 静默注入失败的防御由 build.sh 打包期断言兜底,
# 此处仅为语法检查, 不重复断言
render() {
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

render "${WORK_DIR}/packaging/rpm/preinstall.sh.tmpl" "${tmp}/preinstall"
render "${WORK_DIR}/packaging/rpm/postinstall.sh.tmpl" "${tmp}/postinstall"
cp "${WORK_DIR}/packaging/rpm/preremove.sh" "${tmp}/preremove"
cp "${WORK_DIR}/packaging/rpm/postremove.sh" "${tmp}/postremove"
sed -i "s|@ARCH@|x86_64|g" "${tmp}/preinstall"

for f in "${tmp}"/*; do
    check_script "${f}"
done

if ((rc)); then
    echo "[lint] 未通过" >&2
    exit 1
fi
echo "[lint] 通过 (shellcheck=$([[ ${have_shellcheck} -eq 1 ]] && echo on || echo off), $((${#first_party[@]} + 4)) 个脚本)"
exit 0
