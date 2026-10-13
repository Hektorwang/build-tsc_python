# tsc_python

## Version=0.13.3

Date=20261013

1. fix(modules): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 run.sh 补加 `set -o errexit`——原先无错误退出保护, 模块内命令失败时 `tsc` 分发器静默继续
2. fix(build/pack.sh): `prepare_payload` 的 `chmod 0755` 从 glob 展开改为 `find -exec`——`shopt -s nullglob` 下 glob 无匹配时展开为空, `chmod` 无参数报错并触发 `set -o errexit` 退出, 改用 `find` 避免该问题
3. fix(rpm/postinstall.sh.tmpl): 删除 `id tsc && chown tsc: ${LOG_DIR}` 死代码——整个代码库从未创建过 `tsc` 用户, 该判断永远为假, 是 makeself 时代的遗留; 日志目录 owner 保持 root
4. fix(build): `build.sh` 开头固定 `umask 022`, 与 `tsc_tools` 对齐, 避免打包机 umask 收紧时静默削掉未显式 chmod 的文件权限
5. docs: 对齐文档与实现——README 中英 `%preun` 描述由「hash 清单」改为按文件名无条件回收; 中文表 tsc_tools drop-in 改为 `00-`; micromamba 离线缓存示例版本 `2.5.0` → `2.9.0`; KNOWN_ISSUES 同步 0.13.3 已补 `errexit` 的现状; README-dev 记录 umask 已固定
6. fix(ansible): `ansible.cfg` 两处运行期写入路径移出 RPM 管辖区——`home` 由 `/home/tsc/tsc_python/ansible/` 改为 `/home/tsc/.ansible` (ANSIBLE_HOME, galaxy 缓存/tmp 等不再落入包内); `retry_files_save_path` 由 `/home/tsc/tsc_python/ansible/retries` 改为 `/var/log/tsc/ansible/retries` (失败剧本的 `.retry` 文件改入日志目录); `%post` 补建 `/var/log/tsc/ansible/retries` 子目录并设 0750 权限。现场已有 `.retry` 文件仍在旧路径, 可手动迁移至新目录

## Version=0.13.2

Date=20261013

1. fix(modules): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 run.sh 原来统一 `find ... -exec glow {} +`, glow 传文件路径时进 TUI 模式, stdout 非 TTY (管道/重定向/输出被上层接管) 时静默输出空内容——`tsc --tsc_python_ansible` 什么都看不到。改为按 TTY 分流: 交互式仍走 glow 翻页, 非交互式直接输出 readme 原文
2. fix(rpm): 硬依赖 `tsc_tools >= 2.1.6` 提升为 `>= 2.1.8`——本包 `%post` 调用 tsc_tools 的 `gen_rag.sh`, 而 `rag.md` 膨胀的根因 (`TSC_MODULES_DIR` 重复追加) 修在 tsc_tools 侧 (其 drop-in 判重 + `gen_rag.sh` 去重); 依赖不抬到 2.1.8 则修复在目标机上不生效, 仍会产出成倍重复的 rag.md
3. docs: 跨包 drop-in 前缀由"两侧同为 `01-`、靠文件名字母序"改为 tsc_tools `00-` / 本包 `01-`, 明确保序 (README 中英、README-dev、profile 与 `%post` 注释同步); 两侧对 `TSC_MODULES_DIR` 的拼装方向相反, 两种加载顺序下结果一致
4. docs(KNOWN_ISSUES): 记录模块 run.sh 与 tsc_tools 规范不一致 (缺 `set -o` 与 `source func`) 及 `tsc --模块名 --help` 文档与实现不符, 均暂缓
5. docs: README 中英"基本用法"补充构建前置条件——无 `build.conf` 时 `bash build.sh` 会直接报"yum 源地址未配置"退出, 需先 `cp build.conf.example build.conf` 填好 `repo_local`, 或显式传 `--repo-local`

## Version=0.13.1

Date=20261012

