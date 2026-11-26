# tsc_python

## Version=0.13.10

Date=20261126

1. fix(deps): 移除 `passlib`——0.12.0 曾把它作为 `password_hash` 的控制器侧依赖引入, 但该库自 2020 年 1.7.4 后停止维护, 且 Python 3.13 移除了 `crypt` 模块, 此前只能靠它兜底; ansible-core 2.21 起 `password_hash` 内置 `CryptFacade` (ctypes 直接调用 libcrypt, 优先于 passlib, 仅 crypt 不支持的算法才回落 passlib), 本包锁定的 2.21.4 已覆盖。两个 role 的使用点均为 `password_hash('sha512')`, md5/sha256/sha512/bcrypt 全在 crypt 路径内; 实测在无 passlib 环境下 sha512/sha256/bcrypt 与整本 playbook 均正常。**版本红线**: ansible-core 必须 >=2.21——2.18/2.19/2.20 的 `do_encrypt` 只有 passlib 分支, 缺包时建用户任务直接失败; 将来若回退 ansible-core, 必须同时恢复 passlib。
2. chore(deps): `requirements.txt` 与实测环境对齐——`pycparser` 3.0 → 3.11 (该包由 conda 层提供、pip 层安装前被 Dockerfile 过滤, 锁文件里的版本只是解析约束, 此前与实际环境不一致); 其余 18 项与安装树逐一核对一致, 未改动。
3. chore(deps): `environment.yml` 60 个显式条目全部钉到 0.13.10 实测版本 (含 `libxcrypt=4.4.38`)——只钉版本、不钉 build string, 保证 x86_64/aarch64 双架构都能求解, 具体 build 由 conda 按目标架构与 python 版本选择; 传递依赖仍随 conda-forge 漂移。唯一例外是 `charset-normalizer>=3.5.0,<3.5.3` (区间钉法): 3.5.2/3.5.3 只有 linux-64/osx-64/win-64 构建, 钉死 3.5.2 会让 aarch64 求解失败; 区间钉法下 x86_64 解到 3.5.2 (与实测环境一致)、aarch64 解到 3.5.1。两架构 dry-run 均已验证 (各 69 包)。`libxcrypt` 是本次移除 passlib 后的实际密码哈希实现, 不要按"冗余条目"清理 (另有 `cyrus-sasl` 的传递依赖兜底)。
4. docs(KNOWN_ISSUES): "conda 层依赖不锁定"的已决策接受项随本次钉版失效, 改写为钉版后的口径: 显式条目钉版本、传递依赖不锁, glibc 基线仍由 `check_glibc_baseline` fail-close 兜底。

## Version=0.13.9

1. refactor(packaging): 包内 drop-in 源 `files/profile` 改名 `files/tsc_python_profile`(无扩展名, 与 `tsc_profile` 同风格)——与 tsc_tools 2.1.15 同因: 包目录若被前置进 PATH, 裸名 `profile` 会让现场的 `source profile` 静默命中本文件而非其自家脚本; `%post` 部署目标 `01-tsc_python-profile.sh` 不变

## Version=0.13.8

Date=20261026

1. fix(rpm, P2): `ansible/hosts` 拆出目录树、以 `%config(noreplace)` 单独入包并收紧 0600——该文件是三个模块工作流的现场编辑点 (受管主机/端口/root 明文密码), 以普通文件随目录树入包时 `rpm -U` 会用包内模板静默覆盖现场 inventory (无备份无警告); noreplace 语义下升级保留现场版本、新版模板落成 `hosts.rpmnew`, 真卸载时现场改过的版本转存 `hosts.rpmsave` 而非删除。0.13.5 放弃 base.yml `%config(noreplace)` 的理由 (schema 漂移 → `AnsibleUndefinedConfigEntry`) 不适用于 hosts——它是纯数据模板, 不存在缺新配置定义的问题。实现: `build.sh` 打包期把 stage 树中的 `tsc_python/ansible/hosts` 移出为 `stage/ansible-hosts` 并 `chmod 0600` (使用模式含明文凭据, 0644 会暴露给同机其他本地账号; nfpm 单文件条目沿用源文件 mode), `nfpm.yaml.tmpl` 增加独立 content 条目, 产物自检 `need_file` 补该路径
2. fix(rpm, P3): `%pre` 的 glibc 门禁 fail-close——`getconf GNU_LIBC_VERSION` 检测不到时由 "WARNING + 跳过校验" 改为中止安装: musl 系 (Alpine) 上此前会放行安装、运行期才以 `version GLIBC_2.xx not found` 暴露, 与 README "musl 系不适用"的口径不符; `getconf` 属 glibc 自带, glibc 系必有, 检测不到即拒装不会误伤受支持环境。顺带把检测链里的 awk 去掉 (`${out#* }` 剥前缀取版本)——门禁脚本不再隐式依赖 gawk (nfpm depends 未声明它, awk 缺失时 `%pre` 会在 errexit 下以 127 中止且报错误导)
3. fix(rpm, P3): `%post` 日志目录对预存在目录补 `chmod 0750`——GNU `install -d -m` 只对新建目录套 mode (实测), `/var/log/tsc` 已存在时 (tsc_tools 先建/旧版本以更松权限建过) 0750 意图静默落空, 显式 chmod 兜住"不放行 other 读"
4. fix(modules, P3): changehostname 模块 README 的命令拼写 `roles/changenhostame.yml` 更正为 `roles/changehostname.yml` (实际文件名), 照抄即 file-not-found; 该 README 经 `gen_rag.sh` 汇入 rag.md, 错误此前随包分发
5. fix(build, P3): 构建日志前置——`log_file` 原在 `build_target` 内才赋值, 配置摘要与 micromamba/jq 下载 (最易出网络故障的阶段) 只上控制台、不落 `log/*.log`; 现 `mkdir`/`log_file` 前置到参数解析之前, 全程可追溯; 连带 `build_target` 的 `tee` 改 `tee -a`——`log_file` 提前开启后, 无 `-a` 的 `tee` 会截断文件、冲掉已写入的前置日志 (旧实现里赋值恰在 `tee` 之前, 该问题从未暴露)
6. feat(build): micromamba 下载补 sha256 校验, 与 jq 同一口径——按版本×架构钉死 `micromamba_sha256_<arch>` 常量 (2.9.0: x86_64 `8761c382…3040dd` / aarch64 `e705ffee…a5852f`), 下载先落 `.dl` 临时文件校验通过再 mv, 缓存命中亦复验校验和; 常量与 `jq_sha256_<arch>` 一同纳入白名单一致性断言, `supported_env.conf` 头注释 checklist 同步; 0.13.7 KNOWN_ISSUES 的"已决策接受 (仅 TLS 保护)"就此收回
7. fix(build): `release-note.md` 版本解析锚定标题行 (`/^#+[[:space:]]*Version=/`, build.sh 与 files/pack.sh 同步)——原非锚定 `/Version=/` 取全文件第一个命中, 若未来版本条目正文在标题前出现 "`Version=`" 字样会解析到错误版本
8. fix(docker): `RUN sh pack.sh` 改 `RUN bash pack.sh`——pack.sh 是 bash 脚本, 原写法依赖 CentOS 的 sh→bash, 换 sh=dash 的基础镜像即碎

