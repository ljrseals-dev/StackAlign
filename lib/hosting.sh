#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
. "$(dirname "${BASH_SOURCE[0]}")/exec.sh"

# Hosting mode planning, operator scope selection, and read-only inspection.
# Runtime apply remains gated until isolation and EL9 acceptance tests pass.

sa_hosting_die() { echo "stackalign hosting: $*" >&2; return 1; }

sa_hosting_plan() {
  local mode=${1:-}
  case "$mode" in
    nginx)
      cat <<'EOF'
StackAlign hosting plan (read-only)
  Mode: nginx
  Edge: Nginx
  Application server: PHP-FPM
  Packages: nginx php-fpm
  Tenant isolation: NOT IMPLEMENTED
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    apache)
      cat <<'EOF'
StackAlign hosting plan (read-only)
  Mode: apache
  Edge/application server: Apache HTTP Server (httpd)
  PHP integration: PHP-FPM; a shared pool is not tenant isolation
  Packages: httpd php-fpm
  Required modules: proxy_module, proxy_fcgi_module, mpm_event_module
  Backend listener: loopback or Unix socket only
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    hybrid)
      cat <<'EOF'
StackAlign hosting plan (read-only)
  Mode: hybrid
  Public edge: Nginx
  Application upstream: Apache HTTP Server (httpd)
  PHP integration: PHP-FPM; a shared pool is not tenant isolation
  Packages: nginx httpd php-fpm
  Nginx-to-Apache upstream: 127.0.0.1:8081 (private backend)
  Apache listener: loopback only; never public
  Required Apache modules: proxy_module, proxy_fcgi_module, mpm_event_module
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    *) sa_hosting_die "usage: stackalign hosting plan <nginx|apache|hybrid>"; return 64 ;;
  esac
  echo "No packages installed; no files written; no services changed."
}

# Interactive operator-intent check. This deliberately records the decision in
# command output only: no config schema or durable scope storage is implemented.
sa_hosting_setup() {
  local answer=""
  [[ -t 0 && -r /dev/tty ]] || { echo "hosting setup requires an interactive terminal; no changes made" >&2; return 2; }
  printf '%s\n' "Who will use this server?" \
    "  1) One administrator managing multiple accounts" \
    "  2) Multiple independent end users (shared hosting)" >&2
  printf 'Select 1 or 2: ' >&2
  IFS= read -r answer </dev/tty || { echo "hosting setup: input unavailable; no changes made" >&2; return 2; }
  case "$answer" in
    1)
      cat <<'EOF'
Hosting scope: SINGLE_ADMIN_MULTI_ACCOUNT
Suitable direction: one administrator manages multiple accounts.
Boundary: this selection does NOT provide independent-user isolation.
PHP-FPM: the shared www pool remains shared; do not claim per-account isolation.
No configuration was saved and no host changes were made.
EOF
      ;;
    2)
      cat <<'EOF'
Hosting scope: INDEPENDENT_END_USERS
Shared-hosting isolation is required.
Status: BLOCKED — per-user Unix identity, dedicated PHP-FPM pool/socket,
filesystem/process/resource/service isolation, and adversarial tests are
not yet implemented and verified.
No configuration was saved and no host changes were made.
EOF
      return 2
      ;;
    *) echo "hosting setup: select 1 or 2; no changes made" >&2; return 64 ;;
  esac
}

sa_hosting_doctor() {
  local mode=${1:-hybrid} missing=0 tool modules=""
  case "$mode" in nginx) set -- nginx php-fpm ;;
    apache) set -- httpd php-fpm ;;
    hybrid) set -- nginx httpd php-fpm ;;
    *) echo "usage: stackalign hosting doctor <nginx|apache|hybrid>" >&2; return 64 ;;
  esac
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf 'available: %s\n' "$tool"
    else
      printf 'missing: %s\n' "$tool"
      missing=1
    fi
  done
  case "$mode" in
    apache|hybrid)
      if command -v httpd >/dev/null 2>&1; then
        if ! modules=$(sa_exec_capture httpd -- -M 2>&1); then
          echo "apache module inspection: FAILED" >&2
          missing=1
        else
          for tool in proxy_module proxy_fcgi_module mpm_event_module; do
            if printf '%s\n' "$modules" | grep -Eq "(^|[[:space:]])${tool}[[:space:]]"; then
              printf 'apache module: %s present\n' "$tool"
            else
              printf 'apache module: %s missing\n' "$tool"
              missing=1
            fi
          done
        fi
      fi
      ;;
  esac
  return "$missing"
}
