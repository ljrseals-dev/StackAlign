#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# Static guardrail for high-risk shell constructs. This is not a shell parser.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
status=0
while IFS= read -r -d '' file; do
    # Ignore full-line comments; report source locations for review.
    hits=$(grep -nE \
        '(^|[;&|[:space:]])eval([[:space:]]|$)|(^|[;&|[:space:]])(bash|sh)[[:space:]]+-c([[:space:]]|$)|curl[^#]*[|][[:space:]]*(bash|sh)|chmod[[:space:]]+(-R[[:space:]]+)?777([[:space:]]|$)|(^|[[:space:]])set[[:space:]]+-x([[:space:]]|$)' \
        "$file" | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' || true)
    if [ -n "$hits" ]; then
        printf 'security-lint: review banned shell construct in %s:\n%s\n' "$file" "$hits" >&2
        status=1
    fi
done < <(find "$ROOT/bin" "$ROOT/lib" "$ROOT/install.sh" -type f \( -name '*.sh' -o -path "$ROOT/bin/*" \) -print0)
exit "$status"
