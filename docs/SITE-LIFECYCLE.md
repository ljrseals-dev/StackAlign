# Administrator-managed static Nginx sites

**Status: experimental; apply is intended for a disposable EL9 host until live-host acceptance is complete.**

## Scope

This workflow creates and archives individual **static-file Nginx virtual hosts** for an administrator managing multiple websites. It is not independent-user shared hosting and does not claim tenant isolation.

- The listener is loopback-only: `127.0.0.1:8080`.
- Each site gets a StackAlign-owned file under `/etc/nginx/conf.d/stackalign-site-<domain>.conf`.
- The document root must already exist, be readable/searchable, use a canonical absolute path, and contain no symlinked path components.
- The generated server block serves static files only. It does not configure PHP-FPM, application routing, TLS, DNS, public ingress, firewall rules, or application databases.
- The workflow does not create, chown, chmod, or delete the document root or its contents.
- `site isolate` remains blocked. A static vhost is not an account or process security boundary.

## Commands

Plan first:

```bash
stackalign site add example.com /var/www/example.com/public
stackalign site remove example.com
```

Apply explicitly:

```bash
sudo stackalign site add example.com /var/www/example.com/public --apply
sudo stackalign site remove example.com --apply
```

`site add` refuses to overwrite an existing target. An identical StackAlign-managed file is treated as unchanged. It writes the new file through a same-directory temporary file and no-clobber hard link, runs `nginx -t`, and reloads Nginx only if the service is already active. It never starts or enables Nginx.

`site remove` accepts only a regular, non-symlink file with the StackAlign ownership marker. It makes a verified mode-0600 backup in a mode-0700 backup directory before removing the config. The backup is retained; the document root is untouched. If validation or reload fails, it attempts to restore the previous configuration and reload it.

## Safety and verification limits

- Apply requires root. The `SA_SITE_TESTING=1` bypass exists only for fake-tool tests and must never be set in production.
- The default backup directory is `/var/lib/stackalign/site-backups`; custom paths must not resolve through symlinks.
- If Nginx is inactive, the configuration is validated and written/archived but no service is started.
- If `systemctl` is unavailable, the command reports that configuration was not reloaded.
- CI uses fake Nginx/systemd commands. Real Nginx parsing, SELinux labeling, service reload, host permissions, and reboot persistence have not yet been validated on a disposable EL9 VM.
