# 批量建立主机 root 用户的 ssh 信任

## 环境依赖

依赖于系统中已经部署了 `ansible` 程序, 如系统中未部署 `ansible`, 可自行部署或安装 `tsc_python`

## 使用说明

配置 `/home/tsc/tsc_tools/ansible/hosts`, 将需要信任本机的主机信息写入 hosts 段
如要设置本机 ssh 到 `root@192.168.1.1` 不需要输入密码

```ini
[hosts] # 只会对放在 hosts 组中的主机做信任
192.168.1.1 ansible_ssh_pass="该主机root用户密码" ansible_ssh_port="该主机ssh服务端口"
```

```bash
source /home/tsc/tsc_profile
# 批量创建信任
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/ssh_authorize_create.yml
# 检查信任
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/sh_authorize_check.yml
# 删除信任
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/ssh_authorize_delete.yml
```