1. fix(build): 修复构建残留混入产物——`docker cp` 取回前整体清空 `output/<arch>/` (cp 是目录合并语义, 不清会把旧布局残留合并进 payload); `package_rpm` 增加 payload 顶层负面断言 (只允许 `tsc_python`, 出现其他目录直接中止打包)。此前旧布局的 `tsc_tools/{ansible,modules}` 残留会被打进 RPM, 与 tsc_tools 命名空间冲突 (安装文件冲突/卸载误删)
2. fix(build): `release` 号由构建日期改为构建时间戳 (`YYYYMMDDHHMMSS`), 同日多次构建的 NVR 可区分
3. fix(build): `--python-version` 入口校验格式 (`3.13` / `3.13.12` 形式), 非法值提前报错而非到容器内才失败; micromamba/jq 下载去掉 `--insecure`, 恢复 TLS 证书校验
4. fix(deps): pip 层安装前过滤 conda 已提供的原生库 (`cryptography` 及构建依赖 `cffi`/`pycparser`), 避免锁文件里的 pip wheel 在版本漂移时覆盖 conda 构建版; `requirements.txt` 按文档规定的 `--no-header --no-annotate` 重新生成 (无自动头, 无 `# via` 注释)
5. chore(env): environment.yml 清理冗余显式条目——`sqlite` CLI (保留 `libsqlite` 即可, 已验证从环境移除)、`typing_extensions` (与 `typing-extensions` 重复)、`libgcc-ng` (`libgcc` 旧别名)、`python_abi`、`tk`; 后四项实际由传递依赖带入 (conda-forge 的 python 包把 tk 列为运行依赖), 显式条目移除后仍存在于环境中, 详见 KNOWN_ISSUES
6. fix(rpm): `/var/log/tsc` 权限 0755 → 0750 (ansible 日志可能含敏感信息)
7. fix(rpm): 冒烟测试统一以 `bash` 运行 (脚本增加被 `sh` 调用时自动转交 bash 的保护)
8. chore(build): `stage/` 由 `package_rpm` 的 RETURN trap 在成功/失败路径统一回收 (此前失败路径不清理); Dockerfile 工作目录 COPY 改为显式文件列表, 不再把 `files/tmp/` 的 micromamba/jq 缓存带入镜像层
9. docs: 更正文档与实现不一致——删除不存在的"旧版 tsc_tools bootstrap 加载块兜底"描述 (实际由 `tsc_tools >= 2.1.6` 硬依赖拦下, `%post` 只在不覆盖已有 `tsc_profile` 的前提下创建); 更正 `rpm -V` 说明 (`%config(noreplace)` 保证升级保留现场 patch, 但校验仍会报 patch 过的 base.yml, 属预期行为); THIRD_PARTY_NOTICES 更正 func 分发描述 (构建期使用, 不随安装包分发); tsc_tools drop-in 名称按 2.1.7 实际命名 `01-tsc_tools-profile.sh` 更正; README 示例 python 版本与 `environment.yml` 默认值对齐
10. chore: 产物不做 GPG 签名 (已决策, 见 README-dev §4.9); 新增 `KNOWN_ISSUES.md` 记录暂缓事项
11. fix(deps): pip/conda 分层边界落地——Dockerfile 过滤列表补充 `packaging`/`typing-extensions` (conda 同样提供, 防止锁文件与 conda 解析漂移时被 pip wheel 覆盖); `files/pack.sh` 新增 `check_pip_conda_overlap` 构建期断言 (某包 dist-info/INSTALLER 为 pip/uv 且 conda-meta 同名, 即禁止出包)
12. refactor(rpm): drop-in `01-tsc_python-profile.sh` 明确为本包独占——每次安装/升级用包内版本刷新, `%preun` 真卸载时无条件回收, 不再保留本地修改; 移除 `.installed_manifest` hash 清单机制 (现场自定义片段请另建文件, 如 `99-local-profile.sh`)
13. chore: `func` 仅保留 `files/func` 一份 (根目录副本已删除, `build.sh` 改源 `files/func`; 容器内 `pack.sh` 本就源同一份)
14. chore: environment.yml 清理结论按实测更正——`sqlite` CLI 已从环境移除; `tk` 由 conda-forge python 包的运行依赖带入, 删显式条目无法剔除 (见 KNOWN_ISSUES)
15. chore: 默认版本对齐 `build.conf.example`——environment.yml 与 README 示例统一到 python 3.13.16, micromamba 兜底默认值统一到 2.9.0 (双架构均已核实可下载)

