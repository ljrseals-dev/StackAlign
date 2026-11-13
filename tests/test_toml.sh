#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
# shellcheck source=../lib/toml.sh
source "$root/lib/toml.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label: expected <$expected>, got <$actual>"
}

assert_has_no_entries() {
    (( ${#TOML_DATA[@]} == 0 )) || fail "TOML_DATA was not empty after failed parse"
}

cat > "$work/valid.toml" <<'EOF'
# Leading comment

root_key = "outside"

[meta]
version = "1.2.3" # inline comment
enabled = true
workers = 12
negative = -7
escaped = "say \"hello\" and \\path"

[[component]]
name = "nginx"
url = "https://example.invalid/a?x=1"

[[mirror]]
name = "primary"
url = "https://mirror.invalid/"

[[component]]
name = "php"
pinned_version = "8.5.12"

[[mirror]]
name = "secondary"
enabled = false
EOF

sa_toml_parse "$work/valid.toml" || fail "valid fixture did not parse"

assert_eq "${TOML_DATA[root_key]}" "outside" "root key"
assert_eq "${TOML_DATA[meta.version]}" "1.2.3" "simple table"
assert_eq "${TOML_DATA[meta.enabled]}" "true" "boolean"
assert_eq "${TOML_DATA[meta.workers]}" "12" "integer"
assert_eq "${TOML_DATA[meta.negative]}" "-7" "negative integer"
assert_eq "${TOML_DATA[meta.escaped]}" 'say "hello" and \path' "escaped quote/backslash"
assert_eq "${TOML_DATA[component.0.name]}" "nginx" "first component"
assert_eq "${TOML_DATA[component.0.url]}" "https://example.invalid/a?x=1" "quoted URL"
assert_eq "${TOML_DATA[component.1.name]}" "php" "second component"
assert_eq "${TOML_DATA[component.1.pinned_version]}" "8.5.12" "second component version"
assert_eq "${TOML_DATA[mirror.0.name]}" "primary" "first mirror index"
assert_eq "${TOML_DATA[mirror.1.name]}" "secondary" "second mirror index"
assert_eq "${TOML_DATA[mirror.1.enabled]}" "false" "false literal"

expect_failure() {
    local label="$1" fixture="$2"
    printf '%s\n' "$fixture" > "$work/invalid.toml"
    TOML_DATA[stale]="must be cleared"
    if sa_toml_parse "$work/invalid.toml" 2>"$work/error.log"; then
        fail "$label unexpectedly parsed"
    fi
    [[ -s "$work/error.log" ]] || fail "$label produced no diagnostic"
    grep -Fq "$work/invalid.toml:" "$work/error.log" || fail "$label diagnostic omitted filename/line"
    assert_has_no_entries
}

expect_failure "unterminated quote" 'value = "unterminated'
expect_failure "invalid value" 'value = 12.5'
expect_failure "unsupported array" 'value = ["one", "two"]'
expect_failure "unsupported dotted key" 'a.b = "value"'
expect_failure "unsupported single-quoted string" "value = 'single'"

printf 'PASS: TOML subset parser assertions passed.\n'
