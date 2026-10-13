# readme

[English](README.md) | 简体中文

## 说明

1. 用于构建 tsc 标准化发布的 python 发布包.
2. 集成 Python 3.13（具体版本来自 `build.conf` 的 `python_version`, 也可用 `--python-version` 覆盖）, 使用 `micromamba` 管理环境, 通过 `nfpm` 打包为 RPM 包.
3. 每 CPU 架构一个 RPM 包 (`x86_64` / `aarch64`), 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中构建, 兼容所有 glibc >= 2.17 的 Linux 发行版.

## 安装

制成品为单个 RPM 包: `tsc_python-<version>-<release>.<arch>.rpm`
(`<version>` 取自 `release-note.md` 的 `Version=`, `<release>` 为构建时间戳 `YYYYMMDDHHMMSS`).

```bash
# 安装
rpm -ivh tsc_python-<version>-<release>.<arch>.rpm

# 升级 / 重装 (带旧版本时用它, 会走升级路径)
rpm -Uvh tsc_python-<version>-<release>.<arch>.rpm

# 查询
rpm -q tsc_python
rpm -ql tsc_python

# 卸载
rpm -e tsc_python
```

`%pre` 在写入任何文件**之前**校验 `root` 权限、CPU 架构(必须与本包架构一致,
见 `.supported_env.conf`)与 glibc 基线 (2.17); 不通过则中止安装, 不留下半成品文件.

`%post` 负责 rpm 本身做不到的收尾: 补模块 `run.sh` 可执行位、创建 `/var/log/tsc`
(ansible 日志目录)、部署 profile（先补建公共入口，再放本包 drop-in）、调用 `tsc_tools`
的 `gen_rag.sh` 重建 `rag.md`、给 ansible 的 `INTERPRETER_PYTHON_FALLBACK` 列表插入本环境
python3。所有步骤幂等。

环境通过 profile **片段 (drop-in)** 暴露，与 `tsc_tools >= 2.1.7` 的分工一致：

| 路径 | 归属 | 卸载是否删除 |
| --- | --- | --- |
| `/home/tsc/tsc_profile` | 公共入口，谁先装谁建，只负责 source `tsc_profile.d/*.sh` | 否（公共基础设施） |
| `/home/tsc/tsc_profile.d/01-tsc_tools-profile.sh` | tsc_tools | 是，由 tsc_tools |
| `/home/tsc/tsc_profile.d/01-tsc_python-profile.sh`（本包） | tsc_python | 是，由 `%preun`（本包独占：每次安装/升级刷新，卸载时无条件回收，不保留本地修改；现场自定义片段请另建文件，如 `99-local-profile.sh`） |

数字前缀决定加载顺序：`00-tsc_tools-profile.sh`（tsc_tools >= 2.1.8）排在
`01-tsc_python-profile.sh`（本包）之前。两侧片段都声明 `TSC_MODULES_DIR`——本包前插自己的
模块目录、tsc_tools 后插它的——因此无论谁先加载，最终变量内顺序都一致（本包模块在前），
且本包片段自带该声明，在没装 tsc_tools 时 `tsc` 也能发现 `tsc_python_*` 模块。两侧都在
目录已存在时跳过自己的声明：重复项会让 `gen_rag.sh` 把同一份 readme 收录两次，rag.md 成倍膨胀。

**运行期依赖**：本 RPM 声明硬依赖 `tsc_tools >= 2.1.8`。2.1.6 是首次在 `tsc_profile` 中提供
drop-in 加载器的版本，但下限抬到 2.1.8——本包 `%post` 调用 tsc_tools 随包的 `gen_rag.sh`，而
rag.md 膨胀的根因（`TSC_MODULES_DIR` 被重复追加）修在 tsc_tools 侧，低版本上仍会产出成倍
重复的 rag.md。目标机请先安装 `tsc_tools`。`%post` 从不改写已存在的 `/home/tsc/tsc_profile`——仅在该文件缺失时
用包内模板创建（模板自带 `tsc_profile.d/*.sh` 加载逻辑），因此不会碰 tsc_tools 自己的文件。

