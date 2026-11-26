# 开发者说明

面向维护/改动 **tsc_python 打包与部署**的人。终端用户视角的安装、升级、卸载与用法见 [README.md](README.md)（中文：[README.zh_CN.md](README.zh_CN.md)）。

- 打包模型：**每 CPU 架构一个 RPM**（`x86_64` / `aarch64`）。环境内含本地编译的二进制，不能像 `tsc_tools` 那样打成 `noarch` 单包。
- 分工：容器内 `files/pack.sh` 只负责**组装安装树**（`output/<arch>/payload/`），RPM 由**宿主机** `build.sh` 用 `nfpm` 打包。
- scriptlet 语言：RPM 忽略脚本首行 shebang，一律用 `/bin/sh` 执行（本包要求该 `/bin/sh` 是 bash），因此 `%pre`/`%post` 里显式 `set +o posix` 退出 POSIX 模式。

---

## 1. 仓库结构（打包相关）

```
build.sh                            构建入口: 拉起容器 → 取回 payload → 渲染 scriptlet → nfpm 打 RPM → 产物自检
Dockerfile                          唯一构建镜像 (CentOS 7.9, glibc 2.17 基线)
ci/lint.sh                          CI/本地通用静态检查 (shellcheck + bash -n, 含 scriptlet 渲染产物)
.github/workflows/lint.yml          GitHub Actions CI (跑 ci/lint.sh)
packaging/rpm/
  nfpm.yaml.tmpl                    nfpm 包定义模板(占位符 @VERSION@ @RELEASE@ @ARCH@ @STAGE_DIR@)
  preinstall.sh.tmpl                %pre  模板, 内含 `# >>> INJECT <file>` 注入标记
  postinstall.sh.tmpl               %post 模板, 内含 `# >>> INJECT <file>` 注入标记
  preremove.sh                      %preun (POSIX-only, 恒返回 0, 不注入)
  postremove.sh                     %postun (清理本包空目录壳, 升级跳过)
  env_check.sh                      环境检测与准入校验 (内联进 %pre)
  lib_min.sh                        最小 LOG* 运行时 (内联进 %pre / %post)
  supported_env.conf                支持条件单一事实源 (架构白名单 + glibc 基线, 内联进 %pre)
release-note.md                     版本号来源 (文件内第一个 `Version=`)
files/
  pack.sh                           容器内打包脚本 (安装树 + jq 随包 + build-info.json)
  tsc_profile                       tsc_profile 公共入口模板 (%post 在入口缺失时部署)
  tsc_python_profile                本包 drop-in 源 (%post 部署为 tsc_profile.d/01-tsc_python-profile.sh)
  ansible/                          ansible.cfg / hosts / roles (随包分发)
  modules/tsc_python_*/             插件模块 (随包分发, 与 tsc_tools 自有模块并存)
  smoke_test.sh                     安装后冒烟测试 (随包分发)
  patch_ansible.py                  ansible 解释器补丁 (随包分发)
