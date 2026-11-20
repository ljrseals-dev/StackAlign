# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
SHELL := /bin/bash
SH_FILES := install.sh bin/stackalign bin/stackalign-oracle $(wildcard lib/*.sh) $(wildcard tests/*.sh) scripts/time-tests.sh scripts/security-lint.sh tests/lib/timing.sh m2b/measure-php-child-rss.sh tests/vm_egress_smoke.sh

.PHONY: test test-timed lint security headers all
all: lint headers test

# Rule 1: SPDX header + author on every source file (first 5 lines).
HDR_FILES := $(SH_FILES) tests/test_tune_math.py .github/workflows/ci.yml .gitea/workflows/ci.yml vendor/versions.toml templates/nginx/site-wordpress.conf.tmpl
headers:
	@bad=0; for f in $(HDR_FILES); do \
	  head -5 "$$f" | grep -q 'SPDX-License-Identifier:' && head -5 "$$f" | grep -q 'Author: Lewis James Seals Jr.' \
	    || { echo "missing SPDX/Author header: $$f"; bad=1; }; \
	done; [ $$bad -eq 0 ] && echo "headers: ok ($(words $(HDR_FILES)) files)"

# Runs every suite, keeps going after a failure, fails at the end if any failed.
test:
	@fail=0; \
	for t in tests/test_*.sh; do \
	  echo "=== $$t"; bash "$$t" || { echo "SUITE FAILED: $$t"; fail=1; }; \
	done; \
	echo "=== tests/test_tune_math.py (PROVISIONAL tuner)"; \
	python3 -I tests/test_tune_math.py || { echo "SUITE FAILED: tests/test_tune_math.py"; fail=1; }; \
	if [ $$fail -ne 0 ]; then echo "RESULT: FAIL"; exit 1; else echo "RESULT: all suites passed"; fi

# Additive timing entry point; the canonical test target above is unchanged.
test-timed:
	@bash ./scripts/time-tests.sh

security:
	@bash ./scripts/security-lint.sh

# bash -n always; ShellCheck is mandatory in CI and optional for local installs.
lint: security
	@for f in $(SH_FILES); do bash -n "$$f" || exit 1; done; echo "bash -n: ok ($(words $(SH_FILES)) files)"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x -s bash -S warning $(SH_FILES) && echo "shellcheck: ok"; \
	else echo "shellcheck: NOT INSTALLED, skipped"; fi
