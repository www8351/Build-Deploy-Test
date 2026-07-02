"""Tests for job18 GCP IAM least-privilege audit (pure + offline; never imports google)."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

DATA = Path(__file__).parent / "data"


# --- analyze -----------------------------------------------------------------

def test_analyze_flags_only_risky_roles(job18):
    bindings = [
        {"role": "roles/owner", "members": ["user:a@x.com", "user:b@x.com"]},
        {"role": "roles/editor", "members": ["user:c@x.com"]},
        {"role": "roles/viewer", "members": ["user:d@x.com"]},
    ]
    violations = job18.analyze(bindings)
    assert violations == [
        {"member": "user:a@x.com", "role": "roles/owner"},
        {"member": "user:b@x.com", "role": "roles/owner"},
        {"member": "user:c@x.com", "role": "roles/editor"},
    ]


def test_analyze_empty_and_missing_members(job18):
    assert job18.analyze([]) == []
    # A risky role with no "members" key must not crash (dict.get default).
    assert job18.analyze([{"role": "roles/owner"}]) == []


# --- to_markdown -------------------------------------------------------------

def test_to_markdown_none_row_when_clean(job18):
    md = job18.to_markdown("proj", [])
    assert "_none_" in md
    assert "| Principal | Role |" in md


def test_to_markdown_sorted_and_formatted(job18):
    violations = [
        {"member": "user:z@x.com", "role": "roles/owner"},
        {"member": "user:a@x.com", "role": "roles/owner"},
        {"member": "user:m@x.com", "role": "roles/editor"},
    ]
    md = job18.to_markdown("proj", violations)
    lines = [ln for ln in md.splitlines() if ln.startswith("| `")]
    # Sorted by (role, member): editor before owner, members alphabetical within role.
    assert lines == [
        "| `user:m@x.com` | `roles/editor` |",
        "| `user:a@x.com` | `roles/owner` |",
        "| `user:z@x.com` | `roles/owner` |",
    ]


# --- append_report -----------------------------------------------------------

def test_append_report_appends_utf8(job18, tmp_path):
    target = tmp_path / "STATUS.md"
    job18.append_report(str(target), "first\n")
    job18.append_report(str(target), "second\n")
    assert target.read_text(encoding="utf-8") == "first\nsecond\n"


# --- offline end-to-end via main() -------------------------------------------

def _run_main(job18, monkeypatch, argv):
    monkeypatch.setattr("sys.argv", ["job18", *argv])
    return job18.main()


def test_main_violations_exit1(job18, monkeypatch, tmp_path, capsys):
    status = tmp_path / "STATUS.md"
    rc = _run_main(
        job18, monkeypatch,
        ["--bindings-file", str(DATA / "bindings_violations.json"),
         "--status-file", str(status), "--project", "demo"],
    )
    assert rc == 1
    out = json.loads(capsys.readouterr().out)
    assert out["project"] == "demo"
    assert out["violations"] == 3  # 2 owner members + 1 editor
    assert "roles/owner" in status.read_text(encoding="utf-8")


def test_main_clean_exit0(job18, monkeypatch, tmp_path, capsys):
    status = tmp_path / "STATUS.md"
    rc = _run_main(
        job18, monkeypatch,
        ["--bindings-file", str(DATA / "bindings_clean.json"),
         "--status-file", str(status)],
    )
    assert rc == 0
    assert json.loads(capsys.readouterr().out)["violations"] == 0
    assert "_none_" in status.read_text(encoding="utf-8")


def test_main_requires_project_or_file(job18, monkeypatch):
    with pytest.raises(SystemExit) as exc:
        _run_main(job18, monkeypatch, [])
    assert exc.value.code == 2  # argparse parser.error


def test_fetch_bindings_raises_when_lib_absent(job18, monkeypatch):
    monkeypatch.setattr(job18, "HAVE_GCP", False)
    with pytest.raises(job18.GCPUnavailableError):
        job18.fetch_bindings("some-project")
