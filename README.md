# readme

## 说明

1. 用于构建 tsc 标准化发布的 python 发布包.
2. 集成 `python3.11.15`（可通过参数覆盖版本）, 使用 `micromamba` 管理环境, 通过 `makeself` 打包为自解压安装包.
3. 分 `Euler` 和 `RedHat` 两个发行版变体, 分 `x86_64` 和 `aarch64` 两种架构, 共四个构建目标.

## 目录结构

```
.
├── build-local.sh          # 本地构建入口脚本
├── Euler.dockerfile        # openEuler / HCE / Euler 构建镜像
├── RedHat.dockerfile       # CentOS 7 / RHEL 7 构建镜像
├── func                    # 日志等公共函数库
├── files/
│   ├── build.sh            # 容器内打包脚本（makeself、checksum、元数据）
│   ├── install.sh          # 安装包内的安装脚本
│   ├── environment.yml     # conda 环境定义（python 版本、系统库）
│   ├── requirements.in     # pip 依赖声明
│   ├── requirements.txt    # pip-compile 生成的锁定依赖
│   ├── tmp/                # 构建临时文件（micromamba 缓存、临时 environment.yml）
│   └── ...
└── output/                 # 构建产物输出目录
```

## 构建前提

- 互联网服务器, 可访问 `https://micro.mamba.pm`（首次下载 micromamba, 后续缓存到 files/tmp/ ）
- Docker 已安装并运行
- 本机架构即为目标架构（x86_64 构建 x86_64 包, aarch64 构建 aarch64 包）
- 本地具备镜像:
  - `openeuler/openeuler:22.03-lts-sp3`
  - `centos:7.9.2009`

## 构建

### 基本用法

```bash
# 构建全部目标（euler + redhat, 当前机器架构）
bash build-local.sh

# 仅构建 Euler 版本
bash build-local.sh -t euler

# 仅构建 RedHat 版本
bash build-local.sh -t redhat
```

### 参数说明

```
-t, --target TARGET         构建目标: euler, redhat, all（默认: all）
-n, --no-cache              禁用 Docker 构建缓存
-m, --micromamba-ver V      指定 micromamba 版本（默认: 2.5.0）
-r, --repo-local URL        RedHat 构建使用的内网 yum 源地址
-p, --python-version V      覆盖 Python 版本（默认使用 environment.yml 中的版本）
-h, --help                  显示帮助
```

### 覆盖 Python 版本

```bash
bash build-local.sh -t euler --python-version 3.12.11
```

### micromamba 缓存

首次构建时脚本自动下载 micromamba 到 `files/tmp/micromamba`, 后续构建直接复用, 版本变更时自动重新下载.

```bash
# 强制重新下载 micromamba（删除缓存即可）
rm files/tmp/micromamba files/tmp/micromamba.version
```

### 构建产物

产物输出到 `output/<target>-<arch>/`, 每次构建包含三个文件：

```
tsc_python-<version>-<os>-<arch>-<timestamp>.sh        # makeself 自解压安装包
tsc_python-<version>-<os>-<arch>-<timestamp>.sh.sha256 # SHA256 校验文件
tsc_python-<version>-<os>-<arch>-<timestamp>.sh.json   # 构建元数据（版本、git 信息等）
```

### 构建日志

每次构建的 Docker 输出保存到 `log/build-<target>-<arch>-<timestamp>.log`.

## 系统适配

| 操作系统                     | 适配包                                         |
| ---------------------------- | ---------------------------------------------- |
| centos-6 / rhel-6            | 不支持                                         |
| centos-7 / rhel-7            | `tsc_python-<version>-RedHat-<arch>-<date>.sh` |
| openEuler / Euler / HCE      | `tsc_python-<version>-Euler-<arch>-<date>.sh`  |
| FitStarrySkyOS / FitServerOS | `tsc_python-<version>-Euler-<arch>-<date>.sh`  |
| KylinOS V10                  | `tsc_python-<version>-Euler-<arch>-<date>.sh`  |
| UOS                          | 不支持                                         |

## 内网部署说明

构建环境最终部署在内网 Gitea, 需自行提供：

- PyPI 源（在 `files/pip.conf` 中配置）
- conda-forge 镜像（在 `files/.condarc` 中配置）
- Docker 基础镜像（提前推送到内网镜像仓库后修改 Dockerfile `FROM` 地址）

### openEuler yum 源

openEuler 官方源在公网可用，内网环境从官网下载对应版本 ISO 挂载或解压后搭建本地源即可.

### CentOS 7 yum 源

CentOS 7 已于 2024 年 6 月 EOL，官方镜像站已下线，**公网已无法获取安装包**。内网构建必须自备源：

1. 从存档渠道（如 `vault.centos.org` 或第三方存档）下载 CentOS 7.9.2009 完整 ISO
2. 将 ISO 解压或挂载后，通过 `createrepo` 建立本地 yum 源
3. 同理准备 EPEL 7 离线包（可从 Fedora 存档获取）
4. 将源地址通过 `--repo-local` 参数传入，或直接修改 `files/centos7.repo` 中的 `REPO_LOCAL` 默认值

```bash
bash build-local.sh -t redhat --repo-local http://<your-internal-repo-server>
```
