#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
#
# tsc_python 安装冒烟测试
#
# 用途: 在目标机安装 tsc_python 后, 验证环境可用性
#       (glibc 基线/核心包导入/运行时功能自检/ansible 实战/TLS)
# 用法: sh smoke_test.sh [--skip-network]
#       TSC_SMOKE_TLS_URL=<url> 可自定义 TLS 探测地址 (默认 https://mirrors.aliyun.com/pypi/simple/)
# 退出码: 0=通过(允许 WARN), 1=存在 FAIL, 2=找不到 python 环境
# 兼容: bash 4.2+ (CentOS 7), 自包含, 不依赖 func 库
#
# 结论口径:
#   PASS - 必须通过的核心项
#   WARN - 条件项 (无外网、已知不兼容组件等), 不影响整体结论
#   FAIL - 环境损坏或不满足运行基线

set -u
set -o pipefail

SKIP_NETWORK=0
for arg in "$@"; do
    case "$arg" in
        --skip-network) SKIP_NETWORK=1 ;;
        -h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $arg (用法见 $0 --help)" >&2; exit 2 ;;
    esac
done

# ---------- 自包含日志 (风格与 func 一致, 不依赖 func) ----------
C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_WARN=$'\033[1;33m'; C_END=$'\033[0m'
if [[ -t 1 ]]; then C_STD=""; else C_OK=""; C_ERR=""; C_WARN=""; C_END=""; fi

PASS=0; WARN=0; FAIL=0

section() { printf '\n######## %s ########\n' "$*"; }

report() {  # $1=PASS|WARN|FAIL|SKIP  $2=名称  $3=说明(可选)
    local st="$1" name="$2" detail="${3:-}" line
    line="[$st] $name"
    [[ -n "$detail" ]] && line="$line ($detail)"
    line="$(printf '%s | %-7s | %s' "$(date '+%F %T')" "$st" "$line")"
    case "$st" in
        PASS) PASS=$((PASS + 1)); printf '%b\n' "${C_OK}${line}${C_END}" ;;
        WARN) WARN=$((WARN + 1)); printf '%b\n' "${C_WARN}${line}${C_END}" >&2 ;;
        FAIL) FAIL=$((FAIL + 1)); printf '%b\n' "${C_ERR}${line}${C_END}" >&2 ;;
        SKIP) printf '%s\n' "$line" ;;
    esac
}

version_ge() {  # $1 >= $2 ?
    [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$1" ]] || [[ "$1" == "$2" ]]
}

import_check() {  # $1=module  $2=严重级别(FAIL|WARN)
    if "$PY" -c "import ${1}" >/dev/null 2>&1; then
        report PASS "import ${1}"
    else
        report "$2" "import ${1}"
    fi
}

# ---------- 定位 python 环境 ----------
ENV_ROOT="${MAMBA_ROOT_PREFIX:-/home/tsc/tsc_tools/micromamba}"
ENV_DIR="${ENV_ROOT}/envs/tsc_python"
PY="${ENV_DIR}/bin/python"
ENV_BIN="${ENV_DIR}/bin"

if [[ ! -x "${PY}" ]]; then
    if [[ -f /home/tsc/tsc_python_profile ]]; then
        source /home/tsc/tsc_python_profile
        PY="$(command -v python 2>/dev/null || true)"
        [[ -n "$PY" ]] && ENV_BIN="$(dirname -- "$PY")"
    fi
fi
if [[ -z "${PY:-}" || ! -x "${PY}" ]]; then
    printf '%b\n' "${C_ERR}未找到 tsc_python 环境 (尝试过 ${ENV_DIR}/bin/python 和 tsc_python_profile)${C_END}" >&2
    exit 2
fi

section "环境与系统信息"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '主机: %s %s | 架构: %s\n' "${NAME:-unknown}" "${VERSION_ID:-}" "$(uname -m)"
fi

host_glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
if [[ -n "$host_glibc" ]]; then
    printf '主机 glibc: %s (包基线 2.17)\n' "$host_glibc"
    if version_ge "$host_glibc" "2.17"; then
        report PASS "主机 glibc >= 2.17" "$host_glibc"
    else
        report FAIL "主机 glibc >= 2.17" "实际 ${host_glibc}, 低于包构建基线 2.17"
    fi
else
    report WARN "主机 glibc 检测" "getconf GNU_LIBC_VERSION 无输出"
fi

printf 'Python: %s\n' "$("$PY" --version 2>&1)"
printf 'OpenSSL: %s\n' "$("$PY" -c 'import ssl; print(ssl.OPENSSL_VERSION)' 2>/dev/null || echo '获取失败')"

section "核心包导入 (对齐当前包声明, 缺失即 FAIL)"
import_check sqlite3     FAIL
import_check ssl         FAIL
import_check yaml        FAIL
import_check jinja2      FAIL
# --- conda 层 (原生链接组件) ---
import_check cffi        FAIL
import_check cryptography FAIL
import_check bcrypt      FAIL
import_check nacl        FAIL
import_check OpenSSL     FAIL
import_check paramiko    FAIL
import_check psycopg2    FAIL
import_check cx_Oracle   FAIL
import_check pymysql     FAIL
import_check gssapi      FAIL
import_check requests    FAIL
import_check urllib3     FAIL
import_check invoke      FAIL
import_check certifi     FAIL
# --- pip 层 ---
import_check ansible     FAIL
import_check asyncssh    FAIL
import_check fastmcp     FAIL
import_check psutil      FAIL
import_check pexpect     FAIL
import_check watchdog    FAIL

section "Python 运行时功能自检"
rt_out="$("$PY" - <<'PYEOF'
import hashlib
import json
import sqlite3
import ssl
import zlib

# sqlite3 内存库读写
conn = sqlite3.connect(":memory:")
conn.execute("CREATE TABLE t (k TEXT PRIMARY KEY, v INTEGER)")
conn.executemany("INSERT INTO t VALUES (?, ?)", [("a", 1), ("b", 2)])
row = conn.execute("SELECT k, v FROM t WHERE k = 'b'").fetchone()
assert row == ("b", 2), f"sqlite3 查询结果异常: {row}"
conn.close()

# 哈希与压缩 (固定已知值, 验证 hashlib 计算正确)
assert hashlib.sha256(b"tsc").hexdigest() == (
    "5efcd711594e059d5f738c9068172914c1ad1b85c127a64d476bc81620401192"
), "sha256 计算结果异常"
assert zlib.decompress(zlib.compress(b"tsc_smoke" * 100)) == b"tsc_smoke" * 100

# ssl 上下文与 json
ctx = ssl.create_default_context()
assert json.loads(json.dumps({"ok": True})) == {"ok": True}

print(f"sqlite3/hashlib/zlib/ssl/json 自检通过")
PYEOF
)"; rc=$?
if [[ $rc -eq 0 ]]; then
    report PASS "运行时功能自检" "${rt_out}"
