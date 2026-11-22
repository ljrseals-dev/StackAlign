# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
SHELL := /bin/bash
SH_FILES := install.sh bin/stackalign bin/stackalign-oracle $(wildcard lib/*.sh) $(wildcard tests/*.sh) scripts/time-tests.sh scripts/security-lint.sh tests/lib/timing.sh m2b/measure-php-child-rss.sh tests/vm_egress_smoke.sh

.PHONY: test test-timed lint security headers all
all: lint headers test

HDR_FILES := Makefile $(SH_FILES) tests/test_tune_math.py scripts/validate_llm_plan.py .github/workflows/ci.yml .gitea/workflows/ci.yml vendor/versions.toml templates/nginx/conf.d/00-performance.conf templates/nginx/site-wordpress.conf.tmpl schema/001-initial.sql
headers:
	@bad=0; for f in $(HDR_FILES); do \
	  awk 'NR <= 6 { \
	    if (index($$0, "SPDX-License-Identifier: MIT")) spdx=1; \
	    if (index($$0, "Copyright (c) 2026 Lewis James Seals Jr.")) copyright=1; \
	    if (index($$0, "Author: Lewis James Seals Jr.")) author=1; \
	    if (index($$0, "Repository: https://github.com/ljrseals-dev/StackAlign")) repository=1; \
	  } END { exit !(spdx && copyright && author && repository) }' "$$f" \
	    || { echo "missing complete provenance header: $$f"; bad=1; }; \
	done; [ $$bad -eq 0 ] && echo "headers: ok ($(words $(HDR_FILES)) files)"

test:
	@fail=0; \
	for t in tests/test_*.sh; do \
	  echo "=== $$t"; bash "$$t" || { echo "SUITE FAILED: $$t"; fail=1; }; \
	done; \
	echo "=== tests/test_tune_math.py (PROVISIONAL tuner)"; \
	python3 -I tests/test_tune_math.py || { echo "SUITE FAILED: tests/test_tune_math.py"; fail=1; }; \
	if [ $$fail -ne 0 ]; then echo "RESULT: FAIL"; exit 1; else echo "RESULT: all suites passed"; fi

test-timed:
	@bash ./scripts/time-tests.sh

security:
	@bash ./scripts/security-lint.sh

lint: security
	@for f in $(SH_FILES); do bash -n "$$f" || exit 1; done; echo "bash -n: ok ($(words $(SH_FILES)) files)"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x -s bash -S warning $(SH_FILES) && echo "shellcheck: ok"; \
	else echo "shellcheck: NOT INSTALLED, skipped"; fi
