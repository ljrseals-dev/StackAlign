#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_tls_clients.sh -- read-only ACME client discovery and strict selection tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap '/usr/bin/rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

for client in certbot acme.sh lego; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$client"
  chmod 700 "$TMP/bin/$client"
done
cat > "$TMP/bin/rpm" <<'RPM'
#!/bin/sh
[ "$1" = "-qf" ] && [ "$2" = "--" ] || exit 1
case "$3" in
  */certbot) printf '%s\n' 'certbot-1.0-1.el9' ;;
  *) exit 1 ;;
esac
RPM
chmod 700 "$TMP/bin/rpm"

# Restrict PATH so host-installed clients cannot make this fixture nondeterministic.
source "$ROOT/lib/tls.sh"
PATH="$TMP/bin"
export PATH

out=$(sa_tls_clients)
case "$out" in *'client: certbot'*'state: AVAILABLE'*'rpm-managed package=certbot-1.0-1.el9'*) ;; *) echo "FAIL: RPM-managed Certbot not reported"; exit 1 ;; esac
case "$out" in *'client: acme.sh'*'state: AVAILABLE'*'manual-or-unknown (DNF provenance NOT VERIFIED)'*) ;; *) echo "FAIL: manual acme.sh provenance not reported"; exit 1 ;; esac
case "$out" in *'client: lego'*'state: AVAILABLE'*) ;; *) echo "FAIL: Lego not reported"; exit 1 ;; esac

[ "$(sa_tls_require_client certbot)" = "$TMP/bin/certbot" ]
[ "$(sa_tls_require_client acme.sh)" = "$TMP/bin/acme.sh" ]
[ "$(sa_tls_require_client lego)" = "$TMP/bin/lego" ]

/usr/bin/rm "$TMP/bin/acme.sh"
set +e
missing=$(sa_tls_require_client acme.sh 2>&1)
rc=$?
set -e
[ "$rc" -eq 69 ]
case "$missing" in *'error=acme_client_not_available:client=acme.sh'*) ;; *) echo "FAIL: missing selected client did not fail explicitly"; exit 1 ;; esac

set +e
invalid=$(sa_tls_require_client unknown 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
case "$invalid" in *'error=acme_client_not_available:client=invalid'*) ;; *) echo "FAIL: invalid client was not rejected"; exit 1 ;; esac

set +e
invalid=$(sa_tls_require_client certbot extra 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
case "$invalid" in *'error=acme_client_not_available:client=invalid'*) ;; *) echo "FAIL: extra client-selection arguments were not rejected"; exit 1 ;; esac

echo "TLS client discovery tests: PASS"
