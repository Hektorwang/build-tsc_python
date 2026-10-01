# readme

English | [简体中文](README.zh_CN.md)

## Overview

1. Builds the standardized TSC Python distribution.
2. Ships Python `3.13.12` (version overridable via parameters), managed by `micromamba`, packaged as a self-extracting installer via `makeself`.
3. One installer per CPU architecture (`x86_64` / `aarch64`); the environment is built in a CentOS 7.9 (glibc 2.17 baseline) container and is compatible with any Linux distribution shipping glibc >= 2.17.

## Repository layout

```text
.
├── build.sh                # build entry script
├── Dockerfile              # the only builder image (CentOS 7.9, glibc 2.17 baseline)
├── func                    # shared function library (logging etc.)
├── release-note.md         # release notes (shipped inside the installer)
├── THIRD_PARTY_NOTICES.md  # third-party notices (English)
├── THIRD_PARTY_NOTICES.zh_CN.md
├── files/
│   ├── pack.sh             # in-container packaging script (makeself, checksum, metadata)
│   ├── install.sh          # installer script embedded in the package
│   ├── environment.yml     # conda environment definition (python version, system libraries)
│   ├── requirements.in     # pip dependency declaration
│   ├── requirements.txt    # pip dependency list
│   ├── tmp/                # build-time files (micromamba/jq cache, generated environment.yml/condarc/pip.conf)
│   └── ...
└── output/                 # build artifact output directory
```

## Prerequisites

The build container is CentOS 7.9 (EL7), which is EOL. **The build must not depend on any internet source**; the following external resources must be prepared in advance:

| Resource | How to obtain |
| --- | --- |
| Builder image `centos:7.9.2009` (one per arch: x86_64 / aarch64) | Pull from the public network and preserve into your internal registry (see below) |
| yum repository (CentOS 7.9 Base ISO is sufficient) | Build with `createrepo` from the archived 7.9.2009 ISO, passed via `--repo-local`; jq is provided by static binaries fetched on demand into `files/tmp/`, no EPEL needed |
| micromamba binary | Download once from `micro.mamba.pm` on an internet-connected machine, copy to the build host's `files/tmp/` (see "Third-party component cache") |
| PyPI index / conda-forge channel | Defaults to the CERNET unified mirror, customizable via `pypi_index`/`conda_forge` in `build.conf`; point to internal mirrors for offline builds (see "Intranet deployment") |

Other requirements:

- Docker installed and running; `build.sh` builds with `--pull=false`, so the build host must already have the **matching-architecture** `centos:7.9.2009` image
- The host architecture equals the target architecture (x86_64 hosts build x86_64 packages, aarch64 hosts build aarch64 packages)

### Preserving the EL7 builder image (strongly recommended)

The CentOS 7 container image went EOL along with the distribution; official channels (Docker Hub / quay.io) may remove it at any time, after which the build environment can never be recreated.
**Preserve both architecture images from an internet-connected machine now** and import them into your internal registry:

```bash
# x86_64
docker pull --platform linux/amd64 centos:7.9.2009
docker save centos:7.9.2009 -o centos-7.9.2009-x86_64.tar

# aarch64 (pulling does not require running it, an x86_64 machine can pull aarch64 images)
docker pull --platform linux/arm64 centos:7.9.2009
docker save centos:7.9.2009 -o centos-7.9.2009-aarch64.tar
```

Note: pulling both architectures on the same machine overwrites the shared tag — `save` each one immediately after pulling, or `docker tag` it to a different name before pulling the next.

Import into the internal registry and switch to the internal address:

```bash
docker load -i centos-7.9.2009-x86_64.tar
docker tag centos:7.9.2009 <internal-registry>/baseimages/centos:7.9.2009
docker push <internal-registry>/baseimages/centos:7.9.2009
# then change Dockerfile's FROM to <internal-registry>/baseimages/centos:7.9.2009
```

## Building

### Basic usage

```bash
# build the installer for the current machine architecture
bash build.sh
```

### Options

```text
-n, --no-cache              disable the Docker build cache
-m, --micromamba-ver V      micromamba version (overrides build.conf)
-r, --repo-local URL        internal yum repo URL used by the build container (overrides build.conf)
-p, --python-version V      override the Python version (overrides build.conf)
    --pypi-index URL        PyPI index URL (overrides build.conf)
    --conda-forge URL       conda-forge channel URL (overrides build.conf)
-h, --help                  show this help
```

### Configuration file

Common parameters can be stored in `build.conf` to avoid typing them every time. Command-line options take precedence over the config file.

```ini
[build]
micromamba_ver = 2.5.0
repo_local     = http://192.168.1.100
python_version = 3.13.12
pypi_index     = https://mirrors.cernet.edu.cn/pypi/web/simple
conda_forge    = https://mirrors.cernet.edu.cn/anaconda/cloud/conda-forge
```

### Overriding the Python version

```bash
bash build.sh --python-version 3.12.11
```

### Third-party component cache (micromamba / jq / makeself)

All third-party build components use a **cache-first, download-on-demand** pattern: a valid local cache is used as-is; on absence or checksum mismatch they are fetched from upstream at pinned versions.

| Component | Cache location | Upstream |
| --- | --- | --- |
| micromamba | `files/tmp/micromamba` (+ `.version`) | micro.mamba.pm |
| jq (static binaries, two architectures) | `files/tmp/jq-x86_64` / `jq-aarch64` (sha256-verified) | github.com/jqlang/jq |
| makeself | `files/makeself.sh` / `makeself-header.sh` | github.com/megastep/makeself |

Offline build hosts can place the files manually. First download on an internet-connected machine (2.5.0 / x86_64 as an example, `linux-aarch64` for aarch64):

```bash
curl -fL -o micromamba "https://micro.mamba.pm/api/micromamba/linux-64/2.5.0"
```

