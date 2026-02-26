# Ansible 批量管理简介

## Ansible inventory 配置样例

### 现场机器情况示例

假设现场有 13 台机器:

| 机器 IP      | 机器角色      | SSHD 端口                     | SSH 用户                       | SSH 密码                                     |
| ------------ | ------------- | ----------------------------- | ------------------------------ | -------------------------------------------- |
| 192.168.1.11 | 系统 A 角色 1 | 2222                          | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.12 | 系统 A 角色 2 | 2222                          | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.13 | 系统 A 角色 2 | 2222                          | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.14 | 系统 A 角色 3 | 2222                          | root                           | <font color=blue>FxxF@fh#0025</font>         |
| 192.168.1.15 | 系统 A 角色 3 | 2222                          | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.16 | 系统 A 角色 2 | 2222                          | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.17 | 系统 A 角色 2 | <font color=blue>60022</font> | root                           | 1.2,3m!9%@FH                                 |
| 192.168.1.18 | 角色 4        | 2222                          | root                           | <font color=blue>已做信任，不提供密码</font> |
| 192.168.1.19 | 角色 4        | 2222                          | root                           | <font color=blue>已做信任，不提供密码</font> |
| 192.168.1.20 | 角色 4        | 2222                          | root                           | <font color=blue>已做信任，不提供密码</font> |
| 192.168.1.21 | 角色 5        | 2222                          | <font color=blue>yunwei</font> | 1.2,3m!9%@FH                                 |
| 192.168.1.22 | 角色 5        | 2222                          | <font color=blue>yunwei</font> | 1.2,3m!9%@FH                                 |
| 192.168.1.23 | 角色 5        | 2222                          | <font color=blue>yunwei</font> | 1.2,3m!9%@FH                                 |

> <font color=red>备注: yunwei 用户具有 sudo 权限.</font>

### inventory 配置文件样例及详解

Ansible inventory 文件是 Ansible 中的一个核心组件, 它定义了 Ansible 可以连接和控制的机器列表, 具有如下特点:

- 可以将多台主机组织成组, 按组对主机进行批量管理.
- 可以创建组的组 (也称为父组), 通过使用 `:children` 后缀来定义更复杂的组层次结构.
- 不仅可以列出主机, 还可以包括变量、连接信息、组的层次结构和组的变量等.

如下是 INI 格式的 inventory 文件样例:

```ini
# 定义机器组-角色1
[r1]
# 机器组包含 192.168.1.11 共 1 台机器
192.168.1.11

# 定义机器组-角色2
[r2]
# 机器组包含 192.168.1.12-192.168.1.13 和 192.168.1.16-192.168.1.17 共 4 台机器
192.168.1.[12:13]
192.168.1.[16:17]
# 这台节点的 sshd 端口不同, 在这里进行单节点变量设置, 覆盖下面的组变量 [all:vars] -> ansible_ssh_port 中设置
192.168.1.17 ansible_ssh_port="60022"

# 定义机器组-角色3
[r3]
# 机器组包含 192.168.1.14-192.168.1.15 共 2 台机器
# 这台节点的 ssh 密码不同, 在这里进行单节点变量设置, 覆盖下面的组变量 [sysa:vars] -> ansible_ssh_pass 中设置
192.168.1.14 ansible_ssh_pass="FxxF@fh#0025"
192.168.1.15

# 定义机器组-系统a
[sysa:children]
# 机器组 (父组) 包含 r1,r2,r3 这三个子组
# 机器组包含 192.168.1.11-192.168.1.17 共 7 台机器
r1
r2
r3

# 以 [组名:vars] 标识的是对这个组和其子组都生效的变量
# 定义变量-系统a机器组, 这个组的变量对它的三个子组也生效
[sysa:vars]
# 机器 SSH 密码
ansible_ssh_pass="1.2,3m!9%@FH"

# 定义机器组-角色4
[r4]
# 机器组包含 192.168.1.18-192.168.1.20 共 3 台机器
192.168.1.[18:20]

# 定义机器组-角色5
[r5]
# 机器组包含 192.168.1.21-192.168.1.23 共 3 台机器
192.168.1.[21:23]

# 定义变量-r5机器组
[r5:vars]
# 机器 SSH 用户
ansible_ssh_user="yunwei"
# 提权 (sudo) 时使用的密码
ansible_become_pass="1.2,3m!9%@FH"
# 启用提权机制 (sudo)
ansible_become=yes

# 定义变量-本文件包含的所有机器
[all:vars]
# 机器 SSH 用户
ansible_ssh_user="root"
# 机器 SSHD 端口
ansible_ssh_port="2222"
```

### 变量作用域和优先级

- `[all:vars]` 中定义变量 `ansible_ssh_port="2222"`, 端口定义覆盖整个文件 (所有机器), 作用域最大, 但优先级最低.

- `[r2]` 中定义机器并指定变量 `192.168.1.17 ansible_ssh_port="60022"`, 端口定义只针对 `192.168.1.17` 这一台机器, 作用域最小, 但优先级最高.

综上所述, Ansible 在解析 inventory 文件时, 会认为 `192.168.1.17` 的 sshd 端口为 60022, 而其他机器的 sshd 端口为 2222.