## Version=0.13.7

Date=20261024

1. docs: 三份 README 的"系统适配"矩阵 (中英主 README 与随包 readme) 替换为"运行要求"——准入条件只有架构一致与 glibc>=2.17 两条, 与 %pre 实际门禁一一对应, **发行版不设门禁**; 原矩阵中机器强制的只有 centos-6 (glibc<2.17 的推论) 与 Alpine (无 glibc) 两行, 其余是"在哪些环境测过"的测试记录却被当成准入条件维护, 且已漂移 (ky10/KylinOS V10 命名不一、UOS 无原因"不支持"与兜底行"其他 glibc>=2.17 理论兼容"自相矛盾)。已验证清单降级为一句非规范性脚注 (CentOS 7.9 / RHEL 7、openEuler / Euler / HCE、KylinOS V10 (ky10)、FitStarrySkyOS / FitServerOS), 不在列属"未验证"而非"不支持", UOS 相应归入未验证
2. refactor(build): `.supported_env.conf` 移至 `packaging/rpm/supported_env.conf`——该文件实际是 %pre 的注入源 (与 lib_min.sh / env_check.sh 同类), 移动后 packaging/rpm/ 聚齐全部 scriptlet 注入源, 根目录不再有点文件; 文件内容即支持条件的全部定义, 名实相符; preinstall.sh.tmpl 的 INJECT 路径与相关注释同步
3. feat(build): 架构 → 第三方组件下载标识收敛为单一 `arch_download_tags()` (原先 micromamba 与 jq 各写一个 case, 可漂移), 并新增支持白名单一致性断言: 本机架构必须在白名单内、白名单每一项都必须有下载映射与 `jq_sha256_<arch>` 常量——白名单加了架构而映射/sha 漏改时, 会打出 %pre 拒装自己目标架构的包, 现在构建期即拦下; conf 头注释附新增架构 checklist

## Version=0.13.6

Date=20261024

1. fix(build): `package_rpm` 成功路径显式回收 `stage/` 并复位 RETURN trap——原 trap 在函数返回后不复位, 其后每个函数返回 (含 LOG*) 都会再触发一次 `rm -rf stage`, 幂等但属卫生问题; 失败路径仍由 RETURN trap 回收, 脚本级 EXIT trap 兜底不变
2. fix(modules): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 run.sh 补 `set -o nounset` / `set -o pipefail` (0.13.3 已补 errexit), 与 tsc_tools 侧模块规范对齐
3. fix(build): 构建入口加 flock 互斥 (仓库根 `.build.lock`, 已入 .gitignore, 非阻塞)——同机并发 `build.sh` 会互踩 `output/<arch>` 清空与 `release/` 旧产物回收, 现第二个实例直接退出并提示; 打包机缺 flock 时显式报错而非静默失去互斥

## Version=0.13.5

Date=20261024