```bash
source /home/tsc/tsc_profile                           # 完整 tsc 环境（加载全部 drop-in）
source /home/tsc/tsc_profile.d/01-tsc_python-profile.sh # 只加载本包环境
```

卸载时 `%preun` **无条件**删除本包 drop-in（该文件名归属本包独占），
`%postun` 清理随之空掉的本包目录壳，包内文件由 rpm 自行删除。有意保留：`/home/tsc/tsc_profile`、
`/home/tsc/tsc_profile.d`（含现场自定义片段）、`/var/log/tsc` 及运行期日志。

若目标机上已有 RPM 之前(自解压包时代)安装的 `tsc_python`, `%pre` 会先把
`/home/tsc/tsc_tools/micromamba` 轮转为 `micromamba.bak.<时间戳>`, 避免两套文件混在一起;
同时把已过时的 `/home/tsc/tsc_python_profile` 轮转为 `.pre-rpm.<时间戳>`, 并摘掉
`tsc_profile` 里那行旧的 source——确认新包可用后自行清理这些备份.

## 目录结构

```text
.
├── build.sh                # 构建入口脚本 (容器构建 -> 安装树 -> nfpm 打 RPM)
├── Dockerfile              # 唯一构建镜像 (CentOS 7.9, glibc 2.17 基线)
├── packaging/rpm/
│   ├── nfpm.yaml.tmpl      # nfpm 包定义模板
│   ├── preinstall.sh.tmpl  # %pre  (环境准入 + 旧目录轮转, 需注入)
│   ├── postinstall.sh.tmpl # %post (模块权限、rag.md、ansible 补丁、profile)
│   ├── preremove.sh        # %preun (按 hash 清单回收 drop-in, 仅 POSIX 语法, 恒返回 0)
│   ├── postremove.sh       # %postun (清理空目录壳)
│   ├── env_check.sh        # 环境检测与准入校验 (内联进 %pre)
│   └── lib_min.sh          # scriptlet 用的最小 LOG* 运行时
├── .supported_env.conf     # 受支持架构白名单 / glibc 基线
├── release-note.md         # 版本发布记录 (随包分发)
├── THIRD_PARTY_NOTICES.md  # 第三方组件声明 (英文)
├── THIRD_PARTY_NOTICES.zh_CN.md
├── files/
│   ├── pack.sh             # 容器内打包脚本（组装安装树、元数据）
│   ├── func                 # 日志等公共函数库（唯一副本）
│   ├── ansible/            # ansible.cfg / hosts / roles (随包分发)
│   ├── modules/            # tsc_python_* 插件模块 (随包分发)
│   ├── environment.yml     # conda 环境定义（python 版本、系统库）
│   ├── requirements.in     # pip 依赖声明
│   ├── requirements.txt    # pip 依赖清单
│   ├── tsc_profile         # profile 公共入口模板 (%post 部署, 不随 tsc_profile.d 分发)
│   ├── profile             # 本包 drop-in 源 (%post 部署为 01-tsc_python-profile.sh)
│   ├── smoke_test.sh       # 安装后冒烟测试 (随包分发)
│   ├── patch_ansible.py    # ansible 解释器补丁 (随包分发)
│   ├── tmp/                # 构建临时文件（micromamba/jq 缓存、生成的 environment.yml/condarc/pip.conf）
│   └── ...
├── output/                 # 中间产物 (各架构的安装树)
└── release/                # RPM 产物目录
```

## 构建前提

构建容器是 CentOS 7.9（EL7），已 EOL。**构建过程不能依赖任何互联网源**，以下外部资源必须提前自备：

