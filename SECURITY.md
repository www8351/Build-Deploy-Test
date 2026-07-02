# Security Policy

`build-deploy-test` is a DevOps and security-automation lab: a set of Jenkins/CI jobs that
harden Linux hosts, lock down networking, scan container images, and audit cloud IAM. Because
the subject matter is security, the repository is held to the same standard it demonstrates.

## Security posture

This repo scans **itself** in CI (`.github/workflows/ci.yml`):

- **Secret detection** — `gitleaks` runs on every push/PR over the event's commits, plus a
  **weekly scheduled full-history sweep** (and on-demand via `workflow_dispatch`).
- **Python SAST** — `ruff`'s `flake8-bandit` (`S`) ruleset lints the Python source. This is
  Python-only and implements a subset of Bandit (pattern-based, no data-flow/taint analysis) —
  it is one layer, not a complete SAST program.
- **Shell** — `shellcheck` + `bash -n` lint every script (correctness-focused; treat its
  security value as best-effort, not a bandit-grade scanner for the root-run jobs).
- **Dependencies** — Dependabot (`pip` + `github-actions`) surfaces CVE/version bumps as PRs.
- **Tests / IaC** — Python is tested on 3.11–3.13 behind an 80% coverage gate, the shell jobs
  are exercised under `bats`, and the OpenTofu is `fmt`- and `validate`-checked.

The `ruff` version is pinned so the SAST gate is deterministic. A failing scan on the repo
that ships defensive tooling is treated as a real defect, not a lint nit.

## Supported scope

Only the latest `main` is supported — this is a lab, not a versioned product, so there are no
backported branches or LTS lines.

The scripts run on a Linux CI agent as **root/sudo** — inherent to host hardening and
firewalling. The **destructive edits are engineered for safety** rather than left to chance:

- `job7_ssh_hardening.sh` timestamps a backup, validates the rewritten config with `sshd -t`
  *before* reloading, and an `EXIT` trap auto-restores the original on any failure — a bad
  edit cannot lock you out.
- `job10_iptables_lockdown.sh` honours `DRY_RUN` to print the ruleset without applying it, and
  otherwise swaps the whole table atomically via `iptables-restore` (no half-open window).
  Both jobs are idempotent on re-run.
- Cloud jobs use **your** credentials, never committed ones: `job15` reads AWS creds from the
  environment (and supports `DRY_RUN`); `job18` uses Application Default Credentials / Workload
  Identity, not static keys. **No secrets, keys, tokens, or `.env` files are committed** —
  gitleaks enforces this, and every cloud call fails closed without the operator's own creds.

Network-exposure defaults are a separate matter — see the honesty note below.

## Reporting a vulnerability

Please report privately first:

1. **Preferred:** open a GitHub private security advisory — *Security → Advisories → Report a
   vulnerability* on this repository. Details stay embargoed until a fix lands.
2. For low-sensitivity issues (a hardening gap, an unsafe default, a lint false-negative), a
   regular GitHub issue is fine.

This is maintained by one person as a portfolio project. Expect a **best-effort
acknowledgement within ~3 business days** and a fix or a written triage decision shortly after.
There is no bug bounty and no formal SLA. Do **not** open a public issue for anything
weaponisable (e.g. a leaked secret) — use the advisory channel so it can be handled under
embargo.

## What this project does NOT protect against

Stated plainly, because a security lab that oversells itself is worse than none:

- **Demo-scope, not production-hardened.** The jobs illustrate techniques; they are not a
  turnkey CIS-benchmarked baseline and have not been validated against every distro / kernel /
  cloud combination.
- **Some network defaults are permissive on purpose** so examples run out of the box — e.g.
  `job15`'s `SSH_CIDR` and `infra/`'s `ssh_cidr` default to `0.0.0.0/0`, and `job10`'s
  default-DROP egress needs an explicit DNS/update rule before it is safe on a live host. Read
  each script's header and set parameters for your environment before enabling.
- **No IaC misconfiguration scanning yet.** The self-scan gates Python (ruff-S), shell
  (shellcheck) and secrets (gitleaks), but does not yet run a config scanner
  (`trivy config` / checkov / tfsec) over `infra/`, Cilium or Falco — a known next control.
- **The trust model assumes a single, trusted operator** on a single-tenant agent. There is no
  multi-tenant isolation and no defence against a malicious operator; running as root means a
  compromised job compromises the host.
- **No runtime monitoring ships enabled.** The rules under `falco/` are illustrative, not a
  managed detection pipeline.

If in doubt, treat this repository as reference material to read and adapt — not as something
to point at production and run unmodified.
