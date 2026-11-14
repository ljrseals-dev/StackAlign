#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/repo.sh -- package repository setup. Written from master prompt v8 Part III.
# Every argument is DATA: validated against a strict allowlist, never eval'd,
# repo file written with printf only. versions.toml is NOT read here (thin
# wrapper in bin/stackalign, not yet written).
#
# ASSUMPTIONS (spec is silent; unmeasured design choices):
#   * sa_repo_install takes optional args 4-6 (repo_url fingerprint key_url) so
#     it can run setup; if the repo file does not exist and they are absent, it
#     refuses rather than guessing.
#   * the GPG key is fetched with curl, its fingerprint compared to the pinned
#     one BEFORE rpm --import; mismatch refuses (rc 4) and imports nothing.
#   * "health check" after install = rpm -q <package>-<version>.
#   * FTP refusal is a case-insensitive substring match (fails closed).
# Env (tests): SA_YUM_REPOS_DIR (default /etc/yum.repos.d).

: "${SA_YUM_REPOS_DIR:=/etc/yum.repos.d}"

# Shared HTTPS fetch and primary-key validation implementation.
# shellcheck source=lib/fetch.sh
source "${SA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/fetch.sh"

_sa_repo_valid() {  # <kind> <value>
  case $1 in
    name)    [[ $2 =~ ^[a-z0-9][a-z0-9_-]*$ ]] ;;
    package) [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] ;;
    version) [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._:~+-]*$ ]] ;;
    url)     [[ $2 =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'*+,\;=%-]+$ ]] ;;
    fpr)     [[ $2 =~ ^[0-9A-Fa-f]{40}$ ]] ;;
    *) return 1 ;;
  esac
}

_sa_repo_ftp() {  # <package> -> 0 if it is an FTP daemon
  local p=${1,,}
  case $p in *vsftpd*|*pure-ftpd*|*proftpd*) return 0 ;; esac
  return 1
}

_sa_repo_bad() { echo "repo: invalid $1: $2" >&2; return 64; }

