#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/verify.sh -- verify a downloaded StackAlign release artifact. Offline, fail closed.
#
# Chain of trust: pinned fingerprint + LOCAL keyring --> detached signature over
# SHA256SUMS --> expiry line inside the signed file --> sha256 of the artifact.
# The keyring and fingerprint must come from somewhere other than the download
# (installed with the tool, or typed in by the operator). Never from the bundle.
#
# Return codes: 0 ok | 4 signature/key/fingerprint failure | 5 checksum failure
#               6 metadata expired or missing | 7 downgrade refused | 64 usage
#
# ASSUMPTION to verify on real hosts: `gpgv --keyring <binary export>` accepts a
# keyring made with `gpg --export`, and its --status-fd VALIDSIG line has the
# primary-key fingerprint in field 12 (GnuPG 2.4.x).

# _sa_verify_sig <sums> <sig> <keyring> <fingerprint>
_sa_verify_sig() {
    local sums=$1 sig=$2 ring=$3 fpr=${4^^} out home prim n
    [[ $fpr =~ ^[0-9A-F]{40}$ ]] || { echo "verify: pinned fingerprint must be 40 hex digits" >&2; return 64; }
    home="$(mktemp -d)" || return 4
    out="$(gpgv --homedir "$home" --status-fd 1 --keyring "$ring" -- "$sig" "$sums" 2>/dev/null)" || { rm -rf "$home"; return 4; }
    rm -rf "$home"
    grep -q '^\[GNUPG:\] GOODSIG ' <<<"$out" || return 4
    if grep -Eq '^\[GNUPG:\] (EXPKEYSIG|REVKEYSIG|EXPSIG|BADSIG|ERRSIG|NO_PUBKEY)' <<<"$out"; then return 4; fi
    n="$(grep -c '^\[GNUPG:\] VALIDSIG ' <<<"$out")"
    [ "$n" -eq 1 ] || return 4
    prim="$(awk '$1=="[GNUPG:]" && $2=="VALIDSIG" {print toupper($12)}' <<<"$out")"
    [ "$prim" = "$fpr" ] || return 4
}

# The signed SHA256SUMS must carry `# expires: YYYY-MM-DDTHH:MM:SSZ` (UTC) in the future.
_sa_verify_expiry() {
    local exp now
    exp="$(awk '/^# expires: /{print $3; exit}' "$1")"
    [[ $exp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 6
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [[ $now < $exp ]] || return 6
}

# Exactly one entry for the artifact name, and its hash must match.
_sa_verify_hash() {
    local sums=$1 name=$2 file=$3 n want got
    n="$(awk -v f="$name" '$2==f {c++} END{print c+0}' "$sums")"
    [ "$n" -eq 1 ] || return 5
    want="$(awk -v f="$name" '$2==f {print $1}' "$sums")"
    [[ $want =~ ^[0-9a-f]{64}$ ]] || return 5
    got="$(sha256sum -- "$file" | awk '{print $1}')"
    [ "$want" = "$got" ] || return 5
}

# sa_verify_artifact <artifact> <SHA256SUMS> <SHA256SUMS.sig> <keyring> <fingerprint>
sa_verify_artifact() {
    [ $# -eq 5 ] || { echo "usage: sa_verify_artifact artifact sums sig keyring fingerprint" >&2; return 64; }
    local art=$1 sums=$2 sig=$3 ring=$4 fpr=$5 name rc=0
    local f
    for f in "$art" "$sums" "$sig" "$ring"; do
        [ -f "$f" ] || { echo "verify: missing file: $f" >&2; return 64; }
    done
    name="${art##*/}"
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || { echo "verify: unsafe artifact name" >&2; return 64; }

    _sa_verify_sig "$sums" "$sig" "$ring" "$fpr" || { rc=$?; [ $rc -eq 64 ] || echo "verify: signature/key check failed" >&2; return $rc; }
    _sa_verify_expiry "$sums" || { echo "verify: release metadata expired or has no expiry" >&2; return 6; }
    _sa_verify_hash "$sums" "$name" "$art" || { echo "verify: checksum mismatch or entry missing/duplicated for $name" >&2; return 5; }
    printf '%s\n' "$art"
}

# sa_verify_not_downgrade <current> <candidate>
# Rollback is deliberately NOT enabled by an environment variable. An operator-
# authorized rollback policy must be implemented separately and must consume
# authenticated release metadata; this helper only enforces monotonic versions.
sa_verify_not_downgrade() {
    local cur=${1:-} cand=${2:-} newest
    [[ $cur =~ ^[0-9]+(\.[0-9]+){0,3}$ && $cand =~ ^[0-9]+(\.[0-9]+){0,3}$ ]] || { echo "verify: bad version string" >&2; return 64; }
    newest="$(printf '%s\n%s\n' "$cur" "$cand" | sort -V | tail -n 1)"
    if [ "$newest" = "$cand" ]; then return 0; fi
    echo "verify: refusing downgrade $cur -> $cand" >&2
    return 7
}
