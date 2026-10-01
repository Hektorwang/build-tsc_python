# readme

## 说明

1. 用来替代 `tsc_pyenv`.
2. 后续作为 `tsc工具集`(`tsc_tools`) 的插件形式存在, 原部分需要依赖 `ansible` 环境的工具和部分用 `python` 实现更方便的工具移到本工具中.
3. 集成 `python3.13.12` 版本（可通过构建参数覆盖）, `python` 包版本也有变化.
4. 按 CPU 架构分包 (`x86_64` / `aarch64`), 兼容 glibc >= 2.17 的 Linux 发行版. 适用情况见后表.

## 安装

### 安装基础功能

1. 将 `tsc_python-<version>-<os>-<arch>-<date>.sh` 上传到目标机, 自解压安装包无需解压
2. 以 `root` 身份执行安装: `sh tsc_python-<version>-<os>-<arch>-<date>.sh`
   (安装耗时约 1-5 分钟; 其他可用参数见 `sh tsc_python-<version>-<os>-<arch>-<date>.sh --help`)

## 验证

安装完成后执行冒烟测试:

```bash
sh /home/tsc/tsc_tools/micromamba/smoke_test.sh
# 无外网环境跳过 TLS 探测:
sh /home/tsc/tsc_tools/micromamba/smoke_test.sh --skip-network
```

覆盖项: glibc 基线、核心包导入、Python 运行时功能自检、ansible localhost ping、TLS 出网、安装链路.

或手动验证:

```bash
source /home/tsc/tsc_profile
which python
# 观察到结果是 /home/tsc/tsc_tools/micromamba/envs/tsc_python/bin/python
```

## 使用

```bash
source /home/tsc/tsc_profile
python <path_to_your_python_script>
```

## 系统适配

| 操作系统                     | 适配情况                                     |
| ---------------------------- | -------------------------------------------- |
| centos-7/rhel-7              | 支持                                         |
| openEuler/Euler/HCE          | 支持                                         |
| FitStarrySkyOS/FitServerOS   | 支持                                         |
| ky10                         | 支持                                         |
| centos-6/rhel-6              | 不支持 (glibc < 2.17)                        |
| uos                          | 不支持                                       |
| 其他 glibc >= 2.17 的 Linux  | 理论兼容, 未测试不承诺                       |
| Alpine (musl)/FreeBSD        | 不支持 (无 glibc)                            |

以上支持项共用同一个安装包, 按架构选择.
