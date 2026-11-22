# StackAlign LEMP beta bootstrap

**Status: hardened single-host baseline in development; real-host validation is still required.**

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

Apply requires root. The installer installs nginx, mariadb-server, php-fpm, and php-mysqlnd from already-enabled DNF repositories; configures the default PHP-FPM www pool to run as nginx with matching Unix-socket ownership; writes a loopback-only Nginx server block; and validates PHP-FPM, MariaDB configuration, and Nginx before service activation. It explicitly binds MariaDB TCP to 127.0.0.1, disables local infile and symbolic links, and leaves local Unix-socket access available.

## Network and application boundary

The generated Nginx server listens only on 127.0.0.1:8080. This is deliberate: the baseline does not open a public listener or change firewall policy. It disables Nginx version disclosure, limits request bodies to 16 MiB, and denies dotfiles while preserving the ACME .well-known namespace for a future separately reviewed TLS workflow. The default document root is /var/www/stackalign/public and contains a small PHP health response. Configured web roots must remain canonical safe paths under /var/www; traversal, symlinked path components, and non-regular managed targets are refused before DNF runs.

MariaDB is started but no application database, application user, password, or remote listener is configured. The installer does not run mysql_secure_installation or claim that database hardening is complete.

## Failure and recovery behavior

Before changing the PHP-FPM pool, StackAlign Nginx site, MariaDB drop-in, and generated PHP health page, the installer snapshots all four managed files. If configuration validation or service activation fails, it attempts to restore those files (or remove newly created files) and restart PHP-FPM and Nginx. If restoration or either restart fails, the recovery snapshot is preserved for manual recovery instead of being deleted. The web root is validated as a canonical absolute path before any package or service command runs; unsafe characters, duplicate/trailing slashes, dot-path components, symlinked path components, and paths that resolve through symlinks are rejected. Existing managed targets must be regular files, not symlinks, before DNF runs.

**Important limitation:** DNF package installation is not reversed on failure. The installer does not snapshot or restore prior service enablement/running state, and it does not roll back a MariaDB data-directory initialization. Inspect the host and remove packages manually if needed. This is not a transactional host rollback guarantee.

## Not included

TLS issuance/renewal, public DNS, public ingress, firewall changes, application database/user provisioning, database credential management, independent-user isolation, verified restore, encryption/off-host backups, PHP application deployment, monitoring/alerting, and unattended updates are not implemented by this bootstrap. Loopback binding and passing syntax checks do not make a public production server.

The repository's install.sh release bootstrap remains intentionally disabled until a versioned artifact and trusted SHA-256 are published. This guide describes invoking the checked-out StackAlign CLI, not a signed release installer.

## Validation

tests/test_lemp.sh uses fake DNF, systemd, MariaDB, PHP-FPM, and Nginx commands. It checks read-only planning, path and symlink refusal before DNF, package selection, PHP-FPM pool edits, MariaDB loopback policy and config validation, Nginx loopback binding and hardening, health-page restoration/removal, restoration of all managed files after injected MariaDB validation failure, preservation of recovery snapshots after injected rollback failure, and service activation commands. These are mock tests only.

Required before calling this beta deployable on supported hosts:

1. Run the full make lint and make test suite on the branch.
2. Run the installer in clean AlmaLinux 9 and Rocky Linux 9 disposable VMs with working DNF repositories.
3. Verify PHP execution through curl http://127.0.0.1:8080/.
4. Verify MariaDB local socket access and confirm no unintended network listener.
5. Inject failures at package install, each config test, and each service activation; verify restoration and document any residual package/service state.
6. Reboot each VM and verify enabled services and the loopback endpoint.
7. Complete release-artifact signing and trust-anchor integration before publishing an installable release.

Do not run this beta bootstrap on production hosts or systems containing important data.
