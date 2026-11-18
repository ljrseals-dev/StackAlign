#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/tls.sh -- read-only certificate lineage status and renewal-scheduler preflight.
# Issuance is disabled until protected EAB handling, atomic pair activation, and
# crash-safe deployment/rollback are implemented and tested.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_CERT_ROOT:=/etc/stackalign/certs}"

# Return the selected executable path without invoking the client.
_sa_tls_client_path() {
    case "${1-}" in
        certbot) type -P certbot 2>/dev/null ;;
        acme.sh) type -P acme.sh 2>/dev/null ;;
        lego) type -P lego 2>/dev/null ;;
        *) return 64 ;;
    esac
}

# Report package ownership only; rpm ownership is not proof of GPG provenance.
_sa_tls_client_provenance() {
    local path=$1 package=""
    if command -v rpm >/dev/null 2>&1; then
        package=$(rpm -qf -- "$path" 2>/dev/null) || package=""
    fi
    if [ -n "$package" ]; then
        printf 'rpm-managed package=%s (signature provenance not independently verified)' "$package"
    else
        printf 'manual-or-unknown (DNF provenance NOT VERIFIED)'
    fi
}

# Read-only inventory. Never runs an ACME client, installs packages, or changes repos.
sa_tls_clients() {
    local client path provenance
    printf '%s\n' 'TLS ACME client inventory (read-only; no installation attempted)'
    for client in certbot acme.sh lego; do
        path=$(_sa_tls_client_path "$client") || path=""
        if [ -n "$path" ]; then
            provenance=$(_sa_tls_client_provenance "$path")
            printf 'client: %s\n  state: AVAILABLE\n  executable: %s\n  provenance: %s\n' \
                "$client" "$path" "$provenance"
        else
            printf 'client: %s\n  state: NOT_INSTALLED\n  provenance: UNKNOWN\n' "$client"
        fi
    done
}

# A future adapter must call this with the lineage's explicit owner. No fallback.
sa_tls_require_client() {
    local client=${1-} path
    [ "$#" -eq 1 ] || {
        echo "error=acme_client_not_available:client=invalid" >&2
        return 64
    }
    case "$client" in certbot|acme.sh|lego) ;; *)
        echo "error=acme_client_not_available:client=invalid" >&2
        return 64 ;;
    esac
    path=$(_sa_tls_client_path "$client") || path=""
    [ -n "$path" ] || {
        echo "error=acme_client_not_available:client=$client" >&2
        return 69
    }
    printf '%s\n' "$path"
}


_sa_tls_domain_ok() { [[ ${1-} =~ ^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
_sa_tls_lineage() { local d=$1; printf '%s' "${d/#\*./_wildcard_.}"; }
_sa_tls_ca_url() {
    case "$1" in
        letsencrypt) echo "https://acme-v02.api.letsencrypt.org/directory" ;;
        zerossl) echo "https://acme.zerossl.com/v2/DV90" ;;
        *) return 1 ;;
    esac
}