output/<arch>/payload/home/tsc/     中间产物: 安装树 (相对 /home/tsc)
release/                            RPM 产物 (按 mtime 只保留最近 5 份)
KNOWN_ISSUES.md                     审查发现的暂缓事项清单 (不随包分发, 修复一项划掉一项)
```

---

## 2. 打包工作流程（`./build.sh` 逐步）

| 步骤 | 动作 |
|---|---|
| 1 | 解析参数与 `build.conf`（micromamba 版本、yum 源、Python 版本、PyPI/conda 源） |
| 2 | 预下载 micromamba 与 jq 静态二进制到 `files/tmp/`（缓存优先，jq 带 sha256 校验；均只取当前架构） |
| 3 | 生成构建期配置 `environment.yml` / `condarc` / `pip.conf` 到 `files/tmp/` |
| 4 | `docker build --target builder`（注入 `REPO_LOCAL` / `ARCH` / `PYPI_INDEX`；pip 层 `uv pip install --index-url` 显式使用 `PYPI_INDEX`——uv 不读 pip.conf）；容器内 `files/pack.sh` 做 glibc 门限检查并组装安装树到 `output/payload/` |
| 5 | `docker cp` 取回产物到 `output/<arch>/`（取回前**整体清空**该目录：`docker cp` 是目录合并语义，不清会把旧布局残留合并进 payload） |
| 6 | **依赖检查**：打包机需提供 `nfpm`（默认 `/bin/nfpm`，可用 `NFPM_BIN` 覆盖） |
| 7 | **版本解析**：取 `release-note.md` 第一个 `Version=`；含 `-` 直接报错（RPM Version 不允许） |
| 8 | **stage**：`output/<arch>/payload/home/tsc` → `stage/payload/home/tsc` |
| 9 | **scriptlet**：`render_template` 把 `# >>> INJECT <file>` 换为该文件内容，再 `sed` 替换 `@ARCH@` |
| 10 | **scriptlet 语法自检**：四个脚本逐个 `bash -n`；随包脚本（`modules/*/run.sh`、`smoke_test.sh`）同样逐个 `bash -n`；再断言 `%pre` 含 `SUPPORTED_ARCHITECTURES=`/`check_env()`、无残留 `@ARCH@`，`%post` 含 `LOGINFO()`；并比对 `build-info.json` 版本与 RPM 版本一致（缺失即中止，pack.sh 无条件生成该文件） |
| 10.5 | **python 主.次版本一致性断言**：`stage` 内必须存在 `lib/python<MM>/site-packages/ansible/config/`（产物自检 need_file 里锚定 `python<MM>` 的条目依赖它） |
| 11 | 渲染 `nfpm.yaml`（渲染后反向断言无残留 `@XXX@` 占位符）并 `nfpm package --packager rpm` |
| 12 | **产物自检**：包信息 / `Requires` / 文件数 / 架构与构建架构一致 / 关键文件齐全（`patch_ansible.py`、`base.yml`、`build-info.json`、jq）/ 关键文件可执行位 / 四段 scriptlet 是否写入 |
| 13 | 生成 `.sha256`；`release/` 按 mtime 只保留最近 5 份产物（打包失败路径不动旧产物）；`stage/` 与构建期临时配置由 EXIT trap 统一回收（`package_rpm` 的 RETURN trap 覆盖不到 Ctrl-C 中断路径） |

产物：`release/tsc_python-<version>-<release>.<arch>.rpm`（`release` 取构建时间戳 `YYYYMMDDHHMMSS`）。

另：构建入口有 flock 互斥（仓库根 `.build.lock`，已入 `.gitignore`）——同机并发 `build.sh`
会互踩 `output/<arch>` 清空与 `release/` 旧产物回收，第二个实例直接退出。

---

## 3. 四段 scriptlet 语义（改之前必须知道）

| 段 | 文件 | 执行时机 | `$1` |
|---|---|---|---|
| `%pre` | `preinstall.sh.tmpl` | 包文件落盘**之前** | 安装 `1` / 升级 `2+`（本脚本不使用） |
| `%post` | `postinstall.sh.tmpl` | 包文件落盘**之后** | 安装 `1` / 升级 `2+`（两者步骤相同且幂等） |
| `%preun` | `preremove.sh` | 卸载**之前**（包内文件还在） | `0` = 真卸载（执行回收） / `>=1` = 升级（直接跳过） |
| `%postun` | `postremove.sh` | 卸载**之后**（包内文件已删） | `0` = 真卸载（清理空目录壳） / `>=1` = 升级（跳过） |

六个必须理解的设计：

