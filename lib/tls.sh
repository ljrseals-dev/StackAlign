#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/tls.sh -- ACME client adapter. Lego primary, Certbot fallback; shells out only.
# Needs: log, sa_history_snapshot <path> [slug], sa_service_reload_safe <service> <snapshot-id>.
# ZeroSSL EAB is passed as client flags and may be visible in process listings.
# Restrict use to single-tenant hosts until clients support a protected secret channel.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_CERT_ROOT:=/etc/stackalign/certs}"

_sa_tls_domain_ok() { [[ $1 =~ ^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
_sa_tls_lineage() { local d=$1; printf '%s' "${d/#\*./_wildcard_.}"; }
_sa_tls_ca_url() {
    case $1 in
        letsencrypt) echo "https://acme-v02.api.letsencrypt.org/directory" ;;
        zerossl)     echo "https://acme.zerossl.com/v2/DV90" ;;
        *) return 1 ;;
    esac
}

# Reports upstream schedulers; returns 2 if one is active.
sa_tls_preflight() {
    local found=0 t
    for t in certbot.timer certbot-renew.timer snap.certbot.renew.timer; do
        if systemctl is-active --quiet "$t" 2>/dev/null; then echo "scheduler: $t active"; found=1; fi
    done
    if { crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; } | grep -q 'acme\.sh'; then
        echo "scheduler: acme.sh cron entry present"; found=1
    fi
    [ "$found" -eq 0 ] || return 2
}

# Refuses while an upstream scheduler is active unless SA_TLS_ALLOW_UPSTREAM=1.
sa_tls_enable_renewal_timer() {
    local rc=0
    sa_tls_preflight >/dev/null || rc=$?
    if [ "$rc" -eq 2 ] && [ "${SA_TLS_ALLOW_UPSTREAM:-0}" != 1 ]; then
        echo "tls: upstream scheduler active; refusing (set SA_TLS_ALLOW_UPSTREAM=1 to override)" >&2
        return 2
    fi
    systemctl enable --now stackalign-renew.timer
}

