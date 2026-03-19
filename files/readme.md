# readme

## 说明

1. 用来替代 `tsc_pyenv`.
2. 后续作为 `tsc工具集`(`tsc_tools`) 的插件形式存在, 原部分需要依赖 `ansible` 环境的工具和部分用 `python` 实现更方便的工具移到本工具中.
3. 集成 `python3.11.15` 版本, `python` 包版本也有变化.
4. 分 `Euler` 和 `RedHat` 版本, 分 `x86_64` 和 `aarch64` 架构. 适用情况见后表.

## 安装

### 安装基础功能

1. 将 `tsc_python-<version>-<os>-<arch>-<releasedate>.tar.gz` 解压到 `/home/tsc/install/`
2. 进入安装包解压目录
3. 执行安装: `sh install.sh`

## 验证

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

| 操作系统            | 适配包                                           |
| ------------------- | ------------------------------------------------ |
| centos-6/rhel-6     | 不支持                                           |
| centos-7/rhel-7     | tsc_python-version-RedHat-arch-releasdate.tar.gz |
| FitStarrySkyOS      | tsc_python-version-Euler-arch-releasdate.tar.gz  |
| openEuler/Euler/HCE | tsc_python-version-Euler-arch-releasdate.tar.gz  |
| ky10                | tsc_python-version-Euler-arch-releasdate.tar.gz  |
| uos                 | 不支持                                           |
