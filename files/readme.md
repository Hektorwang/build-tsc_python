# readme

## 说明

1. 用来替代 `tsc_pyenv`.
2. 后续作为 `tsc工具集`(`tsc_tools`) 的插件形式存在, 原部分需要依赖 `ansible` 环境的工具和部分用 `python` 实现更方便的工具移到本工具中.
3. 集成 Python 3.13（具体版本由构建配置 `python_version` 决定, 可通过构建参数覆盖）, `python` 包版本也有变化.
4. 按 CPU 架构分包 (`x86_64` / `aarch64`), 兼容 glibc >= 2.17 的 Linux 发行版. 适用情况见后表.

## 安装

制成品为 RPM 包 `tsc_python-<version>-<release>.<arch>.rpm`, 以 `root` 身份安装:

```bash
# 安装
rpm -ivh tsc_python-<version>-<release>.<arch>.rpm
# 升级 / 重装 (目标机已有旧版本时用它)
rpm -Uvh tsc_python-<version>-<release>.<arch>.rpm
```

安装前 `%pre` 会校验 `root` 权限、CPU 架构(须与本包架构一致)与 glibc (>= 2.17), 不通过则中止安装且不写入任何文件.

## 卸载

```bash
rpm -e tsc_python
```

包内文件由 rpm 删除, 安装时部署的 profile drop-in (`/home/tsc/tsc_profile.d/01-tsc_python-profile.sh`)
由 `%preun` 无条件回收 (该文件名归属本包独占, 不保留本地修改; 现场自定义片段请另建文件),
空目录壳由 `%postun` 清理; `/home/tsc/tsc_profile` 公共入口、`tsc_profile.d`
目录本身与 `/var/log/tsc` 及运行期日志保留.

## 环境加载

本包以 profile 片段 (drop-in) 形式暴露环境: `/home/tsc/tsc_profile.d/01-tsc_python-profile.sh`.
公共入口 `/home/tsc/tsc_profile` 按文件名顺序加载 `tsc_profile.d/*.sh`
(首次安装时由本包或 tsc_tools 创建).

> 本 RPM 硬依赖 `tsc_tools >= 2.1.6` (首次在 `tsc_profile` 中提供 drop-in 加载器的版本), 目标机请先安装 tsc_tools. `%post` 从不改写已存在的 `/home/tsc/tsc_profile`, 仅在其缺失时用包内模板创建 (模板自带加载逻辑), 不会碰 tsc_tools 自己的文件.

```bash
source /home/tsc/tsc_profile                           # 完整 tsc 环境
source /home/tsc/tsc_profile.d/01-tsc_python-profile.sh # 只加载本包环境
```

## 验证

安装完成后执行冒烟测试:

```bash
bash /home/tsc/tsc_python/smoke_test.sh
# 无外网环境跳过 TLS 探测:
bash /home/tsc/tsc_python/smoke_test.sh --skip-network
```

覆盖项: glibc 基线、核心包导入、Python 运行时功能自检、ansible localhost ping、TLS 出网、安装链路.

或手动验证:

```bash
source /home/tsc/tsc_profile
which python
# 观察到结果是 /home/tsc/tsc_python/envs/tsc_python/bin/python
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

以上支持项按架构选用同一个 RPM 包.
