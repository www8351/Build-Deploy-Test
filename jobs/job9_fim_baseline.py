#!/usr/bin/env python3
"""
JOB 9 - file integrity monitor (FIM).

Builds a SHA-256 baseline of sensitive paths (/etc, /var/spool/cron,
/root/.ssh) in an SQLite database. With --verify it compares the current state
against that baseline and emits differential metrics (added / removed /
modified counts) to syslog as JSON for log aggregators.

Usage:
    sudo ./job9_fim_baseline.py                 # build / refresh the baseline
    sudo ./job9_fim_baseline.py --verify        # check current state vs baseline
    ./job9_fim_baseline.py --paths ./dir --db out.db   # scan arbitrary roots
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import logging.handlers
import os
import sqlite3
import sys

DEFAULT_PATHS = ["/etc", "/var/spool/cron", "/root/.ssh"]
DEFAULT_DB = "fim_baseline.db"
CHUNK = 65536


class FIMError(Exception):
    """Base error for the FIM utility."""


class BaselineNotFoundError(FIMError):
    """Raised when --verify runs before a baseline exists."""


class JsonFormatter(logging.Formatter):
    """Render each log record as a single JSON object for aggregators."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "level": record.levelname,
            "event": record.getMessage(),
        }
        metrics = getattr(record, "metrics", None)
        if metrics is not None:
            payload["metrics"] = metrics
        return json.dumps(payload)


def build_logger() -> logging.Logger:
    """Log to syslog as JSON where available, else fall back to stderr."""
    logger = logging.getLogger("fim")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler: logging.Handler
    try:
        handler = logging.handlers.SysLogHandler(address="/dev/log")
    except (OSError, AttributeError):
        handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
    return logger


def sha256_file(path: str) -> str:
    """Return the SHA-256 hex digest of a file, streamed in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def db_sidecars(db_path: str) -> set[str]:
    """Absolute paths of the SQLite DB and its journal/WAL sidecars to exclude
    from scanning, so the baseline never records or diffs against itself."""
    base = os.path.abspath(db_path)
    return {base + suffix for suffix in ("", "-journal", "-wal", "-shm")}


def iter_files(
    roots: list[str], logger: logging.Logger, exclude: set[str] | None = None
) -> list[str]:
    """Collect regular (non-symlink) files under each existing root, skipping
    any path in `exclude` (matched by absolute path)."""
    skip = exclude or set()
    found: list[str] = []
    for root in roots:
        if not os.path.isdir(root):
            logger.warning("skip missing root", extra={"metrics": {"root": root}})
            continue
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                full = os.path.join(dirpath, name)
                if os.path.islink(full) or not os.path.isfile(full):
                    continue
                if os.path.abspath(full) in skip:
                    continue
                found.append(full)
    return found


def connect(db_path: str) -> sqlite3.Connection:
    """Open the baseline DB, creating the schema if absent."""
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS baseline ("
        "path TEXT PRIMARY KEY, sha256 TEXT NOT NULL, size INTEGER, mtime REAL)"
    )
    return conn


def build_baseline(db_path: str, roots: list[str], logger: logging.Logger) -> int:
    """Hash every file under the roots and store the baseline. Returns count."""
    conn = connect(db_path)
    count = 0
    exclude = db_sidecars(db_path)
    try:
        with conn:
            conn.execute("DELETE FROM baseline")
            for path in iter_files(roots, logger, exclude):
                try:
                    stat = os.stat(path)
                    conn.execute(
                        "INSERT OR REPLACE INTO baseline VALUES (?, ?, ?, ?)",
                        (path, sha256_file(path), stat.st_size, stat.st_mtime),
                    )
                    count += 1
                except OSError as exc:
                    logger.warning(
                        "unreadable file",
                        extra={"metrics": {"path": path, "error": str(exc)}},
                    )
    finally:
        conn.close()
    logger.info("baseline built", extra={"metrics": {"files": count, "db": db_path}})
    return count


def verify(db_path: str, roots: list[str], logger: logging.Logger) -> int:
    """Compare current state to the baseline. Returns 1 on drift, 0 if clean."""
    if not os.path.isfile(db_path):
        raise BaselineNotFoundError(f"no baseline at {db_path}; build it first")
    conn = connect(db_path)
    try:
        baseline = {
            row[0]: row[1]
            for row in conn.execute("SELECT path, sha256 FROM baseline")
        }
    finally:
        conn.close()
    if not baseline:
        raise BaselineNotFoundError("baseline is empty; build it first")

    current = set(iter_files(roots, logger, db_sidecars(db_path)))
    added = sorted(current - baseline.keys())
    removed = sorted(baseline.keys() - current)
    modified = []
    for path in current & baseline.keys():
        try:
            if sha256_file(path) != baseline[path]:
                modified.append(path)
        except OSError as exc:
            logger.warning(
                "unreadable file",
                extra={"metrics": {"path": path, "error": str(exc)}},
            )
    modified.sort()

    metrics = {
        "added": len(added),
        "removed": len(removed),
        "modified": len(modified),
        "baseline_files": len(baseline),
        "added_paths": added,
        "removed_paths": removed,
        "modified_paths": modified,
    }
    drift = len(added) + len(removed) + len(modified)
    if drift:
        logger.warning("integrity drift detected", extra={"metrics": metrics})
    else:
        logger.info("integrity ok", extra={"metrics": metrics})
    return 1 if drift else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="SHA-256 file integrity monitor.")
    parser.add_argument("--db", default=DEFAULT_DB, help="SQLite baseline path")
    parser.add_argument(
        "--paths", nargs="+", default=DEFAULT_PATHS, help="roots to scan"
    )
    parser.add_argument(
        "--verify", action="store_true", help="compare current state to baseline"
    )
    args = parser.parse_args()

    logger = build_logger()
    try:
        if args.verify:
            return verify(args.db, args.paths, logger)
        build_baseline(args.db, args.paths, logger)
        return 0
    except FIMError as exc:
        logger.error("fim error", extra={"metrics": {"error": str(exc)}})
        return 2


if __name__ == "__main__":
    sys.exit(main())
