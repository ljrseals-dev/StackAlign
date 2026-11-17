# Centmin Mod capability gap and StackAlign adoption plan

**Research snapshot:** 2026-11-17  
**Upstream reference:** Centmin Mod 141.00beta01 menu and addon catalogue (source commit e70d770884694c7491ad112f7d936634cd1fa2f2)  
**StackAlign baseline:** feat/internet-access-wizard at c221951260e38eca1eb7c9d3ab1f9d1b4b445650 (PR #52 head; stacked on PR #51)

This is a capability comparison, not a claim that Centmin Mod's implementation is suitable to copy or run on a StackAlign host. Centmin Mod's repository is GPL-3.0; StackAlign is MIT. Do not copy upstream implementation code into StackAlign without a deliberate licensing decision. Implement compatible behavior independently, or use Centmin Mod itself as a separately installed product on a fresh host.

## Executive summary

Centmin Mod is a much broader hosting control toolkit than StackAlign's current beta. Its documented 24-option menu covers initial stack installation, virtual hosts, DNS, Nginx/PHP/MariaDB version management, database administration, persistent configuration, PostgreSQL, Memcached, OPcache, Redis/Imagick/Suhosin/FFmpeg PHP extensions, SSH port changes, compression utilities, data transfer/backup, WordPress hosting, and self-updating. Its addon catalogue adds ACME certificates, malware scanning, DKIM, WP-CLI, Redis server, Passenger, Node.js, Go, Ruby, Python runtimes, Docker, rclone, GeoIP, and system information pages.

StackAlign already contains several building blocks, but many are not reachable from the CLI, are plan-only, are incomplete, or lack live-host validation. The main gap is not simply missing package names: it is complete lifecycle behavior, safe multi-tenant isolation, integration, rollback, and acceptance tests.

## Capability matrix

Legend:
- **Implemented** — behavior exists and is wired, subject to the documented test limits.
- **Partial / gated** — a library, template, plan, or narrow behavior exists, but lifecycle/apply/integration is incomplete.
- **Missing** — no implementation found in the inspected baseline.
- **Do not adopt** — upstream feature conflicts with StackAlign's security or packaging policy.

| Centmin Mod capability | StackAlign evidence | Assessment | Work needed |
|---|---|---|---|
| Full Nginx + PHP-FPM + MariaDB bootstrap | lib/lemp.sh; EL9 distro packages; loopback-only 127.0.0.1:8080 | **Partial / implemented beta** | Expand only after supported-host and rollback tests; no production claim yet |
| Nginx virtual-host create/list/remove | site command remains a stub; hosting modes are read-only | **Missing** | Safe site lifecycle, config validation, ownership, idempotence, removal/backup |
| Apache and Nginx/Apache hybrid | lib/hosting.sh, PR #51 | **Plan only / apply blocked** | Implement tenant-aware pools, loopback upstream, service recovery, adversarial isolation tests |
| Multi-user/shared hosting | Hosting setup detects scope but does not persist it; shared PHP-FPM pool | **Missing** | Per-tenant Unix identity, PHP-FPM pool/socket, filesystem/process/resource/service isolation |
| Authoritative DNS / NSD | Internet planner only; no DNS zone service | **Missing** | Prefer external DNS provider integration; self-hosted authoritative DNS is optional and high operational burden |
| Nginx source upgrade/downgrade and module rebuild | DNF update planning only; update check/pin/status stubs; no tested package matrix | **Partial / gated** | Version pinning, transaction preview, tested NEVRA matrix, rollback, service health; source-build parity is not a goal |
| PHP version upgrade/downgrade and full extension rebuild | DNF plan path; no source build or version switch lifecycle | **Partial / gated** | Supported PHP stream policy, extension compatibility matrix, staged update and recovery |
| MariaDB version upgrade and management | MariaDB package bootstrap; db lifecycle is a stub | **Partial** | Database/user lifecycle, safe credential channel, schema-aware backup/restore, tested major upgrades |
| MySQL database/user administration | PRs #56–#58 add read-only server/schema/account inventory and plan/apply database creation; no user/grant lifecycle | **Partial** | Add least-privilege database users/grants, password rotation, dependency-aware drop with pre-drop backup and verified restore |
| PostgreSQL server management | No PostgreSQL module or CLI | **Missing** | Optional backend module and versioned package/backup/health contract |
| Persistent configuration manager | Generic INI parser; schema validation and writer not complete | **Partial** | Versioned schemas, typed validation, atomic writes, ownership/mode checks, drift and rollback |
| Memcached server lifecycle | PHP extension allowlist does not install/manage Memcached server | **Missing** | Optional service install/config/health/resource cap; never expose unauthenticated cache ports publicly |
| OPcache | Not explicitly provisioned or managed in LEMP bootstrap | **Missing / unverified** | Detect distro package state, configure and validate PHP runtime cache |
| Redis server | redis PHP extension allowlist only | **Partial** | Redis server lifecycle, protected bind/auth, persistence policy, service health |
| Redis PHP extension | lib/extensions.sh allowlists php-pecl-redis | **Partial** | Verify package names per EL/PHP stream and test loaded module |
| ImageMagick PHP extension | lib/extensions.sh allowlists php-pecl-imagick | **Partial** | Verify package availability/ABI and runtime test |
| FFmpeg and PHP extension | ffmpeg-php package mapping exists | **Partial / package assumption** | Verify package source and compatibility; separate media binary from PHP extension |
| Other PHP extensions (igbinary, APCu, Memcached, MongoDB, Swoole, IMAP, mailparse, intl, compression) | No complete extension catalogue | **Missing / partial** | Add only supported packages with PHP ABI checks and per-extension tests |
| Suhosin | No module | **Do not prioritize** | Legacy extension; use maintained PHP hardening controls instead |
| TLS issuance and renewal | PR #55 wires read-only `tls status` and active scheduler preflight; issuance adapter is fail-closed | **Partial / diagnostics only** | Implement protected EAB/DNS credentials, three-client lineage ownership, atomic cert/key activation, crash recovery, scheduler isolation, renewal, and real-host issuance/reload tests |
| WordPress vhost/cache install | templates/nginx/site-wordpress.conf.tmpl exists; no full WordPress installer/cache lifecycle | **Partial / missing** | Secure application install, database/user, WP-CLI, cache integration, updates, file permissions |
| Backup and data transfer | PR #54 wires logical mysqldump and physical MariaBackup creation plus list/integrity checks; restore remains blocked | **Partial / guarded** | Add authenticated encryption, retention policy, off-host replication, verified restore with pre-restore snapshot/rollback, and disaster-recovery tests |
| SSH tunnel migration and key management | SFTP key-only account module; no host-to-host migration workflow | **Partial** | Explicit migration plans, source/destination checks, resumability, integrity verification |
| Multi-thread compression utilities | No installer/manager for pigz, pbzip2, zstd, lbzip2 | **Missing** | Optional tools only if benchmarked and packaged by supported repositories |
| SSH port change | SFTP module supports key-only chroot accounts; no SSH port manager | **Do not prioritize** | Port changes are not a substitute for key-only auth, firewall policy, and private admin access |
| SELinux disable | No disable path; Apache docs explicitly say do not disable SELinux | **Do not adopt** | Keep SELinux enforcing; add policy diagnostics/labels if needed |
| Firewall / intrusion protection | lib/firewall.sh supports nftables/firewalld detection and CrowdSec/Fail2ban package install; lib/egress.sh handles outbound policy | **Partial** | Complete inbound policy, persistence, safe recovery, service configuration, real-host lockout tests |
| CSF integration | No CSF module | **Missing / not recommended as a default** | Prefer supported native nftables/firewalld policy; avoid competing firewall managers |
| Malware scanning | lib/security.sh queues advisory ClamAV findings; no quarantine/delete | **Partial** | Scheduled scans, safe reporting, signature update policy, false-positive workflow; no automatic destructive quarantine |
| DKIM / mail stack | No Postfix/OpenDKIM/DNS mail lifecycle | **Missing** | Optional mail-auth module only if email hosting is in scope; SPF/DKIM/DMARC remain DNS-owner tasks |
| Vhost stats / Linfo / monitoring | No monitoring dashboard or per-site traffic reporting | **Missing** | Privacy-preserving metrics, protected endpoints, disk/service alerts, log retention |
| Log rotation | No StackAlign logrotate manager found | **Missing** | Nginx/PHP-FPM/MariaDB rotation policies and safe validation |
| Add-on runtimes: Passenger, Node.js, Go, Ruby, Python, Docker | No supported lifecycle in CLI | **Missing / optional scope** | Use per-app runtimes only when demanded; isolate services and pin versions |
| GeoIP / CDN real-IP integration | No complete module | **Missing** | Trusted proxy CIDR management, current provider ranges, safe log IP handling |
| Release self-update | install.sh refuses placeholder SHA; release verifier is not integrated with updater | **Partial / gated** | Signed release manifest, independent trust anchor, anti-rollback, staged update/rollback |
| Server alerts and scheduled maintenance | No complete disk alert / update scheduler / notification subsystem | **Missing** | Explicit schedules, owner-only config, dry-run, bounded notifications, audit trail |

## Upstream installation compatibility

Centmin Mod is a standalone, root-run server stack installer, not a library or plugin to install inside StackAlign. Its 141.00beta01 entry point explicitly requires UID 0, creates and mounts a temporary setup filesystem in some memory profiles, installs prerequisite packages, and manages its own Nginx/PHP/MariaDB build and configuration paths. Running that installer on an existing StackAlign host would create competing ownership of packages, configuration, services, and update policy.

**Do not chain Centmin's installer from StackAlign.** If the operator chooses Centmin Mod as the server platform, install it on a clean, separate host and do not also let StackAlign manage the same Nginx/PHP/MariaDB services. For StackAlign, implement the required feature behavior natively under its EL9/DNF, configuration-snapshot, and rollback contracts.

The upstream source branch is useful as a feature and behavior reference, but its GPL-3.0 code is not copied into this MIT repository.

## StackAlign work already present but not complete

These should be completed and wired before creating duplicate implementations:

1. **TLS:** lib/tls.sh already contains an ACME adapter. The CLI command is still a stub. Review existing secret handling and renewal scheduler before exposing it.
2. **Backups:** PR #54 wires `backup run logical|physical`, `backup list`, and `backup verify`; credential defaults files must be owner-only. Logical verification checks gzip integrity only; physical verification checks the prepared checkpoint marker. Restore remains blocked pending pre-restore snapshots, engine-specific recovery, rollback, and live restore tests. Encryption, retention, and off-host replication are not wired.
3. **Security scanning:** lib/security.sh queues advisory ClamAV findings. It does not remediate or quarantine.
4. **Firewall:** lib/firewall.sh has backend selection and an intrusion-tool package install helper; that is not equivalent to Centmin Mod's complete CSF-managed stack.
5. **PHP extensions:** lib/extensions.sh has a four-item package allowlist (Redis, Imagick, FFmpeg PHP, libheif); package availability is an explicit assumption.
6. **WordPress:** a configuration template exists, but the application/database/cache installer is absent.
7. **Update engine:** package transaction code exists, but tested version matrices are empty and check, pin, and status remain stubs.
8. **Hosting:** PR #51 adds Apache/hybrid planning and scope prompts only. Per-tenant isolation remains blocked.
9. **Internet access:** PR #52 adds preference capture and read-only planning only. DNS, TLS, firewall, and tunnel provisioning remain blocked.

## Upstream addon inventory cross-check

The 141.00beta01 source tree contains 34 addon scripts. This cross-check expands the menu comparison so that optional features are not missed.

| Upstream addon(s) | StackAlign assessment | Adoption direction |
|---|---|---|
| acmetool.sh | Partial: lib/tls.sh has ACME client helpers but the CLI is not wired | Finish the native TLS lifecycle first; do not copy the script |
| anubis.sh | Missing | Optional bot-abuse protection; evaluate only behind an explicit reverse-proxy threat model |
| avginstall.sh | Missing | Do not adopt legacy antivirus bundle without current vendor/security review |
| customcurl.sh, wget.sh | Missing | Prefer supported EL packages and vendor security updates; no custom system curl replacement by default |
| devtoolset-4.sh, devtoolset-6.sh | Missing | Do not install legacy compiler toolsets globally; use isolated build containers when needed |
| docker.sh | Missing | Optional container runtime only; do not grant the Pinecone sidecar Docker socket access |
| ffmpeg.sh | Partial | Package mapping exists for FFmpeg PHP, but the media runtime and end-to-end ABI checks are not implemented |
| geoip.sh | Missing | Add trusted-proxy CIDR and database update design before exposing GeoIP data |
| git2_install.sh | Missing | Prefer distribution Git unless a specific tested version is required |
| golang.sh, nodejs.sh, ruby.sh, passenger.sh | Missing | Optional per-application runtimes; require version pinning and service isolation |
| ioncube.sh | Missing | Optional proprietary loader; license acceptance and PHP ABI compatibility required |
| ius-repo.sh | Do not adopt by default | Third-party repository expansion conflicts with StackAlign's conservative repository trust policy |
| linfo.sh | Missing | Avoid public system-information pages; if implemented, protect behind administrator authentication |
| maldet.sh | Partial | ClamAV advisory scanning exists; no LMD real-time monitoring/quarantine lifecycle |
| mysqladmin_shell.sh | Partial | Database administration CLI is still a stub; implement native least-privilege db commands instead |
| opendkim.sh | Missing | Optional mail-auth subsystem; DNS SPF/DKIM/DMARC still requires domain-owner action |
| php-libheif.sh | Partial | libheif appears in the extension allowlist; validate package/ABI/runtime before claiming support |
| php72-mcrypt.sh, php73-mcrypt.sh, php74-mcrypt.sh, php80-mcrypt.sh | Do not prioritize | Legacy mcrypt/PHP compatibility is not a modern default; prefer maintained cryptographic APIs |
| python27_install.sh, python34_install.sh, python35_install.sh, python36_install.sh, python_switch_el8.sh | Do not adopt | Legacy Python versions and global interpreter switching are unsafe defaults; use supported system Python or isolated runtimes |
| rclone.sh | Partial | rclone copy helper exists in lib/backup.sh; credentials, encryption, retention, and restore verification are incomplete |
| redis-server-install.sh | Missing | Redis PHP extension is not a Redis server; add protected bind/auth/persistence and service checks |
| wpcli.sh | Missing | WordPress config template exists, but WP-CLI and a full WordPress lifecycle do not |
 
The upstream source tree also contains standalone data-management scripts for backup, MariaBackup/restore, SSH tunnel transfers, key generation, and logging. StackAlign's current backup library is only a partial building block; it is not equivalent to the full transfer/migration workflow.

## Platform support difference

Centmin Mod's 141.00beta01 documentation lists AlmaLinux/Rocky Linux 8, 9, and 10 support (plus a legacy CentOS 7 path on the stable branch). StackAlign's current LEMP apply gate is EL9 x86_64 only. Do not expand StackAlign's OS matrix until each distribution/version has package, SELinux, systemd, Nginx, PHP-FPM, MariaDB, rollback, and CI acceptance coverage.

## Existing-module hazards to resolve before CLI wiring

- **TLS EAB secrets:** lib/tls.sh passes ZeroSSL EAB key material as command-line flags; the process arguments may be visible to other local users. Do not wire ZeroSSL DNS issuance until secrets are passed through a protected file descriptor or equivalent private channel. The module also needs integration tests for scheduler conflicts, certificate/key staging, snapshot rollback, and service reload.
- **Firewall lockout:** lib/firewall.sh renders an input chain with a default-drop policy. The apply helper validates with nft -c and atomically loads the table, but it does not itself provide a timed rollback. Do not expose an apply command without a tested revert timer, console recovery instructions, and remote lockout tests.
- **Backup confidentiality/recovery:** lib/backup.sh uses a MySQL defaults file and supports logical dump, physical MariaBackup, and rclone copy. It does not yet provide a complete encrypted backup format, integrity manifest, retention, restore verification, or tested disaster-recovery flow. Never put database passwords in command arguments.
- **Extension package drift:** lib/extensions.sh explicitly labels package names as assumptions. Resolve the package against the enabled repo and PHP ABI before install; do not claim an extension loaded merely because DNF installed a similarly named package.
- **Malware findings:** lib/security.sh queues ClamAV findings as advisory JSONL only. It intentionally does not quarantine/delete; preserve that boundary until a human-reviewed remediation workflow exists.
- **Tenant boundary:** a virtual host, separate document root, or Apache upstream is not a tenant security boundary. Do not expose shared hosting apply until the Unix identity, PHP-FPM pool/socket, filesystem, process, resource, and service controls are adversarially tested.

## Priority order

### P0 — close safety and lifecycle foundations
- Wire the existing TLS module into a tested CLI workflow.
- Wire backup and restore with authenticated/encrypted off-host backup, manifests, and restore verification.
- Finish configuration schema validation and persistence.
- Complete package update transaction preview, version pins, tested matrix, and release verifier integration.
- Implement tenant identity and PHP-FPM isolation before any shared-hosting apply path.
- Keep SELinux enforcing; avoid FTP daemon installation and avoid exposing database/admin services.

### P1 — hosting operations
- Site/vhost create/list/disable/remove with Nginx and optional Apache/hybrid backends.
- Database/user create/list/drop with least-privilege grants and secret-file handoff.
- WordPress deployment as an opt-in application profile, not a privileged root plugin installer.
- PHP runtime/extension compatibility and OPcache/Redis/Memcached management.
- Protected service status, logs, disk alerts, and per-site metrics.

### P2 — optional integrations
- PostgreSQL.
- Rclone/S3 and SSH-tunnel migration.
- FFmpeg/media tools, GeoIP, WP-CLI, Passenger, Node/Go/Ruby runtimes.
- Compression utilities and DKIM/mail-auth support.

Do not implement an upstream feature merely because Centmin Mod has a menu item. Each feature needs a supported OS/package policy, threat model, plan/apply contract, tests, recovery behavior, and a clear owner.

## Pinecone Neural harness integration

The ljrseals-dev/pinecone-neural main branch inspected for this comparison was v2.4. It had a critical mismatch between its security description and implementation: AgentHarness called eval/exec on model-generated Python with a restricted builtins dictionary; the separate Docker/gVisor sandbox helper was not used by that agent loop. The default .env.example also shipped demo API keys, and session IDs were not scoped to the authenticated API-key principal.

A separate hardening PR has been opened:

- [pinecone-neural PR #1 — Harden agent tools and session isolation](https://github.com/ljrseals-dev/pinecone-neural/pull/1)
- Branch: fix/structured-tool-execution
- Push CI run: PASS for the new tests and compile check.
- PR CI: passed on Ubuntu and AlmaLinux 9 (run #44035274780).
- Changes replace model-generated Python with registered JSON tools, validate tool schemas/timeouts, bound calculator arithmetic, scope sessions per API-key user, remove demo keys, and run the container as a non-root UID.

**Integration rule:** Pinecone is a planning/recommendation sidecar, not a privileged host-control plane. StackAlign must never give it root, a Docker socket, host filesystem mounts, or arbitrary shell/SQL tools. Initial integration is read-only: the harness may receive a sanitized doctor and repository inventory snapshot and return an operator-reviewed plan. Host changes remain in StackAlign's own explicit --apply workflows. Do not install/use the vulnerable upstream main revision as a host automation agent.

The StackAlign client in this branch is intentionally planning-only. A managed sidecar installer is deferred until the hardened harness PR is reviewed/merged and its runtime deployment contract is verified. Provider credentials must be supplied by the operator and never committed.

## Upstream references

- Centmin Mod menu: https://centminmod.com/menu
- Centmin Mod addons: https://centminmod.com/addons
- Centmin Mod getting started: https://centminmod.com/getstarted
- Centmin Mod PHP-FPM features: https://centminmod.com/phpfpm
- Centmin Mod source repository: https://github.com/centminmod/centminmod
- Active 141.00beta01 source branch: https://github.com/centminmod/centminmod/tree/141.00beta01
- Centmin Mod GPL-3.0 license: https://github.com/centminmod/centminmod/blob/master/license.txt