1. fix(build/Dockerfile, P0): pip 层补 `--index-url`——uv 不读取 pip.conf (官方兼容性约定, 亦不读 `PIP_INDEX_URL` 等 pip 专属配置), 此前 `uv pip install` 一直从默认 pypi.org 解析, `build.conf` 的 `pypi_index` 对 pip 层实际无效: 有公网的构建机无感, 离线内网机构建会失败且报错误导; 现由 build.sh 经 `--build-arg PYPI_INDEX` 注入, `uv pip install --index-url` 显式指定, 并加空值断言拦下漏传
2. refactor(rpm): 放弃 base.yml 的 `%config(noreplace)`, 改为普通文件随批量安装树入包——noreplace 保住的是整份旧 schema: 一旦升级同时抬高 ansible-core 版本, 现场保留的旧 base.yml 缺少新版新增配置定义, ansible 访问即抛 `AnsibleUndefinedConfigEntry`, 而新版原版被落成 `base.yml.rpmnew`, `%post` 补丁不合并它, 需现场手工恢复; 普通文件形态下升级由 rpm 覆盖为新版原版, `%post` 幂等重打解释器补丁; base.yml 本就不是现场定制点 (ansible.cfg 才是), `rpm -V` 不再报 config 差异。连带移除 pack.sh 的 `stage_ansible_base` 与 build.sh 的暂存并入/哨兵区间摘除/批量树防御删除
3. fix(build): `build-info.json` 缺失由 WARNING 放行改为中止打包, 并纳入产物自检 `need_file`——pack.sh 无条件生成该文件, 缺失即容器侧异常, 与其余门禁 (glibc/占位符/python 版本) 的 fail-close 口径对齐
4. fix(build): release/ 旧产物不再打包前全删 (原写法下 nfpm 一旦失败, 本机上一份可用 RPM 已被删掉)——现仅清同 NVR 目标文件, 打包成功后按 mtime 只保留最近 5 份 (含对应 `.sha256`)
5. refactor(build): jq 缓存与容器注入收窄到当前架构——`ensure_jq` 原本强制双架构二进制齐备, x86_64 构建机会因 aarch64 jq 下载失败而中断; Dockerfile 改 `COPY ./files/tmp/jq-${ARCH}` (BuildKit, build.sh 传入 `--build-arg ARCH`)
6. feat(rpm): jq 静态二进制随包分发于 `envs/tsc_python/bin/jq`——yq 的硬依赖, 目标机未必自带 (EL7 无 jq 且 EPEL 已不可用); 放 env bin 而非 mamba root bin: micromamba activate 只把 root 的 condabin 挂上 PATH, root bin 不在其中, 放那里 yq 找不到; 二进制纯静态链接, 不引入额外 glibc 要求。THIRD_PARTY_NOTICES 中英同步 (jq 随包分发, MIT); 冒烟测试 jq 检查改查包内 `${ENV_BIN}/jq` (未激活环境也能命中)
7. feat(rpm): `%post` 的 profile 与日志目录部署改 `install -d -m` / `install -m 0644`——目标机收紧的 umask (如 0077) 不再影响落盘权限; drop-in 部署失败的错误语义不变
8. fix(rpm): depends 补 `findutils`——`%postun` 用 find 自底向上清理本包空目录壳, 既有 depends 已声明 grep/sed/coreutils, 补齐同一口径
9. docs: README 中英 / files/README / README-dev 声明本包以 root 运行为前提 (包内容、profile 与 `/var/log/tsc` 均 root 属主, 不创建运行用户)
10. ci: 新增 `ci/lint.sh` (shellcheck + bash -n, scriptlet 模板按 build.sh 同一语义渲染后检查) 与 GitHub Actions workflow; 本地可直接 `bash ci/lint.sh`。顺带修掉存量 lint 发现: `NFPM_VERSION`/`local backup` 声明与赋值分离 (SC2155), smoke_test 移除未用的 `C_STD`
11. docs(KNOWN_ISSUES): 记录 2026-10-24 第二轮审查的暂缓项与已决策接受项 (micromamba 无校验和/conda 不锁定/host_key_checking 为团队设计等)

## Version=0.13.4

Date=20261014

