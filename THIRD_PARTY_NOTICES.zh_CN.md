# 第三方组件声明

[English](THIRD_PARTY_NOTICES.md) | 简体中文

本安装包及构建工具涉及以下第三方开源组件, 按各自许可证使用与分发. 除另有说明外, 所有组件均以未修改形式使用.

---

## 一、安装包内分发的组件

### Python 运行时

| 组件 | 版本 | 许可证 | 来源 |
| --- | --- | --- | --- |
| Python | 见包内元数据 | PSF-2.0 (BSD 风格) | https://www.python.org |
| micromamba | 见包内元数据 | BSD-3-Clause | https://github.com/mamba-org/mamba |

### conda 层第三方库

以 conda-forge 渠道预编译包形式分发, 每个包的许可证记录于环境自带元数据 `<env>/conda-meta/*.json` 的 `license` 字段.

其中 copyleft 类组件 (未修改分发即满足义务: 保留本声明并保证源码可从上游获取):

- `readline` (GPL-3.0-only)
- `paramiko` (LGPL-2.1-or-later)
- `psycopg2` (LGPL-3.0-or-later)
- `libxcrypt` / `libnsl` / `libntlm` / `keyutils` (LGPL-2.1 系)
- `ld_impl_linux-64` (GPL-3.0-only)

`libgcc` / `libgomp` / `libstdcxx` 为 GPL-3.0 **附带 GCC 运行时库例外**, 按例外条款可自由随非 GPL 程序分发.

其余组件为 MIT / BSD / Apache-2.0 / ISC / Zlib / Public-Domain 等宽松许可证.

### pip 层第三方库

pip 装包的许可证以各自 `*.dist-info/METADATA` 的 `License` 字段与随包 LICENSE 文件为准.

主要 copyleft 组件:

- `ansible-core` (GPL-3.0-or-later)

其余以 MIT / BSD / Apache-2.0 / ISC 为主.

---

## 二、构建工具仓库涉及

| 组件 | 许可证 | 来源 | 说明 |
| --- | --- | --- | --- |
| makeself | GPL-2.0-or-later | https://github.com/megastep/makeself | 构建时按锁定版本获取; 由其生成的自解压安装包经作者声明不受 GPL 约束 |
| jq | MIT | https://github.com/jqlang/jq | 构建时按锁定版本获取, 仅在构建容器内使用 |

本仓库自身代码以 **GPL-3.0-or-later** 发布, 见仓库根目录 `LICENSE`.

---

## 分发合规说明

1. 本安装包不包含任何闭源或商业授权组件.
2. GPL / LGPL 组件均以未修改形式分发, 并通过本声明与包内元数据保留许可证信息; 其源码可通过对应上游仓库 (conda-forge / PyPI) 公开获取, 满足 GPL/LGPL 的源码提供义务.
3. 本包携带的 shell 脚本通过命令行方式调用上述组件, 不构成 GPL 意义上的衍生作品.
4. 如对任何组件做了修改并对外分发, 需按其许可证提供修改后源码.