# Render a Certbot HTTP-01 webroot command without executing it.
# Issuance remains disabled pending source verification and deployment acceptance.
sa_tls_certbot_http01_plan() {
    local domain=${1-} webroot=${2-} email=${3-} resolved certbot config work logs root_mode cert_root
    local arg quoted email_re='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    [ "$#" -eq 3 ] || {
        echo "error=tls_certbot_http01_invalid_arguments" >&2
        return 64
    }
    _sa_tls_domain_ok "$domain" || {
        echo "error=tls_http01_domain_invalid" >&2
        return 64
    }
    case "$domain" in
        \*.*) echo "error=tls_http01_wildcard_requires_dns01" >&2; return 64 ;;
    esac
    [[ $email =~ $email_re ]] || {
        echo "error=tls_contact_email_invalid" >&2
        return 64
    }
    case "$webroot" in
        /*) ;;
        *) echo "error=tls_http01_webroot_invalid" >&2; return 64 ;;
    esac
    case "$webroot" in
        *"/../"*|*"/./"*|*/..|*/.) echo "error=tls_http01_webroot_invalid" >&2; return 64 ;;
    esac
    [ -d "$webroot" ] && [ ! -L "$webroot" ] || {
        echo "error=tls_http01_webroot_unavailable" >&2
        return 1
    }
    resolved=$(realpath -e -- "$webroot" 2>/dev/null) || {
        echo "error=tls_http01_webroot_unavailable" >&2
        return 1
    }
    [[ $resolved == "$webroot" && $resolved != / ]] || {
        echo "error=tls_http01_webroot_not_canonical" >&2
        return 1
    }
    cert_root=${SA_CERT_ROOT:-/etc/stackalign/certs}
    case "$cert_root" in
        /*) ;;
        *) echo "error=tls_certificate_root_invalid" >&2; return 64 ;;
    esac
    case "$cert_root" in
        *"/../"*|*"/./"*|*/..|*/.) echo "error=tls_certificate_root_invalid" >&2; return 64 ;;
    esac
    [ -d "$cert_root" ] && [ ! -L "$cert_root" ] || {
        echo "error=tls_certificate_root_unavailable" >&2
        return 1
    }
    resolved=$(realpath -e -- "$cert_root" 2>/dev/null) || return 1
    [[ $resolved == "$cert_root" && $resolved != / ]] || {
        echo "error=tls_certificate_root_not_canonical" >&2
        return 1
    }
    root_mode=$(stat -c '%a' -- "$cert_root" 2>/dev/null || echo invalid)
    [ "$root_mode" = 700 ] || {
        echo "error=tls_certificate_root_permissions_unsafe" >&2
        return 1
    }
    certbot=$(sa_tls_require_client certbot) || return $?
    config="$cert_root/.certbot/config"
    work="$cert_root/.certbot/work"
    logs="$cert_root/.certbot/logs"

    printf 'state: PLAN_ONLY\n'
    printf 'client: certbot\n'
    printf 'client_executable: %s\n' "$certbot"
    printf 'source_provenance: NOT_VERIFIED\n'
    printf 'challenge: http-01 (webroot)\n'
    printf 'domain: %s\n' "$domain"
    printf 'webroot: %s\n' "$resolved"
    printf 'execution: NOT_RUN\n'
    printf 'argv:'
    for arg in "$certbot" certonly --non-interactive --agree-tos --email "$email" \
        --webroot --webroot-path "$resolved" --preferred-challenges http \
        --server https://acme-v02.api.letsencrypt.org/directory -d "$domain" \
        --config-dir "$config" --work-dir "$work" --logs-dir "$logs"; do
        printf -v quoted '%q' "$arg"
        printf ' %s' "$quoted"
    done
    printf '\n'
}

# Reports known ACME renewal schedulers; returns 2 if one is active.
sa_tls_preflight() {
    local found=0 t
    for t in certbot.timer certbot-renew.timer snap.certbot.renew.timer acme.sh.timer lego-renew.timer stackalign-renew.timer; do
        if systemctl is-active --quiet "$t" 2>/dev/null; then echo "scheduler: $t active"; found=1; fi
    done
    if { crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; } | grep -Eq 'acme\.sh|(^|[[:space:]/])(lego|certbot)([[:space:]]|$)'; then
        echo "scheduler: ACME client cron entry present"; found=1
    fi
    [ "$found" -eq 0 ] || return 2
}

# Renewal automation is disabled until lineage ownership and scheduler isolation exist.
sa_tls_enable_renewal_timer() {
    echo "tls: renewal timer enablement BLOCKED — scheduler ownership and renewal execution are not implemented" >&2
    return 2
}