1. fix(modules, P0): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 `run.sh` 第 19 行 `show_readme "${WORK_DIR}"/"README.md` 引号未闭合, bash 报 `unexpected EOF while looking for matching '"'`, **三个模块整份不可用**; 该缺陷由 0.13.2 的"按 TTY 分流"改动引入, 0.13.2 与 0.13.3 两个已发布版本均受影响
2. fix(build): 打包期增加随包脚本语法自检——对 stage 内本包自带的 `modules/*/run.sh` 与 `smoke_test.sh` 逐个 `bash -n`; 此前 `bash -n` 只遍历 `stage/rpm-scripts/*`, 产物自检只查存在性与可执行位, 语法错误会一路随包发布(范围限定为包自有脚本: conda 环境内散落大量不由本仓维护的 `*.sh`, 全量纳入只会引入噪音)
3. fix(Dockerfile): pip 层 `RUN` 的 `|| true` 收窄到 arch 判断本身——原写法 `A && B && C && D || true && E && G` 左结合, `micromamba activate` 失败会被 `|| true` 救成真, `uv pip install` 继续在未激活的环境(EL7 上是系统 python 2.7)里执行, 装出的包根本不在 payload 中而构建仍标记成功; 另加 `CONDA_PREFIX` 断言, activate 未生效即构建失败
4. fix(build): jq 下载后补 sha256 校验——先落 `.dl` 临时文件, 校验通过再 `mv` 到目标; 此前 `jq_sha256_*` 两个常量只用于校验**已有缓存**, 新下载的二进制 `chmod +x` 后直接使用, 与 README "sha256-verified" 的描述不符, 损坏/被篡改的二进制会原样进容器
5. fix(pack.sh): `check_pip_conda_overlap` 去掉 `2>/dev/null || true`——解释器损坏、heredoc 异常等任何失败都被吞成空串, 使这条"构建期兜底断言"恒为通过 (fail-open); 现扫描失败即中止出包, 且扫描到的 `dist-info` 数为 0 时(判定方法失效的假阴性)同样中止
6. fix(pack.sh): `check_glibc_baseline` 由 fail-open 改为 fail-close——缺少 `objdump` 或未扫到任何 ELF 符号时禁止出包(此前只 WARNING 放行, 超标产物会静默流入现场); 扫描范围由 `-type f` 改为 `! -type d` 并放宽体积过滤: conda 环境里大量 `.so` 是软链 (`libfoo.so -> libfoo.so.1`), 只扫常规文件会漏掉它们身上的 `GLIBC_` 符号要求
7. fix(pack.sh): `PYTHON_VERSION` 补 `|| true`, 与下一行 `MICROMAMBA_VERSION` 对称——python 缺失时管道在 `pipefail` 下返回非零, `errexit` 会在 `:-unknown` 兜底生效之前终止整个构建
8. fix(build): 增加 `@PYTHON_MM@` 与真实环境的一致性断言——`py_mm` 由 `environment.yml` 文本正则抠出, 真实目录名由 conda 解析结果决定, 二者漂移会让 `base.yml` 以一个不存在的路径入包, `%post` 的 patch 与 `%config(noreplace)` 同时失效而产物自检无感
9. fix(build): `nfpm.yaml` 渲染后反向断言无残留 `@XXX@` 占位符(模板新增占位符而 `build.sh` 漏配 `-e` 时会静默出包); `py_mm` 解析改用 `sed -n '1p'` 替代 `head -n1`(head 提前退出会让上游 grep 收到 SIGPIPE 返回 141, 在 `pipefail` + `errexit` 下脚本无任何提示直接中断); `NFPM_VERSION` 补 `|| true`
10. fix(build): `stage/` 与构建期临时配置改由 EXIT trap 统一回收——`package_rpm` 的 RETURN trap 只在函数正常返回时触发, Ctrl-C 中断路径下不触发, 会留下 GB 级 payload 拷贝
11. fix(build): 产物自检补 `patch_ansible.py` 与 `%config(noreplace)` 的 `base.yml`——后者是唯一的 config 条目, 暂存缺失时 `build.sh` 的兜底会删掉整段, 不在此断言的话产物会静默丢掉 ansible 解释器回退配置
12. fix(rpm/postinstall): drop-in 部署失败由无条件 `LOGSUCCESS` 改为 `LOGERROR`——本脚本不设 `errexit`, `cp` 失败(磁盘满/权限)时安装者看到"部署成功"而环境实际未生效; 调用点同步改为显式报错
13. fix(rpm/scriptlet): `%pre`/`%post` 的 `BASH_VERSION` 判断移到 `set +o posix` 与 `shopt -s nullglob` 之前——rpm 一律用 `/bin/sh` 执行 scriptlet, 若 `/bin/sh` 是 dash, 这两行会先以 `Illegal option`/`not found` 失败并退出, 友好提示永远打不出来
14. docs: README 中英与 README-dev 的 tsc_tools 版本口径统一为 2.1.8(本包硬依赖下限; 提 2.1.7 处注明其为首个提供 drop-in 加载器的版本); README-dev §2 打包流程表"三个脚本"更正为四个, 并补记随包脚本自检与 `@PYTHON_MM@` 断言两步
15. fix(build): `nfpm.yaml.tmpl` 的 ansible `base.yml` 段改用哨兵注释 `# >>> BEGIN/<<< END ansible_base_noreplace` 界定——此前 `build.sh` 的兜底 `sed` 区间锚在中文注释文案与 `type: config|noreplace` 两处, 改注释即失效(产物带指向不存在 src 的条目, 报错与真实原因无关), 结束行被改时更会一路删到文件尾把 `scripts:` 段一起删掉而 nfpm 不报错; 摘除后新增断言(`grep -q ansible_base.yml` 必须为空), 摘不掉即中止打包
16. docs(profile): `TSC_MODULES_DIR` 的判重保持原有的"两端补冒号 + 子串匹配"三行写法——该变量只由本工具链的 drop-in 追加, 不存在需要规范化处理的书写变体; 一度引入的规范化+逐段比较已回退, 与 tsc_tools 2.1.10 侧保持一致

## Version=0.13.3

Date=20261013

1. fix(modules): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 run.sh 补加 `set -o errexit`——原先无错误退出保护, 模块内命令失败时 `tsc` 分发器静默继续
2. fix(build/pack.sh): `prepare_payload` 的 `chmod 0755` 从 glob 展开改为 `find -exec`——`shopt -s nullglob` 下 glob 无匹配时展开为空, `chmod` 无参数报错并触发 `set -o errexit` 退出, 改用 `find` 避免该问题
3. fix(rpm/postinstall.sh.tmpl): 删除 `id tsc && chown tsc: ${LOG_DIR}` 死代码——整个代码库从未创建过 `tsc` 用户, 该判断永远为假, 是 makeself 时代的遗留; 日志目录 owner 保持 root
4. fix(build): `build.sh` 开头固定 `umask 022`, 与 `tsc_tools` 对齐, 避免打包机 umask 收紧时静默削掉未显式 chmod 的文件权限
5. docs: 对齐文档与实现——README 中英 `%preun` 描述由「hash 清单」改为按文件名无条件回收; 中文表 tsc_tools drop-in 改为 `00-`; micromamba 离线缓存示例版本 `2.5.0` → `2.9.0`; KNOWN_ISSUES 同步 0.13.3 已补 `errexit` 的现状; README-dev 记录 umask 已固定
6. fix(ansible): `ansible.cfg` 两处运行期写入路径移出 RPM 管辖区——`home` 由 `/home/tsc/tsc_python/ansible/` 改为 `/home/tsc/.ansible` (ANSIBLE_HOME, galaxy 缓存/tmp 等不再落入包内); `retry_files_save_path` 由 `/home/tsc/tsc_python/ansible/retries` 改为 `/var/log/tsc/ansible/retries` (失败剧本的 `.retry` 文件改入日志目录); `%post` 补建 `/var/log/tsc/ansible/retries` 子目录并设 0750 权限。现场已有 `.retry` 文件仍在旧路径, 可手动迁移至新目录
7. fix(rpm): `patch_ansible.py` 的 `INTERPRETER_PYTHON_FALLBACK` 列表只保留本包 RPM 形态的解释器路径——移除自解压包时代的残留路径 (`/home/tsc/tsc_tools/micromamba/...`、`miniconda3`、`.pyenv`), 那些安装形态已由 `%pre` 轮转、路径不复存在, 留在列表里只会干扰解释器发现。注意: 从旧版本升级的机器上 `base.yml` 为 `%config(noreplace)`, 已插入的旧路径不会被动掉, 如需清理可现场手动编辑或删除包内 base.yml 后重装
8. refactor(build): 版本号解析统一为 awk 一种写法 (`files/pack.sh` 与 `build.sh` 一致: 取 `release-note.md` 第一个 `Version=` 行并去空白; 原先 pack.sh 用 `grep -oP`, 两套解析可漂移), `package_rpm` 增加断言——`build-info.json` 的版本与 RPM NVR 不一致即中止打包, 保证包内元数据与包版本一致

