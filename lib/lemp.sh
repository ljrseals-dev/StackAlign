#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/lemp.sh -- guarded EL9 LEMP bootstrap (distribution repositories only).
# This is a beta bootstrap: it creates a loopback-only HTTP endpoint on :8080.
# It does not configure public DNS, TLS, firewall rules, tenants, or databases.

: "${SA_LEMP_ETC_ROOT:=/etc}"
: "${SA_LEMP_WEB_ROOT:=/var/www/stackalign}"
: "${SA_LEMP_OS_RELEASE_FILE:=/etc/os-release}"

sa_lemp_die() { echo "stackalign install: $*" >&2; return 1; }

# The web root is interpolated into an Nginx directive by sed. Restrict it to
# an absolute, normalized path alphabet so delimiters, replacement operators,
# whitespace, and Nginx syntax cannot alter the generated configuration.
sa_lemp_web_root_valid() {
  local web=${SA_LEMP_WEB_ROOT:-} resolved
  [[ $web == /* && $web =~ ^/[A-Za-z0-9._/-]+$ ]] || {
    echo "stackalign install: web root must be an absolute path containing only letters, digits, dot, underscore, slash, and hyphen" >&2
    return 64
  }
  resolved=$(realpath -m -- "$web" 2>/dev/null) || {
    echo "stackalign install: cannot resolve web root safely" >&2
    return 64
  }
  [[ $resolved == "$web" ]] || {
    echo "stackalign install: web root must not resolve through symlinks or non-normalized components" >&2
    return 64
  }
  [[ $web != *//* && $web != */ ]] || {
    echo "stackalign install: web root must not contain duplicate or trailing slashes" >&2
    return 64
  }
  case "$web" in
    *"/../"*|*/..|*"/./"*|*/.)
      echo "stackalign install: web root must not contain dot or dot-dot path components" >&2
      return 64 ;;
  esac
}

# Refuse symlinked path components, not just symlinked leaf files. A
# symlinked public/ directory would otherwise redirect the generated health
# page outside the configured web root even when index.php itself is regular.
sa_lemp_path_components_safe() {
  local candidate=$1 current=/ component
  local -a components=()
  IFS=/ read -r -a components <<< "$candidate"
  for component in "${components[@]}"; do
    [ -n "$component" ] || continue
    current="${current%/}/$component"
    if [ -L "$current" ]; then
      echo "stackalign install: refusing symlinked path component: $current" >&2
      return 64
    fi
  done
}

# Refuse symlink/non-regular managed targets before DNF or file writes.
sa_lemp_targets_safe() {
  local path
  for path in "$SA_LEMP_ETC_ROOT/php-fpm.d" "$SA_LEMP_ETC_ROOT/nginx/conf.d" "$SA_LEMP_WEB_ROOT" "$SA_LEMP_WEB_ROOT/public"; do
    sa_lemp_path_components_safe "$path" || return $?
    if [ -e "$path" ] && [ ! -d "$path" ]; then
      echo "stackalign install: managed directory path is not a directory: $path" >&2
      return 64
    fi
  done
  for path in "$SA_LEMP_ETC_ROOT/php-fpm.d/www.conf" "$SA_LEMP_ETC_ROOT/nginx/conf.d/stackalign.conf" "$SA_LEMP_WEB_ROOT/public/index.php"; do
    if [ -L "$path" ]; then
      echo "stackalign install: refusing symlinked managed target: $path" >&2
      return 64
    fi
    if [ -e "$path" ] && [ ! -f "$path" ]; then
      echo "stackalign install: managed target is not a regular file: $path" >&2
      return 64
    fi
  done
}

