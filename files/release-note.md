# release-note

## Version=0.9.3

1. chore: 改为使用 `makeself` 打包, 这样可以直接安装.
2. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.

## Version=0.9.2

Date=2025801

1. chore: 使用 `Jenkinsfile` 做自动集成.
2. feat: 增加原 `tsc_tools` 中的批量修改主机名和批量做 ssh 信任的工具迁移到本工具中.
3. feat: 增加 `xlrd`.
4. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.

## Version=0.9.1

Date=20250727

1. feat: 因为不再支持 `el6`, 后续操作系统都有 `systemd`, 不再集成 `supervisor`.
2. feat: 缩减第三方包数量. 以能支持 `ansible`; 在 `zeppelin` 中处理数据; 和一些单机工具开发为目的.
3. feat: 仅固定核心第三方包版本, 不再强制固定全部第三方包版本. 仅通过 `pip-tools` 做简单控制.
4. refact: 使用 `docker buildx` 多系统多架构编译.
5. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.
6. TODO: 使用 `Jenkinsfile` 做自动集成.
7. TODO: 打包环境集成自定 `uv_download` 工具, 以支持在需要扩展第三方包的情况下自建多系统多架构 `pypi` 源.

## Version=0.9.0

Date=20250715

1. Initial
2. TODO: 将 `tsc_tools` 中需要使用 python 的工具迁移到本工具中
3. TODO: 使用 docker buildx 交叉编译
