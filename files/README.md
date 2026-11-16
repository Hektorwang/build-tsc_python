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

安装前 `%pre` 会校验 `root` 权限、CPU 架构(须与本包架构一致)与 glibc (>= 2.17), glibc 无法识别时同样拒装, 不通过则中止安装且不写入任何文件.

升级 (`rpm -Uvh`) 时现场维护的 `/home/tsc/tsc_python/ansible/hosts` (inventory, 模块工作流要求现场把受管主机与凭据写进去) **不会被覆盖**: 该文件以 `%config(noreplace)` 入包, 升级保留现场版本, 新版模板落成 `hosts.rpmnew`; 该文件按 0600 落盘 (使用模式含明文凭据, 不放行同机其他账号读).

> 本包以 **root 运行**为前提: 包内容、profile 与 `/var/log/tsc` 均为 root 属主且仅 root 可用, 本包不创建独立运行用户. 另随包分发 jq 静态二进制于 `envs/tsc_python/bin/jq` (yq 的硬依赖, 激活环境后即可用).

## 卸载

```bash
rpm -e tsc_python
```

包内文件由 rpm 删除, 安装时部署的 profile drop-in (`/home/tsc/tsc_profile.d/01-tsc_python-profile.sh`)
由 `%preun` 无条件回收 (该文件名归属本包独占, 不保留本地修改; 现场自定义片段请另建文件),
空目录壳由 `%postun` 清理; `/home/tsc/tsc_profile` 公共入口、`tsc_profile.d`
目录本身与 `/var/log/tsc` 及运行期日志保留. 现场改过的 `ansible/hosts` 也不会被销毁——
rpm 卸载时将其转存为 `hosts.rpmsave` (`ansible/` 目录壳因此留下, 数据不再需要后可手工清理).

## 环境加载

本包以 profile 片段 (drop-in) 形式暴露环境: `/home/tsc/tsc_profile.d/01-tsc_python-profile.sh`.
公共入口 `/home/tsc/tsc_profile` 按文件名顺序加载 `tsc_profile.d/*.sh`
(首次安装时由本包或 tsc_tools 创建).

> 本 RPM 硬依赖 `tsc_tools >= 2.1.8` (2.1.6 是首次提供 drop-in 加载器的版本, 下限抬到 2.1.8 是因为 rag.md 去重的修复在 tsc_tools 侧), 目标机请先安装 tsc_tools. `%post` 从不改写已存在的 `/home/tsc/tsc_profile`, 仅在其缺失时用包内模板创建 (模板自带加载逻辑), 不会碰 tsc_tools 自己的文件.

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

## 运行要求

准入条件只有两条, **发行版不设门禁** (安装时 `%pre` 强制校验):

1. 本机架构与包架构一致: `x86_64` / `aarch64`;
2. glibc >= 2.17 (musl 系如 Alpine 无 glibc, 不适用; glibc 无法识别时同样拒装).

凡满足上述两条的 Linux 均可安装。已验证环境 (**参考信息, 非准入条件**): CentOS 7.9 / RHEL 7、
openEuler / Euler / HCE、KylinOS V10 (ky10)、FitStarrySkyOS / FitServerOS。
不在此列属"未验证", 不是"不支持".

按架构选用同一个 RPM 包 (`x86_64` / `aarch64`), 两个架构的包仅二进制不同.