sa_lemp_host_check() {
  sa_lemp_web_root_valid || return $?
  [ "${SA_LEMP_TESTING:-0}" = 1 ] && return 0
  [ "${EUID:-$(id -u)}" -eq 0 ] || { sa_lemp_die "apply requires root"; return 1; }
  [ -r "$SA_LEMP_OS_RELEASE_FILE" ] || { sa_lemp_die "cannot read $SA_LEMP_OS_RELEASE_FILE"; return 1; }
  local id="" version="" arch
  # Parse only ID and VERSION_ID as data; never source os-release.
  while IFS= read -r line; do
    case $line in ID=*) id=${line#ID=} ;; VERSION_ID=*) version=${line#VERSION_ID=} ;; esac
  done < "$SA_LEMP_OS_RELEASE_FILE"
  id=${id%\"}; id=${id#\"}
  version=${version%\"}; version=${version#\"}
  arch=$(uname -m) || return 1
  case "$id:$version:$arch" in
    almalinux:9*:x86_64|rocky:9*:x86_64|rhel:9*:x86_64|ol:9*:x86_64|centos:9*:x86_64) ;;
    *) sa_lemp_die "supported apply target is EL9 x86_64 (AlmaLinux, Rocky, RHEL, Oracle Linux, or CentOS Stream); found $id $version $arch"; return 1 ;;
  esac
  command -v dnf >/dev/null 2>&1 || { sa_lemp_die "dnf is required"; return 1; }
  command -v systemctl >/dev/null 2>&1 || { sa_lemp_die "systemctl is required"; return 1; }
}

sa_lemp_plan() {
  sa_lemp_host_check || return $?
  cat <<EOF
StackAlign LEMP beta plan (no changes made)
  Target: EL9 x86_64
  Packages: nginx mariadb-server php-fpm php-mysqlnd (enabled DNF repositories)
  Web root: $SA_LEMP_WEB_ROOT/public
  HTTP endpoint: 127.0.0.1:8080 (loopback only; not publicly exposed)
  Services: mariadb, php-fpm, nginx (enable and start)
  Configuration: PHP-FPM www pool and isolated Nginx server block
  Safety: existing configuration files are snapshotted before edits
  Excluded: TLS, firewall, DNS, public listener, database/user provisioning,
            tenant isolation, backups, and production hardening
Re-run as root with: stackalign install --apply
EOF
}

sa_lemp_restore() {
  local backup=$1 path
  for path in "$SA_LEMP_ETC_ROOT/nginx/conf.d/stackalign.conf" "$SA_LEMP_ETC_ROOT/php-fpm.d/www.conf" "$SA_LEMP_WEB_ROOT/public/index.php"; do
    if [ -e "$backup$path" ] || [ -L "$backup$path" ]; then
      cp -a "$backup$path" "$path" || return 1
    else
      rm -f "$path" || return 1
    fi
  done
}