## Version=0.13.2

Date=20261013

1. fix(modules): 三个文档模块 (`tsc_python_ansible`/`tsc_python_batch_user_manager`/`tsc_python_changehostname`) 的 run.sh 原来统一 `find ... -exec glow {} +`, glow 传文件路径时进 TUI 模式, stdout 非 TTY (管道/重定向/输出被上层接管) 时静默输出空内容——`tsc --tsc_python_ansible` 什么都看不到。改为按 TTY 分流: 交互式仍走 glow 翻页, 非交互式直接输出 readme 原文
2. fix(rpm): 硬依赖 `tsc_tools >= 2.1.6` 提升为 `>= 2.1.8`——本包 `%post` 调用 tsc_tools 的 `gen_rag.sh`, 而 `rag.md` 膨胀的根因 (`TSC_MODULES_DIR` 重复追加) 修在 tsc_tools 侧 (其 drop-in 判重 + `gen_rag.sh` 去重); 依赖不抬到 2.1.8 则修复在目标机上不生效, 仍会产出成倍重复的 rag.md
3. docs: 跨包 drop-in 前缀由"两侧同为 `01-`、靠文件名字母序"改为 tsc_tools `00-` / 本包 `01-`, 明确保序 (README 中英、README-dev、profile 与 `%post` 注释同步); 两侧对 `TSC_MODULES_DIR` 的拼装方向相反, 两种加载顺序下结果一致
4. docs(KNOWN_ISSUES): 记录模块 run.sh 与 tsc_tools 规范不一致 (缺 `set -o` 与 `source func`) 及 `tsc --模块名 --help` 文档与实现不符, 均暂缓
5. docs: README 中英"基本用法"补充构建前置条件——无 `build.conf` 时 `bash build.sh` 会直接报"yum 源地址未配置"退出, 需先 `cp build.conf.example build.conf` 填好 `repo_local`, 或显式传 `--repo-local`

## Version=0.13.1

Date=20261012

