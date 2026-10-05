#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
WORK_DIR="$(dirname "$(readlink -f "$0")")"
find "${WORK_DIR}" -type f -iname "readme.md" -exec glow {} +