# sa_tls_issue <domain> <client> <ca> <challenge> <webroot|dns_provider> <email> <service>
sa_tls_issue() {
    [ $# -eq 7 ] || { echo "usage: sa_tls_issue domain client ca challenge webroot|provider email service" >&2; return 64; }
    local domain=$1 client=$2 ca=$3 chal=$4 extra=$5 email=$6 svc=$7 url lin dir work snap crt key base
    local stage_crt stage_key stage_client pub_crt pub_key
    _sa_tls_domain_ok "$domain" || { echo "tls: bad domain: $domain" >&2; return 64; }
    case $client in lego|certbot) ;; *) echo "tls: bad client: $client" >&2; return 64 ;; esac
    url="$(_sa_tls_ca_url "$ca")" || { echo "tls: bad ca: $ca" >&2; return 64; }
    [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { echo "tls: bad email" >&2; return 64; }
    [[ $svc =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "tls: bad service" >&2; return 64; }
    case $chal in
        http-01) [[ $extra == /* && -d $extra ]] || { echo "tls: webroot must be an existing absolute dir" >&2; return 64; } ;;
        dns-01)  [[ $extra =~ ^[a-z0-9-]+$ ]] || { echo "tls: bad dns provider" >&2; return 64; }
                 [ "$client" = lego ] || { echo "tls: dns-01 needs lego" >&2; return 64; } ;;
        *) echo "tls: bad challenge: $chal" >&2; return 64 ;;
    esac
    if [ "$ca" = zerossl ] && { [ -z "${SA_TLS_EAB_KID:-}" ] || [ -z "${SA_TLS_EAB_HMAC:-}" ]; }; then
        echo "tls: zerossl needs SA_TLS_EAB_KID and SA_TLS_EAB_HMAC" >&2; return 1
    fi

    lin="$(_sa_tls_lineage "$domain")"; dir="$SA_CERT_ROOT/$lin"
    [[ ! -L "$SA_CERT_ROOT" && ! -L "$dir" ]] || { echo "tls: refusing symlinked certificate path" >&2; return 1; }
    if [ -f "$dir/.client" ] && [ "$(cat "$dir/.client")" != "$client" ]; then
        echo "tls: $domain is owned by $(cat "$dir/.client"); refusing to switch to $client" >&2; return 1
    fi
    ( umask 077; mkdir -p -- "$dir" ) || return 1
    work="$(mktemp -d)" || return 1

    if [ "$client" = lego ]; then
        local -a args=(--path "$work" --email "$email" --accept-tos --server "$url" --domains "$domain")
        [ "$ca" = zerossl ] && args+=(--eab --kid "$SA_TLS_EAB_KID" --hmac "$SA_TLS_EAB_HMAC")
        if [ "$chal" = http-01 ]; then args+=(--http --http.webroot "$extra"); else args+=(--dns "$extra"); fi
        if ! lego "${args[@]}" >&2; then rm -rf -- "$work"; return 1; fi
        base="${domain/#\*/_}"
        crt="$work/certificates/$base.crt"; key="$work/certificates/$base.key"
    else
        local -a cargs=(certonly --non-interactive --agree-tos -m "$email" --cert-name "$domain" -d "$domain"
                     --server "$url" --webroot -w "$extra"
                     --config-dir "$work/c" --work-dir "$work/w" --logs-dir "$work/l")
        [ "$ca" = zerossl ] && cargs+=(--eab-kid "$SA_TLS_EAB_KID" --eab-hmac-key "$SA_TLS_EAB_HMAC")
        if ! certbot "${cargs[@]}" >&2; then rm -rf -- "$work"; return 1; fi
        crt="$work/c/live/$domain/fullchain.pem"; key="$work/c/live/$domain/privkey.pem"
    fi
    if [ ! -s "$crt" ] || [ ! -s "$key" ]; then
        echo "tls: client produced no cert/key" >&2; rm -rf -- "$work"; return 1
    fi
    pub_crt="$work/cert.pub"; pub_key="$work/key.pub"
    if ! openssl x509 -in "$crt" -pubkey -noout > "$pub_crt" ||
       ! openssl pkey -in "$key" -pubout > "$pub_key" ||
       ! cmp -s "$pub_crt" "$pub_key"; then
        echo "tls: certificate and private key do not match or cannot be validated" >&2
        rm -rf -- "$work"; return 1
    fi

    snap="$(sa_history_snapshot "$dir" "pre-tls-$lin")" || {
        rm -rf -- "$work"; echo "tls: snapshot failed" >&2; return 1;
    }
    stage_crt="$(mktemp "$dir/.fullchain.XXXXXX")" || { rm -rf -- "$work"; return 1; }
    stage_key="$(mktemp "$dir/.privkey.XXXXXX")" || {
        rm -f -- "$stage_crt"; rm -rf -- "$work"; return 1;
    }
    stage_client="$(mktemp "$dir/.client.XXXXXX")" || {
        rm -f -- "$stage_crt" "$stage_key"; rm -rf -- "$work"; return 1;
    }
    if ! cp -- "$crt" "$stage_crt" || ! cp -- "$key" "$stage_key" ||
       ! chmod 644 "$stage_crt" || ! chmod 600 "$stage_key"; then
        rm -f -- "$stage_crt" "$stage_key" "$stage_client"; rm -rf -- "$work"; return 1
    fi
    printf '%s\n' "$client" > "$stage_client" || {
        rm -f -- "$stage_crt" "$stage_key" "$stage_client"; rm -rf -- "$work"; return 1;
    }
    chmod 600 "$stage_client" || {
        rm -f -- "$stage_crt" "$stage_key" "$stage_client"; rm -rf -- "$work"; return 1;
    }

    if ! mv -f -- "$stage_crt" "$dir/fullchain.pem" ||
       ! mv -f -- "$stage_key" "$dir/privkey.pem" ||
       ! mv -f -- "$stage_client" "$dir/.client"; then
        sa_history_rollback "$snap" || log "tls: deployment rollback failed for snapshot $snap"
        rm -f -- "$stage_crt" "$stage_key" "$stage_client"
        rm -rf -- "$work"
        return 1
    fi
    rm -rf -- "$work"
    sa_service_reload_safe "$svc" "$snap" || {
        log "tls: reload failed; snapshot $snap holds the previous files"
        return 1
    }
    log "tls: $domain issued by $client, deployed to $dir"
}
