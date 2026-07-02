"""Shared test fixtures.

The job modules are digit-prefixed (``jobs/job9_fim_baseline.py``), so they are not
valid Python identifiers and cannot be imported by name. ``package = false`` in
pyproject also means there is no import path. We load each module by file path with
importlib and hand it to tests as a fixture.
"""
from __future__ import annotations

import importlib.util
import logging
import sys
from pathlib import Path

JOBS_DIR = Path(__file__).resolve().parent.parent / "jobs"


def load_job(filename: str):
    """Load a job module from ``jobs/<filename>`` under a synthetic module name."""
    path = JOBS_DIR / filename
    mod_name = "_" + path.stem  # e.g. "_job9_fim_baseline"
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = module
    spec.loader.exec_module(module)
    return module


import pytest  # noqa: E402


@pytest.fixture(scope="session")
def job9():
    return load_job("job9_fim_baseline.py")


@pytest.fixture(scope="session")
def job11():
    return load_job("job11_api_health_monitor.py")


@pytest.fixture(scope="session")
def job18():
    return load_job("job18_gcp_iam_least_priv.py")


@pytest.fixture
def dummy_logger():
    """A logger with a NullHandler, so job9's pure functions never touch /dev/log."""
    logger = logging.getLogger("test-fim")
    logger.handlers.clear()
    logger.addHandler(logging.NullHandler())
    logger.setLevel(logging.INFO)
    return logger
