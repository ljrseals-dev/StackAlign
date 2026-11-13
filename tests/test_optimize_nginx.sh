#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
conf="$ROOT/templates/nginx/conf.d/00-performance.conf"
site="$ROOT/templates/nginx/site-wordpress.conf.tmpl"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
has() { grep -Fq -- "$2" "$1"; }
has "$conf" 'map $http_user_agent $sa_is_ai_crawler' && ok "AI crawler map is defined in http context" || bad "AI crawler map"
has "$conf" 'fastcgi_cache_path' && ok "FastCGI cache zone is declared" || bad "FastCGI cache zone"
has "$site" 'fastcgi_cache_bypass $sa_skip_cache;' && ok "lookup bypass is configured" || bad "lookup bypass"
has "$site" 'fastcgi_no_cache $sa_skip_cache $upstream_http_set_cookie;' && ok "cache write blocked for bypass and Set-Cookie" || bad "cache write bypass"
has "$site" '$http_authorization' && ok "Authorization requests bypass cache" || bad "Authorization bypass"
has "$site" '$sa_has_auth_cookie' && ok "authentication cookies bypass cache" || bad "cookie bypass"
if grep -Eq 'fastcgi_ignore_headers[[:space:]]+(Set-Cookie|Cache-Control|Expires)' "$site"; then bad "upstream cache safety headers are not ignored"; else ok "upstream Set-Cookie and cache-control policy remains active"; fi
if grep -Eq 'http_if_none_match|http_if_modified_since' "$site"; then bad "conditional request headers remain untouched"; else ok "conditional request headers remain untouched"; fi
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