1. **`%pre` 必须自包含**。此刻包内文件尚未落盘，不能 `source` 包内任何文件，所以 `lib_min.sh` / `supported_env.conf` / `env_check.sh` 是**内联**进 `%pre` 的文本，而不是从磁盘读取。
2. **`lib_min.sh` 是 `func` 的 shim**。它只提供 5 个 `LOG*`、`is_element_in_array` 与 `version_ge`，与 `func` 里的同名函数**同名同签名**；日志前缀由调用方设置的 `__LOG_TAG` 决定。改任一侧的签名或行为，必须同步另一侧。
3. **`%preun` 在升级时全部跳过**。回收工作交给新包的 `%post` 重建，避免出现"升级过程中工具被删空"的窗口。
4. **`%preun` 只用 POSIX 语法，且任何分支都 `exit 0`**。`%preun` 返回非零会让 rpm 拒绝卸载，让机器卡在"卸不掉"的状态比留下几个文件更糟。这也是它不注入 bash 版 `lib_min.sh` 的原因。
5. **profile 是 drop-in，三个角色各管一段**（与 tsc_tools 2.1.8+ 同构；2.1.7 已有 drop-in 模型但前缀与本包同为 `01-`，本包硬依赖下限为 2.1.8）。

   | 路径 | 谁部署 | 卸载谁删 |
   |---|---|---|
   | `/home/tsc/tsc_profile` | 公共入口，谁先装谁建，只 source `tsc_profile.d/*.sh` | 都不删 |
   | `tsc_profile.d/00-tsc_tools-profile.sh` | tsc_tools `%post` | tsc_tools `%preun` |
   | `tsc_profile.d/01-tsc_python-profile.sh` | 本包 `%post`（源为 `/home/tsc/tsc_python/tsc_python_profile`） | 本包 `%preun` |

   加载顺序 = 文件名排序 = 变量拼装顺序。片段把 `/home/tsc/tsc_python/tsc_python_profile` 拷过去即可，`Profile` 源与公用入口模板 `tsc_profile` 都随包放在环境根目录。tsc_tools >= 2.1.8 起其 drop-in 名为 `00-tsc_tools-profile.sh`（2.1.7 为 `01-tsc_tools-profile.sh`，与本包同前缀、先后靠字母序），以数字前缀明确保序：tsc_tools 片段先加载（前插 PATH、后插其模块目录），本包片段后加载（激活环境、前插自己的模块目录）；两侧对 `TSC_MODULES_DIR` 的拼装方向不同（本包前插、tsc_tools 后插），最终 PATH 中本包环境优先、模块目录本包在前，与上表语义自洽——两种加载顺序下结果一致，不因前缀变化而翻转。

6. **包外的东西要么记清单要么明确不删**。drop-in 由 `%post` 部署（不在 rpm 文件清单里），但**文件名归属本包独占**：每次安装/升级都用包内版本刷新，`%preun` 真卸载时**无条件**删除——不保留本地修改（现场要自定义片段就另建文件，如 `99-local-profile.sh`，别占用本包的名字）。公用入口 `tsc_profile`、`tsc_profile.d` 目录、`/var/log/tsc`、`%pre` 轮转出的备份一律保留。

`TSC_MODULES_DIR` 是 tsc 发现模块的唯一途径（`tsc`/`gen_rag.sh` 遍历该变量里的目录），本包模块独占 `/home/tsc/tsc_python/modules`（与 tsc_tools 的 modules 解耦）。本包片段因此要声明一次，并用 `":${TSC_MODULES_DIR:-}:"` 判重：**重复项会让 gen_rag.sh 把同一份 readme 收录两次。**

本包在 `nfpm.yaml.tmpl` 的 `depends` 里声明硬依赖 `tsc_tools >= 2.1.8`。下限取 2.1.8 而非"提供 drop-in 加载器"的 2.1.6，是因为本包 `%post` 调用的是 tsc_tools 随包的 `gen_rag.sh`，而 `rag.md` 膨胀的根因（`TSC_MODULES_DIR` 被重复追加）修在 tsc_tools 侧（其 drop-in 判重 + `gen_rag.sh` 去重）——低版本上修复不生效，仍会产出成倍重复的 rag.md。`%post` **不改写**已存在的 `tsc_profile`（只在该文件缺失时用包内模板创建，模板自带加载逻辑），因此不会动 tsc_tools 的文件、也不会让 `rpm -V tsc_tools` 报差异；低于下限的 tsc_tools 由 RPM 依赖直接拦下，没有也不做加载块 bootstrap。

### 3.1 安装树布局（`nfpm.yaml` 的 `dst: /home/tsc`）

```
/home/tsc/tsc_python/                       环境本体根目录 (mamba root + envs/tsc_python)
/home/tsc/tsc_python/<docs>                 随包文档与工具 (release-note/readme/THIRD_PARTY_NOTICES/smoke_test/patch_ansible/build-info)
/home/tsc/tsc_python/tsc_profile            tsc_profile 公共入口模板 (%post 在入口缺失时部署)
/home/tsc/tsc_python/tsc_python_profile  本包 drop-in 源 (%post 部署为 tsc_profile.d/01-tsc_python-profile.sh)
/home/tsc/tsc_python/ansible/               ansible.cfg / hosts / roles
/home/tsc/tsc_python/modules/tsc_python_*/  插件模块
```

