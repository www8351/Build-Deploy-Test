#!/usr/bin/env python3
"""
JOB 11 - asynchronous API health monitor.

Fires concurrent HTTP requests at a list of endpoints with aiohttp/asyncio,
checks for HTTP 200/201, validates that each JSON body parses as an object
(Pydantic v2), and prints aggregate latency percentiles (p50/p95/p99) plus a
JSON summary to stdout. Exits non-zero if any endpoint is unhealthy.

Usage:
    ./job11_api_health_monitor.py --url https://api.example.com/health
    ./job11_api_health_monitor.py --url http://a/h --url http://b/h --count 20
    ./job11_api_health_monitor.py --urls-file urls.txt --method GET --concurrency 32
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import sys
import time

import aiohttp
from pydantic import BaseModel, ConfigDict, ValidationError


class JsonEnvelope(BaseModel):
    """Schema gate: the body must deserialize to a JSON object. Extra keys are
    allowed so this validates any well-formed JSON API response."""

    model_config = ConfigDict(extra="allow")


class Probe(BaseModel):
    """Result of a single request."""

    url: str
    status: int | None
    ok: bool
    schema_ok: bool
    latency_ms: float
    error: str | None = None


def percentile(values: list[float], pct: float) -> float:
    """Nearest-rank percentile of a list (0.0 for an empty list)."""
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(0, math.ceil(pct / 100 * len(ordered)) - 1)
    return round(ordered[rank], 2)


async def probe_once(
    session: aiohttp.ClientSession,
    method: str,
    url: str,
    timeout: float,
    sem: asyncio.Semaphore,
) -> Probe:
    """Issue one request and classify the outcome (never raises)."""
    async with sem:
        start = time.monotonic()
        try:
            async with session.request(
                method, url, timeout=aiohttp.ClientTimeout(total=timeout)
            ) as resp:
                body = await resp.text()
                latency_ms = round((time.monotonic() - start) * 1000, 2)
                schema_ok = False
                try:
                    data = json.loads(body)
                    if isinstance(data, dict):
                        JsonEnvelope.model_validate(data)
                        schema_ok = True
                except (json.JSONDecodeError, ValidationError):
                    schema_ok = False
                return Probe(
                    url=url,
                    status=resp.status,
                    ok=resp.status in (200, 201),
                    schema_ok=schema_ok,
                    latency_ms=latency_ms,
                )
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            latency_ms = round((time.monotonic() - start) * 1000, 2)
            return Probe(
                url=url,
                status=None,
                ok=False,
                schema_ok=False,
                latency_ms=latency_ms,
                error=str(exc),
            )


async def run(
    urls: list[str], method: str, count: int, concurrency: int, timeout: float
) -> list[Probe]:
    """Fan out count requests per URL, bounded by a concurrency semaphore."""
    sem = asyncio.Semaphore(concurrency)
    async with aiohttp.ClientSession() as session:
        tasks = [
            probe_once(session, method, url, timeout, sem)
            for url in urls
            for _ in range(count)
        ]
        return await asyncio.gather(*tasks)


def summarize(probes: list[Probe]) -> dict[str, object]:
    """Aggregate probe results into a summary dict."""
    ok_latencies = [p.latency_ms for p in probes if p.ok]
    return {
        "total": len(probes),
        "ok": sum(1 for p in probes if p.ok),
        "failed": sum(1 for p in probes if not p.ok),
        "schema_ok": sum(1 for p in probes if p.schema_ok),
        "p50_ms": percentile(ok_latencies, 50),
        "p95_ms": percentile(ok_latencies, 95),
        "p99_ms": percentile(ok_latencies, 99),
    }


def load_urls(args: argparse.Namespace) -> list[str]:
    urls = list(args.url or [])
    if args.urls_file:
        with open(args.urls_file, encoding="utf-8") as handle:
            urls += [line.strip() for line in handle if line.strip()]
    return urls


def main() -> int:
    parser = argparse.ArgumentParser(description="Async API health monitor.")
    parser.add_argument("--url", action="append", help="target URL (repeatable)")
    parser.add_argument("--urls-file", help="file with one URL per line")
    parser.add_argument("--method", default="GET", help="HTTP method")
    parser.add_argument("--count", type=int, default=1, help="requests per URL")
    parser.add_argument("--concurrency", type=int, default=16, help="max in flight")
    parser.add_argument("--timeout", type=float, default=10.0, help="per-request seconds")
    args = parser.parse_args()

    urls = load_urls(args)
    if not urls:
        parser.error("no URLs given (use --url or --urls-file)")

    probes = asyncio.run(
        run(urls, args.method.upper(), args.count, args.concurrency, args.timeout)
    )
    summary = summarize(probes)
    print(json.dumps(summary))
    for probe in probes:
        if not probe.ok:
            print(
                f"UNHEALTHY {probe.url} status={probe.status} err={probe.error}",
                file=sys.stderr,
            )
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
