# tsc_python

## Version=0.11.0

Date=20261001

1. feat: 包命名去除发行版标识, 改为 `tsc_python-<version>-<arch>-<date>.sh`; 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中构建, 单架构单包兼容 glibc >= 2.17 的 Linux 发行版
2. feat: `build.sh` 增加 glibc 符号扫描门限检查, 环境内 ELF 的最高 GLIBC_ 要求超过 2.17 时禁止出包; 元数据 JSON 的 `os_variant` 字段替换为 `glibc_baseline`
3. fix(install.sh): `check_env` 由校验发行版家族改为仅校验目标机架构
4. chore: 依赖移除 `pyinotify` (0.9.6 依赖 py3.12 已移除的 asyncore, 无法 import), 增加 `watchdog`
5. chore: `Euler.dockerfile` 退役, 构建容器统一为 `Dockerfile` (centos:7.9); `build.sh` 移除 `-t/--target` 参数, 收敛为单架构单构建
6. chore: jq 改用静态二进制 (1.8.1, 双架构), 构建不再依赖 EPEL, `epel-local` 源移除
7. chore: conda-forge 与 PyPI 源统一切换到教育网联合镜像站 (`mirrors.cernet.edu.cn`); 新增 `THIRD_PARTY_NOTICES.md` 随包分发第三方组件声明
8. feat: 构建源全部可配置: `build.conf` 新增 `pypi_index`/`conda_forge` 键, `build.sh` 新增 `--pypi-index`/`--conda-forge` 参数; `files/pip.conf` 与 `files/.condarc` 移除, 改为构建时生成到 `files/tmp/`
9. feat: `makeself` 与 `jq` 改为与 micromamba 相同的缓存优先按需下载模式 (jq 带 sha256 校验), 第三方组件不再随仓库分发, 移除无引用的 `argbash` 存档
10. chore: 开源准备: 新增 GPL-3.0 `LICENSE` 与源码文件 SPDX 标识; 内网地址移出版本控制 (`build.conf` 移出跟踪并提供 `build.conf.example`); `THIRD_PARTY_NOTICES` 拆分为中英文文件 (`THIRD_PARTY_NOTICES.md` / `THIRD_PARTY_NOTICES.zh_CN.md`), README 提供中英文版本 (`README.md` / `README.zh_CN.md`)
11. chore: `release-note.md` 与 `THIRD_PARTY_NOTICES*.md` 移至仓库根目录并随产物分发; `RedHat.dockerfile` 更名为 `Dockerfile`; `build-local.sh` 更名为 `build.sh`, 容器内 `files/build.sh` 更名为 `files/pack.sh`
12. docs: README 新增依赖管理与 pip-compile 锁定流程说明 (`--no-header --no-annotate`, 锁文件保持源无关); `requirements.txt` 头部注释移除 (生成物不保留流程注释), 声明层注释保留在 `requirements.in`

## Version=0.10.0

Date=20260507

1. feat: 修改 ansible 查找 interpreter 的路径, 在原 `ansible/config/base.yml` 中的 `INTERPRETER_PYTHON_FALLBACK.default` 列表插入 `tsc_python` 和 `tsc_pyenv` 的 python3 路径

## Version=0.9.7

Date=20260331

1. feat: 因为 ansible==2.9.27 已经无法在 python==3.13.12下工作, 改为使用 ansible-core

## Version=0.9.6

Date=20260330

1. chore: 默认python版本修改到 3.13.12
2. chore: 组件版本随之微调
3. TODO: modules里面工具还没弄过
4. TODO: ansible 和 ansible-runner 的版本问题

## Version=0.9.5

Date=20260319

1. feat: 增加本地构建配置文件 `build.conf`, 若本地构建时, 不指定参数则使用该配置文件中的内容
2. fix: 修复 func 中滚动更新文件夹的不适配低版本 bash 问题
3. fix(install.sh): 修复了在解压和拷贝文件时没有上级目录的问题
4. feat(environment.yml): 固化版本
5. feat: 使用micromamba创建环境时指定仅使用 conda-forge 源, 避免使用 anaconda 源带来的版权问题

## Version=0.9.4

Date=20260318

1. refact: 改为本地构建方式，使用 `build-local.sh` 在本机同架构容器中执行打包，不再依赖 `buildx` 跨架构编译。
2. refact: `build-local.sh` 引入 `func` 日志系统，统一日志格式，支持 `getopt` 参数解析。
3. feat: `build-local.sh` 新增 `build.conf` 配置文件支持，`-m`/`-r`/`-p` 参数优先于配置文件，配置文件优先于内置默认值。
4. feat: `build-local.sh` 支持 `--python-version` 参数，通过注入临时 `environment.yml` 覆盖 Python 版本，不修改原始文件。
5. feat: micromamba 改为由 `build-local.sh` 在 host 上预下载并缓存到 `files/tmp/`，构建时直接 `COPY` 进容器，避免多目标重复下载。
6. refact: Dockerfile 中移除 micromamba 在线下载步骤，改为从 `files/tmp/micromamba` 取得。
7. feat: `PYTHON_VERSION`、`MICROMAMBA_VERSION` 由 `build-local.sh` 解析后通过 `--build-arg` 传入容器，`files/build.sh` 直接读取环境变量，不再自行执行命令取值。
8. chore: 移除 Rust 相关依赖（`.cargo_config`），`cryptography`、`bcrypt` 改由 `conda-forge` 提供预编译版本。
9. feat: `files/build.sh` 增加 Git 信息（commit/branch/tag）、SHA256 checksum 及元数据 JSON 输出，修正 `build_date`/`build_timestamp` 语义。
10. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中。
11. TODO: 迁移到内网 Gitea，配置 Gitea Actions Runner 实现自动构建。

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