## Version=0.13.0

Date=20261012

1. refactor(build): 制成品由 makeself 自解压包改为 RPM, 产出 `release/tsc_python-<version>-<release>.<arch>.rpm` (`version` 取自本文件 `Version=`, `release` 为构建日期); 打包脚本集中到 `packaging/rpm/`
2. refactor(build): 容器内 `files/pack.sh` 不再打自解压包, 改为组装安装树 `output/<arch>/payload/` (镜像 `/home/tsc` 布局) 并生成 `build-info.json`; RPM 由宿主机 `build.sh` 用 nfpm 打包——nfpm 不必进入构建容器, 且宿主机可直接对产物做 `rpm -q` 自检
3. feat(build): 打包前检查打包机是否提供 `nfpm` (默认 `/bin/nfpm`, 可用 `NFPM_BIN` 覆盖), 缺失时明确报错退出; 四段 scriptlet 逐个 `bash -n` 语法自检; 渲染完整性断言 (注入文件存在、`@ARCH@` 已替换)
4. feat(build): 产物自检包含包信息/依赖/文件数/关键文件是否齐全 (profile 源与公共入口模板、micromamba、环境 python3 与 ansible、smoke_test.sh、ansible.cfg、模块 run.sh)/关键文件可执行位/四段 scriptlet 是否写入
5. feat(rpm): `%pre` 做环境准入校验 (root 权限、CPU 架构须与本包架构一致且在 `.supported_env.conf` 白名单内、glibc >= 2.17), 不通过则中止安装, 不留下半成品文件——原先自解压包是先解包再校验
6. feat(rpm): `%pre` 发现已有非 RPM (自解压包时代) 安装时, 先把 `/home/tsc/tsc_tools/micromamba` 轮转为 `micromamba.bak.<时间戳>`, 避免两套文件混装; 升级 (rpm -U) 时该目录由本包旧版本持有, 原样保留
7. feat(rpm): `%post` 承接原 `install.sh` 的收尾动作 (模块 `run.sh` 可执行位、`/var/log/tsc` 日志目录、`gen_rag.sh` 重建 `rag.md`、`patch_ansible.py` 打解释器补丁), 各步骤幂等; `%preun` 仅在真卸载 (`$1==0`) 时回收, 升级交由新包 `%post` 重建
8. refactor(path): 环境本体从 `/home/tsc/tsc_tools/micromamba` 迁到 `/home/tsc/tsc_python`——不再是"塞在 tsc_tools 下的一个子目录", 而是与 tsc_tools 平级的独立组件; 随包文档/工具与 `build-info.json` 同步改为 `/home/tsc/tsc_python/`, 自解压包时代的旧目录仍由 `%pre` 轮转
9. feat(rpm): profile 改为与 tsc_tools 同构的 drop-in 模型——`/home/tsc/tsc_profile` 是公共入口 (只 source `/home/tsc/tsc_profile.d/*.sh`, 谁先装谁创建, 所有工具卸载都不删), 本包片段由 `%post` 部署为 `tsc_profile.d/01-tsc_python-profile.sh` (源为随包的 `/home/tsc/tsc_python/profile`), 数字前缀决定加载顺序 (`01-tsc_tools-profile.sh` 在前); 卸载由 `%preun` 按 `<ENV_ROOT>/.installed_manifest` 里的 sha256 校验回收 (片段被改过则保留), 目录壳由新增的 `%postun` 清理
10. feat(profile): drop-in 增加 `TSC_MODULES_DIR` 声明——tsc 与 `gen_rag.sh` 靠该变量 (冒号分隔多目录) 发现模块, 本包因此自建声明, 使单独安装 tsc_python 时 `tsc` 也能看到 `tsc_python_*` 模块; 已由 `01-tsc_tools-profile.sh` 声明过同一目录则跳过, 避免重复项让 `gen_rag.sh` 把同一份 readme 收录两次
11. fix(rpm): `%post` 清理早期形态的 drop-in `tsc_python.sh` (无包认领时删除), 避免升级后同一份环境被加载两次; `%post` 顺序调整为先部署 profile 再跑 `gen_rag.sh`, 使后者能取到 `TSC_MODULES_DIR`
12. feat(rpm): `%pre` 新增 `rotate_legacy_profile`——自解压包时代留下的 `/home/tsc/tsc_python_profile` 及其在 `tsc_profile` 里的旧 `source` 行已过时, 与旧环境目录一样按"`rpm -qf` 认领则跳过"的规则轮转/摘行, 避免两份 profile 并存说不清哪份生效
13. chore: 构建依赖与文档去掉 makeself (不再参与打包); 随包文档与工具路径改用新环境根目录 `/home/tsc/tsc_python/`
14. feat(rpm): RPM 新增硬依赖 `tsc_tools >= 2.1.6` (见 `packaging/rpm/nfpm.yaml.tmpl` 的 `depends`)——`/home/tsc/tsc_profile` 加载 `tsc_profile.d/*.sh` 的加载器由该版本起提供; 低于此版本时 `%post` 虽会 bootstrap 一段加载块兜底, 但建议直接装对齐版本
15. fix(pack): 环境内二进制 (`tsc_python/bin/*`、`envs/tsc_python/bin/*`) 在打包时归一化到 0755——构建容器 umask 002 会让它们带上组写位 (0775), 共享目录 /home/tsc 下 root 所有的二进制保持 0755 更干净, 也避免产物自检因权限非 0755 而失败

