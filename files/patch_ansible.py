import yaml

import ansible
from pathlib import Path

ansible_package_path = Path(ansible.__file__).parent

base_yml_path = ansible_package_path / "config" / "base.yml"
with open(base_yml_path, "r", encoding="utf-8") as f:
    config = yaml.safe_load(f)

# alias ansible='ansible -e "ansible_interpreter_python_fallback=/home/tsc/tsc_tools/micromamba/envs/tsc_python/bin/python3:/home/tsc/.pyenv/shims/python3:python3.14:python3.13:python3.12:python3.11:python3.10:python3.9:/usr/bin/python3:python3"'

tsc_interpreter = [
    "/home/tsc/tsc_tools/micromamba/envs/tsc_python/bin/python3",
    "/home/tsc/.pyenv/shims/python3",
    "/home/tsc/miniconda3/envs/tsc_python/bin/python3",
]

fallback_list = config["INTERPRETER_PYTHON_FALLBACK"]["default"]

fallback_list[0:0] = tsc_interpreter

with open(base_yml_path, "w", encoding="utf-8") as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)