本包把 ansible 配置与插件模块都装在独立的 `/home/tsc/tsc_python/` 树下，与 `tsc_tools` 的 `modules` 命名空间解耦，两边不会产生同名文件冲突。环境本体目录从早期的 `tsc_tools/micromamba` 迁到了 `tsc_python`——它不再是"塞在 tsc_tools 下的一个子目录"，而是一个与 tsc_tools 平级的独立组件。

---

## 4. 改动本组件时的注意点

### 4.1 版本号

只改 `release-note.md` 顶部的 `Version=`，`release` 号自动取构建时间戳（`YYYYMMDDHHMMSS`，精确到秒，同日多次构建 NVR 可区分）。**不能在版本号里用 `-`**。

### 4.2 架构

包与架构一一对应：x86_64 机器出 `x86_64` 包，aarch64 机器出 `aarch64` 包。新增架构按 `packaging/rpm/supported_env.conf` 头注释的 checklist：补 `build.sh` 的 `arch_download_tags()` 映射与 `jq_sha256_<arch>` 常量、白名单加一项——构建期断言会拦下前两步的遗漏；并确认 `build.sh` 的 `ARCH="$(arch)"` 能取到该值。

支持口径：**准入条件只有架构与 glibc 两条, 发行版不设门禁**（`env_check.sh` 头注释记录了这一决策的理由——国产 OS 的 `os-release` 名称五花八门, 按发行版家族判断极脆弱）。README 中的"已验证环境"清单是测试记录, 非准入条件, 不构成第二事实源。

`%pre` 是唯一的架构闸门：它既校验本机架构在白名单内，也校验其与所装包的构建架构一致（`--ignorearch` 强行安装时仍会拦下）。

### 4.3 glibc 基线

环境在 glibc 2.17（CentOS 7.9）容器中构建。`files/pack.sh` 的 `check_glibc_baseline` 用 `objdump` 扫描包内 ELF 的最高 `GLIBC_` 符号要求，超标即禁止出包；`%pre` 在安装时再校验目标机 glibc 不低于基线。

### 4.4 改 `func` 或日志函数

`%pre` / `%post` **不**内联 `func`，只内联 `lib_min.sh`，所以改 `func` 不影响安装流程。但 `func` 与 `lib_min.sh` 的 `LOG*` 必须保持同名同签名。

### 4.5 注入是静默的

`render_template` 用 `awk ... getline` 读被注入文件，**文件不存在时静默输出空**。后果：产出缺 `SUPPORTED_*` 或 `LOG*` 的 scriptlet，目标机在 `set -u` 下以 unbound 变量报错，安装失败，而**打包期毫无感知**（`bash -n` 只查语法）。

`build.sh` 已加渲染完整性断言（§2 步骤 10）。**若新增 `.tmpl` 或注入文件，请同步补断言。**

### 4.6 旧的非 RPM 安装残留

`%pre` 的 `rotate_legacy_install` 只在 `/home/tsc/tsc_tools/micromamba` **不被任何已安装包认领**时才轮转。判断依赖 `rpm -qf`，升级路径下必须原样保留该目录，否则新包 `%post` 会对着一个被搬空的目录工作。环境本体已迁到 `/home/tsc/tsc_python`，这个旧路径只针对自解压包时代的残留。

同类的还有 `rotate_legacy_profile`：自解压包时代的 `/home/tsc/tsc_python_profile` 与它在 `tsc_profile` 里留下的 `source` 行，在改用 drop-in 后都成了过时痕迹，按同样规则一轮转/摘行（只摘本包那一行，tsc_tools 与用户内容不动）。若将来再迁移 profile 挂载方式，这两处要同步改。

`%post` 里还有一处同型清理 `STALE_DROPIN`：drop-in 早期叫 `tsc_python.sh`，升级上来时若它还挂着（且无包认领）会被删掉，否则同一份环境会被加载两次。

### 4.7 文件权限

`files/pack.sh` 对模块 `run.sh`、`smoke_test.sh` 与环境内二进制（`tsc_python/bin/*`、`envs/tsc_python/bin/*`）显式 `chmod 0755`；profile 相关文件（被 source，不需要可执行位）显式 `chmod 0644`。环境二进制之所以要显式归一化，是因为构建容器 umask 002 会让它们带上组写位（0775），而共享目录 `/home/tsc` 下 root 所有的二进制保持 0755 更干净，也避免产物自检因权限非 0755 而失败。其余文件沿用容器内构建出的 mode。nfpm 按 stage 里的实际 mode 打包。

