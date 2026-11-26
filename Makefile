# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
SHELL := /bin/bash
SH_FILES := install.sh bin/stackalign bin/stackalign-oracle $(wildcard lib/*.sh) $(wildcard tests/*.sh) scripts/time-tests.sh scripts/security-lint.sh tests/lib/timing.sh

.PHONY: test test-timed lint security headers all
all: lint headers test

# Require copyright, SPDX, author, and canonical repository headers in the first six lines.
# Preserve the legacy two-field check for this branch's inherited baseline.
HDR_FILES := $(SH_FILES) Makefile tests/test_tune_math.py .github/workflows/ci.yml .gitea/workflows/ci.yml
# Apply the full four-field contract to every file changed or introduced by this PR.
HDR_STRICT_FILES := Makefile bin/stackalign lib/state.sh lib/llm.sh lib/llm_host.sh tests/test_state.sh tests/test_agent.sh tests/test_llm.sh tests/test_llm_host.sh scripts/validate_llm_plan.py schema/001-initial.sql .github/workflows/ci.yml
headers:
	@bad=0; for f in $(HDR_FILES); do \
	  head -6 "$$f" | grep -q 'SPDX-License-Identifier:' && head -6 "$$f" | grep -q 'Author: Lewis James Seals Jr.' \
	    || { echo "missing SPDX/Author header: $$f"; bad=1; }; \
	done; \
	for f in $(HDR_STRICT_FILES); do \
	  awk 'NR <= 6 { \
	    if (index($$0, "SPDX-License-Identifier: MIT")) spdx=1; \
	    if (index($$0, "Copyright (c) 2026 Lewis James Seals Jr.")) copyright=1; \
	    if (index($$0, "Author: Lewis James Seals Jr.")) author=1; \
	    if (index($$0, "Repository: https://github.com/ljrseals-dev/StackAlign")) repository=1; \
	  } END { exit !(spdx && copyright && author && repository) }' "$$f" \
	    || { echo "missing complete provenance header: $$f"; bad=1; }; \
	done; [ $$bad -eq 0 ] && echo "headers: ok (legacy baseline + strict PR files)"
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