| 资源 | 获取方式 |
| --- | --- |
| 构建容器镜像 `centos:7.9.2009`（x86_64 / aarch64 各一份） | 提前从公网拉取并固化保存到内网镜像仓库（见下节） |
| yum 源（CentOS 7.9 Base ISO 即可） | 用 vault 存档的 7.9.2009 ISO `createrepo` 自建, 地址经 `--repo-local` 传入; jq 由脚本按需下载的静态二进制提供（缓存于 `files/tmp/`）, 不需要 EPEL |
| micromamba 二进制 | 在有外网的机器从 `micro.mamba.pm` 下载一次, 拷入构建机 `files/tmp/`（见"第三方组件缓存"） |
| PyPI 源 / conda-forge 源 | 默认教育网联合镜像站, 经 `build.conf` 的 `pypi_index`/`conda_forge` 自定义; 离线构建改为内网源（见"内网部署说明"） |

其他要求:

- Docker 已安装并运行; `build.sh` 以 `--pull=false` 构建, 构建机本地必须已具备**对应架构**的 `centos:7.9.2009` 镜像
- 本机架构即为目标架构（x86_64 构建 x86_64 包, aarch64 构建 aarch64 包）
- RPM 打包步骤需要打包机提供 `nfpm` (默认取 `/bin/nfpm`, 亦可用 `NFPM_BIN=/path/to/nfpm ./build.sh` 指定)

### 固化保存 EL7 构建镜像（强烈建议）

CentOS 7 容器镜像已随发行版 EOL, 官方渠道（Docker Hub / quay.io）随时可能下架, 一旦下架将永远无法再创建构建环境.
**请立即在有外网的机器上把两个架构的镜像固化保存**, 并导入内网镜像仓库:

```bash
# x86_64
docker pull --platform linux/amd64 centos:7.9.2009
docker save centos:7.9.2009 -o centos-7.9.2009-x86_64.tar

# aarch64 (拉取不需要运行, x86_64 机器也能拉 aarch64 镜像)
docker pull --platform linux/arm64 centos:7.9.2009
docker save centos:7.9.2009 -o centos-7.9.2009-aarch64.tar
```

注意: 同一台机器连续拉取两个架构时 tag 相同会互相覆盖, 每次拉取后立即 `save` 落盘, 或拉取后先 `docker tag` 改名再拉下一个.

导入内网镜像仓库并改用内网地址:

```bash
docker load -i centos-7.9.2009-x86_64.tar
docker tag centos:7.9.2009 <内网registry>/baseimages/centos:7.9.2009
docker push <内网registry>/baseimages/centos:7.9.2009
# 然后把 Dockerfile 的 FROM 改为 <内网registry>/baseimages/centos:7.9.2009
```

## 构建

### 基本用法

```bash
# 构建当前机器架构的安装包
bash build.sh
```

> **前置条件**: `build.sh` 在没有任何配置时会直接报错退出——
> `yum 源地址未配置: 请通过 --repo-local 参数或 build.conf 的 repo_local 键提供`。
> 首次构建请先从 `build.conf.example` 生成 `build.conf` 并至少填好 `repo_local`,
> 或每次显式传 `--repo-local`:

```bash
cp build.conf.example build.conf   # 然后按内网环境修改 repo_local / pypi_index / conda_forge
# 或
bash build.sh --repo-local http://<内网 yum 源>
```

### 参数说明

```text
-n, --no-cache              禁用 Docker 构建缓存
-m, --micromamba-ver V      指定 micromamba 版本（覆盖 build.conf）
-r, --repo-local URL        构建容器使用的内网 yum 源地址（覆盖 build.conf）
-p, --python-version V      覆盖 Python 版本（覆盖 build.conf）
    --pypi-index URL        PyPI 索引地址（覆盖 build.conf）
    --conda-forge URL       conda-forge 通道地址（覆盖 build.conf）
-h, --help                  显示帮助
```

### 配置文件

常用参数可写入 `build.conf`，避免每次手动传参。命令行参数优先级高于配置文件。

```ini
[build]
micromamba_ver = 2.9.0
repo_local     = http://192.168.1.100
python_version = 3.13.16
pypi_index     = https://mirrors.cernet.edu.cn/pypi/web/simple
conda_forge    = https://mirrors.cernet.edu.cn/anaconda/cloud/conda-forge
```

### 覆盖 Python 版本

```bash
bash build.sh --python-version 3.12.11
```

