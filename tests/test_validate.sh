#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/validate.sh"
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/root" "$T/outside"
mkdir -m 700 "$T/root/sub"
ln -s "$T/outside" "$T/root/link"

sa_validate_package_name nginx
sa_validate_db_name app_db
sa_validate_site_name tenant-01
sa_validate_domain example.com
sa_validate_service_name nginx
sa_validate_port 443
sa_validate_path_under_root "$T/root" "$T/root/sub/file"

for bad in 'pkg;id' '$(id)' '`id`' '-leading' $'line\nbreak' ''; do
    if sa_validate_package_name "$bad" >/dev/null 2>&1; then
        echo "unsafe package name accepted" >&2; exit 1
    fi
done
for bad in 'db;DROP' '1leading' '-option' $'newline\nname'; do
    if sa_validate_db_name "$bad" >/dev/null 2>&1; then
        echo "unsafe database name accepted" >&2; exit 1
    fi
done
for bad in 'example.com;id' '-example.com' 'example..com' 'example.com.' 'localhost' $'example.com\n'; do
    if sa_validate_domain "$bad" >/dev/null 2>&1; then
        echo "unsafe domain accepted" >&2; exit 1
    fi
done
for bad in 0 65536 999999 -1 abc ''; do
    if sa_validate_port "$bad" >/dev/null 2>&1; then
        echo "invalid port accepted" >&2; exit 1
    fi
done
if sa_validate_path_under_root "$T/root" "$T/outside/file" >/dev/null 2>&1; then
    echo "path escape accepted" >&2; exit 1
fi
if sa_validate_path_under_root "$T/root" "$T/root/link/file" >/dev/null 2>&1; then
    echo "symlink escape accepted" >&2; exit 1
fi
if sa_validate_path_under_root "$T/root" "$T/root/../outside/file" >/dev/null 2>&1; then
    echo "traversal accepted" >&2; exit 1
fi

echo "shared input validators: PASS"