else
    report FAIL "运行时功能自检" "见上方 Python 报错"
fi

section "ansible 实战 (localhost ping, 验证解释器发现与模块执行)"
ANSIBLE_BIN="${ENV_BIN}/ansible"
if [[ -x "${ANSIBLE_BIN}" ]] || ANSIBLE_BIN="$(command -v ansible 2>/dev/null)"; then
    printf 'ansible: %s\n' "$("$ANSIBLE_BIN" --version 2>/dev/null | head -n1)"
    ping_out="$(timeout 120 "${ANSIBLE_BIN}" localhost -i 'localhost,' -c local -m ping 2>/dev/null || true)"
    if grep -q "pong" <<<"${ping_out}"; then
        report PASS "ansible localhost ping"
    else
        report FAIL "ansible localhost ping" "未收到 pong, 检查解释器发现(patch_ansible)与 jinja2"
    fi
else
    report FAIL "ansible 可执行文件" "未找到 ansible 命令"
fi

section "TLS 出网探测 (失败仅告警)"
if (( SKIP_NETWORK == 1 )); then
    report SKIP "TLS 出网探测" "已按 --skip-network 跳过"
elif tls_out="$("$PY" - <<'PYEOF'
import os
import socket
import urllib.request

socket.setdefaulttimeout(8)
url = os.environ.get("TSC_SMOKE_TLS_URL", "https://mirrors.aliyun.com/pypi/simple/")
req = urllib.request.Request(url, method="HEAD")
with urllib.request.urlopen(req) as resp:
    print("HTTP", resp.status)
PYEOF
)"; then
    report PASS "TLS 出网探测" "${tls_out}"
else
    report WARN "TLS 出网探测" "不通 (离线环境属正常, 用 TSC_SMOKE_TLS_URL 可指定内网源)"
fi

section "安装链路与外部依赖 (WARN 级)"
if [[ -f /home/tsc/tsc_python_profile ]]; then
    report PASS "tsc_python_profile 存在"
else
    report WARN "tsc_python_profile 存在" "/home/tsc/tsc_python_profile 未找到 (未按默认路径安装?)"
fi
if [[ -f /home/tsc/tsc_profile ]] && grep -q "tsc_python_profile" /home/tsc/tsc_profile; then
    report PASS "tsc_profile 已挂载 tsc_python_profile"
else
    report WARN "tsc_profile 已挂载 tsc_python_profile" "/home/tsc/tsc_profile 中缺少 source 行"
fi
if command -v jq >/dev/null 2>&1; then
    report PASS "jq 可用" "yq 依赖 jq"
else
    report WARN "jq 可用" "缺少 jq, yq 将无法工作 (工作环境规范应已提供)"
fi

section "汇总"
printf '%b\n' "${C_END}=========================================================${C_END}"
printf '冒烟测试完成: PASS=%d WARN=%d FAIL=%d\n' "$PASS" "$WARN" "$FAIL"
if (( FAIL > 0 )); then
    printf '%b\n' "${C_ERR}结论: 未通过 (存在 FAIL)${C_END}" >&2
    exit 1
fi
printf '%b\n' "${C_OK}结论: 通过${C_END}"
exit 0
