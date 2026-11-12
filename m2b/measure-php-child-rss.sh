#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# m2b/measure-php-child-rss.sh
#
# Measures per-worker PSS during active requests. Run as root on the
# dedicated 512 MiB RAM / 512 MiB swap measurement VM.

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

if ! systemctl is-active --quiet php-fpm; then
    echo "Error: php-fpm is not running." >&2
    exit 1
fi

command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
command -v pgrep >/dev/null || { echo "pgrep is required." >&2; exit 1; }

TEST_DIR="/var/www/html"
TEST_FILE="$TEST_DIR/test.php"
mkdir -p "$TEST_DIR"

if id nginx >/dev/null 2>&1; then
    WEB_USER="nginx"
elif id apache >/dev/null 2>&1; then
    WEB_USER="apache"
else
    echo "Could not identify nginx or apache web-server account." >&2
    exit 1
fi

measure_case() {
    local label="$1"
    local php_body="$2"
    local sample
    local max_mean_kb=0
    local max_workers=0
    local pids=()

    cat > "$TEST_FILE" <<EOF
<?php
$php_body
?>
EOF
    chown "$WEB_USER:$WEB_USER" "$TEST_FILE"

    echo
    echo "=== $label: launching 20 concurrent requests ==="
    for _ in {1..20}; do
        curl -fsS --max-time 120 http://127.0.0.1/test.php >/dev/null &
        pids+=("$!")
    done

    # Sample while requests are still executing. The PHP payloads deliberately
    # hold their working set for six seconds so this is a peak-load snapshot,
    # rather than an idle-after-completion measurement.
    for _ in {1..10}; do
        local total_pss_kb=0
        local count=0
        for pid in $(pgrep -f 'php-fpm: pool' || true); do
            [[ -r "/proc/$pid/smaps_rollup" ]] || continue
            sample=$(awk '/^Pss:/ {print $2}' "/proc/$pid/smaps_rollup")
            [[ "$sample" =~ ^[0-9]+$ ]] || continue
            echo "  PID $pid: $sample kB PSS"
            total_pss_kb=$((total_pss_kb + sample))
            count=$((count + 1))
        done

        if (( count > 0 )); then
            local mean_kb=$((total_pss_kb / count))
            if (( mean_kb > max_mean_kb )); then
                max_mean_kb="$mean_kb"
                max_workers="$count"
            fi
        fi
        sleep 0.5
    done

    # Reap every curl and fail if any request failed.
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    if (( max_workers == 0 )); then
        echo "No php-fpm pool workers were observed." >&2
        exit 1
    fi

    local mean_pss_mib=$(((max_mean_kb + 1023) / 1024))
    echo "Peak sample: $max_workers workers; mean PSS ${max_mean_kb} kB"
    echo "mean_pss_mib=$mean_pss_mib"
}

measure_case "BASELINE" 'echo "baseline"; sleep(6);'
measure_case "HEAVY" '
$data = [];
for ($i = 0; $i < 50000; $i++) {
    $data[] = str_repeat("x", 100);
}
echo "heavy";
sleep(6);
'

echo
echo "Measurement complete. Record both mean_pss_mib values and VM details."