# _sa_tls_status_one <lineage-dir> <domain>
_sa_tls_status_one() {
    local dir=$1 domain=$2 client=unknown crt="$1/fullchain.pem" key="$1/privkey.pem"
    local expiry=unknown cert_state=MISSING host_state=UNKNOWN key_state=MISSING renewal=UNKNOWN
    local probe=$domain work key_mode client_mode rc=0
    [ ! -L "$dir" ] || { printf 'lineage: %s\n  state: UNSAFE_SYMLINK\n' "$domain"; return 1; }

    if [ -f "$dir/.client" ] && [ ! -L "$dir/.client" ]; then
        client=$(cat -- "$dir/.client" 2>/dev/null) || client=unknown
        client_mode=$(stat -c '%a' -- "$dir/.client" 2>/dev/null || echo invalid)
        case "$client" in lego|certbot|acme.sh) ;; *) client=UNKNOWN; rc=1 ;; esac
        case "$client_mode" in 400|600) ;; *) rc=1 ;; esac
    else
        rc=1
    fi

    if [ -L "$crt" ] || [ -L "$key" ]; then
        printf 'lineage: %s\n  client: %s\n  state: UNSAFE_SYMLINK\n' "$domain" "$client"
        return 1
    fi
    if [ ! -s "$crt" ] || [ ! -s "$key" ]; then
        printf 'lineage: %s\n  client: %s\n  certificate: MISSING\n  private_key: MISSING\n' "$domain" "$client"
        return 1
    fi
    command -v openssl >/dev/null 2>&1 || { echo "tls: openssl is not installed" >&2; return 69; }

    expiry=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null) || {
        printf 'lineage: %s\n  client: %s\n  certificate: INVALID\n  private_key: NOT_CHECKED\n' "$domain" "$client"
        return 1
    }
    if openssl x509 -in "$crt" -noout -checkend 0 >/dev/null 2>&1; then
        cert_state=NOT_EXPIRED
    else
        cert_state=EXPIRED
        rc=1
    fi
    if [[ $domain == \*.* ]]; then probe="stackalign-probe.${domain#*.}"; fi
    if openssl x509 -in "$crt" -noout -checkhost "$probe" >/dev/null 2>&1; then
        host_state=MATCH
    else
        host_state=MISMATCH
        rc=1
    fi
    key_mode=$(stat -c '%a' -- "$key" 2>/dev/null || echo invalid)
    case "$key_mode" in 400|600) ;; *) key_state=UNSAFE_PERMISSIONS; rc=1 ;; esac
    if [ "$key_state" != UNSAFE_PERMISSIONS ]; then
        work=$(mktemp -d) || return 1
        if openssl x509 -in "$crt" -pubkey -noout > "$work/cert.pub" 2>/dev/null &&
           openssl pkey -in "$key" -pubout -passin pass: > "$work/key.pub" 2>/dev/null &&
           cmp -s "$work/cert.pub" "$work/key.pub"; then
            key_state=MATCH
        else
            key_state=MISMATCH
            rc=1
        fi
        rm -rf -- "$work"
    fi
    if openssl x509 -in "$crt" -noout -checkend 2592000 >/dev/null 2>&1; then
        renewal=OUTSIDE_30_DAY_WINDOW
    else
        renewal=DUE_WITHIN_30_DAYS
    fi

    printf 'lineage: %s\n  client: %s\n  certificate: %s\n  expires: %s\n  hostname: %s (%s)\n  private_key: %s\n  renewal: %s\n' \
        "$domain" "$client" "$cert_state" "$expiry" "$host_state" "$probe" "$key_state" "$renewal"
    return "$rc"
}

# sa_tls_status [domain] -- read-only certificate and key inspection.
sa_tls_status() {
    local root=${SA_CERT_ROOT:-/etc/stackalign/certs} resolved domain lineage dir entry found=0 rc=0
    [ $# -le 1 ] || { echo "usage: sa_tls_status [domain]" >&2; return 64; }
    [[ $root == /* && $root != *..* ]] || { echo "tls: certificate root must be an absolute safe path" >&2; return 64; }
    [ ! -L "$root" ] || { echo "tls: refusing symlinked certificate root" >&2; return 1; }
    if [ ! -d "$root" ]; then
        echo "tls: no managed certificate lineages found"
        return 0
    fi
    resolved=$(realpath -e -- "$root" 2>/dev/null) || return 1
    [[ $resolved == "$root" ]] || { echo "tls: certificate root resolves through a symlink" >&2; return 1; }
    command -v openssl >/dev/null 2>&1 || { echo "tls: openssl is not installed" >&2; return 69; }

    if [ $# -eq 1 ]; then
        domain=$1
        _sa_tls_domain_ok "$domain" || { echo "tls: invalid domain" >&2; return 64; }
        lineage=$(_sa_tls_lineage "$domain")
        dir="$root/$lineage"
        [ -d "$dir" ] || { echo "tls: no managed lineage for $domain"; return 1; }
        _sa_tls_status_one "$dir" "$domain"
        return $?
    fi

    while IFS= read -r -d '' entry; do
        if [ -L "$entry" ]; then
            printf 'lineage: %s\n  state: UNSAFE_SYMLINK\n' "${entry##*/}" >&2
            rc=1
            continue
        fi
        [ -d "$entry" ] || continue
        found=1
        lineage=${entry##*/}
        if [[ $lineage == _wildcard_.* ]]; then domain="*${lineage#_wildcard_}"; else domain=$lineage; fi
        _sa_tls_status_one "$entry" "$domain" || rc=1
    done < <(find "$root" -mindepth 1 -maxdepth 1 -print0)
    [ "$found" -eq 1 ] || echo "tls: no managed certificate lineages found"
    return "$rc"
}

# sa_tls_issue is deliberately fail-closed. The previous adapter passed
# ZeroSSL EAB secrets in argv and deployed cert/key as separate file renames.
# Do not restore issuance until both secret transport and atomic activation exist.
sa_tls_issue() {
    echo "tls: issuance BLOCKED — protected EAB transport and crash-safe atomic certificate/key deployment are not implemented" >&2
    return 2
}
\
