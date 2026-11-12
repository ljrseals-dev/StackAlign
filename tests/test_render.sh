#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/render.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

# shellcheck disable=SC2034 # Passed by name to sa_render_apply/sa_render_plan.
declare -A M=( [A]="alpha" [B]='{{A}}' )
printf 'x={{A}} y={{B}}\nend\n' > "$T/t.tpl"

# substitution + single pass (B's value "{{A}}" must NOT be re-expanded)
sa_render_apply "$T/t.tpl" "$T/o.conf" M >/dev/null
[ "$(cat "$T/o.conf")" = $'x=alpha y={{A}}\nend' ] && ok "substitution, no re-expansion" || bad "substitution, no re-expansion"
# trailing newline preserved
[ "$(tail -c1 "$T/o.conf" | od -An -tx1 | tr -d ' ')" = "0a" ] && ok "trailing newline preserved" || bad "trailing newline preserved"

# unbound refusal
printf '{{NOPE}}\n' > "$T/u.tpl"
sa_render_apply "$T/u.tpl" "$T/u.out" M 2>/dev/null; rc=$?
{ [ $rc -ne 0 ] && [ ! -e "$T/u.out" ]; } && ok "unbound refused, nothing written" || bad "unbound refused, nothing written"
SA_RENDER_ALLOW_UNBOUND=1 sa_render_apply "$T/u.tpl" "$T/u.out" M >/dev/null
[ "$(cat "$T/u.out")" = "" ] && ok "ALLOW_UNBOUND substitutes empty" || bad "ALLOW_UNBOUND substitutes empty"

# idempotency: second run is a no-op (mtime unchanged)
m1=$(stat -c %Y.%y "$T/o.conf"); sleep 1.1
out=$(sa_render_apply "$T/t.tpl" "$T/o.conf" M); m2=$(stat -c %Y.%y "$T/o.conf")
{ [ "$m1" = "$m2" ] && [ "$out" = "unchanged: $T/o.conf" ]; } && ok "idempotent no-op" || bad "idempotent no-op"

# plan writes nothing
printf 'new={{A}}\n' > "$T/p.tpl"
before=$(ls -A "$T" | sort | tr '\n' ' ')
sa_render_plan "$T/p.tpl" "$T/p.out" M >/dev/null
after=$(ls -A "$T" | sort | tr '\n' ' ')
{ [ "$before" = "$after" ] && [ ! -e "$T/p.out" ]; } && ok "plan writes nothing" || bad "plan writes nothing"

# mode preserved via chmod --reference
printf 'old\n' > "$T/m.out"; chmod 0640 "$T/m.out"
sa_render_apply "$T/p.tpl" "$T/m.out" M >/dev/null
[ "$(stat -c %a "$T/m.out")" = 640 ] && ok "mode preserved" || bad "mode preserved"

# snapshot hook is called when defined
CALLED=""; sa_history_snapshot() { CALLED="$1"; echo id; }
printf 'again\n' > "$T/h.tpl"; printf 'old\n' > "$T/h.out"
sa_render_apply "$T/h.tpl" "$T/h.out" M >/dev/null
[ "$CALLED" = "$T/h.out" ] && ok "snapshot hook called before write" || bad "snapshot hook called before write"

# no sed -i anywhere in lib/render.sh
grep -vE '^[[:space:]]*#' "$ROOT/lib/render.sh" | grep -E 'sed[[:space:]]+(-[a-zA-Z]*i|--in-place)' >/dev/null \
  && bad "no sed -i" || ok "no sed -i"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
