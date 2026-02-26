# 批量修改主机名功能

## 环境依赖

依赖于系统中已经部署了 `ansible` 程序, 如系统中未部署 `ansible`, 可自行部署或安装 `tsc_python`

## 使用说明

配置 `/home/tsc/tsc_tools/ansible/hosts`, 将各主机需修改的主机名设置为对应主机的 `hostname` 变量.  
如要把 `192.168.1.1` 主机名设置为 `my1_1`, 则在 `hosts` 段中设置为:

```ini
[hosts]
# 只会修改放在 hosts 组中的主机名
# 如果运行在 ssh 主信任机上, 可无需密码
192.168.1.1 hostname="my1_1" ansible_ssh_pass="该主机root用户密码" ansible_ssh_port="该主机ssh服务端口"
```

```bash
# 执行批量修改
ansible-playbook -i /home/tsc/tsc_tools/ansible/hosts /home/tsc/tsc_tools/ansible/roles/changenhostame.yml
```