Then place them on the build host at the following paths (the version file contains `<version>-<arch>`):

```text
files/tmp/micromamba          # downloaded binary archive
files/tmp/micromamba.version  # text file, e.g. 2.5.0-x86_64
```

Force re-downloading (just delete the caches):

```bash
rm -f files/tmp/micromamba files/tmp/micromamba.version
rm -f files/tmp/jq-x86_64 files/tmp/jq-aarch64
rm -f files/makeself.sh files/makeself-header.sh
```

### Build artifacts

Artifacts are written to `output/<arch>/`; each build produces three files:

```bash
tsc_python-<version>-<arch>-<date>.sh        # makeself self-extracting installer
tsc_python-<version>-<arch>-<date>.sh.sha256 # SHA256 checksum file
tsc_python-<version>-<arch>-<date>.sh.json   # build metadata (version, time, arch, glibc baseline, ...)
```

### Build logs

Docker output of each build is saved to `log/build-<arch>-<timestamp>.log`.

## Dependencies

`files/requirements.in` is the **declaration layer** — the top-level modules we actually use, maintained by hand. The build never reads this file (comments in it survive `pip-compile`).

`files/requirements.txt` is the **install list** — the build runs `uv pip install -r` against it. Since it is (or will be) generated, do not put process notes in it.

Current transitional state: `requirements.txt` is hand-maintained and unpinned — when you change `requirements.in`, update `requirements.txt` to match.

### Locking versions (planned)

Once the package stabilizes, lock the dependency set:

```bash
# run from the repository root (requires pip-tools: pip install pip-tools)
pip-compile files/requirements.in --no-header --no-annotate

# uv equivalent
uv pip compile files/requirements.in -o files/requirements.txt --no-header --no-annotate
```

- `--no-header` / `--no-annotate` keep the output clean: no autogenerated header, no `# via` annotations
- the lock file must stay **index-free**: never pass `--index-url` / `--extra-index-url` to pip-compile — the mirror is injected at build time via `pypi_index` in `build.conf` (or `--pypi-index`). If an `--index-url` line ever appears in the output, delete it.

## Supported systems

| Operating system             | Status                                       |
| ---------------------------- | -------------------------------------------- |
| centos-7 / rhel-7            | supported                                    |
| openEuler / Euler / HCE      | supported                                    |
| FitStarrySkyOS / FitServerOS | supported                                    |
| KylinOS V10                  | supported                                    |
| centos-6 / rhel-6            | not supported (glibc < 2.17)                 |
| UOS                          | not supported                                |
| other glibc >= 2.17 Linux    | theoretically compatible, untested (e.g. Debian/Arch/SUSE) |
| Alpine (musl) / FreeBSD      | not supported (no glibc)                     |

All supported systems use the same installer `tsc_python-<version>-<arch>-<date>.sh`, selected by architecture; the installer verifies the target machine's architecture automatically.

## Intranet deployment

External resources required by the build and their configuration:

- **PyPI index**: defaults to the CERNET unified mirror; offline build hosts point `pypi_index` in `build.conf` (or `--pypi-index`) to an internal index
- **conda-forge channel**: defaults to the CERNET unified mirror's conda-forge channel; offline build hosts point `conda_forge` in `build.conf` (or `--conda-forge`) to an internal channel, or to a self-hosted minimal conda-forge mirror (see below)
- **Docker base image**: push to the internal registry and change `Dockerfile`'s `FROM` (see "Preserving the EL7 builder image")
- **yum repository**: see the next section

### Self-hosting a minimal conda-forge mirror (optional)

There is no need to mirror the whole conda-forge (tens of TB); it suffices to host the dependency closure resolved for your environment:

```bash
# 1) on an internet-connected machine, dry-run the same environment.yml to obtain the exact
#    package URLs (the full dependency closure)
micromamba create -f environment.yml --dry-run --json > plan.json

# 2) extract all package URLs from plan.json and download them, grouped by platform
#    (linux-64 / linux-aarch64 / noarch)
jq -r '.actions.LINK[] | .url' plan.json | xargs -P 8 -n 1 curl -fLO

# 3) lay them out as a channel: <channel>/<subdir>/<packages> (noarch packages go to noarch/)
#    aarch64 packages are collected by repeating steps 1-2 on an ARM machine

# 4) generate the index (requires conda-index: pip install conda-index)
conda-index /srv/conda-forge

# 5) publish the directory via nginx, then point the build at it
bash build.sh --conda-forge http://<internal-server>/conda-forge
```

When `environment.yml` changes, re-run steps 1-2 to incrementally add the new closure.

### CentOS 7 yum repository

CentOS 7 went EOL in June 2024 and the official mirror sites are gone — **packages are no longer available from the public network**. Intranet builds must provide their own repository:

1. Download the full CentOS 7.9.2009 ISO from an archive source (e.g. `vault.centos.org` or third-party archives)
2. Extract or mount the ISO and build a local yum repository with `createrepo`
3. Pass the repo address via `--repo-local`, or edit the `base_local_url` placeholder in `files/centos7.repo` directly

```bash
bash build.sh --repo-local http://<your-internal-repo-server>
```

## License

The code of this project is released under **GPL-3.0-or-later**, see [LICENSE](LICENSE) at the repository root.

Third-party components referenced by the repository follow their own licenses, see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (Chinese version: [THIRD_PARTY_NOTICES.zh_CN.md](THIRD_PARTY_NOTICES.zh_CN.md)):
the makeself scripts (GPL-2.0-or-later; the self-extracting installers they generate are declared by the author not to be subject to the GPL) and the jq static binaries (MIT) are fetched at build time at pinned versions and are not distributed with this repository.

The tsc_python installers produced by this tool are distributed to internal environments only.