1. fix(build): 修复构建残留混入产物——`docker cp` 取回前整体清空 `output/<arch>/` (cp 是目录合并语义, 不清会把旧布局残留合并进 payload); `package_rpm` 增加 payload 顶层负面断言 (只允许 `tsc_python`, 出现其他目录直接中止打包)。此前旧布局的 `tsc_tools/{ansible,modules}` 残留会被打进 RPM, 与 tsc_tools 命名空间冲突 (安装文件冲突/卸载误删)
2. fix(build): `release` 号由构建日期改为构建时间戳 (`YYYYMMDDHHMMSS`), 同日多次构建的 NVR 可区分
3. fix(build): `--python-version` 入口校验格式 (`3.13` / `3.13.12` 形式), 非法值提前报错而非到容器内才失败; micromamba/jq 下载去掉 `--insecure`, 恢复 TLS 证书校验
4. fix(deps): pip 层安装前过滤 conda 已提供的原生库 (`cryptography` 及构建依赖 `cffi`/`pycparser`), 避免锁文件里的 pip wheel 在版本漂移时覆盖 conda 构建版; `requirements.txt` 按文档规定的 `--no-header --no-annotate` 重新生成 (无自动头, 无 `# via` 注释)
5. chore(env): environment.yml 清理冗余显式条目——`sqlite` CLI (保留 `libsqlite` 即可, 已验证从环境移除)、`typing_extensions` (与 `typing-extensions` 重复)、`libgcc-ng` (`libgcc` 旧别名)、`python_abi`、`tk`; 后四项实际由传递依赖带入 (conda-forge 的 python 包把 tk 列为运行依赖), 显式条目移除后仍存在于环境中, 详见 KNOWN_ISSUES
6. fix(rpm): `/var/log/tsc` 权限 0755 → 0750 (ansible 日志可能含敏感信息)
7. fix(rpm): 冒烟测试统一以 `bash` 运行 (脚本增加被 `sh` 调用时自动转交 bash 的保护)
8. chore(build): `stage/` 由 `package_rpm` 的 RETURN trap 在成功/失败路径统一回收 (此前失败路径不清理); Dockerfile 工作目录 COPY 改为显式文件列表, 不再把 `files/tmp/` 的 micromamba/jq 缓存带入镜像层
9. docs: 更正文档与实现不一致——删除不存在的"旧版 tsc_tools bootstrap 加载块兜底"描述 (实际由 `tsc_tools >= 2.1.6` 硬依赖拦下, `%post` 只在不覆盖已有 `tsc_profile` 的前提下创建); 更正 `rpm -V` 说明 (`%config(noreplace)` 保证升级保留现场 patch, 但校验仍会报 patch 过的 base.yml, 属预期行为); THIRD_PARTY_NOTICES 更正 func 分发描述 (构建期使用, 不随安装包分发); tsc_tools drop-in 名称按 2.1.7 实际命名 `01-tsc_tools-profile.sh` 更正; README 示例 python 版本与 `environment.yml` 默认值对齐
10. chore: 产物不做 GPG 签名 (已决策, 见 README-dev §4.9); 新增 `KNOWN_ISSUES.md` 记录暂缓事项
11. fix(deps): pip/conda 分层边界落地——Dockerfile 过滤列表补充 `packaging`/`typing-extensions` (conda 同样提供, 防止锁文件与 conda 解析漂移时被 pip wheel 覆盖); `files/pack.sh` 新增 `check_pip_conda_overlap` 构建期断言 (某包 dist-info/INSTALLER 为 pip/uv 且 conda-meta 同名, 即禁止出包)
12. refactor(rpm): drop-in `01-tsc_python-profile.sh` 明确为本包独占——每次安装/升级用包内版本刷新, `%preun` 真卸载时无条件回收, 不再保留本地修改; 移除 `.installed_manifest` hash 清单机制 (现场自定义片段请另建文件, 如 `99-local-profile.sh`)
13. chore: `func` 仅保留 `files/func` 一份 (根目录副本已删除, `build.sh` 改源 `files/func`; 容器内 `pack.sh` 本就源同一份)
14. chore: environment.yml 清理结论按实测更正——`sqlite` CLI 已从环境移除; `tk` 由 conda-forge python 包的运行依赖带入, 删显式条目无法剔除 (见 KNOWN_ISSUES)
15. chore: 默认版本对齐 `build.conf.example`——environment.yml 与 README 示例统一到 python 3.13.16, micromamba 兜底默认值统一到 2.9.0 (双架构均已核实可下载)

## Version=0.13.0

Date=20261012

1. refactor(build): 制成品由 makeself 自解压包改为 RPM, 产出 `release/tsc_python-<version>-<release>.<arch>.rpm` (`version` 取自本文件 `Version=`, `release` 为构建日期); 打包脚本集中到 `packaging/rpm/`
2. refactor(build): 容器内 `files/pack.sh` 不再打自解压包, 改为组装安装树 `output/<arch>/payload/` (镜像 `/home/tsc` 布局) 并生成 `build-info.json`; RPM 由宿主机 `build.sh` 用 nfpm 打包——nfpm 不必进入构建容器, 且宿主机可直接对产物做 `rpm -q` 自检
3. feat(build): 打包前检查打包机是否提供 `nfpm` (默认 `/bin/nfpm`, 可用 `NFPM_BIN` 覆盖), 缺失时明确报错退出; 四段 scriptlet 逐个 `bash -n` 语法自检; 渲染完整性断言 (注入文件存在、`@ARCH@` 已替换)
4. feat(build): 产物自检包含包信息/依赖/文件数/关键文件是否齐全 (profile 源与公共入口模板、micromamba、环境 python3 与 ansible、smoke_test.sh、ansible.cfg、模块 run.sh)/关键文件可执行位/四段 scriptlet 是否写入
5. feat(rpm): `%pre` 做环境准入校验 (root 权限、CPU 架构须与本包架构一致且在 `.supported_env.conf` 白名单内、glibc >= 2.17), 不通过则中止安装, 不留下半成品文件——原先自解压包是先解包再校验
6. feat(rpm): `%pre` 发现已有非 RPM (自解压包时代) 安装时, 先把 `/home/tsc/tsc_tools/micromamba` 轮转为 `micromamba.bak.<时间戳>`, 避免两套文件混装; 升级 (rpm -U) 时该目录由本包旧版本持有, 原样保留
7. feat(rpm): `%post` 承接原 `install.sh` 的收尾动作 (模块 `run.sh` 可执行位、`/var/log/tsc` 日志目录、`gen_rag.sh` 重建 `rag.md`、`patch_ansible.py` 打解释器补丁), 各步骤幂等; `%preun` 仅在真卸载 (`$1==0`) 时回收, 升级交由新包 `%post` 重建
8. refactor(path): 环境本体从 `/home/tsc/tsc_tools/micromamba` 迁到 `/home/tsc/tsc_python`——不再是"塞在 tsc_tools 下的一个子目录", 而是与 tsc_tools 平级的独立组件; 随包文档/工具与 `build-info.json` 同步改为 `/home/tsc/tsc_python/`, 自解压包时代的旧目录仍由 `%pre` 轮转
9. feat(rpm): profile 改为与 tsc_tools 同构的 drop-in 模型——`/home/tsc/tsc_profile` 是公共入口 (只 source `/home/tsc/tsc_profile.d/*.sh`, 谁先装谁创建, 所有工具卸载都不删), 本包片段由 `%post` 部署为 `tsc_profile.d/01-tsc_python-profile.sh` (源为随包的 `/home/tsc/tsc_python/profile`), 数字前缀决定加载顺序 (`01-tsc_tools-profile.sh` 在前); 卸载由 `%preun` 按 `<ENV_ROOT>/.installed_manifest` 里的 sha256 校验回收 (片段被改过则保留), 目录壳由新增的 `%postun` 清理
10. feat(profile): drop-in 增加 `TSC_MODULES_DIR` 声明——tsc 与 `gen_rag.sh` 靠该变量 (冒号分隔多目录) 发现模块, 本包因此自建声明, 使单独安装 tsc_python 时 `tsc` 也能看到 `tsc_python_*` 模块; 已由 `01-tsc_tools-profile.sh` 声明过同一目录则跳过, 避免重复项让 `gen_rag.sh` 把同一份 readme 收录两次
11. fix(rpm): `%post` 清理早期形态的 drop-in `tsc_python.sh` (无包认领时删除), 避免升级后同一份环境被加载两次; `%post` 顺序调整为先部署 profile 再跑 `gen_rag.sh`, 使后者能取到 `TSC_MODULES_DIR`
12. feat(rpm): `%pre` 新增 `rotate_legacy_profile`——自解压包时代留下的 `/home/tsc/tsc_python_profile` 及其在 `tsc_profile` 里的旧 `source` 行已过时, 与旧环境目录一样按"`rpm -qf` 认领则跳过"的规则轮转/摘行, 避免两份 profile 并存说不清哪份生效
13. chore: 构建依赖与文档去掉 makeself (不再参与打包); 随包文档与工具路径改用新环境根目录 `/home/tsc/tsc_python/`
14. feat(rpm): RPM 新增硬依赖 `tsc_tools >= 2.1.6` (见 `packaging/rpm/nfpm.yaml.tmpl` 的 `depends`)——`/home/tsc/tsc_profile` 加载 `tsc_profile.d/*.sh` 的加载器由该版本起提供; 低于此版本时 `%post` 虽会 bootstrap 一段加载块兜底, 但建议直接装对齐版本
15. fix(pack): 环境内二进制 (`tsc_python/bin/*`、`envs/tsc_python/bin/*`) 在打包时归一化到 0755——构建容器 umask 002 会让它们带上组写位 (0775), 共享目录 /home/tsc 下 root 所有的二进制保持 0755 更干净, 也避免产物自检因权限非 0755 而失败