### 第三方组件缓存（micromamba / jq）

第三方构建组件全部采用 **缓存优先, 按需下载** 模式: 本地已有缓存则直接使用, 缺失或校验不符时从上游按锁定版本下载.

| 组件 | 缓存位置 | 上游 |
| --- | --- | --- |
| micromamba | `files/tmp/micromamba` (+ `.version`) | micro.mamba.pm |
| jq (双架构静态二进制) | `files/tmp/jq-x86_64` / `jq-aarch64` (带 sha256 校验) | github.com/jqlang/jq |

离线构建机可从有外网的机器手动放置, 先在有外网的机器上下载（以 2.5.0 / x86_64 为例, aarch64 用 `linux-aarch64`）:

```bash
curl -fL -o micromamba "https://micro.mamba.pm/api/micromamba/linux-64/2.5.0"
```

拷贝到构建机后按如下路径与内容放置（version 文件内容为 `<版本>-<架构>`）:

```text
files/tmp/micromamba          # 下载的二进制归档
files/tmp/micromamba.version  # 文本文件, 内容如: 2.5.0-x86_64
```

强制重新下载（删除缓存即可）:

```bash
rm -f files/tmp/micromamba files/tmp/micromamba.version
rm -f files/tmp/jq-x86_64 files/tmp/jq-aarch64
```

### 构建产物

容器内 `files/pack.sh` 把安装树写到 `output/<arch>/payload/`, 宿主机 `build.sh` 再打成 RPM 输出到 `release/`:

```bash
tsc_python-<version>-<release>.<arch>.rpm        # RPM 包
tsc_python-<version>-<release>.<arch>.rpm.sha256 # SHA256 校验文件
```

`<version>` 取自 `release-note.md` 的 `Version=`, `<release>` 为构建时间戳 (`YYYYMMDDHHMMSS`).
构建元数据 (python / micromamba 版本、glibc 基线) 随包分发在
`/home/tsc/tsc_python/build-info.json`.

### 构建日志

每次构建的 Docker 输出保存到 `log/build-<arch>-<timestamp>.log`.

## 依赖管理

`files/requirements.in` 是**声明层**——记录实际要用的顶层模块, 人工维护. 构建不读取本文件 (其中的注释不会被 pip-compile 覆盖).

`files/requirements.txt` 是**安装清单**——构建执行 `uv pip install -r` 的对象. 它是 (或将是) 生成物, 不要在里面写流程性注释.

`requirements.txt` 是生成的**已锁定**安装清单 (`uv pip compile` 产出的 `==` 固定版本); 不要手工改版本号——改 `requirements.in` 后重新生成即可.

**分层边界**: conda 已提供的一切 (原生库 + conda 也有的纯 python 包: `cryptography`/`cffi`/
`pycparser`/`packaging`/`typing-extensions`) 都在 `uv pip install` 之前被过滤掉 (见
`Dockerfile`), pip 层只装 conda 没有的: `ansible-core` / `asyncssh` 仍声明这些依赖, 但 pip
发现环境里已满足, 直接沿用 conda 版本——避免锁文件与 conda 解析漂移时 pip wheel 覆盖 conda
构建版. `files/pack.sh` 的 `check_pip_conda_overlap` 在构建期兜底断言这条边界: 一旦某包实际
由 pip/uv 装入而 conda 也提供它, 直接禁止出包.

### 锁定 / 重新生成版本

依赖集已锁定进 `requirements.txt` (`==` 固定版本). 当 `requirements.in` 变动时重新生成:

```bash
# 在仓库根目录执行 (需 pip-tools: pip install pip-tools)
pip-compile files/requirements.in --no-header --no-annotate

# uv 等价命令
uv pip compile files/requirements.in -o files/requirements.txt --no-header --no-annotate
```

- `--no-header` / `--no-annotate` 保持输出干净: 不带自动生成头, 不带 `# via` 追踪注释
- 锁文件必须**不含镜像地址**: 不要给 pip-compile 传 `--index-url`/`--extra-index-url`——镜像在构建期经 `build.conf` 的 `pypi_index`（或 `--pypi-index`）注入; 若输出出现 `--index-url` 行, 删掉即可

