#!/usr/bin/env python3
"""
JOB 18 - GCP IAM least-privilege audit.

Reads a project's IAM policy (via Workload Identity / Application Default
Credentials - no static service-account keys), flags any principal holding
roles/owner or roles/editor, and appends a Markdown violation table to a status
file. Exits non-zero when violations are found so CI can gate on it.

Usage:
    ./job18_gcp_iam_least_priv.py --project my-gcp-project
    ./job18_gcp_iam_least_priv.py --bindings-file bindings.json   # offline mode
"""
from __future__ import annotations

import argparse
import json
import sys

try:  # optional at import time; only needed for a live GCP fetch
    from google.cloud import resourcemanager_v3

    HAVE_GCP = True
except ImportError:
    HAVE_GCP = False

RISKY_ROLES = {"roles/owner", "roles/editor"}


class GCPError(Exception):
    """Base error for the audit."""


class GCPUnavailableError(GCPError):
    """Raised when a live fetch is requested but the client library is absent."""


def analyze(bindings: list[dict]) -> list[dict]:
    """Return {member, role} rows for every principal with a risky role."""
    violations: list[dict] = []
    for binding in bindings:
        role = binding.get("role", "")
        if role in RISKY_ROLES:
            for member in binding.get("members", []):
                violations.append({"member": member, "role": role})
    return violations


def to_markdown(project: str, violations: list[dict]) -> str:
    """Render the violations as a Markdown table section."""
    lines = [
        "",
        f"## GCP IAM least-privilege audit - {project}",
        "",
        "| Principal | Role |",
        "|-----------|------|",
    ]
    if not violations:
        lines.append("| _none_ | _no roles/owner or roles/editor found_ |")
    else:
        for row in sorted(violations, key=lambda r: (r["role"], r["member"])):
            lines.append(f"| `{row['member']}` | `{row['role']}` |")
    lines.append("")
    return "\n".join(lines)


def append_report(path: str, text: str) -> None:
    """Append the Markdown table to the status file."""
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(text)


def fetch_bindings(project_id: str) -> list[dict]:
    """Fetch IAM bindings from GCP using Application Default Credentials."""
    if not HAVE_GCP:
        raise GCPUnavailableError(
            "google-cloud-resourcemanager not installed; use --bindings-file"
        )
    client = resourcemanager_v3.ProjectsClient()
    policy = client.get_iam_policy(resource=f"projects/{project_id}")
    return [{"role": b.role, "members": list(b.members)} for b in policy.bindings]


def main() -> int:
    parser = argparse.ArgumentParser(description="GCP IAM least-privilege audit.")
    parser.add_argument("--project", help="GCP project id")
    parser.add_argument(
        "--status-file", default="STATUS.md", help="file to append the table to"
    )
    parser.add_argument(
        "--bindings-file", help="JSON list of bindings (offline mode, skips GCP)"
    )
    args = parser.parse_args()

    try:
        if args.bindings_file:
            with open(args.bindings_file, encoding="utf-8") as handle:
                bindings = json.load(handle)
            project = args.project or "offline"
        else:
            if not args.project:
                parser.error("--project is required (or pass --bindings-file)")
            bindings = fetch_bindings(args.project)
            project = args.project

        violations = analyze(bindings)
        append_report(args.status_file, to_markdown(project, violations))
        print(json.dumps({"project": project, "violations": len(violations)}))
        return 1 if violations else 0
    except GCPError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