## Version=0.12.0

Date=20261004

1. feat: 新增 `tsc_python_batch_user_manager` 模块: 批量建立管理机到目标机的 root 信任; 批量创建业务用户并赋予免密码 sudo, 建立到业务用户的 ssh 信任; 按 `create`/`check`/`delete` 三个剧本组织, 以 `root`/`user` 标签选择执行范围; 全程原生 ansible 模块, 适配 RHEL 系与 DEBIAN 系 (sudo 缺失显式报错, SELinux enforcing 下自动修正 `.ssh` 上下文, 校验强制仅密钥连接防误判)
2. fix(requirements): 新增 `passlib`: ansible `password_hash` 过滤器的控制器侧依赖, 缺失时创建用户的任务会直接失败
3. feat(modules): 模块 readme 增加 front matter (category/keywords/description/usage), run.sh 补可执行位; `install.sh` 在合并 modules 后调用 tsc_tools (>= 2.1.7) 的 `gen_rag.sh` 重建 `rag.md`, 使 `tsc` 命令入口可查询并调用本包模块
4. chore(modules): 确立模块命名规范 — tsc_tools 自有模块用 `tsc_` 前缀, tsc_python 插件模块统一 `tsc_python_` 前缀; tsc_tools 升级安装按此前缀识别并保护插件内容 (退役的 `tsc_ssh_authorize` 模块本轮不再随包分发)

## Version=0.11.0

Date=20261001

1. feat: 包命名去除发行版标识, 改为 `tsc_python-<version>-<arch>-<date>.sh`; 环境统一在 CentOS 7.9 (glibc 2.17 基线) 容器中构建, 单架构单包兼容 glibc >= 2.17 的 Linux 发行版
2. feat: `build.sh` 增加 glibc 符号扫描门限检查, 环境内 ELF 的最高 GLIBC_ 要求超过 2.17 时禁止出包; 元数据 JSON 的 `os_variant` 字段替换为 `glibc_baseline`
3. fix(install.sh): `check_env` 由校验发行版家族改为仅校验目标机架构; 安装时创建 ansible 日志目录 `/var/log/tsc` 并归属 tsc 用户
4. chore: 依赖移除 `pyinotify` (0.9.6 依赖 py3.12 已移除的 asyncore, 无法 import), 增加 `watchdog`
5. chore: `Euler.dockerfile` 退役, 构建容器统一为 `Dockerfile` (centos:7.9); `build.sh` 移除 `-t/--target` 参数, 收敛为单架构单构建
6. chore: jq 改用静态二进制 (1.8.1, 双架构), 构建不再依赖 EPEL, `epel-local` 源移除
7. chore: conda-forge 与 PyPI 源统一切换到教育网联合镜像站 (`mirrors.cernet.edu.cn`); 新增 `THIRD_PARTY_NOTICES.md` 随包分发第三方组件声明
8. feat: 构建源全部可配置: `build.conf` 新增 `pypi_index`/`conda_forge` 键, `build.sh` 新增 `--pypi-index`/`--conda-forge` 参数; `files/pip.conf` 与 `files/.condarc` 移除, 改为构建时生成到 `files/tmp/`
9. feat: `makeself` 与 `jq` 改为与 micromamba 相同的缓存优先按需下载模式 (jq 带 sha256 校验), 第三方组件不再随仓库分发, 移除无引用的 `argbash` 存档
10. chore: 开源准备: 新增 GPL-3.0 `LICENSE` 与源码文件 SPDX 标识; 内网地址移出版本控制 (`build.conf` 移出跟踪并提供 `build.conf.example`); `THIRD_PARTY_NOTICES` 拆分为中英文文件 (`THIRD_PARTY_NOTICES.md` / `THIRD_PARTY_NOTICES.zh_CN.md`), README 提供中英文版本 (`README.md` / `README.zh_CN.md`)
11. chore: `release-note.md` 与 `THIRD_PARTY_NOTICES*.md` 移至仓库根目录并随产物分发; `RedHat.dockerfile` 更名为 `Dockerfile`; `build-local.sh` 更名为 `build.sh`, 容器内 `files/build.sh` 更名为 `files/pack.sh`
12. docs: README 新增依赖管理与 pip-compile 锁定流程说明 (`--no-header --no-annotate`, 锁文件保持源无关); `requirements.txt` 头部注释移除 (生成物不保留流程注释), 声明层注释保留在 `requirements.in`