## 系统适配

| 操作系统                     | 适配情况                                     |
| ---------------------------- | -------------------------------------------- |
| centos-7 / rhel-7            | 支持                                         |
| openEuler / Euler / HCE      | 支持                                         |
| FitStarrySkyOS / FitServerOS | 支持                                         |
| KylinOS V10                  | 支持                                         |
| centos-6 / rhel-6            | 不支持 (glibc < 2.17)                        |
| UOS                          | 不支持                                       |
| 其他 glibc >= 2.17 的 Linux  | 理论兼容, 未测试不承诺 (如 Debian/Arch/SUSE) |
| Alpine (musl) / FreeBSD      | 不支持 (无 glibc)                            |

以上支持项按架构选用同一个 RPM 包 (`x86_64` / `aarch64`); `%pre` 会在写入任何文件前校验目标机架构与 glibc 基线.

## 内网部署说明

构建所需的外部资源与对应配置：

- **PyPI 源**: 默认教育网联合镜像站; 离线构建机用 `build.conf` 的 `pypi_index`（或 `--pypi-index`）指向内网源
- **conda-forge 源**: 默认教育网联合镜像站的 conda-forge 通道; 离线构建机用 `build.conf` 的 `conda_forge`（或 `--conda-forge`）指向内网通道, 也可指向自建的最小化 conda-forge 源（见下）
- **Docker 基础镜像**: 推送到内网镜像仓库后修改 `Dockerfile` 的 `FROM` 地址（见"固化保存 EL7 构建镜像"）
- **yum 源**: 见下节

### 自建最小化 conda-forge 源（可选）

不必镜像整个 conda-forge（数十 TB）, 只需包含环境解析到的包闭包即可:

```bash
# 1) 有外网的机器上, 用与构建相同的 environment.yml 做 dry-run, 得到精确的包下载地址 (含完整依赖闭包)
micromamba create -f environment.yml --dry-run --json > plan.json

# 2) 从 plan.json 提取全部包 URL 并按平台归档下载 (linux-64 / linux-aarch64 / noarch)
jq -r '.actions.LINK[] | .url' plan.json | xargs -P 8 -n 1 curl -fLO

# 3) 归入 channel 布局: <channel>/<subdir>/<包文件> (noarch 包放 noarch/)
#    aarch64 的包在 ARM 机器上重复步骤 1-2 收集

# 4) 生成索引 (需 conda-index: pip install conda-index)
conda-index /srv/conda-forge

# 5) nginx 发布该目录, 然后配置构建源指向它
bash build.sh --conda-forge http://<内网服务器>/conda-forge
```

environment.yml 变更后重跑步骤 1-2 增量补充新闭包即可.

### CentOS 7 yum 源

CentOS 7 已于 2024 年 6 月 EOL，官方镜像站已下线，**公网已无法获取安装包**。内网构建必须自备源：

1. 从存档渠道（如 `vault.centos.org` 或第三方存档）下载 CentOS 7.9.2009 完整 ISO
2. 将 ISO 解压或挂载后，通过 `createrepo` 建立本地 yum 源
3. 将源地址通过 `--repo-local` 参数传入，或直接修改 `files/centos7.repo` 中的 `base_local_url` 默认值

```bash
bash build.sh --repo-local http://<your-internal-repo-server>
```

## 许可证

本项目自身代码以 **GPL-3.0-or-later** 发布, 见根目录 [LICENSE](LICENSE).

仓库引用的第三方组件遵循其各自许可证, 详见 [THIRD_PARTY_NOTICES.zh_CN.md](THIRD_PARTY_NOTICES.zh_CN.md) (英文版: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)):
micromamba 二进制 (BSD-3-Clause) 与 jq 静态二进制 (MIT) 均在构建时按锁定版本获取, 不随本仓库分发.

由本工具产出的 tsc_python RPM 包仅面向内部环境分发.
