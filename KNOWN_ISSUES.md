# 暂缓事项 (KNOWN ISSUES)

2026-10-13 审查/维护记录的**暂缓处理**项, 按优先级排列。修复任意一项前先读对应上下文;
修复后从本文件删除对应条目, 并在 `release-note.md` 记录。

本轮已处理 (不在本文件): 构建残留混入 RPM (output 清理 + 负面断言)、文档与实现不一致、
micromamba/jq 下载 TLS 校验、pip 层 cryptography、`/var/log/tsc` 0750、冒烟测试 bash 化、
release 时间戳、`--python-version` 校验、`stage/` 失败路径清理、Dockerfile/environment.yml
清理、GPG 签名决策、pip/conda 分层边界 (Dockerfile 过滤 + pack.sh 断言)、drop-in 无条件
归属本包、`func` 单份 (`files/func`)、文档模块 `glow` 在非 TTY 下静默无输出 (按 TTY 分流)、
drop-in 前缀明确保序 (本包 `01-` / tsc_tools `00-`, 不再依赖字母序)。

---

## 1. ansible 运行期写入包内路径 (P1) —— 暂缓

`files/ansible/ansible.cfg`:

- `retry_files_save_path=/home/tsc/tsc_python/ansible/retries` — 失败剧本的 `.retry`
  文件写在 rpm 管辖区内 (目录由 ansible 自动创建, 已核实 `playbook_executor.py` 的
  `makedirs_safe`);
- `home=/home/tsc/tsc_python/ansible/` — ANSIBLE_HOME (galaxy 缓存/tmp 等) 同样落在包内。

后果: 运行期产生无主文件; `%postun` 只删空目录, 卸载后残留。
建议: 改到 `/var/log/tsc` (retry) 与 `/home/tsc/.ansible` (缓存), 或接受现状并文档化。
注意: 改路径会影响现场已有 `.retry` 文件位置, 需在 release-note 提示。

## 2. 跨包契约无机制校验 (P2) —— 暂时无视

与 tsc_tools 的协作全靠约定: `tsc_profile` 公共入口"谁先装谁创建"、drop-in 命名与排序、
`TSC_MODULES_DIR` 拼装方向、`gen_rag.sh` 的归属与调用时机。两侧仓库独立演进, 无交叉校验。

已收口的部分 (不再属于本条): drop-in 前缀改为 `00-tsc_tools` / `01-tsc_python`, 保序不再
依赖文件名字母序; 两侧 `TSC_MODULES_DIR` 声明均已判重, rag.md 膨胀问题已修复。

剩余: 无任何机制在任一侧变更时校验另一侧是否仍兼容。建议: `%post` 里对 tsc_tools 侧
关键文件做存在性/内容抽检 (如 `gen_rag.sh`、`00-tsc_tools-profile.sh`), 不达标时告警
而非失败; 或两侧仓库在同一处维护契约文档。

## 3. tk 无法从环境剔除 (P3) —— 2026-10-13 再确认

conda-forge 的 `python` 包把 `tk >=8.6.13` 列为**运行依赖**，因此 environment.yml 移除显式
`tk` 条目后，`wish`/`wish8.6` 与整套 X 库仍会随 python 进入环境（新构建实测：
`python-3.13.16` 的 depends 含 `tk >=8.6.13,<8.7.0a0`，`env/bin/wish` 存在）。
`typing_extensions`(pyopenssl 传递依赖)、`libgcc-ng`、`python_abi`(python/C 扩展自动带入)
同理——显式条目移除只是去掉冗余声明，改变不了环境内容。

如确需剔除 tk：换 python 分发来源，或打包后手动删（会破坏依赖一致性，**不建议**）。
现状：接受；冒烟测试不测 tkinter。

## 4. 模块 run.sh 规范与 tsc_tools 不一致 (P3) —— 暂缓

tsc_tools 的模块 run.sh 统一以 `set -o errexit / nounset / pipefail` 开头并 `source ../../func`
(经 `tsc` 分发器以子进程调用时, 父进程的 `LOG*` 只经 `export -f` 继承, 不 source 就没有
`__log`, 首次打日志即报错); 本包三个 `tsc_python_*` 模块的 run.sh 都没有, 属于文档展示型
模块, 暂不影响使用, 但错误不会暴露、也没有统一日志输出。

另: 两侧 README 都写着 `tsc --模块名 --help` 可看帮助, 实现上 `--help` 是作为普通参数
透传给模块 run.sh 的 (tsc_tools 侧实测 `tsc --tsc_drop_cache --help` 报"释放阈值必须为整数"),
文档与实现不一致。要么由 `tsc` 分发器统一拦截 `--help` 并打印模块 readme 元数据,
要么更正 README。

## 5. 小事 (P3)

- `nfpm.yaml.tmpl` 的 `maintainer` 是占位符 `tsc_python maintainers`, 无联系方式;
- `smoke_test.sh` 的 TLS 探测默认地址是公网阿里云源, 内网机默认只会 WARN, 可考虑默认
  指向 `pypi_index` (需传入, 暂不值当);
- RPM 内环境含 `info/` (micromamba recipe 元数据), 如需瘦身可在 pack.sh 评估剔除
  (保留则便于现场核对, 现状为保留)。