## Version=0.10.0

Date=20260507

1. feat: 修改 ansible 查找 interpreter 的路径, 在原 `ansible/config/base.yml` 中的 `INTERPRETER_PYTHON_FALLBACK.default` 列表插入 `tsc_python` 和 `tsc_pyenv` 的 python3 路径

## Version=0.9.7

Date=20260331

1. feat: 因为 ansible==2.9.27 已经无法在 python==3.13.12下工作, 改为使用 ansible-core

## Version=0.9.6

Date=20260330

1. chore: 默认python版本修改到 3.13.12
2. chore: 组件版本随之微调
3. TODO: modules里面工具还没弄过
4. TODO: ansible 和 ansible-runner 的版本问题

## Version=0.9.5

Date=20260319

1. feat: 增加本地构建配置文件 `build.conf`, 若本地构建时, 不指定参数则使用该配置文件中的内容
2. fix: 修复 func 中滚动更新文件夹的不适配低版本 bash 问题
3. fix(install.sh): 修复了在解压和拷贝文件时没有上级目录的问题
4. feat(environment.yml): 固化版本
5. feat: 使用micromamba创建环境时指定仅使用 conda-forge 源, 避免使用 anaconda 源带来的版权问题

## Version=0.9.4

Date=20260318

1. refact: 改为本地构建方式，使用 `build-local.sh` 在本机同架构容器中执行打包，不再依赖 `buildx` 跨架构编译。
2. refact: `build-local.sh` 引入 `func` 日志系统，统一日志格式，支持 `getopt` 参数解析。
3. feat: `build-local.sh` 新增 `build.conf` 配置文件支持，`-m`/`-r`/`-p` 参数优先于配置文件，配置文件优先于内置默认值。
4. feat: `build-local.sh` 支持 `--python-version` 参数，通过注入临时 `environment.yml` 覆盖 Python 版本，不修改原始文件。
5. feat: micromamba 改为由 `build-local.sh` 在 host 上预下载并缓存到 `files/tmp/`，构建时直接 `COPY` 进容器，避免多目标重复下载。
6. refact: Dockerfile 中移除 micromamba 在线下载步骤，改为从 `files/tmp/micromamba` 取得。
7. feat: `PYTHON_VERSION`、`MICROMAMBA_VERSION` 由 `build-local.sh` 解析后通过 `--build-arg` 传入容器，`files/build.sh` 直接读取环境变量，不再自行执行命令取值。
8. chore: 移除 Rust 相关依赖（`.cargo_config`），`cryptography`、`bcrypt` 改由 `conda-forge` 提供预编译版本。
9. feat: `files/build.sh` 增加 Git 信息（commit/branch/tag）、SHA256 checksum 及元数据 JSON 输出，修正 `build_date`/`build_timestamp` 语义。
10. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中。
11. TODO: 迁移到内网 Gitea，配置 Gitea Actions Runner 实现自动构建。

## Version=0.9.3

1. chore: 改为使用 `makeself` 打包, 这样可以直接安装.
2. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.

## Version=0.9.2

Date=2025801

1. chore: 使用 `Jenkinsfile` 做自动集成.
2. feat: 增加原 `tsc_tools` 中的批量修改主机名和批量做 ssh 信任的工具迁移到本工具中.
3. feat: 增加 `xlrd`.
4. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.

## Version=0.9.1

Date=20250727

1. feat: 因为不再支持 `el6`, 后续操作系统都有 `systemd`, 不再集成 `supervisor`.
2. feat: 缩减第三方包数量. 以能支持 `ansible`; 在 `zeppelin` 中处理数据; 和一些单机工具开发为目的.
3. feat: 仅固定核心第三方包版本, 不再强制固定全部第三方包版本. 仅通过 `pip-tools` 做简单控制.
4. refact: 使用 `docker buildx` 多系统多架构编译.
5. TODO: 将 `tsc_tools` 中需要使用 `python` 的工具迁移到本工具中.
6. TODO: 使用 `Jenkinsfile` 做自动集成.
7. TODO: 打包环境集成自定 `uv_download` 工具, 以支持在需要扩展第三方包的情况下自建多系统多架构 `pypi` 源.

## Version=0.9.0

Date=20250715

1. Initial
2. TODO: 将 `tsc_tools` 中需要使用 python 的工具迁移到本工具中
3. TODO: 使用 docker buildx 交叉编译