## ansible 批量执行命令

### 配置 inventory 文件

### 命令格式

```bash
ansible -i <path_to_inventory_file> <组名/IP> -m 模块名称 -a '参数'
```

### 批量执行命令示例

如果使用操作系统包管理器安装的 ansible, 可直接使用 ansible 命令, 如果使用 tsc_tools-full 或 tsc_python 中集成的 ansible, 需先导入环境变量

```bash
source /home/tsc/tsc_profile
ansible <commands>
```

#### 批量测试机器 SSH 连通性:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts all -m ping
# 参数选项:
# all: 指代 inventory 文件中配置的所有机器. 等效写法: '*' 或 "*" 或 \*
# -m ping: 指定使用 ping 模块

# 输出返回:
# SUCCESS 和 "ping": "pong" 代表连通性正常
# UNREACHABLE 代表连通性异常
```

#### 批量查看机器 CPU 架构:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts r1 -m shell -a "arch"
# 参数选项:
# r1: 指代 r1 机器组
# -m shell: 指定使用 shell 模块
# -a "arch": 指定传递给 shell 模块的参数, 这里传递的命令是 arch, 会在远程主机上执行 arch 命令
```

#### 批量查看机器最近 15 分钟内的平均负载:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts 192.168.1.11,192.168.1.13 -m shell -a "uptime | awk '{print \$NF}'"

# 参数选项:
# 192.168.1.11,192.168.1.13: 这里指定了两台主机, 使用逗号分隔

# 注意事项:
# -a 参数中的 $ 可能需要使用 \ 转义
```

#### 查看单机平均负载信息:

```bash
ansible /home/tsc/tsc_tools/ansible/hosts 192.168.1.11 -m shell -a "uptime"
```

批量执行脚本:

```bash
# cat /tmp/1.sh
#!/bin/bash
uptime
```

```bash
ansible /home/tsc/tsc_tools/ansible/hosts sysa,r4 -m script -a '/tmp/1.sh'

# 参数选项:
# sysa,r4: 这里指定了两个机器组, 使用逗号分隔
# -m script: 指定使用 script 模块
# -a '/tmp/1.sh': Ansible 会将本机 /tmp/1.sh 脚本文件自动批量分发到用户指定的机器并执行该脚本文件
```

## tsc_ansible 批量拷贝文件

### 配置 inventory 文件

### 批量拷贝文件示例

#### 从控制节点拷贝文件到远程主机:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts r4 -m copy -a "src=/root/anaconda-ks.cfg dest=/tmp/"
# 参数选项:
# r4: 指代角色4机器组

# 实现效果:
# 将本机 /root/anaconda-ks.cfg 批量拷贝到远程主机的 /tmp 目录下
```

#### 从控制节点拷贝文件到远程主机:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts 192.168.1.12,192.168.1.17 -m copy -a "src=/etc/fstab dest=/tmp/fstab_backup mode=0644 owner=root group=root"
# 参数选项:
# 92.168.1.12,192.168.1.17: 这里指定了两台主机, 使用逗号分隔

# 实现效果:
# 将本机 /etc/fstab 文件批量拷贝到远程主机的 /tmp/ 目录下, 并且文件名设置为 fstab_backup, 文件权限设置为 0644, 文件的属主和属组均设置为 root
```

#### 指定文件内容在远程主机上创建文件:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts '*' -m copy -a "content='* * * * * root /sbin/ntpdate 172.17.1.100' dest=/etc/cron.d/ntpdate_cron"
# 参数选项:
# '*': 指代 inventory 文件中配置的所有机器. 等效写法: all 或 "*" 或 \*

# 实现效果:
# 在远程主机上创建文件 /etc/cron.d/ntpdate_cron, 文件内容是 "* * * * * root /sbin/ntpdate 172.17.1.100"
```

#### 从远程主机拷贝文件到控制节点:

```bash
ansible -i /home/tsc/tsc_tools/ansible/hosts \* -m fetch -a 'src=/etc/hosts dest=/tmp/{{ inventory_hostname }}_hosts flat=yes'
# 参数选项:
# \*: 指代 inventory 文件中配置的所有机器. 等效写法: all 或 "*" 或 '*'
# flat=yes 表示不会复制文件的远程目录结构, 只将文件本身保存到用户指定的目录

# 注意事项:
# {{ inventory_hostname }} 是一个 Ansible 特殊变量, 代表当前任务运行的远程主机的名称
# flat=yes 不复制远程目录结构, 最终拷贝过来的文件形如 "/tmp/172.17.14.12_hosts"
# flat=false 复制远程目录结构, 最终拷贝过来的文件理论上形如 "/tmp/172.17.14.12_hosts/172.17.14.12/etc/hosts", 需要注意的是该应用场景下 Ansible 无法自动递归创建目录, 所以您可能会发现执行报错: "Unable to create local directories(/tmp/172.17.14.12_hosts/172.17.14.12/etc)"

# 实现效果:
# 将远程主机的 /etc/hosts 文件批量拷贝到本机 /tmp 目录下, 文件命名成 "远程主机名称_hosts"
```
