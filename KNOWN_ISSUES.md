# 暂缓事项 (KNOWN ISSUES)

2026-10-13 审查/维护记录的**暂缓处理**项, 按优先级排列。修复任意一项前先读对应上下文;
修复后从本文件删除对应条目, 并在 `release-note.md` 记录。

本轮已处理 (不在本文件): 构建残留混入 RPM (output 清理 + 负面断言)、文档与实现不一致、
micromamba/jq 下载 TLS 校验、pip 层 cryptography、`/var/log/tsc` 0750、冒烟测试 bash 化、
release 时间戳、`--python-version` 校验、`stage/` 失败路径清理、Dockerfile/environment.yml
清理、GPG 签名决策、pip/conda 分层边界 (Dockerfile 过滤 + pack.sh 断言)、drop-in 无条件
归属本包、`func` 单份 (`files/func`)、文档模块 `glow` 在非 TTY 下静默无输出 (按 TTY 分流)、
drop-in 前缀明确保序 (本包 `01-` / tsc_tools `00-`, 不再依赖字母序)、ansible 运行期写入
包内路径 (`home` 改到 `/home/tsc/.ansible`，`retry_files_save_path` 改到
`/var/log/tsc/ansible/retries`，`%post` 补建子目录)、跨包契约无机制校验 (接受现状, 忽略)。
2026-10-24 第二轮审查处理: uv pip 层 `--index-url` 显式注入 (uv 不读 pip.conf, 此前
`pypi_index` 对 pip 层无效)、base.yml 放弃 `%config(noreplace)` (跨 ansible-core 升级会留
stale schema, 见 README-dev §4.8)、build-info.json 缺失改 fail-close 并入产物自检、
release/ 旧产物按 mtime 保留最近 5 份 (打包失败不再连带删除)、jq 收窄到当前架构且随包分发
(`envs/tsc_python/bin`)、depends 补 findutils、root-only 运行前提写入文档、`%post` profile
部署改 `install -d/-m` 固定 mode、新增 CI lint (`ci/lint.sh` + GitHub Actions)。
0.13.6: `package_rpm` 成功路径显式回收 stage 并复位 RETURN trap、模块 run.sh 补
nounset/pipefail、构建入口加 flock 互斥。
0.13.7: 支持口径收敛为"架构 + glibc 两条, 发行版不设门禁"——三份 README 的系统适配
矩阵替换为运行要求 + 非规范性已验证脚注 (消除 ky10/KylinOS 命名漂移与 UOS 行自相
矛盾); `.supported_env.conf` 移至 packaging/rpm/ 聚齐 scriptlet 注入源; build.sh 架构
下载标识收敛单映射并加白名单一致性断言。
2026-10-26 第三轮审查处理: `ansible/hosts` 拆出目录树以 `%config(noreplace)` 单独入包
并收紧 0600 (升级不再覆盖现场 inventory/凭据, 见 README-dev §4.11)、`%pre` glibc 门禁
fail-close 并去掉对 gawk 的隐式依赖、`%post` 日志目录对预存在目录补 chmod 0750、
changehostname 模块 README 命令拼写 (changenhostame.yml → changehostname.yml)、构建
日志前置到下载阶段、micromamba 下载与缓存命中补 sha256 校验 (与 jq 同口径)、
release-note 版本解析锚定标题行、Dockerfile 改 `bash pack.sh`。

---

## 1. tk 无法从环境剔除 (P3) —— 2026-10-13 再确认

conda-forge 的 `python` 包把 `tk >=8.6.13` 列为**运行依赖**，因此 environment.yml 移除显式
`tk` 条目后，`wish`/`wish8.6` 与整套 X 库仍会随 python 进入环境（新构建实测：
`python-3.13.16` 的 depends 含 `tk >=8.6.13,<8.7.0a0`，`env/bin/wish` 存在）。
`typing_extensions`(pyopenssl 传递依赖)、`libgcc-ng`、`python_abi`(python/C 扩展自动带入)
同理——显式条目移除只是去掉冗余声明，改变不了环境内容。

如确需剔除 tk：换 python 分发来源，或打包后手动删（会破坏依赖一致性，**不建议**）。
现状：接受；冒烟测试不测 tkinter。

## 2. 模块 run.sh 规范与 tsc_tools 不一致 (P3) —— 暂缓

tsc_tools 多数功能模块 `source ../../func`; 本包三个 `tsc_python_*` 文档展示型模块
不 `source func` (本包 RPM 也不分发 `func`)。经 `tsc` 分发器调用时可靠父进程
`export -f` 继承 `LOG*`/`__log` (tsc_tools >= 2.1.9 已补 `__log` 导出); 直接跑 `run.sh`
则没有统一日志。各模块现状自洽, **不强制统一**, 接受差异 (0.13.6 已对齐
errexit/nounset/pipefail 三件套)。

另: 两侧 README 都写着 `tsc --模块名 --help` 可看帮助, 实现上 `--help` 仍是透传给模块
的普通参数(由各模块自行处理; tsc_tools 2.1.9 起部分模块已拦截)。要么由 `tsc` 分发器
统一拦截, 要么更正 README——暂缓。

## 3. 小事 (P3)

- `nfpm.yaml.tmpl` 的 `maintainer` 是占位符 `tsc_python maintainers`, 无联系方式 (已决策忽略);
- `smoke_test.sh` 的 TLS 探测默认地址是公网阿里云源, 内网机默认只会 WARN, 可考虑默认
  指向 `pypi_index` (需传入, 暂不值当);
- RPM 内环境含 `info/` (micromamba recipe 元数据), 如需瘦身可在 pack.sh 评估剔除
  (保留则便于现场核对, 现状为保留);
- Dockerfile 工作目录 COPY 是显式文件清单, 漏文件不报错只会静默不随包; 可考虑把
  `files/` 拆 runtime/ 与 tmp/ 两个子目录改整目录 COPY;
- 卸载 (`%preun` 真卸载分支) 后 `rag.md` 不重建, 仍列 tsc_python_* 模块; 可 best-effort
  调一次 `gen_rag.sh` (失败不阻断);
- nfpm 版本无下限断言 (`NFPM_VERSION` 已抓取但只打日志; 语法依赖 2.47.0 验证过的
  `type:` 语法);
- batch_user_manager role `update_password: always` + 无盐 `password_hash('sha512')`:
  每次重跑都会重置密码且任务恒 changed (影响实施流程, 待现场侧评估固定盐或改
  `on_create`);
- `%pre` 的 `check_env` 以 127 表示校验失败 (语义上是 "command not found"), 可换明确的
  自定义退出码;
- `FROM centos:7.9.2009` 未按 digest 钉死, 内网 registry 里的镜像被覆盖时构建无感;
- `requirements.in` 留有大段历史注释 (Django 全家桶等), 可清理。

## 4. 已决策接受 (2026-10-24, 不再处理)

- conda 层依赖不锁定 (仅 python 钉版, 其余随 conda-forge 漂移; conda-forge glibc 基线
  迁移时由 `check_glibc_baseline` fail-close 拦下, 不会流出超标产物) —— 决策: 忽略;
- `ansible.cfg` 的 `host_key_checking=False` —— 团队实施设计, 接受。

(原"micromamba 下载无 sha256 校验"已于 0.13.8 修复并移出本清单。)
