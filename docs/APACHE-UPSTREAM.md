# Apache upstream integration

**Status: architecture and read-only planning contract; runtime integration not yet enabled.**

## Decision

Apache HTTP Server is an optional application upstream. Nginx remains StackAlign's default edge server. The hybrid topology is Nginx -> Apache -> dedicated PHP-FPM pool.

Apache may also be selected as the direct web server for single-tenant compatibility evaluation. Neither direct Apache nor hybrid mode is currently a production-ready deployment path.

## Why Apache is upstreamed

Apache supports reverse proxying through `mod_proxy` and PHP-FPM through `mod_proxy_fcgi`. This allows applications that depend on Apache behavior or configuration conventions to run behind the StackAlign Nginx edge without replacing the edge layer.

Official references:

- https://httpd.apache.org/docs/current/mod/mod_proxy.html
- https://httpd.apache.org/docs/current/mod/mod_proxy_fcgi.html
- https://httpd.apache.org/docs/current/mod/event.html

## Required configuration shape

Hybrid Nginx proxy location:

```nginx
location / {
    proxy_pass http://127.0.0.1:8081;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Apache PHP-FPM handler (illustrative; socket path and ownership must match the dedicated pool):

```apache
<FilesMatch "\\.php$">
    SetHandler "proxy:unix:/run/php-fpm/stackalign-apache.sock|fcgi://localhost/"
</FilesMatch>
```

These snippets are examples only. StackAlign does not currently render or install them.

## Security constraints

- Apache must bind only to loopback or a protected Unix socket in hybrid mode.
- Never expose the Apache backend port publicly.
- Do not rely on virtual hosts for tenant isolation.
- Do not use the shared PHP-FPM `www` pool for a claimed isolated tenant.
- A shared Apache daemon is not per-tenant process isolation.
- `mod_suexec` is not a substitute for PHP-FPM pool separation.
- Do not weaken SELinux or disable it to make the integration work.
- Do not add third-party repositories or import signing keys automatically.

## Apply gate

Runtime apply is intentionally unavailable until the tenant identity and service/cgroup model is implemented. The existing LEMP beta remains unchanged.
