# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Hek <hektorwang@gmail.com>
import ansible
import yaml
from pathlib import Path

ansible_package_path = Path(ansible.__file__).parent

base_yml_path = ansible_package_path / "config" / "base.yml"
with open(base_yml_path, "r", encoding="utf-8") as f:
    config = yaml.safe_load(f)

tsc_interpreter = [
    "/home/tsc/tsc_tools/micromamba/envs/tsc_python/bin/python3",
    "/home/tsc/.pyenv/shims/python3",
    "/home/tsc/miniconda3/envs/tsc_python/bin/python3",
]

fallback_list = config["INTERPRETER_PYTHON_FALLBACK"]["default"]

# 只插入尚不存在的路径, 重复安装时保持幂等
new_entries = [p for p in tsc_interpreter if p not in fallback_list]
if not new_entries:
    print("patch_ansible: interpreter paths already present, skip")
    raise SystemExit(0)

fallback_list[0:0] = new_entries

with open(base_yml_path, "w", encoding="utf-8") as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)

print(f"patch_ansible: inserted {len(new_entries)} interpreter paths")
