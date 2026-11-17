#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# Hosting engine contracts and read-only plans. Runtime apply is deliberately
# gated until tenant isolation and real EL9 integration tests are complete.

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
  Public listener: NOT CONFIGURED by this planner
  Tenant isolation: NOT IMPLEMENTED
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    apache)
      cat <<'EOF'
StackAlign hosting plan (read-only)
  Mode: apache
  Edge/application server: Apache HTTP Server (httpd)
  PHP integration: dedicated PHP-FPM pool via mod_proxy_fcgi
  Packages: httpd php-fpm
  Required modules: proxy_module, proxy_fcgi_module, mpm_event_module
  Backend listener: loopback or Unix socket only
  Tenant isolation: NOT IMPLEMENTED; single-tenant evaluation only
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    hybrid)
      cat <<'EOF'
StackAlign hosting plan (read-only)
  Mode: hybrid
  Public edge: Nginx
  Application upstream: Apache HTTP Server (httpd)
  PHP integration: dedicated PHP-FPM pool via mod_proxy_fcgi
  Packages: nginx httpd php-fpm
  Nginx-to-Apache upstream: 127.0.0.1:8081 (private backend)
  Apache listener: loopback only; never public
  Required Apache modules: proxy_module, proxy_fcgi_module, mpm_event_module
  Tenant isolation: NOT IMPLEMENTED; single-tenant evaluation only
  Apply: BLOCKED pending tenant lifecycle and live-host validation
EOF
      ;;
    *) sa_hosting_die "usage: stackalign hosting plan <nginx|apache|hybrid>"; return 64 ;;
  esac
  echo "No packages installed; no files written; no services changed."
}

sa_hosting_doctor() {
  local missing=0 tool
  for tool in nginx httpd php-fpm; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf 'available: %s\n' "$tool"
    else
      printf 'missing: %s\n' "$tool"
    fi
  done
  if command -v httpd >/dev/null 2>&1; then
    if httpd -M 2>&1 | grep -Eq 'proxy_module'; then
      echo "apache module: proxy_module present"
    else
      echo "apache module: proxy_module missing"; missing=1
    fi
    if httpd -M 2>&1 | grep -Eq 'proxy_fcgi_module'; then
      echo "apache module: proxy_fcgi_module present"
    else
      echo "apache module: proxy_fcgi_module missing"; missing=1
    fi
  fi
  return "$missing"
}
