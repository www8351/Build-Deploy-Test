"""Tests for job9 file-integrity monitor: baseline / verify / drift with tmp dirs."""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3

import pytest

# --- sha256_file -------------------------------------------------------------

def test_sha256_matches_hashlib(job9, tmp_path):
    f = tmp_path / "a.txt"
    f.write_bytes(b"hello world")
    assert job9.sha256_file(str(f)) == hashlib.sha256(b"hello world").hexdigest()


def test_sha256_large_file_chunk_loop(job9, tmp_path):
    # Larger than CHUNK (64 KiB) to exercise the streamed read loop.
    blob = b"x" * (job9.CHUNK * 3 + 17)
    f = tmp_path / "big.bin"
    f.write_bytes(blob)
    assert job9.sha256_file(str(f)) == hashlib.sha256(blob).hexdigest()


# --- db_sidecars -------------------------------------------------------------

def test_db_sidecars_returns_four_variants(job9, tmp_path):
    db = str(tmp_path / "base.db")
    base = os.path.abspath(db)
    assert job9.db_sidecars(db) == {
        base, base + "-journal", base + "-wal", base + "-shm"
    }


# --- iter_files --------------------------------------------------------------

def test_iter_files_skips_missing_root_and_exclude(job9, tmp_path, dummy_logger):
    (tmp_path / "sub").mkdir()
    keep = tmp_path / "sub" / "keep.txt"
    keep.write_text("k")
    drop = tmp_path / "sub" / "drop.txt"
    drop.write_text("d")
    missing = tmp_path / "nope"

    found = job9.iter_files(
        [str(tmp_path / "sub"), str(missing)],
        dummy_logger,
        exclude={os.path.abspath(str(drop))},
    )
    assert os.path.abspath(str(keep)) in {os.path.abspath(p) for p in found}
    assert os.path.abspath(str(drop)) not in {os.path.abspath(p) for p in found}


@pytest.mark.skipif(os.name == "nt", reason="symlink needs privilege on Windows")
def test_iter_files_skips_symlink(job9, tmp_path, dummy_logger):
    real = tmp_path / "real.txt"
    real.write_text("r")
    link = tmp_path / "link.txt"
    os.symlink(real, link)
    found = job9.iter_files([str(tmp_path)], dummy_logger)
    assert str(link) not in found


# --- build_baseline ----------------------------------------------------------

def _build_tree(root):
    (root / "d1").mkdir()
    (root / "d1" / "f1").write_text("one")
    (root / "d1" / "f2").write_text("two")
    (root / "f3").write_text("three")
    return 3


def test_build_baseline_counts_and_no_growth(job9, tmp_path, dummy_logger):
    root = tmp_path / "tree"
    root.mkdir()
    n = _build_tree(root)
    db = str(tmp_path / "b.db")

    count1 = job9.build_baseline(db, [str(root)], dummy_logger)
    assert count1 == n

    # Rebuild: DELETE-then-insert means the row count must not grow.
    count2 = job9.build_baseline(db, [str(root)], dummy_logger)
    assert count2 == n
    conn = sqlite3.connect(db)
    try:
        rows = conn.execute("SELECT COUNT(*) FROM baseline").fetchone()[0]
    finally:
        conn.close()
    assert rows == n


# --- verify ------------------------------------------------------------------

@pytest.fixture
def built(job9, tmp_path, dummy_logger):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = str(tmp_path / "b.db")
    job9.build_baseline(db, [str(root)], dummy_logger)
    return db, root


def test_verify_clean_returns_zero(job9, built, dummy_logger):
    db, root = built
    assert job9.verify(db, [str(root)], dummy_logger) == 0


def test_verify_detects_added(job9, built, dummy_logger):
    db, root = built
    (root / "new.txt").write_text("new")
    assert job9.verify(db, [str(root)], dummy_logger) == 1


def test_verify_detects_removed(job9, built, dummy_logger):
    db, root = built
    (root / "f3").unlink()
    assert job9.verify(db, [str(root)], dummy_logger) == 1


def test_verify_detects_modified(job9, built, dummy_logger):
    db, root = built
    (root / "f3").write_text("CHANGED")
    assert job9.verify(db, [str(root)], dummy_logger) == 1


def test_verify_missing_db_raises(job9, tmp_path, dummy_logger):
    with pytest.raises(job9.BaselineNotFoundError):
        job9.verify(str(tmp_path / "absent.db"), [str(tmp_path)], dummy_logger)


def test_verify_empty_baseline_raises(job9, tmp_path, dummy_logger):
    empty = tmp_path / "empty"
    empty.mkdir()
    db = str(tmp_path / "e.db")
    job9.build_baseline(db, [str(empty)], dummy_logger)  # zero files
    with pytest.raises(job9.BaselineNotFoundError):
        job9.verify(db, [str(empty)], dummy_logger)


# --- main smoke (argparse wiring) --------------------------------------------

def test_main_build_then_verify_and_drift(job9, tmp_path, monkeypatch):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = str(tmp_path / "m.db")
    # Avoid the SysLogHandler path entirely.
    monkeypatch.setattr(job9, "build_logger", lambda: __import__("logging").getLogger("x"))

    monkeypatch.setattr("sys.argv", ["job9", "--db", db, "--paths", str(root)])
    assert job9.main() == 0  # build

    monkeypatch.setattr("sys.argv", ["job9", "--db", db, "--paths", str(root), "--verify"])
    assert job9.main() == 0  # clean

    (root / "f3").write_text("MUTATED")  # non-vacuous drift
    assert job9.main() == 1


# --- logging + main error path -----------------------------------------------

def test_json_formatter_emits_metrics(job9):
    import logging as _logging
    rec = _logging.LogRecord("fim", _logging.INFO, __file__, 1, "an event", None, None)
    rec.metrics = {"files": 3}
    payload = json.loads(job9.JsonFormatter().format(rec))
    assert payload == {"level": "INFO", "event": "an event", "metrics": {"files": 3}}


def test_build_logger_returns_logger(job9):
    # On Windows /dev/log is absent, so this exercises the stderr fallback branch.
    logger = job9.build_logger()
    assert logger.handlers  # a handler was attached


def test_main_verify_without_baseline_returns_2(job9, tmp_path, monkeypatch):
    monkeypatch.setattr(job9, "build_logger",
                        lambda: __import__("logging").getLogger("x"))
    monkeypatch.setattr(
        "sys.argv",
        ["job9", "--db", str(tmp_path / "none.db"), "--paths", str(tmp_path), "--verify"],
    )
    assert job9.main() == 2  # BaselineNotFoundError -> exit 2