sa_repo_setup() {  # <name> <repo_url> <gpg_fingerprint> <gpg_key_url>
  [ $# -eq 4 ] || { echo "usage: sa_repo_setup <name> <repo_url> <fingerprint> <key_url>" >&2; return 64; }
  local name=$1 url=$2 fpr=${3// /} keyurl=$4
  _sa_repo_valid name "$name"  || { _sa_repo_bad name "$name"; return 64; }
  _sa_repo_valid url "$url"    || { _sa_repo_bad repo_url "$url"; return 64; }
  _sa_repo_valid fpr "$fpr"    || { _sa_repo_bad fingerprint "$3"; return 64; }
  _sa_repo_valid url "$keyurl" || { _sa_repo_bad key_url "$keyurl"; return 64; }
  fpr=${fpr^^}

  local tmpd key
  tmpd=$(mktemp -d) || return 1
  key="$tmpd/key.asc"
  if ! sa_fetch_gpg_key "$keyurl" "$fpr" "$key"; then
    rm -rf -- "$tmpd"
    echo "repo: key fetch or primary fingerprint validation failed; nothing imported" >&2
    return 4
  fi

  local file="$SA_YUM_REPOS_DIR/stackalign-$name.repo" content
  content=$(printf '[stackalign-%s]\nname=StackAlign %s\nbaseurl=%s\nenabled=1\ngpgcheck=1\ngpgkey=%s\n' \
            "$name" "$name" "$url" "$keyurl"; printf x); content=${content%x}
  mkdir -p -- "$SA_YUM_REPOS_DIR"
  # Avoid process-substitution in cmp: under some environments /dev/fd compares
  # fail even when bytes are identical, which breaks setup idempotency.
  local cmpfile wrote=0
  cmpfile=$(mktemp "$SA_YUM_REPOS_DIR/.sa-repo-cmp.XXXXXX") || { rm -rf -- "$tmpd"; return 1; }
  printf '%s' "$content" > "$cmpfile" || { rm -rf "$tmpd" "$cmpfile"; return 1; }
  if [ -f "$file" ] && cmp -s -- "$file" "$cmpfile"; then
    rm -f -- "$cmpfile"
    echo "repo $name: unchanged"
  else
    chmod 0644 -- "$cmpfile" || { rm -rf "$tmpd" "$cmpfile"; return 1; }
    mv -f -- "$cmpfile" "$file" || { rm -rf "$tmpd" "$cmpfile"; return 1; }
    echo "repo $name: written"
    wrote=1
  fi

  # A new or changed repo definition needs its validated signing key imported.
  # An unchanged definition does not repeat the rpmdb operation.
  if [ "$wrote" -eq 1 ]; then
    rpm --import "$key" || {
      rm -rf -- "$tmpd"
      echo "repo: rpm --import failed" >&2
      return 1
    }
  fi
  rm -rf -- "$tmpd"
}

# sa_repo_inventory
# Read-only view of configured .repo stanzas. Potentially credential-bearing
# URL/key values are never printed; only presence flags are emitted. Boolean
# values are per-repository settings, not DNF's effective merged configuration.
sa_repo_inventory() {
  [ $# -eq 0 ] || { echo "usage: sa_repo_inventory" >&2; return 64; }
  local dir=${SA_YUM_REPOS_DIR:-/etc/yum.repos.d}
  local -a files
  files=("$dir"/*.repo)
  printf 'repo_id\tenabled\tgpgcheck\trepo_gpgcheck\tsslverify\tbaseurl\tmirrorlist\tmetalink\tgpgkey\n'
  [ -d "$dir" ] || return 0
  [ -f "${files[0]}" ] || return 0
  awk '
    function norm(v) {
      v = tolower(v)
      if (v ~ /^(1|yes|true)$/) return "1"
      if (v ~ /^(0|no|false)$/) return "0"
      if (v == "") return "unset"
      return "invalid"
    }
    function emit() {
      if (section ~ /^[A-Za-z0-9_.:-]+$/) {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", section,
          norm(enabled), norm(gpgcheck), norm(repo_gpgcheck), norm(sslverify),
          baseurl, mirrorlist, metalink, gpgkey
      }
    }
    FNR == 1 {
      if (NR > 1) emit()
      section = ""
      enabled = gpgcheck = repo_gpgcheck = sslverify = ""
      baseurl = mirrorlist = metalink = gpgkey = "no"
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^[#;]/) next
      if (line ~ /^\[[^][]+\]$/) {
        emit()
        section = substr(line, 2, length(line) - 2)
        enabled = gpgcheck = repo_gpgcheck = sslverify = ""
        baseurl = mirrorlist = metalink = gpgkey = "no"
        next
      }
      if (section == "" || line !~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) next
      key = line
      sub(/[[:space:]]*=.*/, "", key)
      value = line
      sub(/^[^=]*=[[:space:]]*/, "", value)
      key = tolower(key)
      if (key == "enabled") enabled = value
      else if (key == "gpgcheck") gpgcheck = value
      else if (key == "repo_gpgcheck") repo_gpgcheck = value
      else if (key == "sslverify") sslverify = value
      else if (key == "baseurl" && value != "") baseurl = "yes"
      else if (key == "mirrorlist" && value != "") mirrorlist = "yes"
      else if (key == "metalink" && value != "") metalink = "yes"
      else if (key == "gpgkey" && value != "") gpgkey = "yes"
    }
    END { emit() }
  ' "${files[@]}"
}

sa_repo_versionlock() {  # <name> <package> <version>
  [ $# -eq 3 ] || { echo "usage: sa_repo_versionlock <name> <package> <version>" >&2; return 64; }
  _sa_repo_valid name "$1"    || { _sa_repo_bad name "$1"; return 64; }
  _sa_repo_valid package "$2" || { _sa_repo_bad package "$2"; return 64; }
  _sa_repo_valid version "$3" || { _sa_repo_bad version "$3"; return 64; }
  if _sa_repo_ftp "$2"; then echo "error=ftp_daemon_refused" >&2; return 3; fi
  dnf versionlock add -- "$2-$3"
}

sa_repo_install() {  # <name> <package> <version> [repo_url fingerprint key_url]
  [ $# -eq 3 ] || [ $# -eq 6 ] || { echo "usage: sa_repo_install <name> <package> <version> [url fpr keyurl]" >&2; return 64; }
  local name=$1 pkg=$2 ver=$3
  _sa_repo_valid name "$name"  || { _sa_repo_bad name "$name"; return 64; }
  _sa_repo_valid package "$pkg" || { _sa_repo_bad package "$pkg"; return 64; }
  _sa_repo_valid version "$ver" || { _sa_repo_bad version "$ver"; return 64; }
  if _sa_repo_ftp "$pkg"; then echo "error=ftp_daemon_refused" >&2; return 3; fi
  if [ $# -eq 6 ]; then
    sa_repo_setup "$name" "$4" "$5" "$6" || return $?
  elif [ ! -f "$SA_YUM_REPOS_DIR/stackalign-$name.repo" ]; then
    echo "repo: $name not set up and no repo args given; refusing" >&2; return 1
  fi
  if rpm -q "$pkg-$ver" >/dev/null 2>&1; then
    echo "$pkg-$ver: already installed"
  else
    dnf install -y -- "$pkg-$ver" || return 1
  fi
  sa_repo_versionlock "$name" "$pkg" "$ver" || return $?
  rpm -q "$pkg-$ver" >/dev/null 2>&1 || { echo "repo: health check failed: $pkg-$ver not installed" >&2; return 1; }
}
