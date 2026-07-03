<div align="center">

# ⚙️ Build · Deploy · Test

### `2 labs` · `6 pipeline jobs` · `12-job security & cloud backlog` · `2026 toolchain`

**A DevOps lab that grows from interactive menus to a Jenkins delivery pipeline — hardening, CVE gates, IaC and runtime threat detection, built one commit per step.**
*מעבדת DevOps שצומחת מתפריטים אינטראקטיביים לפייפליין אספקה ב-Jenkins — הקשחה, שערי CVE, תשתית-כקוד וזיהוי איומים בזמן ריצה, בנויה קומיט-אחד-לכל-שלב.*

<br/>

[![CI](https://github.com/www8351/build-deploy-test/actions/workflows/ci.yml/badge.svg)](https://github.com/www8351/build-deploy-test/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/www8351/build-deploy-test/python-coverage-comment-action-data/endpoint.json)](https://github.com/www8351/build-deploy-test/tree/python-coverage-comment-action-data)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
<br/>
![Bash](https://img.shields.io/badge/Bash-5%2B-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-uv-3776AB?logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-pipeline--as--code-D24939?logo=jenkins&logoColor=white)
![OpenTofu](https://img.shields.io/badge/OpenTofu-IaC-FFDA18?logo=opentofu&logoColor=black)
![Trivy](https://img.shields.io/badge/Trivy-CVE%20gate-1904DA?logo=aqua&logoColor=white)

</div>

---

## 🌍 What is this? · מה זה?

<table>
<tr>
<td width="50%" valign="top">

### 🇬🇧 English

A DevOps lab: two interactive **Labs**, six **build/deploy Jobs** (Docker) wired as a
Jenkins delivery pipeline, plus a **Security & Cloud backlog** (jobs 7–18) — SSH/firewall
hardening, CVE + file-integrity scanning, encrypted backups, async health monitoring, and
AWS/GCP provisioning & IAM audit.

It ships a **2026 open-source toolchain**: `uv` (Python deps), **OpenTofu** (IaC),
**Cilium** (eBPF NetworkPolicies) and **Falco** (runtime threat detection), plus
**CycloneDX/SPDX SBOMs** from the CVE scan. Built **one commit per step**, so the git
history reads as a step-by-step walkthrough.

</td>
<td width="50%" valign="top">

<div dir="rtl">

### 🇮🇱 עברית

מעבדת DevOps: שני **Labs** אינטראקטיביים, שישה **Jobs** של build/deploy (Docker) המחוברים
כפייפליין אספקה ב-Jenkins, ובנוסף **בק‏לוג אבטחה וענן** (jobs 7–18) — הקשחת SSH/פיירוול,
סריקת CVE ושלמות-קבצים, גיבויים מוצפנים, ניטור בריאות אסינכרוני, והקמת AWS/GCP + ביקורת IAM.

הפרויקט מגיע עם **טולצ'יין קוד-פתוח 2026**: `uv` (תלויות פייתון), **OpenTofu** (תשתית-כקוד),
**Cilium** (מדיניות רשת eBPF) ו-**Falco** (זיהוי איומים בזמן ריצה), בתוספת **SBOM**
בפורמט CycloneDX/SPDX מסריקת ה-CVE. נבנה **קומיט-אחד-לכל-שלב**.

</div>

</td>
</tr>
</table>

> 🐧 Scripts target a **Linux Jenkins agent** (`useradd`, a package manager, `docker`). Install
> scripts auto-detect `apt-get` / `dnf` / `yum` — Debian/Ubuntu **and** RHEL/CentOS.

---

## ▶️ See it run

![Demo: make test, then the CVE gate blocking a deploy and firewall/EC2 dry-runs](docs/demo.svg)

No cloud, no root, no risk — `make demo` runs the non-destructive dry-run jobs, `make test`
runs the full suite:

```console
$ make test
39 passed, 1 skipped — coverage 94% (jobs/*.py)
✓ tests/bats  16 tests  (jobs 7/8/10/13/15)

$ THRESHOLD=0 ./jobs/job8_trivy_docker_scan.sh      # CVE gate
Found 2 HIGH,CRITICAL vulnerabilities (threshold: 0).
✗ Vulnerability count exceeds threshold — blocking deployment.   (exit 1)

$ DRY_RUN=1 ./jobs/job10_iptables_lockdown.sh        # firewall, rendered not applied
:INPUT DROP [0:0]
-A INPUT -p tcp --dport 8351 -m conntrack --ctstate NEW -j ACCEPT
✓ Done: dry run, no rules applied.
```

---

## 🚀 Quick start

```bash
git clone https://github.com/www8351/build-deploy-test.git
cd build-deploy-test
chmod +x labs/*.sh jobs/*.sh

# Labs (interactive menus)
./labs/lab1_menu.sh
python3 labs/lab2_menu.py

# Build jobs (parameters via env vars)
USER_NAME=tester1  ./jobs/job1_users_tar.sh
HOST_PORT=8351     ./jobs/job2_docker_nginx.sh
                   ./jobs/job3_containers_log.sh

# Security & cloud jobs (7-18) — most destructive or need creds; read the header first
IMAGE=nginx THRESHOLD=0            ./jobs/job8_trivy_docker_scan.sh
sudo DRY_RUN=true APP_PORT=8351    ./jobs/job10_iptables_lockdown.sh
DRY_RUN=true                       ./jobs/job15_aws_ec2_provision.sh   # needs aws-cli v2
```

---

## 🧱 The 6 build jobs (Jenkins pipeline)

| Job | Script | What it does | Params |
|:-:|--------|--------------|--------|
| 1 | `job1_users_tar.sh` | create user, 5 files, `tar` → `zipfile.tgz` | `USER_NAME` |
| 2 | `job2_docker_nginx.sh` | pull nginx, run on `:8351`, `curl` it | `HOST_PORT` |
| 3 | `job3_containers_log.sh` | write each container's ID/Image/Name/IP → `Log.txt` | — |
| 4 | `job4_pull_remote.sh` | `ssh` to remote host, `docker pull` | `REMOTE_HOST`, `REMOTE_USER`, `IMAGE` |
| 5 | `job5_deploy3_ips.sh` | deploy 3 containers, print IPs | `COUNT`, `IMAGE` |
| 6 | `job6_send_mail.sh` | send an "all good" mail | `RECIPIENT`, `SUBJECT`, `BODY` |

Chain: **Job 1 → 2 → 3 → 4 → 5 → 6**. Jobs 4 & 6 auto-skip when `REMOTE_HOST` / `RECIPIENT`
are empty, so the pipeline runs green on a single agent.

---

<details>
<summary><b>🛡️ Security & Cloud jobs (7–18)</b> — hardening, scanning, provisioning</summary>

<br/>

Each is standalone (not part of the 1→6 flow) and self-contained: `set -Eeuo pipefail` /
custom exceptions, idempotent where it edits state, dry-run or rollback on destructive ones,
structured (JSON/Markdown) output, and a **non-zero exit that gates a pipeline**.

| Job | Script | What it does | Exit gate |
|:-:|--------|--------------|-----------|
| 7 | `job7_ssh_hardening.sh` | idempotent `sshd_config` hardening, backup, `sshd -t` validate, **trap auto-restores** on fail | fails if `sshd -t` rejects |
| 8 | `job8_trivy_docker_scan.sh` | Trivy CVE scan → JSON (+ optional SBOM), counts HIGH/CRITICAL | exit ≠0 if findings > `THRESHOLD` |
| 9 | `job9_fim_baseline.py` | file-integrity monitor: SHA-256 → SQLite baseline; `--verify` diffs → syslog | 0 clean / 1 drift / 2 error |
| 10 | `job10_iptables_lockdown.sh` | default-DROP + allow lo/established/SSH/APP, atomic `iptables-restore` | applies only when `DRY_RUN=false` |
| 11 | `job11_api_health_monitor.py` | async probes (aiohttp), Pydantic v2 gate, p50/p95/p99 | exit 1 if any endpoint unhealthy |
| 13 | `job13_pg_dump_encrypt.sh` | `pg_dump \| zstd \| gpg` **streamed** (no plaintext on disk) | fails on any pipe error |
| 15 | `job15_aws_ec2_provision.sh` | aws-cli v2: least-open SG, **IMDSv2 required**, base64 user-data | fails fast on missing creds |
| 18 | `job18_gcp_iam_least_priv.py` | GCP IAM audit: flag `owner`/`editor` bindings, Markdown report | exit 1 on violations / 2 on error |

> ⚠️ Jobs 7 & 10 change system state. Job 10 defaults to **dry-run**; job 7 validates and
> **auto-rolls-back**. Cloud jobs 15/18 need real credentials. Gaps (12/14/16/17) are backlog
> items — the numbering is intentional, not missing work.

</details>

<details>
<summary><b>🧰 2026 toolchain & IaC</b> — uv · OpenTofu · Cilium · Falco · SBOM</summary>

<br/>

Each was validated locally through its official container (`ghcr.io/opentofu/opentofu`,
`falcosecurity/falco`, `aquasec/trivy`).

- **`uv`** — the *only* Python workflow (no `pip` / `venv`). Deps pinned in a committed
  `uv.lock` (68 packages); CI runs `uv sync --all-extras --locked` — a drifted lock fails the build.
- **OpenTofu (`infra/`)** — declarative twin of `job15`: hardened EC2, **IMDSv2 required**,
  least-open SG, SSM-resolved AL2023. State on a self-hosted **`pg` backend** (no S3 / no TF Cloud).
- **Cilium (`k8s/cilium/`)** — eBPF twin of `job10`: default-deny `web` namespace, re-open only
  TCP 8351 + DNS, plus a **clusterwide Host Firewall** (audit-mode stageable).
- **Falco (`falco/`)** — runtime rules (sensitive-file reads, container shells, `/etc` writes)
  on the `modern_ebpf` CO-RE driver; **all external outputs disabled** (data sovereignty).
- **SBOM (Job 8)** — CycloneDX by default / SPDX on request, generated *before* the CVE gate so
  it exists as evidence even for a failing image.

```bash
uv sync --all-extras --locked && uv run pytest tests/python
tofu -chdir=infra init -backend=false && tofu -chdir=infra validate
falco --validate falco/falco_rules.local.yaml
SBOM_FORMAT=cyclonedx ./jobs/job8_trivy_docker_scan.sh   # -> sbom.cdx.json
```

</details>

<details>
<summary><b>🧪 Testing</b> — a real CI gate, not decoration</summary>

<br/>

```bash
make test          # pytest (Python jobs) + bats (shell jobs)
make test-py       # Python only, with the coverage gate (≥80%, currently ~94%)
make test-bats     # shell only
make lint          # ruff + shellcheck + bash -n
```

- **Python (pytest)** — digit-prefixed job modules loaded via `importlib` in `conftest.py`.
  job9 FIM (hash + drift 0/1/raise), job11 health monitor (loopback aiohttp test server, no
  real network), job18 IAM (offline `--bindings-file` e2e).
- **Shell (bats-core)** — dry-run / idempotency / arg-guard only; a `setup()` stub dir shadows
  `sudo`/`sshd`/`iptables-restore`/`aws` and "must never run" stubs fail loudly.

</details>

<details>
<summary><b>🔧 Jenkins setup</b> — pipeline-as-code (recommended)</summary>

<br/>

1. Install Jenkins + a JDK, unlock, install suggested plugins.
2. Let the `jenkins` user run job commands (`visudo` NOPASSWD for lab scope; `usermod -aG docker jenkins`).
3. **New Item → Pipeline** → *Pipeline script from SCM* → Git
   `https://github.com/www8351/build-deploy-test.git`, branch `main`, script path `Jenkinsfile`.
4. **Build with Parameters** — every job param exposed with a sane default (`USER_NAME=tester1`,
   `HOST_PORT=8351`, `IMAGE=nginx`, `COUNT=3`, …). Security jobs 7–18 wired as an **opt-in
   `Security & Compliance` stage group, all default-skipped**; destructive ones guarded default-false.

A *Preflight* stage wipes stale artifacts and fails fast if the agent lacks docker or passwordless
sudo. `Log.txt` / `zipfile.tgz` archived every run. A freestyle-jobs alternative (4b) exists too.

</details>

<details>
<summary><b>🔒 Security & notes</b></summary>

<br/>

A security repo should scan itself — CI has a dedicated **`security`** job: **gitleaks** (secret
detection + weekly full-history sweep), **ruff `flake8-bandit`** (Python SAST), **Dependabot**
(`pip` + `github-actions`). Policy & threat model: **[SECURITY.md](SECURITY.md)** — honest about
what the lab does *not* protect against.

`.gitignore` keeps the repo clean (every `*.md` ignored except this README; local lifecycle files
stay on disk). `.gitattributes` forces LF on `*.sh`/`*.py` so the Linux agent never chokes on CRLF.

</details>

---

<div align="center">

**Built by [@www8351](https://github.com/www8351)** · Licensed under [MIT](LICENSE)

<sub>One commit per step · every destructive job dry-runs or rolls back.</sub>

</div>