`build.sh` 开头固定 `umask 022`（与 `tsc_tools` 一致），避免打包机 umask 收紧（如 `0077`）静默削掉未显式 chmod 的文件权限。

### 4.8 ansible base.yml 以普通文件入包, %post 幂等重打补丁

`patch_ansible.py` 在 `%post` 里改写 ansible 的 `ansible/config/base.yml`（`INTERPRETER_PYTHON_FALLBACK`）。base.yml **随批量安装树以普通文件入包**——0.13.5 之前曾以 `%config(noreplace)` 单独声明（构建侧移出安装树暂存、`nfpm.yaml` 单列条目、`stage_ansible_base` + 哨兵区间摘除那套机制均为此服务），现已放弃，理由：

- `noreplace` 保住的是**整份旧文件**：一旦某次升级同时抬高了 ansible-core 版本，现场保留的旧 base.yml 缺少新版新增的配置定义，而 ansible 代码访问未知配置项会直接抛 `AnsibleUndefinedConfigEntry`——新版原版被落成 `base.yml.rpmnew`，`%post` 补丁又不合并它，需要管理员手工发现并恢复；
- 普通文件形态下，升级由 rpm 直接覆盖为新版原版，`%post` 再幂等重打解释器补丁，上述窗口不存在；
- 代价是现场手改的 base.yml 会在升级时被覆盖——base.yml 本就不是现场定制点（`ansible.cfg` 才是），该代价可接受；顺带 `rpm -V` 不再对 base.yml 报 config 差异。

若将来确需再引入 `%config` 类条目：nfpm 2.47.0 用的是 `type: config|noreplace`，**没有** `config_noreplace` 这个布尔字段（后者会让 nfpm 解析失败），且只能打在**独立 content 条目**上，无法标在目录整体拷贝里的单文件。

### 4.9 新增随包 shell 脚本

`build.sh` 在打包期对本包自带的 `smoke_test.sh` 与 `modules/*/run.sh` 逐个 `bash -n`（范围限定 `stage/payload/home/tsc/tsc_python` 下 `-maxdepth 3`，有意不含 conda 环境内散落的 `*.sh`——那些不由本仓维护，纳入只会引入噪音）。新增随包脚本若落在该范围外（层级更深或文件名不同），需同步扩大自检范围。

这条自检是 0.13.2 事故的直接产物：三个模块 `run.sh` 因引号未闭合整份不可用，而当时打包期只查了文件存在性与可执行位，缺陷随 0.13.2 / 0.13.3 两个版本发布。

### 4.10 产物不签名

**已决策：不做 GPG 签名**（内网裸 `rpm -ivh`/`rpm -Uvh` 分发，产物 `SIGPGP=(none)`）。若将来改走 dnf 制品库且仓库 `gpgcheck=1`（默认），未签名包会被拒装——届时需重新评估：补签名，或在仓库配置里关掉 `gpgcheck`。

---

## 5. 本地验证手段

```bash
# 静态检查 (CI 同款: shellcheck + bash -n, 含 scriptlet 模板渲染产物; 无 shellcheck 时该项降级跳过)
bash ci/lint.sh

# 语法
bash -n build.sh files/pack.sh

# 构建 + 内置产物自检 (需 docker / nfpm / rpm)
./build.sh

# 核对产物
rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' release/*.rpm
rpm -qp --requires release/*.rpm
rpm -qlpv          release/*.rpm | head        # 文件与权限
rpm -qp --scripts  release/*.rpm               # 看四段 scriptlet 是否齐全

# 冒烟测试 (在目标机安装后执行, 用 bash 运行; 被 sh 调用时脚本会自动转交 bash)
bash /home/tsc/tsc_python/smoke_test.sh
bash /home/tsc/tsc_python/smoke_test.sh --skip-network

# 真实安装/卸载 (破坏性, 仅在测试机执行)
rpm -ivh release/*.rpm && rpm -q tsc_python && rpm -ql tsc_python
rpm -e tsc_python
```

---

## 6. 提交约定

- 提交信息用中文，形如 `type(scope): 摘要——细节; ...`，细节可较长（沿用仓库既有风格）。
- 改动影响用户可见行为时，同步更新 `release-note.md` 对应 `Version=` 段落的条目。
