# readme

[English](README.md) | 简体中文

## 说明

1. 用于构建 tsc 标准化发布的 python 发布包.
2. 集成 `python3.13.12`（可通过参数覆盖版本）, 使用 `micromamba` 管理环境, 通过 `makeself` 打包为自解压安装包.
3. 每 CPU 架构一个安装包 (`x86_64` / `aarch64`), 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中构建, 兼容所有 glibc >= 2.17 的 Linux 发行版.

## 目录结构

```text
.
├── build.sh                # 构建入口脚本
├── Dockerfile              # 唯一构建镜像 (CentOS 7.9, glibc 2.17 基线)
├── func                    # 日志等公共函数库
├── release-note.md         # 版本发布记录 (随包分发)
├── THIRD_PARTY_NOTICES.md  # 第三方组件声明 (英文)
├── THIRD_PARTY_NOTICES.zh_CN.md
├── files/
│   ├── pack.sh             # 容器内打包脚本（makeself、checksum、元数据）
│   ├── install.sh          # 安装包内的安装脚本
│   ├── environment.yml     # conda 环境定义（python 版本、系统库）
│   ├── requirements.in     # pip 依赖声明
│   ├── requirements.txt    # pip 依赖清单
│   ├── tmp/                # 构建临时文件（micromamba/jq 缓存、生成的 environment.yml/condarc/pip.conf）
│   └── ...
└── output/                 # 构建产物输出目录
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
micromamba_ver = 2.5.0
repo_local     = http://192.168.1.100
python_version = 3.13.12
pypi_index     = https://mirrors.cernet.edu.cn/pypi/web/simple
conda_forge    = https://mirrors.cernet.edu.cn/anaconda/cloud/conda-forge
```

### 覆盖 Python 版本

```bash
bash build.sh --python-version 3.12.11
```

### 第三方组件缓存（micromamba / jq / makeself）

第三方构建组件全部采用 **缓存优先, 按需下载** 模式: 本地已有缓存则直接使用, 缺失或校验不符时从上游按锁定版本下载.

| 组件 | 缓存位置 | 上游 |
| --- | --- | --- |
| micromamba | `files/tmp/micromamba` (+ `.version`) | micro.mamba.pm |
| jq (双架构静态二进制) | `files/tmp/jq-x86_64` / `jq-aarch64` (带 sha256 校验) | github.com/jqlang/jq |
| makeself | `files/makeself.sh` / `makeself-header.sh` | github.com/megastep/makeself |

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
rm -f files/makeself.sh files/makeself-header.sh
```

### 构建产物

产物输出到 `output/<arch>/`, 每次构建包含三个文件：

```bash
tsc_python-<version>-<arch>-<date>.sh        # makeself 自解压安装包
tsc_python-<version>-<arch>-<date>.sh.sha256 # SHA256 校验文件
tsc_python-<version>-<arch>-<date>.sh.json   # 构建元数据（版本、时间、架构、glibc 基线等）
```

### 构建日志

每次构建的 Docker 输出保存到 `log/build-<arch>-<timestamp>.log`.

## 依赖管理

`files/requirements.in` 是**声明层**——记录实际要用的顶层模块, 人工维护. 构建不读取本文件 (其中的注释不会被 pip-compile 覆盖).

`files/requirements.txt` 是**安装清单**——构建执行 `uv pip install -r` 的对象. 它是 (或将是) 生成物, 不要在里面写流程性注释.

当前过渡态: `requirements.txt` 手工维护且未锁版本——修改 `requirements.in` 后需同步更新 `requirements.txt`.

### 锁定版本（计划中）

包稳定后锁定依赖集:

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

以上支持项共用同一个安装包 `tsc_python-<version>-<arch>-<date>.sh`, 按架构选择; 安装器会自动校验目标机架构.

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
makeself 脚本 (GPL-2.0-or-later, 其生成的自解压安装包经作者声明不受 GPL 约束) 与 jq 静态二进制 (MIT) 均在构建时按锁定版本获取, 不随本仓库分发.

由本工具产出的 tsc_python 安装包仅面向内部环境分发.
