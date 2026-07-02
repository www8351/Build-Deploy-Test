# Developer entry points. Requires: uv (Python), bats (shell tests), tofu (IaC).
# CI runs the same commands — see .github/workflows/ci.yml.

.PHONY: help install test test-py test-bats cov lint fmt tf-validate demo

help:
	@echo "make install     - resolve Python deps into a uv venv (all extras)"
	@echo "make test        - run the full suite (pytest + bats)"
	@echo "make test-py     - Python tests only, with coverage gate"
	@echo "make test-bats   - shell (bats) tests only"
	@echo "make cov         - Python tests with term-missing coverage report"
	@echo "make lint        - ruff + shellcheck + bash -n"
	@echo "make fmt         - ruff --fix + tofu fmt"
	@echo "make tf-validate - tofu fmt -check + validate (infra/)"
	@echo "make demo        - run the safe (dry-run) jobs to see them work"

install:
	uv sync --all-extras

test: test-py test-bats

test-py:
	uv run pytest tests/python --cov=jobs --cov-report=term-missing --cov-fail-under=80

test-bats:
	bats tests/bats

cov:
	uv run pytest tests/python --cov=jobs --cov-report=term-missing

lint:
	uv run ruff check labs jobs tests
	shellcheck labs/*.sh jobs/*.sh
	for f in labs/*.sh jobs/*.sh; do bash -n "$$f"; done

fmt:
	uv run ruff check --fix labs jobs tests
	tofu -chdir=infra fmt

tf-validate:
	tofu fmt -check -recursive infra
	tofu -chdir=infra init -backend=false
	tofu -chdir=infra validate

# Run the non-destructive jobs so a reviewer can see them work with no cloud,
# no root and no risk. Every job here is a dry-run / render path.
demo:
	@echo "== job10 iptables lockdown (DRY_RUN) =="
	@DRY_RUN=1 bash jobs/job10_iptables_lockdown.sh
	@echo "== job13 encrypted pg_dump (DRY_RUN) =="
	@GPG_RECIPIENT=demo@example.com DRY_RUN=1 bash jobs/job13_pg_dump_encrypt.sh
	@echo "== job15 EC2 provision (DRY_RUN) =="
	@DRY_RUN=1 bash jobs/job15_aws_ec2_provision.sh
