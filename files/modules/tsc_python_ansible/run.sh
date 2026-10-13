#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -o errexit
WORK_DIR="$(dirname "$(readlink -f "$0")")"

# glow 传文件路径时进 TUI 模式: 交互式终端下是想要的翻页效果, 但 stdout 非 TTY
# (管道 / 重定向 / 输出被上层脚本接管) 时静默输出空内容——实测 `tsc --模块` 在有
# TTY 时正常, 输出被接管时什么都看不到。这里按 TTY 分流, 非交互式直接输出原文,
# 保证任何调用方式都能看到文档。
show_readme() {
    local readme="$1"
    if [[ -t 1 ]] && command -v glow >/dev/null 2>&1; then
        glow "${readme}"
    else
        cat "${readme}"
    fi
}

show_readme "${WORK_DIR}"/"README.md
