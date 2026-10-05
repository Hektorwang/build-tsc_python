---
category: 主机管理
keywords:
  - 用户创建
  - ssh 信任
  - sudo
  - 免密码
  - 批量
  - ansible
description: 批量建立管理机到目标机的 root 信任; 批量创建业务用户并赋予免密码 sudo, 建立到业务用户的 ssh 信任; 支持校验与回收
usage: tsc --tsc_python_batch_user_manager
---

# 批量创建用户并建立 ssh 信任

## 功能

1. 建立管理机到目标机 `root` 用户的 ssh 信任 (`root` 标签).
2. 在管理机和目标机创建业务用户 `new_user`, 赋予免密码 sudo, 并建立管理机到目标机该用户的 ssh 信任 (`user` 标签).
3. 校验信任与免密码 sudo 的建立结果.
4. 回收上述信任, sudo 与用户.

## 环境依赖

1. 依赖于系统中已经部署了 `ansible`, 如系统中未部署 `ansible`, 可自行部署或安装 `tsc_python`.
2. 管理机以 `root` 身份执行.
3. 目标机需有 `python3` (>= 3.6), 或已安装 `tsc_python` / `tsc_tools-full`.
4. 适配 RHEL 系与 DEBIAN 系: 目标机缺少 `sudo` 时会尝试安装并显式报错, 不会静默跳过; SELinux enforcing 下自动修正 `.ssh` 上下文, 无需关闭 SELinux.

## 使用说明

配置 `/home/tsc/tsc_tools/ansible/hosts`, 将目标机信息写入 `hosts` 段, 并在 `[all:vars]` 段配置业务用户:

```ini
[hosts] # 只会对放在 hosts 组中的主机做操作
192.168.1.11 ansible_ssh_pass="该主机root用户密码" ansible_ssh_port="该主机ssh服务端口"
192.168.1.12 ansible_ssh_pass="该主机root用户密码" ansible_ssh_port="该主机ssh服务端口"

[all:vars]
ansible_user=root
# 需新建的业务用户名和初始密码, 仅本模块使用
new_user="product"
new_user_psw="该用户的初始密码"
```

在管理机上运行, `--tags` 选择执行范围 (`root`=仅第 1 项, `user`=仅第 2 项, 不带参数为全部):

```bash
source /home/tsc/tsc_profile

# 建立 (建立后自动执行 batch_user_manager_check.yml 校验效果更佳)
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/batch_user_manager_create.yml [--tags root|user]

# 校验
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/batch_user_manager_check.yml [--tags root|user]

# 回收
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/batch_user_manager_delete.yml [--tags root|user]
```

check 剧本使用 `BatchMode` 强制仅凭密钥连接, 不会因密码可用而误判:

- `localhost`: 业务用户存在, 私钥在位
- `hosts` (`root`): 仅凭密钥以 `root` 连接成功
- `hosts` (`user`): 仅凭密钥以 `new_user` 连接成功, 且 `sudo` 免密码提权到 `root`

## 注意事项

!!! 注意, 目标机或管理机上已存在同名的 `new_user` 时, 该用户会受到如下影响 !!!
!!! 注意, 目标机或管理机上已存在同名的 `new_user` 时, 该用户会受到如下影响 !!!
!!! 注意, 目标机或管理机上已存在同名的 `new_user` 时, 该用户会受到如下影响 !!!

- 用户密码被重置为 `new_user_psw`
- 用户家目录调整为 `/home/${new_user}`
- 管理机上已存在该用户的 `~/.ssh/id_rsa` 与 `~/.ssh/authorized_keys` 时继续使用, 否则新生成

其他:

1. `new_user_psw` 明文保存在 inventory 中, 注意控制文件权限
2. 目标机 `root` 密码登录被禁用 (`PermitRootLogin prohibit-password`) 时, 无法通过密码引导建立信任, 需先经控制台处理
