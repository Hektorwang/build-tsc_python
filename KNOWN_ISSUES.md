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

tsc_tools 多数功能模块以 `set -o errexit / nounset / pipefail` 开头并 `source ../../func`;
本包三个 `tsc_python_*` 文档展示型模块在 0.13.3 已补 `errexit`, 仍缺 `nounset`/`pipefail`,
且不 `source func`(本包 RPM 也不分发 `func`)。经 `tsc` 分发器调用时可靠父进程
`export -f` 继承 `LOG*`/`__log`(tsc_tools >= 2.1.9 已补 `__log` 导出); 直接跑 `run.sh`
则没有统一日志。各模块现状自洽, **不强制统一**, 接受差异。

另: 两侧 README 都写着 `tsc --模块名 --help` 可看帮助, 实现上 `--help` 仍是透传给模块
的普通参数(由各模块自行处理; tsc_tools 2.1.9 起部分模块已拦截)。要么由 `tsc` 分发器
统一拦截, 要么更正 README——暂缓。

## 3. 小事 (P3)

- `nfpm.yaml.tmpl` 的 `maintainer` 是占位符 `tsc_python maintainers`, 无联系方式;
- `smoke_test.sh` 的 TLS 探测默认地址是公网阿里云源, 内网机默认只会 WARN, 可考虑默认
  指向 `pypi_index` (需传入, 暂不值当);
- RPM 内环境含 `info/` (micromamba recipe 元数据), 如需瘦身可在 pack.sh 评估剔除
  (保留则便于现场核对, 现状为保留)。
