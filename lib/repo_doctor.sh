#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Read-only repository diagnostics. Network, GPG, journal and backup checks
# remain SKIP until their shared implementations are available.

_sa_repo_doc_escape() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

_sa_repo_doc_check() {
  local id=$1 title=$2 status=$3 detail=$4 hint=${5:-}
  REPO_DOC_IDS+=("$id"); REPO_DOC_TITLES+=("$title")
  REPO_DOC_STATUS+=("$status"); REPO_DOC_DETAILS+=("$detail")
  REPO_DOC_HINTS+=("$hint")
}

sa_repo_doctor() {
  local json=0 strict=0 section=repo arg
  while [ $# -gt 0 ]; do
    arg=$1; shift
    case $arg in
      --json) json=1 ;;
      --strict) strict=1 ;;
      --section) [ $# -gt 0 ] || { echo "doctor: --section needs a value" >&2; return 64; }; section=$1; shift ;;
      *) echo "doctor: unexpected argument: $arg" >&2; return 64 ;;
    esac
  done
  [ "$section" = repo ] || { echo "doctor: only --section repo is supported by this entry point" >&2; return 64; }

  local os_id=unknown os_version=unknown arch backend=none backend_version=unknown os_release_file=${SA_OS_RELEASE_FILE:-/etc/os-release}
  local eol=false vault=false dir=${SA_YUM_REPOS_DIR:-/etc/yum.repos.d}
  local -a files=() repo_ids=()
  local pass=0 warn=0 fail=0 skip=0 status detail title hint
  local id family version
  arch=$(uname -m 2>/dev/null || printf unknown)
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id=${ID:-unknown}; os_version=${VERSION_ID:-unknown}
  fi
  family=$os_id; version=$os_version
  case "$os_id" in
    centos) case "$os_version" in 7|7.*) family=centos-7; eol=true; vault=true ;; *) family=centos-stream ;; esac ;;
    rhel|rocky|almalinux|ol|fedora) [ "$os_id" != ol ] || family=oraclelinux ;;
    *) family=unknown ;;
  esac
  if command -v dnf >/dev/null 2>&1; then
    backend=dnf; backend_version=$(dnf --version 2>/dev/null | sed -n '1{s/[^0-9.].*$//;p;}')
  elif command -v yum >/dev/null 2>&1; then
    backend=yum; backend_version=$(yum --version 2>/dev/null | sed -n '1{s/[^0-9.].*$//;p;}')
  fi
  [ -n "$backend_version" ] || backend_version=unknown

  REPO_DOC_IDS=(); REPO_DOC_TITLES=(); REPO_DOC_STATUS=()
  REPO_DOC_DETAILS=(); REPO_DOC_HINTS=()

  case "$family" in
    rhel|rocky|almalinux|centos-stream|centos-7|oraclelinux|fedora)
      _sa_repo_doc_check REPO-001 "distribution support" PASS "$family $version, arch $arch" ;;
    *) _sa_repo_doc_check REPO-001 "distribution support" FAIL "unsupported distribution: $family $version" "Use a supported EL-family host." ;;
  esac
  if [ "$backend" = dnf ] || [ "$backend" = yum ]; then
    _sa_repo_doc_check REPO-002 "package backend" PASS "$backend $backend_version"
  else
    _sa_repo_doc_check REPO-002 "package backend" FAIL "neither dnf nor yum is executable" "Install the distribution package backend." 
  fi

  if [ -d "$dir" ]; then
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$dir" -maxdepth 1 -type f -name '*.repo' -print0 2>/dev/null | sort -z)
  fi
  local syntax_bad=0 f count=0 section_id enabled_value enabled_total=0
  for f in "${files[@]}"; do
    awk '
      /^[[:space:]]*([#;]|$)/ { next }
      /^[[:space:]]*\[[^][]+\][[:space:]]*$/ { next }
      /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ { next }
      { bad=1 }
      END { exit bad }
    ' "$f" || syntax_bad=1
    while IFS= read -r section_id; do
      [[ $section_id =~ ^[A-Za-z0-9_.:-]+$ ]] && repo_ids+=("$section_id")
    done < <(awk '/^[[:space:]]*\[[^][]+\][[:space:]]*$/ {gsub(/^[[:space:]]*\[|\][[:space:]]*$/,""); print}' "$f")
    count=$(awk '
      /^[[:space:]]*\[[^][]+\][[:space:]]*$/ { if (active && enabled !~ /^(0|no|false)$/) n++; active=1; enabled="1"; next }
      active && /^[[:space:]]*enabled[[:space:]]*=/ { v=$0; sub(/^[^=]*=[[:space:]]*/,"",v); v=tolower(v); if (v ~ /^(0|no|false)$/) enabled="0"; else if (v ~ /^(1|yes|true)$/) enabled="1"; else enabled="invalid" }
      END { if (active && enabled !~ /^(0|no|false)$/) n++; print n+0 }
    ' "$f")
    # Accumulate enabled stanzas per file without trusting DNF effective config.
    enabled_total=$((${enabled_total:-0} + count))
  done
  if [ "$syntax_bad" -eq 0 ]; then
    _sa_repo_doc_check REPO-003 "repo config syntax" PASS "${#files[@]} files inspected"
  else
    _sa_repo_doc_check REPO-003 "repo config syntax" FAIL "one or more .repo files contain malformed lines" "Review repository stanza syntax before package operations."
  fi
  if [ "${enabled_total:-0}" -ge 1 ]; then
    _sa_repo_doc_check REPO-004 "enabled repos" PASS "$enabled_total enabled repo stanza(s)"
  else
    _sa_repo_doc_check REPO-004 "enabled repos" WARN "zero enabled repository stanzas detected" "Enable a trusted repository only after reviewing its signing-key policy."
  fi
  _sa_repo_doc_check REPO-005 "metadata reachability" SKIP "network checks are disabled; no metadata was refreshed" "Run an explicit repository validation command when implemented."
  _sa_repo_doc_check REPO-006 "GPG key verification" SKIP "shared repo-key verification interface is not wired" "Use the existing repository key verification workflow; no key was imported."
  if [ "$eol" = true ]; then
    _sa_repo_doc_check REPO-007 "EOL handling" WARN "CentOS 7 is EOL; Vault configuration is not verified" "Treat Vault as UNVERIFIED and use only a disposable test host."
  else
    _sa_repo_doc_check REPO-007 "EOL handling" PASS "host is not identified as CentOS 7 EOL"
  fi
  _sa_repo_doc_check REPO-008 "journal hygiene" SKIP "repository audit journal is not implemented"
  _sa_repo_doc_check REPO-009 "backup integrity" SKIP "repository backup manifests are not implemented"

  for status in "${REPO_DOC_STATUS[@]}"; do
    case $status in PASS) pass=$((pass+1));; WARN) warn=$((warn+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; esac
  done
  local overall=PASS rc=0
  [ "$warn" -eq 0 ] || overall=WARN
  [ "$fail" -eq 0 ] || overall=FAIL
  if [ "$fail" -gt 0 ] || { [ "$strict" -eq 1 ] && [ "$warn" -gt 0 ]; }; then rc=2; fi

  if [ "$json" -eq 1 ]; then
    printf '{"schema":"stackalign.repo.doctor/v1","generated_at":"%s","host":{"family":"%s","version":"%s","arch":"%s","backend":"%s","eol":%s,"vault_eligible":%s},"summary":{"pass":%d,"warn":%d,"fail":%d,"skip":%d,"overall":"%s"},"checks":[' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(_sa_repo_doc_escape "$family")" "$(_sa_repo_doc_escape "$version")" "$(_sa_repo_doc_escape "$arch")" "$backend" "$eol" "$vault" "$pass" "$warn" "$fail" "$skip" "$overall"
    local i
    for i in "${!REPO_DOC_IDS[@]}"; do
      [ "$i" -eq 0 ] || printf ','
      printf '{"id":"%s","title":"%s","status":"%s","details":{"detail":"%s"}' "${REPO_DOC_IDS[$i]}" "$(_sa_repo_doc_escape "${REPO_DOC_TITLES[$i]}")" "${REPO_DOC_STATUS[$i]}" "$(_sa_repo_doc_escape "${REPO_DOC_DETAILS[$i]}")"
      [ -z "${REPO_DOC_HINTS[$i]}" ] || printf ',"remediation_hint":"%s"' "$(_sa_repo_doc_escape "${REPO_DOC_HINTS[$i]}")"
      printf '}'
    done
    printf ']}\n'
  else
    echo "repo"
    local i
    for i in "${!REPO_DOC_IDS[@]}"; do
      printf '  [%s] %s %s (%s)\n' "${REPO_DOC_STATUS[$i]}" "${REPO_DOC_IDS[$i]}" "${REPO_DOC_TITLES[$i]}" "${REPO_DOC_DETAILS[$i]}"
    done
    printf '  summary: %d PASS, %d WARN, %d FAIL, %d SKIP\n' "$pass" "$warn" "$fail" "$skip"
  fi
  return "$rc"
}