## Version=0.12.0

Date=20261004

1. feat: 新增 `tsc_python_batch_user_manager` 模块: 批量建立管理机到目标机的 root 信任; 批量创建业务用户并赋予免密码 sudo, 建立到业务用户的 ssh 信任; 按 `create`/`check`/`delete` 三个剧本组织, 以 `root`/`user` 标签选择执行范围; 全程原生 ansible 模块, 适配 RHEL 系与 DEBIAN 系 (sudo 缺失显式报错, SELinux enforcing 下自动修正 `.ssh` 上下文, 校验强制仅密钥连接防误判)
2. fix(requirements): 新增 `passlib`: ansible `password_hash` 过滤器的控制器侧依赖, 缺失时创建用户的任务会直接失败
3. feat(modules): 模块 readme 增加 front matter (category/keywords/description/usage), run.sh 补可执行位; `install.sh` 在合并 modules 后调用 tsc_tools (>= 2.1.7) 的 `gen_rag.sh` 重建 `rag.md`, 使 `tsc` 命令入口可查询并调用本包模块
4. chore(modules): 确立模块命名规范 — tsc_tools 自有模块用 `tsc_` 前缀, tsc_python 插件模块统一 `tsc_python_` 前缀; tsc_tools 升级安装按此前缀识别并保护插件内容 (退役的 `tsc_ssh_authorize` 模块本轮不再随包分发)

## Version=0.11.0

Date=20261001

1. feat: 包命名去除发行版标识, 改为 `tsc_python-<version>-<arch>-<date>.sh`; 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中构建, 单架构单包兼容 glibc >= 2.17 的 Linux 发行版
2. feat: `build.sh` 增加 glibc 符号扫描门限检查, 环境内 ELF 的最高 GLIBC_ 要求超过 2.17 时禁止出包; 元数据 JSON 的 `os_variant` 字段替换为 `glibc_baseline`
3. fix(install.sh): `check_env` 由校验发行版家族改为仅校验目标机架构; 安装时创建 ansible 日志目录 `/var/log/tsc` 并归属 tsc 用户
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