sa_lemp_apply() {
  [ "${SA_LEMP_TESTING:-0}" = 1 ] || [ "${EUID:-$(id -u)}" -eq 0 ] || { sa_lemp_die "apply requires root"; return 1; }
  sa_lemp_host_check || return $?
  sa_lemp_targets_safe || return $?
  local etc="$SA_LEMP_ETC_ROOT" web="$SA_LEMP_WEB_ROOT"
  local pool="$etc/php-fpm.d/www.conf" site="$etc/nginx/conf.d/stackalign.conf"
  local backup failed=0
  echo "Installing distro-provided LEMP packages (no third-party repositories added)"
  dnf -y install nginx mariadb-server php-fpm php-mysqlnd || { sa_lemp_die "DNF package installation failed"; return 1; }

  backup=$(mktemp -d) || return 1
  mkdir -p "$backup$etc/php-fpm.d" "$backup$etc/nginx/conf.d" "$backup$web/public"
  [ ! -e "$pool" ] && [ ! -L "$pool" ] || cp -a "$pool" "$backup$pool" || { rm -rf "$backup"; return 1; }
  [ ! -e "$site" ] && [ ! -L "$site" ] || cp -a "$site" "$backup$site" || { rm -rf "$backup"; return 1; }
  [ ! -e "$web/public/index.php" ] && [ ! -L "$web/public/index.php" ] || cp -a "$web/public/index.php" "$backup$web/public/index.php" || { rm -rf "$backup"; return 1; }
  mkdir -p "$etc/php-fpm.d" "$etc/nginx/conf.d" "$web/public" || failed=1

  if [ "$failed" -eq 0 ]; then
    [ -f "$pool" ] || failed=1
    if [ "$failed" -eq 0 ]; then
      sed -E -i \
        -e 's/^[;[:space:]]*user[[:space:]]*=.*/user = nginx/' \
        -e 's/^[;[:space:]]*group[[:space:]]*=.*/group = nginx/' \
        -e 's|^[;[:space:]]*listen[.]owner[[:space:]]*=.*|listen.owner = nginx|' \
        -e 's|^[;[:space:]]*listen[.]group[[:space:]]*=.*|listen.group = nginx|' \
        -e 's|^[;[:space:]]*listen[.]mode[[:space:]]*=.*|listen.mode = 0660|' "$pool" || failed=1
      grep -Eq '^user[[:space:]]*=[[:space:]]*nginx$' "$pool" || failed=1
      grep -Eq '^group[[:space:]]*=[[:space:]]*nginx$' "$pool" || failed=1
      grep -Eq '^listen[.]owner[[:space:]]*=[[:space:]]*nginx$' "$pool" || failed=1
      grep -Eq '^listen[.]group[[:space:]]*=[[:space:]]*nginx$' "$pool" || failed=1
    fi
  fi

  if [ "$failed" -eq 0 ]; then
    cat > "$site" <<'NGINX'
server {
    listen 127.0.0.1:8080;
    server_name localhost;
    root /var/www/stackalign/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php-fpm/www.sock;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX
    sed -i "s|^    root /var/www/stackalign/public;|    root $web/public;|" "$site" || failed=1
    cat > "$web/public/index.php" <<'PHP'
<?php
header('Content-Type: text/plain; charset=utf-8');
echo "StackAlign LEMP beta: PHP-FPM is responding\n";
PHP
    chmod 0644 "$site" "$web/public/index.php" || failed=1
  fi

  if [ "$failed" -eq 0 ]; then php-fpm -t || failed=1; fi
  if [ "$failed" -eq 0 ]; then nginx -t || failed=1; fi
  if [ "$failed" -eq 0 ]; then
    systemctl enable --now mariadb || failed=1
    systemctl enable --now php-fpm || failed=1
    systemctl enable --now nginx || failed=1
  fi
  if [ "$failed" -eq 0 ]; then
    systemctl is-active --quiet mariadb || failed=1
    systemctl is-active --quiet php-fpm || failed=1
    systemctl is-active --quiet nginx || failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "install: configuration or service activation failed; restoring prior StackAlign-managed config" >&2
    sa_lemp_restore "$backup" || echo "CRITICAL: configuration restore failed; inspect $backup" >&2
    systemctl restart php-fpm >/dev/null 2>&1 || true
    systemctl restart nginx >/dev/null 2>&1 || true
    rm -rf "$backup"
    sa_lemp_die "LEMP apply did not complete; installed RPMs may remain and require manual removal"
    return 1
  fi
  rm -rf "$backup"
  cat <<EOF
StackAlign LEMP beta installed.
  Local endpoint: http://127.0.0.1:8080/
  Document root: $web/public
  Services: nginx, php-fpm, mariadb (enabled and active)
  Note: MariaDB is running but no database/user was created or secured for an application.
  Note: endpoint is loopback-only; TLS, public ingress, firewall, backups and tenant
        isolation are outside this beta bootstrap.
EOF
}

sa_lemp_install() {
  case "${1:-plan}" in
    plan) sa_lemp_plan ;;
    apply) sa_lemp_apply ;;
    *) sa_lemp_die "usage: install [--plan|--apply]"; return 64 ;;
  esac
}
