# StackAlign LEMP beta bootstrap

**Status: experimental beta implementation; real-host validation is still required.**

## Supported apply target

- AlmaLinux 9 x86_64
- Rocky Linux 9 x86_64
- RHEL 9 x86_64
- Oracle Linux 9 x86_64
- CentOS Stream 9 x86_64

The installer uses packages from the host's already-enabled DNF repositories. It does not add repositories, import signing keys, pin exact RPM NEVRAs, or compile upstream software.

## Commands

Run the plan first:

    sudo stackalign install

The plan is read-only. Apply only in a disposable VM:

    sudo stackalign install --apply

Apply requires root. The installer installs nginx, mariadb-server, php-fpm, and php-mysqlnd; configures the default PHP-FPM www pool to run as nginx with a matching Unix-socket owner/group; writes an Nginx server block; validates with php-fpm -t and nginx -t; then enables and starts MariaDB, PHP-FPM, and Nginx.

## Network and application boundary

The generated Nginx server listens only on 127.0.0.1:8080. This is deliberate: the beta does not open a public listener or change firewall policy. The default document root is /var/www/stackalign/public and contains a small PHP response page.

MariaDB is started but no application database, application user, password, or remote listener is configured. The installer does not run mysql_secure_installation or claim that database hardening is complete.

## Failure and recovery behavior

Before changing the PHP-FPM pool, StackAlign Nginx site file, and generated PHP health page, the installer copies any existing versions to a private temporary directory. If configuration validation or service activation fails, it attempts to restore those files (or remove a newly created health page) and restart PHP-FPM and Nginx. The configurable web root is validated as an absolute, normalized path before any package or service command runs; unsafe characters, duplicate/trailing slashes, dot-path components, and paths that resolve through symlinks are rejected. Existing managed targets must be regular files, not symlinks, before DNF runs; this prevents the generated health page from following a pre-existing symlink outside the document root.

**Important limitation:** DNF package installation is not reversed on failure. The installer does not snapshot or restore prior service enablement/running state, and it does not roll back a MariaDB data-directory initialization. Inspect the host and remove packages manually if needed. This is not a transactional host rollback guarantee.

## Not included

TLS issuance/renewal, public DNS, public ingress, firewall changes, application database provisioning, database credential management, tenant isolation, backups, PHP application deployment, production hardening, monitoring, and unattended updates are not implemented by this bootstrap.

The repository's install.sh release bootstrap remains intentionally disabled until a versioned artifact and trusted SHA-256 are published. This guide describes invoking the checked-out StackAlign CLI, not a signed release installer.

## Validation

tests/test_lemp.sh uses fake DNF, systemd, PHP-FPM, and Nginx commands. It checks planning, package selection, PHP-FPM pool edits, loopback binding, document-root handling, unsafe web-root and symlink-resolved path rejection, managed-target symlink refusal, syntax-test invocation, health-page restoration/removal after injected validation failures, and service activation commands. These are mock tests only.

Required before calling this beta deployable on supported hosts:

1. Run the full make lint and make test suite on the branch.
2. Run the installer in clean AlmaLinux 9 and Rocky Linux 9 disposable VMs with working DNF repositories.
3. Verify PHP execution through curl http://127.0.0.1:8080/.
4. Verify MariaDB local socket access and confirm no unintended network listener.
5. Inject failures at package install, each config test, and each service activation; verify restoration and document any residual package/service state.
6. Reboot each VM and verify enabled services and the loopback endpoint.
7. Complete release-artifact signing and trust-anchor integration before publishing an installable release.

Do not run this beta bootstrap on production hosts or systems containing important data.
