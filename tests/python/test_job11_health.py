"""Tests for job11 async API health monitor: pure aggregation + loopback probes."""
from __future__ import annotations

import argparse
import asyncio

import aiohttp
import pytest
from aiohttp import web

# --- percentile (pure) -------------------------------------------------------

def test_percentile_empty_is_zero(job11):
    assert job11.percentile([], 50) == 0.0


def test_percentile_single(job11):
    assert job11.percentile([42.0], 99) == 42.0


def test_percentile_nearest_rank(job11):
    values = [10.0, 20.0, 30.0, 40.0, 50.0]
    # rank = ceil(pct/100 * n) - 1
    assert job11.percentile(values, 50) == 30.0   # ceil(2.5)-1 = 2
    assert job11.percentile(values, 95) == 50.0   # ceil(4.75)-1 = 4
    assert job11.percentile(values, 100) == 50.0  # max


# --- summarize (pure) --------------------------------------------------------

def _probe(job11, *, ok, schema_ok=False, latency=1.0):
    return job11.Probe(
        url="http://x", status=200 if ok else 500, ok=ok,
        schema_ok=schema_ok, latency_ms=latency,
    )


def test_summarize_counts_and_percentiles_over_ok_only(job11):
    probes = [
        _probe(job11, ok=True, schema_ok=True, latency=10.0),
        _probe(job11, ok=True, schema_ok=False, latency=20.0),
        _probe(job11, ok=False, latency=999.0),  # excluded from latency stats
    ]
    s = job11.summarize(probes)
    assert s["total"] == 3
    assert s["ok"] == 2
    assert s["failed"] == 1
    assert s["schema_ok"] == 1
    assert s["p99_ms"] == 20.0  # 999 (failed) must not appear


# --- load_urls ---------------------------------------------------------------

def test_load_urls_merges_and_strips(job11, tmp_path):
    f = tmp_path / "urls.txt"
    f.write_text("http://a\n\n  http://b  \n")
    args = argparse.Namespace(url=["http://c"], urls_file=str(f))
    assert job11.load_urls(args) == ["http://c", "http://a", "http://b"]


def test_load_urls_empty(job11):
    args = argparse.Namespace(url=None, urls_file=None)
    assert job11.load_urls(args) == []


# --- JsonEnvelope schema gate ------------------------------------------------

def test_json_envelope_allows_extra(job11):
    obj = job11.JsonEnvelope.model_validate({"anything": 1, "nested": {"a": 2}})
    assert obj is not None


# --- probe_once against a loopback server (no real network) ------------------

@pytest.fixture
async def base_url(aiohttp_server):
    async def ok(_req):
        return web.json_response({"status": "ok"})

    async def text(_req):
        return web.Response(text="hello", content_type="text/plain")

    async def array(_req):
        return web.json_response([1, 2, 3])

    async def err(_req):
        return web.Response(status=500)

    async def slow(_req):
        await asyncio.sleep(0.3)
        return web.json_response({"status": "ok"})

    app = web.Application()
    app.router.add_get("/ok", ok)
    app.router.add_get("/text", text)
    app.router.add_get("/array", array)
    app.router.add_get("/err", err)
    app.router.add_get("/slow", slow)
    server = await aiohttp_server(app)
    return str(server.make_url("")).rstrip("/")


async def _run_probe(job11, url, timeout=5.0):
    sem = asyncio.Semaphore(1)
    async with aiohttp.ClientSession() as session:
        return await job11.probe_once(session, "GET", url, timeout, sem)


async def test_probe_ok_json_object(job11, base_url):
    p = await _run_probe(job11, base_url + "/ok")
    assert p.ok is True and p.schema_ok is True and p.status == 200


async def test_probe_ok_non_json(job11, base_url):
    p = await _run_probe(job11, base_url + "/text")
    assert p.ok is True and p.schema_ok is False


async def test_probe_json_array_not_object(job11, base_url):
    p = await _run_probe(job11, base_url + "/array")
    assert p.ok is True and p.schema_ok is False


async def test_probe_500_not_ok(job11, base_url):
    p = await _run_probe(job11, base_url + "/err")
    assert p.ok is False and p.status == 500


async def test_probe_timeout_never_raises(job11, base_url):
    p = await _run_probe(job11, base_url + "/slow", timeout=0.1)
    assert p.ok is False
    assert p.error is not None
    assert p.latency_ms > 0  # bounded, not asserted for equality (not flaky)


async def test_run_fans_out(job11, base_url):
    probes = await job11.run([base_url + "/ok"], "GET", count=3, concurrency=2, timeout=5.0)
    assert len(probes) == 3
    assert all(p.ok for p in probes)


# --- main() CLI wiring (sync; fake run() so no outer event loop is needed) ----

def test_main_prints_summary_and_gates(job11, monkeypatch, capsys):
    canned = [
        job11.Probe(url="http://x", status=200, ok=True, schema_ok=True, latency_ms=5.0),
        job11.Probe(url="http://y", status=None, ok=False, schema_ok=False,
                    latency_ms=1.0, error="boom"),
    ]

    async def fake_run(*_a, **_k):
        return canned

    monkeypatch.setattr(job11, "run", fake_run)
    monkeypatch.setattr("sys.argv", ["job11", "--url", "http://x", "--url", "http://y"])
    rc = job11.main()
    assert rc == 1  # one unhealthy -> gate fails
    out = capsys.readouterr()
    assert '"failed": 1' in out.out
    assert "UNHEALTHY" in out.err


def test_main_no_urls_errors(job11, monkeypatch):
    monkeypatch.setattr("sys.argv", ["job11"])
    with pytest.raises(SystemExit) as exc:
        job11.main()
    assert exc.value.code == 2
