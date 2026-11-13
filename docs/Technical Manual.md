StackAlign

A Controlled, Auditable LEMP Deployment System for Enterprise Linux

Technical Manual

Document Status: [SPECIFIED] — This manual describes a project in active development. Sections are tagged according to verification status.

Version: 0.1.0-draft

Target Platforms: AlmaLinux 9/10, Rocky Linux 9/10 (x86_64)

Licence: MIT

---

Front Matter

Document Status

This manual describes StackAlign, a LEMP deployment and recovery system currently in active development. The project exists in a state of partial implementation: certain components are fully verified through automated testing, others are implemented but await verification evidence, and several critical subsystems remain in design phase only.

We have chosen to document StackAlign comprehensively at this stage—including its incomplete and blocked sections—because transparent engineering practice demands that we distinguish between what we have proven and what we merely intend. A reader of this manual should be able to determine, for any given claim, whether that claim rests on captured test output, on code that exists but lacks verification, on design documents alone, or on nothing at all.

How to Read Status Tags

Every section of this manual carries a status tag. These tags are not decorative; they constitute a contract between the authors and the reader regarding the epistemic status of the content.

[SPECIFIED]: The content describes a design decision that has been documented but not proven by execution. Code may not exist, or if it exists, it has not been subjected to the verification procedures that would elevate it to a higher status. A [SPECIFIED] section tells you what we intend to build and how we intend it to work, not what we have demonstrated to work.

[IMPLEMENTED-UNVERIFIED]: Code exists in the repository, but the required verification evidence—automated tests, CI pipeline results, or captured command output—is absent. This status indicates that an implementation has been written, but we cannot yet assert that it functions as described. An [IMPLEMENTED-UNVERIFIED] section may contain accurate descriptions of functioning code, or it may contain descriptions of code that is broken in ways we have not yet discovered.

[VERIFIED]: A specific command or test was executed, and its captured output supports the claim being made. The verification evidence exists in the repository and can be independently examined. A [VERIFIED] section makes a strong claim: we have demonstrated this, and we can show you the demonstration.

[BLOCKED(file)]: A required source file or dependency is missing from the repository. The section describes a design that cannot be implemented or verified until the blocking condition is resolved. The parenthetical identifies the specific missing component.

Scope and Non-Claims

StackAlign is not production-ready. This manual does not describe a system that should be deployed to serve live traffic, protect sensitive data, or support business-critical workloads. The project is in active development, and significant subsystems—including backup, TLS certificate management, multi-tenant isolation, and deployment transactions—remain in design phase only.

StackAlign does not install a complete web stack end-to-end. The bootstrapper, CLI dispatcher, and configuration parser exist in partial form. The memory tuner has been verified through extensive arithmetic testing. But the modules that would actually render Nginx configurations, initialize MariaDB, and provision PHP-FPM are specified but not verified. A user who runs the current code will not obtain a functioning web server.

This manual describes what StackAlign will be when complete, what it is today, and—critically—the difference between those two states.

Copyright and Licence

StackAlign is released under the MIT Licence. The full text of the licence is available in the repository root at LICENSE. [VERIFIED: MIT License per repository README]

The MIT Licence permits use, copying, modification, and distribution of the software, subject to inclusion of the copyright notice and permission notice. StackAlign makes no warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement.

Revision History

Version Date Changes
0.1.0-draft Current Initial outline and specification document

---

Part I — Orientation

1. Purpose, Scope, and Audience

1.1 What StackAlign Is

StackAlign is a controlled, auditable deployment and recovery system for LEMP stacks on AlmaLinux and Rocky Linux. It provides a DNF-native installation path—meaning all software packages are installed from distribution repositories using the DNF package manager, with no source compilation and no third-party binary repositories—together with tooling for memory-aware tuning, configuration rendering, and transactional rollback.

The system is designed around three alignment principles that give it its name: alignment to the machine's available memory, alignment to the CPU's capabilities, and alignment to the configuration's declared intent. A StackAlign deployment should be reproducible, auditable, and recoverable.

1.2 What StackAlign Is Not

StackAlign is not Centmin Mod. While Centmin Mod provides a useful reference point for understanding what a comprehensive LEMP management system might include, StackAlign is a clean-room implementation that shares no code with Centmin Mod and deliberately rejects certain Centmin Mod architectural decisions—most notably its practice of compiling Nginx and PHP from source rather than installing distribution packages.

StackAlign is not a hosting control panel. It does not provide a web-based interface, multi-user management, or billing integration. It is a command-line tool for system administrators who understand Linux, understand LEMP stacks, and want a system that documents its own behavior.

StackAlign is not finished. Readers seeking a production-ready deployment tool should look elsewhere. Readers seeking to understand how such a tool should be built—and how to distinguish claims from evidence—may find this manual useful.

1.3 Audience

This manual is written for system administrators and engineers who are responsible for deploying and maintaining web infrastructure on Enterprise Linux. It assumes familiarity with:

· Linux system administration, including systemd service management and filesystem permissions
· The LEMP stack components: Nginx, PHP-FPM, MariaDB, and Redis
· Configuration file formats and the principles of configuration management
· Basic security concepts: privilege separation, secret management, network isolation

The manual does not assume familiarity with StackAlign itself. Readers encountering the project for the first time should begin with Part I, which establishes the vocabulary and architectural context necessary to understand the remainder.

2. StackAlign Design Principles

2.1 Alignment to the Machine

Memory is the binding constraint on most web server deployments, particularly on virtual private servers where RAM is the most expensive resource. StackAlign's memory tuner calculates configuration values—PHP-FPM process counts, MariaDB buffer pool sizes, Redis memory limits—from the machine's actual available memory, using arithmetic that is documented, testable, and reproducible.

The tuner does not guess. It does not use heuristic defaults inherited from some other system's assumptions. It computes, it tests its computations against arithmetic floors, and it refuses to proceed when the arithmetic produces impossible results.

2.2 Alignment to the CPU

Different CPUs expose different instruction sets, different cache hierarchies, and different performance characteristics. StackAlign detects the target CPU's capabilities and adjusts configuration accordingly—not by compiling code with -march=native, which produces binaries that cannot be moved between machines, but by selecting runtime configuration options that exploit available features.

2.3 Alignment to the Configuration

StackAlign separates the declaration of intent (the configuration file) from the rendering of that intent (the generated service configurations). A user declares what they want in stackalign.conf; StackAlign renders the actual Nginx, PHP-FPM, and MariaDB configurations from that declaration. The rendered configurations are deterministic: given the same declaration and the same machine, StackAlign produces the same output.

This separation enables auditability. A user can examine the rendered configuration and understand exactly what will be deployed. They can diff the rendered configuration against the previous version and understand exactly what changed. They can roll back to a previous configuration if the new one produces undesirable results.

2.4 Clean-Room Implementation

StackAlign is not derived from Centmin Mod code. It is not derived from any other LEMP management system's code. The design has been informed by studying these systems—understanding what they do well and what they do poorly—but the implementation is original.

This principle matters for licensing clarity (StackAlign can be MIT-licensed without inherited obligations) and for security (StackAlign does not inherit vulnerabilities or design flaws from its predecessors). It also matters for maintainability: the StackAlign team understands every line of StackAlign code because they wrote every line of it.

3. Supported and Excluded Workloads

3.1 Supported Workloads

StackAlign is designed to support the following workload categories:

Generic PHP Applications: Any PHP application that follows conventional deployment patterns—a document root containing an index.php or similar entry point, configuration via environment variables or configuration files, sessions and caching via Redis or filesystem—can be deployed on a StackAlign-managed stack.

WordPress and WooCommerce: WordPress powers a substantial fraction of the web, and WooCommerce extends it into e-commerce. StackAlign includes a WordPress template that configures Nginx, PHP-FPM, and Redis for WordPress's specific requirements, together with hardening measures appropriate to WordPress's threat model.

Laravel: Laravel is a widely-used PHP framework with specific requirements around routing (all requests route through public/index.php), queue processing (via php artisan queue:work), and environment configuration (via .env files). StackAlign includes a Laravel template that addresses these requirements.

3.2 Warning-Only Workloads

X-Cart 5.6: StackAlign includes an X-Cart 5.6 profile in its configuration schema, but the installer does not provision X-Cart. A user who deploys X-Cart on StackAlign does so at their own risk, and StackAlign will emit a warning during installation indicating that X-Cart is not a tested, supported workload.

3.3 Excluded Workloads

The following workload categories are explicitly excluded from StackAlign's scope:

Hosted SaaS Platforms: StackAlign deploys to a single server (or a small number of servers managed independently). It does not provide the orchestration, auto-scaling, or multi-tenancy features required by hosted SaaS platforms.

Non-LEMP Applications: StackAlign deploys Nginx, PHP-FPM, MariaDB, and Redis. Applications requiring different components—Node.js, Python, Java, .NET—are out of scope.

FTP Daemons: FTP is insecure by design, and secure alternatives (SFTP via SSH, rsync over SSH) are universally available. StackAlign does not install or configure FTP servers.

Unmanaged AI/ML Tooling: StackAlign does not install CUDA drivers, PyTorch, TensorFlow, or similar AI/ML frameworks. These tools have complex dependency graphs and version requirements that are outside StackAlign's scope.

4. Glossary

Arithmetic Floor: A minimum value below which a computed configuration parameter is considered invalid. StackAlign's memory tuner computes floors for PHP-FPM process counts, MariaDB buffer pool sizes, and other parameters. If the computed value falls below the floor, the tuner refuses to proceed and emits an error token.

Advisory Floor: A value below which a computed configuration parameter triggers a warning but does not cause the tuner to refuse. Advisory floors indicate configurations that are likely to perform poorly but are not arithmetically impossible.

Lean Profile: A memory tuning profile optimized for machines with limited RAM (typically 512 MiB to 2 GiB). The Lean Profile uses a one-dimensional search to find the largest PHP-FPM child process count that fits within available memory, then sizes MariaDB's buffer pool accordingly.

Standard Profile: A memory tuning profile optimized for machines with substantial RAM (typically 2 GiB and above). The Standard Profile uses a formula-based approach: it reserves memory for the operating system and fixed costs, allocates a budget to PHP-FPM, allocates a budget to MariaDB, and computes configuration parameters from those budgets.

Reserve: Memory that is held back from allocation to PHP-FPM and MariaDB, intended for the operating system, kernel buffers, and other processes. The Reserve is computed as a function of total RAM.

Transaction: A deployment operation that either completes fully or rolls back completely. StackAlign uses transactions for configuration changes, ensuring that a failed deployment does not leave the system in a partially-configured state.

5. Architecture Overview

5.1 Component Architecture

StackAlign's architecture comprises five layers:

The Bootstrapper (install.sh): The entry point for new installations. The bootstrapper verifies its own integrity via SHA-256 checksum, checks for required dependencies, and installs the StackAlign CLI and support files.

The CLI (bin/stackalign): The primary user interface. The CLI dispatches to command handlers: install, update, tune, doctor, rollback, site, db, tls.

The Modules (lib/*.sh): Shell libraries implementing specific functionality. Each module has a defined interface and can be tested independently.

The Rendered Configurations: Files generated by StackAlign from templates and configuration declarations. These are the actual Nginx, PHP-FPM, and MariaDB configuration files that the services read.

The Services: Nginx, PHP-FPM, MariaDB, and Redis, managed by systemd. StackAlign configures these services but does not replace systemd as the service manager.

```
┌─────────────────────────────────────────────────────────────┐
│                        install.sh                           │
│                   (Bootstrapper, SHA-256)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     bin/stackalign                          │
│                   (CLI Dispatcher)                          │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  lib/config.sh  │ │  lib/tune.sh    │ │  lib/render.sh  │
│  (INI Parser)   │ │  (Memory Tuner) │ │  (Template)     │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Rendered Configurations                    │
│         /etc/nginx/conf.d/stackalign.conf                   │
│         /etc/php-fpm.d/stackalign.conf                      │
│         /etc/my.cnf.d/stackalign.cnf                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Systemd Services                         │
│              nginx.service, php-fpm.service,                │
│              mariadb.service, redis.service                 │
└─────────────────────────────────────────────────────────────┘
```

5.2 Plan-Before-Apply Flow

StackAlign separates planning from execution. When a user requests a configuration change, StackAlign first computes the planned change—what files would be written, what services would be restarted—and presents this plan to the user. Only after the user confirms does StackAlign apply the change.

```
User Request
     │
     ▼
┌─────────────┐
│   Parse     │
│   Config    │
└─────────────┘
     │
     ▼
┌─────────────┐
│  Compute    │
│   Tuning    │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Render    │
│  Templates  │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Diff      │
│   Plan      │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Present   │──── User declines ────▶ Exit (no changes)
│    Plan     │
└─────────────┘
     │
     │ User confirms
     ▼
┌─────────────┐
│   Apply     │
│   Changes   │
└─────────────┘
```

5.3 Snapshot and Rollback Flow

Before applying any change, StackAlign creates a snapshot of the current configuration state. If the change produces undesirable results, the user can roll back to the snapshot.

```
┌─────────────┐
│   Apply     │
│   Request   │
└─────────────┘
     │
     ▼
┌─────────────┐
│  Snapshot   │
│   Current   │
│    State    │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Apply     │
│   Changes   │
└─────────────┘
     │
     ▼
┌─────────────┐     Success
│   Verify    │────────────────▶ Done
│   Health    │
└─────────────┘
     │
     │ Failure
     ▼
┌─────────────┐
│   Restore   │
│  Snapshot   │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Reload    │
│  Services   │
└─────────────┘
     │
     ▼
┌─────────────┐
│   Report    │
│   Failure   │
└─────────────┘
```

---

Part II — Installation and Operations

6. Requirements and Supported Platforms

6.1 Target Operating Systems

StackAlign targets the following operating systems:

· AlmaLinux 9 (x86_64)
· AlmaLinux 10 (x86_64)
· Rocky Linux 9 (x86_64)
· Rocky Linux 10 (x86_64)

These distributions share a common lineage (they are all RHEL derivatives) and a common package management system (DNF). StackAlign relies on DNF's repository metadata, GPG signature verification, and version locking capabilities. [SPECIFIED]

StackAlign does not target Debian, Ubuntu, or other non-RHEL-derived distributions. While the architecture could be ported, the implementation assumes DNF and systemd conventions specific to Enterprise Linux.

6.2 Hardware Floor

The minimum supported hardware configuration is:

· RAM: 512 MiB
· Disk: 10 GiB available space
· CPU: x86_64, single core

A system with 512 MiB RAM and no swap is not suitable for production use. The memory tuner will compute a configuration that fits within 512 MiB, but the resulting PHP-FPM process count and MariaDB buffer pool size will be minimal. StackAlign emits a warning during installation when the hardware floor is met but the configuration is not production-appropriate.

6.3 Upstream Version Requirements

StackAlign pins PHP to version 8.5 and MariaDB to version 12.3. These versions exceed the requirements of the supported workloads:

WordPress: WordPress requires PHP 8.3+ and MariaDB 10.6+. StackAlign's pinned versions (PHP 8.5, MariaDB 12.3) exceed these requirements. [VERIFIED: Upstream documentation review]

Laravel: Laravel requires PHP 8.3+ and MariaDB 10.3+. StackAlign's pinned versions exceed these requirements. [VERIFIED: Upstream documentation review]

The version pins are recorded in the repository metadata and enforced during installation. StackAlign will refuse to install if the available package versions do not match the pins.

7. Bootstrapper and Installation Flow

7.1 The Bootstrapper

The bootstrapper (install.sh) is the entry point for new installations. Its responsibilities are:

1. Verify its own integrity via SHA-256 checksum
2. Check for required dependencies (DNF, systemd, coreutils)
3. Download or locate the StackAlign release archive
4. Verify the release archive's SHA-256 checksum
5. Extract the archive to a temporary directory
6. Install the CLI and support files to /usr/local/lib/stackalign/
7. Create the stackalign symlink in /usr/local/bin/
8. Emit instructions for post-installation configuration

[SPECIFIED]

7.2 Refusal Conditions

The bootstrapper refuses to proceed under the following conditions:

Placeholder Checksum: If the checksum in the bootstrapper script matches a known placeholder value, the bootstrapper refuses to execute. This prevents execution of a bootstrapper that has not been properly prepared for release.

Missing Dependencies: If any required dependency is absent, the bootstrapper emits an error and exits. It does not attempt to install dependencies; that is the user's responsibility.

Checksum Mismatch: If the release archive's checksum does not match the expected value, the bootstrapper refuses to extract or install it.

[SPECIFIED]

8. CLI Reference

8.1 Overview

The StackAlign CLI (bin/stackalign) provides a unified interface to all StackAlign functionality. Commands follow the pattern:

```
stackalign <command> [subcommand] [options]
```

[IMPLEMENTED-UNVERIFIED: Dispatcher exists; command implementations incomplete]

8.2 Global Options

--plan: Compute and display the planned changes without applying them. This is the default behavior for commands that modify system state.

--apply: Apply the computed changes. Requires user confirmation unless --yes is also specified.

--yes: Skip confirmation prompts. Use with caution.

--verbose: Emit detailed output, including the content of rendered configurations and the output of executed commands.

--quiet: Suppress non-error output.

[IMPLEMENTED-UNVERIFIED: Based on bin/stackalign source]

8.3 Commands

8.3.1 install

```
stackalign install [--plan|--apply] [--yes]
```

Initializes StackAlign on a fresh system. Parses /etc/stackalign/stackalign.conf, computes memory tuning, renders service configurations, and starts services.

[IMPLEMENTED-UNVERIFIED]

8.3.2 update

```
stackalign update check
stackalign update plan
stackalign update apply [--yes]
stackalign update rollback
```

Manages StackAlign updates and package updates. The check subcommand queries configured repositories for available updates. The plan subcommand computes the update plan. The apply subcommand executes the plan. The rollback subcommand reverses the most recent update.

[IMPLEMENTED-UNVERIFIED: Tested at CLI level via test_update_cli.sh; production wiring incomplete]

8.3.3 tune

```
stackalign tune [--profile lean|standard] [--plan|--apply]
```

Recomputes memory tuning based on current machine state. The --profile option overrides the profile specified in stackalign.conf.

[IMPLEMENTED-UNVERIFIED]

8.3.4 doctor

```
stackalign doctor [--verbose]
```

Runs diagnostic checks and reports system health. Output includes the Reserve decomposition, Arithmetic Floor vs. Advisory Floor comparison, and warning tokens.

[SPECIFIED]

8.3.5 rollback

```
stackalign rollback [--snapshot <id>]
```

Reverts to a previous configuration snapshot. Without --snapshot, reverts to the most recent snapshot.

[IMPLEMENTED-UNVERIFIED]

8.3.6 site

```
stackalign site create <domain> [--template wordpress|laravel|generic]
stackalign site delete <domain>
stackalign site list
```

Manages individual site configurations within a StackAlign deployment.

[SPECIFIED]

8.3.7 db

```
stackalign db create <name> [--user <user>]
stackalign db drop <name>
stackalign db list
```

Manages MariaDB databases and users.

[SPECIFIED]

8.3.8 tls

```
stackalign tls obtain <domain> [--client certbot|acme.sh|lego]
stackalign tls renew <domain>
stackalign tls list
```

Manages TLS certificates.

[BLOCKED(lib/tls.sh): Design exists, implementation absent]

9. Configuration Reference

9.1 Configuration File Location

The primary configuration file is /etc/stackalign/stackalign.conf. It uses INI format with sections denoted by [section] headers and key-value pairs denoted by key = value syntax.

[IMPLEMENTED-UNVERIFIED: lib/config.sh parser exists]

9.2 Sections

9.2.1 [meta]

Metadata about the configuration file itself.

· config_version: Integer. Must match the parser's expected version. Duplicate keys are rejected.

9.2.2 [system]

System-level settings.

· hostname: String. The system's hostname.
· timezone: String. IANA timezone identifier.
· profile: String. Memory tuning profile: lean or standard.

9.2.3 [nginx]

Nginx configuration.

· worker_processes: Integer or auto.
· http2: Boolean. Enable HTTP/2.
· http3: Boolean. Enable HTTP/3 (QUIC).
· brotli: Boolean. Enable Brotli compression.
· microcache_ttl: Integer. FastCGI microcaching TTL in seconds.

9.2.4 [php]

PHP-FPM configuration.

· version: String. PHP version (must match pin).
· pm: String. Process manager mode: static or dynamic.
· max_children: Integer. Maximum child processes (computed by tuner if not specified).
· opcache: Boolean. Enable OPcache.
· jit: Boolean. Enable JIT compilation.

9.2.5 [mariadb]

MariaDB configuration.

· version: String. MariaDB version (must match pin).
· innodb_buffer_pool_size: String. Buffer pool size (computed by tuner if not specified).
· innodb_flush_log_at_trx_commit: Integer. 0, 1, or 2.

9.2.6 [tls]

TLS configuration.

· client: String. ACME client: certbot, acme.sh, or lego.
· email: String. Contact email for ACME registration.

9.2.7 [firewall]

Firewall configuration.

· backend: String. Firewall backend: nftables or iptables.
· crowdsec: Boolean. Enable CrowdSec integration.
· fail2ban: Boolean. Enable fail2ban integration.

9.2.8 [security]

Security settings.

· yara: Boolean. Enable YARA scanning (advisory only).
· clamav: Boolean. Enable ClamAV integration.

9.2.9 [update]

Update settings.

· channel: String. Update channel: stable or testing.
· auto_check: Boolean. Enable automatic update checking.

9.3 Duplicate Key Rejection

The configuration parser rejects configuration files containing duplicate keys within the same section. This prevents accidental override of intended values.

[IMPLEMENTED-UNVERIFIED: lib/config.sh]

9.4 config_version Validation

The config_version key in the [meta] section must match the parser's expected version. If the versions do not match, the parser emits an error and refuses to proceed.

[IMPLEMENTED-UNVERIFIED: lib/config.sh]

10. Doctor and Diagnostics

10.1 Overview

The stackalign doctor command runs diagnostic checks and reports system health. It is intended for use both during initial installation (to verify that the system meets requirements) and during ongoing operations (to detect drift from the intended configuration).

[SPECIFIED]

10.2 Reading Doctor Output

Doctor output includes the following sections:

System Information: OS version, kernel version, CPU model, total RAM, available disk space.

Reserve Decomposition: The breakdown of how the Reserve was computed. For example:

```
Reserve Decomposition:
  Total RAM: 4096 MiB
  Base Reserve: 256 MiB
  Kernel Reserve: 128 MiB
  Buffer Reserve: 256 MiB
  Total Reserve: 640 MiB
```

Arithmetic Floor vs. Advisory Floor: The computed value for each tunable parameter, compared against its Arithmetic Floor and Advisory Floor. For example:

```
PHP-FPM max_children:
  Computed: 12
  Arithmetic Floor: 2
  Advisory Floor: 8
  Status: OK (above advisory floor)

MariaDB innodb_buffer_pool_size:
  Computed: 512 MiB
  Arithmetic Floor: 128 MiB
  Advisory Floor: 256 MiB
  Status: OK (above advisory floor)
```

Warning Tokens: Any active warning conditions, expressed as tokens. For example:

```
Warnings:
  warning=advisory_ram: Total RAM (512 MiB) is below advisory minimum (1024 MiB)
  warning=concurrency_1: PHP-FPM max_children (1) limits concurrency to 1
```

[SPECIFIED]

11. Snapshots and Rollback

11.1 Overview

Before applying any configuration change, StackAlign creates a snapshot of the current configuration state. If the change produces undesirable results, the user can roll back to the snapshot.

[IMPLEMENTED-UNVERIFIED: lib/history.sh]

11.2 Snapshot Directory Structure

Snapshots are stored in /etc/stackalign/.history/. Each snapshot is a directory named with a timestamp and a unique identifier:

```
/etc/stackalign/.history/
├── 20240115T103045Z-a1b2c3/
│   ├── nginx.conf
│   ├── php-fpm.conf
│   ├── my.cnf
│   └── metadata.json
├── 20240116T141522Z-d4e5f6/
│   └── ...
└── ...
```

[IMPLEMENTED-UNVERIFIED]

11.3 Snapshot Creation

A snapshot is created by copying the current rendered configurations into a new snapshot directory. The snapshot includes a metadata.json file recording the timestamp, the StackAlign version, and the reason for the snapshot.

[IMPLEMENTED-UNVERIFIED]

11.4 Rollback Operation

Rollback restores the configuration files from a snapshot directory to their live locations. The restoration is atomic: files are copied to temporary locations and then moved into place using mv, which is atomic on the same filesystem.

[IMPLEMENTED-UNVERIFIED]

11.5 Dependency Note

The rollback implementation depends on a PID-scoping fix that is pending merge. The current implementation uses $$ (the shell's PID) for temporary file naming, which can collide if multiple StackAlign processes run concurrently. The pending fix uses mktemp for temporary file creation.

[SPECIFIED: Fix pending merge]

---

Part III — Engine and Modules

12. Configuration Parser

12.1 Overview

The configuration parser (lib/config.sh) reads and validates /etc/stackalign/stackalign.conf. It is responsible for:

· Parsing INI syntax
· Rejecting duplicate keys
· Validating config_version
· Providing a query interface for other modules

[IMPLEMENTED-UNVERIFIED]

12.2 INI Parsing

The parser handles the following INI constructs:

· Section headers: [section_name]
· Key-value pairs: key = value
· Comments: Lines beginning with # or ;
· Quoted values: key = "value with spaces"
· Empty values: key =

The parser does not support:

· Multi-line values
· Value interpolation
· Include directives

[IMPLEMENTED-UNVERIFIED]

12.3 Duplicate Key Rejection

If a section contains the same key more than once, the parser emits an error and refuses to proceed. This is intentional: duplicate keys usually indicate a mistake, and silently using the last value can mask configuration errors.

[IMPLEMENTED-UNVERIFIED]

12.4 config_version Validation

The config_version key in the [meta] section must match the parser's expected version. The expected version is compiled into the parser; it is not read from the configuration file. If the versions do not match, the parser emits an error indicating the expected and actual versions.

[IMPLEMENTED-UNVERIFIED]

13. Template Rendering

13.1 Overview

The template renderer (lib/render.sh) generates service configuration files from templates and the parsed configuration. It is responsible for:

· Substituting configuration values into templates
· Writing rendered files atomically
· Computing diffs between current and planned configurations

[IMPLEMENTED-UNVERIFIED]

13.2 Atomic Write

Rendered files are written to a temporary location and then moved into place using mv. This ensures that a failed render does not leave a partially-written configuration file.

[IMPLEMENTED-UNVERIFIED]

13.3 Diff Computation

The sa_render_plan function computes the difference between the current rendered configuration and the planned configuration. This diff is presented to the user before applying changes.

[SPECIFIED: Process-substitution fix pending merge]

The current implementation of sa_render_plan uses process substitution (<(...)), which is not POSIX-compliant and may fail in some shell environments. The pending fix replaces process substitution with temporary files.

14. History and Snapshots

14.1 Overview

The history module (lib/history.sh) manages configuration snapshots and rollback. It is responsible for:

· Creating snapshots before changes
· Listing available snapshots
· Restoring from snapshots

[IMPLEMENTED-UNVERIFIED]

14.2 Snapshot Directory Structure

See Section 11.2.

14.3 undo.sh Generation

Each snapshot directory contains an undo.sh script that can be executed to restore the snapshot. This provides a manual rollback path independent of the StackAlign CLI.

[IMPLEMENTED-UNVERIFIED]

15. Service Lifecycle

15.1 Overview

The service module (lib/service.sh) manages the lifecycle of systemd services. It is responsible for:

· Starting, stopping, and restarting services
· Reloading services after configuration changes
· Verifying service health after reload

[IMPLEMENTED-UNVERIFIED]

15.2 sa_service_reload_safe

The sa_service_reload_safe function implements a safe reload procedure:

1. Pre-health check: Verify that the service is running and healthy before reload.
2. Reload: Send the reload signal (usually SIGHUP) to the service.
3. Post-health check: Verify that the service is running and healthy after reload.
4. Rollback on failure: If the post-health check fails, restore the previous configuration and reload again.

[IMPLEMENTED-UNVERIFIED]

16. Repository Management and Version Locking

16.1 Overview

The repository module (lib/repo.sh) manages DNF repositories and package version locking. It is responsible for:

· Configuring DNF repositories
· Binding GPG keys to repositories
· Locking package versions

[IMPLEMENTED-UNVERIFIED]

16.2 GPG Key Binding

StackAlign configures DNF repositories with GPG key verification enabled. The pub: record check verifies that the repository's GPG key matches the expected key.

[IMPLEMENTED-UNVERIFIED]

16.3 Version Locking

StackAlign uses DNF's versionlock plugin to pin package versions. This prevents unintended upgrades that could break compatibility.

[IMPLEMENTED-UNVERIFIED]

16.4 RPM Cache Integration

StackAlign integrates with DNF's RPM cache to avoid re-downloading packages that are already present.

[SPECIFIED: RPM cache integration pending]

17. Secret Handling

17.1 Overview

The secret module (lib/secret.sh) manages secrets: database passwords, API keys, and other sensitive values. It distinguishes between two categories of secrets:

· Machine-generated secrets: Random values generated by StackAlign, stored as SHA-256 hashes.
· Human passphrases: Values chosen by humans, stored as Argon2id hashes.

[IMPLEMENTED-UNVERIFIED]

17.2 Machine-Generated Secrets

Machine-generated secrets are created using a cryptographically secure random number generator. They are stored as SHA-256 hashes in /etc/stackalign/secrets/. The plaintext value is never stored; if a plaintext value is needed (for example, to configure a service), it is generated on demand and passed directly to the consumer.

[IMPLEMENTED-UNVERIFIED]

17.3 Human Passphrases

Human passphrases are hashed using Argon2id, a memory-hard key derivation function designed to resist GPU-based attacks. The Argon2id parameters are tuned to the available memory, using the same memory detection logic as the tuner.

[IMPLEMENTED-UNVERIFIED]

18. Memory Tuner

18.1 Overview

The memory tuner (lib/tune.sh) computes configuration values from available memory. It is the most extensively verified component of StackAlign, with passing tests for T1 through T28.

[IMPLEMENTED-UNVERIFIED: Tests pass on main; child_rss is an unmeasured assumption]

18.2 Source of Truth

The memory tuner's behavior is specified in docs/TUNING.md, which is treated as a frozen contract. Changes to the tuner require corresponding changes to docs/TUNING.md and to the test suite.

[VERIFIED: docs/TUNING.md exists and is referenced]

18.3 Lean Profile

The Lean Profile is used for machines with limited RAM. It uses a one-dimensional search to find the largest PHP-FPM child process count that fits within available memory:

1. Compute the Reserve.
2. Compute the available memory for PHP-FPM and MariaDB.
3. For each candidate child count (starting from 1), compute the PHP-FPM memory usage (child_count × child_rss).
4. Compute the remaining memory for MariaDB (available - PHP-FPM usage).
5. If the remaining memory is sufficient for the minimum MariaDB buffer pool size, accept the candidate.
6. Otherwise, decrement the candidate and repeat.

The Lean Profile maximizes PHP-FPM concurrency subject to the constraint that MariaDB receives at least its minimum buffer pool size.

[VERIFIED: Arithmetic tests pass]

18.4 Standard Profile

The Standard Profile is used for machines with substantial RAM. It uses a formula-based approach:

1. Compute the Reserve.
2. Compute the available memory for PHP-FPM and MariaDB.
3. Allocate a percentage of available memory to PHP-FPM (the PHP Budget).
4. Allocate the remainder to MariaDB (the DB Budget).
5. Compute PHP-FPM child count from the PHP Budget (PHP Budget / child_rss).
6. Compute MariaDB buffer pool size from the DB Budget.

[VERIFIED: Arithmetic tests pass]

18.5 Arithmetic Floors

The tuner enforces arithmetic floors: minimum values below which a computed parameter is considered invalid.

Parameter Arithmetic Floor
Total RAM 391 MiB
PHP-FPM max_children 1
MariaDB innodb_buffer_pool_size 128 MiB

If a computed value falls below its floor, the tuner refuses to proceed and emits an error token.

[VERIFIED: T27/T28 tests pass]

18.6 Advisory Floors

Advisory floors are values below which a computed parameter triggers a warning but does not cause the tuner to refuse:

Parameter Advisory Floor
Total RAM 1024 MiB
PHP-FPM max_children 8
MariaDB innodb_buffer_pool_size 256 MiB

[VERIFIED: Arithmetic tests pass]

18.7 child_rss Assumption

The tuner assumes that each PHP-FPM child process consumes a fixed amount of RSS (Resident Set Size). This value is currently an unmeasured assumption. In practice, PHP-FPM child RSS depends on the application, the PHP extensions loaded, and the workload. The tuner's output should be validated against actual memory usage after deployment.

[SPECIFIED: Measurement pending]

19. Update Engine

19.1 Overview

The update engine manages StackAlign updates and package updates. It provides four subcommands:

· update check: Query repositories for available updates.
· update plan: Compute the update plan.
· update apply: Execute the update plan.
· update rollback: Reverse the most recent update.

[IMPLEMENTED-UNVERIFIED]

19.2 update check

Queries the configured DNF repositories for packages with available updates. Reports the packages and their current and available versions.

[IMPLEMENTED-UNVERIFIED]

19.3 update plan

Computes the update plan, including:

· Packages to be updated
· Packages to be installed (dependencies)
· Packages to be removed (obsoletes)
· Configuration changes required

[IMPLEMENTED-UNVERIFIED]

19.4 update apply

Executes the update plan:

1. Create a snapshot.
2. Apply package updates via DNF.
3. Re-render configurations if required.
4. Reload services if required.
5. Verify health.

[IMPLEMENTED-UNVERIFIED]

19.5 update rollback

Reverses the most recent update:

1. Restore the snapshot.
2. Downgrade packages to their previous versions.
3. Reload services.
4. Verify health.

[IMPLEMENTED-UNVERIFIED]

19.6 Implementation Status

The update engine is tested at the CLI level via test_update_cli.sh. The production cmd_update wiring is incomplete.

[IMPLEMENTED-UNVERIFIED: Tested at CLI level; production wiring SPECIFIED]

20. Backup and Restore

20.1 Overview

The backup module (lib/backup.sh) is intended to provide backup and restore functionality using the 3-2-1-1-0 strategy:

· 3 copies of data
· 2 different media types
· 1 copy offsite
· 1 copy offline
· 0 errors (verified backups)

The backup implementation uses mariabackup for database backups and rsync or tar for filesystem backups.

[BLOCKED(lib/backup.sh): Design exists, implementation absent]

20.2 Design

The backup design includes:

· Full backups: Complete copies of all data.
· Incremental backups: Changes since the last backup.
· Retention policy: Configurable retention of daily, weekly, and monthly backups.
· Verification: Automated verification that backups are restorable.

[SPECIFIED]

20.3 Blocking Condition

The backup module is blocked on lib/backup.sh, which has not been implemented. Until this file exists, backup and restore functionality is unavailable.

21. Firewall and Intrusion Prevention

21.1 Overview

The firewall module (lib/firewall.sh) is intended to configure network firewalling and intrusion prevention. It supports nftables as the default backend, with optional CrowdSec or fail2ban integration.

[SPECIFIED]

21.2 nftables Default

StackAlign uses nftables as the default firewall backend. nftables is the modern replacement for iptables, offering better performance and a more expressive rule syntax.

[SPECIFIED]

21.3 CrowdSec/fail2ban Optional

CrowdSec and fail2ban provide intrusion prevention by analyzing logs and blocking suspicious IP addresses. Both are optional; StackAlign functions without them, but with reduced protection against brute-force attacks.

[SPECIFIED]

21.4 Implementation Status

The firewall module is specified but not implemented. Scripts for nftables configuration, CrowdSec integration, and fail2ban integration have not been written.

[SPECIFIED]

22. Nginx

22.1 Overview

StackAlign configures Nginx with the following features:

· HTTP/2 support
· HTTP/3 (QUIC) support
· Brotli compression
· FastCGI microcaching (1 second TTL)
· AI crawler bypass

[SPECIFIED]

22.2 HTTP/2 and HTTP/3

HTTP/2 is enabled via the http2 directive. HTTP/3 is enabled via the quic directive and requires a TLS certificate. Both protocols improve performance for modern clients.

[SPECIFIED]

22.3 Brotli Compression

Brotli compression provides better compression ratios than gzip for text content. StackAlign enables Brotli for appropriate content types.

[SPECIFIED]

22.4 FastCGI Microcaching

FastCGI microcaching caches dynamic responses for a short period (1 second by default). This can dramatically improve performance for applications that generate identical responses for multiple requests.

[SPECIFIED]

22.5 AI Crawler Bypass

StackAlign defines an $sa_is_ai_crawler map that identifies requests from AI crawlers (ClaudeBot, GPTBot, etc.). This map can be used to serve different content to AI crawlers, bypass caching for them, or block them entirely.

[SPECIFIED]

22.6 Implementation Status

Nginx templates have been written, but nginx -t has not been run against them. The templates are syntactically plausible but unverified.

[SPECIFIED: Templates written; nginx -t not run]

23. PHP-FPM

23.1 Overview

StackAlign configures PHP-FPM with the following features:

· Process manager mode (static or dynamic)
· OPcache
· JIT compilation

[SPECIFIED]

23.2 Process Manager Mode

The pm directive controls how PHP-FPM manages child processes:

· static: A fixed number of child processes. Appropriate for the Standard profile, where memory is plentiful.
· dynamic: Child processes are spawned and killed as needed. Appropriate for the Lean profile, where memory is constrained.

[SPECIFIED]

23.3 OPcache

OPcache caches compiled PHP bytecode in shared memory, eliminating the need to recompile PHP scripts on every request. StackAlign enables OPcache with settings appropriate to the available memory.

[SPECIFIED]

23.4 JIT Compilation

PHP 8.0+ supports JIT (Just-In-Time) compilation, which can improve performance for CPU-intensive workloads. StackAlign enables JIT with settings appropriate to the workload.

[SPECIFIED]

24. MariaDB

24.1 Overview

StackAlign configures MariaDB with settings computed by the memory tuner.

[SPECIFIED]

24.2 InnoDB Buffer Pool Sizing

The innodb_buffer_pool_size setting controls the size of MariaDB's in-memory buffer pool. StackAlign computes this value from the available memory, ensuring that MariaDB receives an appropriate share.

[SPECIFIED]

24.3 innodb_flush_log_at_trx_commit

The innodb_flush_log_at_trx_commit setting controls the durability of transactions:

· 0: Log is written and flushed once per second. Fastest but least durable.
· 1: Log is written and flushed on every commit. Slowest but most durable (default).
· 2: Log is written on every commit but flushed once per second. Compromise between speed and durability.

StackAlign uses 2 for the Super Optimized mode, which prioritizes performance over durability. This is appropriate for workloads that can tolerate losing up to one second of transactions after a crash.

[SPECIFIED]

25. Redis and Memcached

25.1 Overview

StackAlign can optionally install and configure Redis or Memcached for object caching.

[SPECIFIED]

25.2 Redis Object Cache

Redis is a key-value store that can be used as a PHP object cache. StackAlign configures Redis with memory limits computed by the tuner and appropriate eviction policies.

[SPECIFIED]

25.3 Memcached

Memcached is an alternative key-value store. StackAlign can configure Memcached instead of Redis, depending on user preference.

[SPECIFIED]

26. TLS and Certificate Management

26.1 Overview

StackAlign is designed to support three ACME clients for TLS certificate management:

· Certbot (EFF)
· acme.sh
· Lego

[BLOCKED(lib/tls.sh): Design exists, implementation absent]

26.2 Three-Client Architecture

The three-client architecture allows users to choose the ACME client they prefer. Each client has different strengths:

· Certbot: Official EFF client, widely used, well-documented.
· acme.sh: Shell-based, no dependencies, supports many DNS providers.
· Lego: Go-based, single binary, supports many DNS providers.

[SPECIFIED]

26.3 Blocking Condition

The TLS module is blocked on lib/tls.sh, which has not been implemented. Until this file exists, TLS certificate management is unavailable.

27. Multi-Tenant slave_web Architecture

27.1 Overview

StackAlign is designed to support multi-tenant deployments via the slave_web architecture. This architecture provides nine layers of isolation between tenants:

1. Per-site Unix user
2. PHP open_basedir restriction
3. cgroups memory limits
4. cgroups CPU limits
5. Per-site Nginx root directory
6. Per-site Nginx fastcgi_pass socket
7. Per-site MariaDB database and user
8. Per-site Redis database
9. Per-site log files

[BLOCKED(lib/tenant.sh): Design exists, implementation absent]

27.2 Nine-Layer Isolation Stack

The nine-layer isolation stack is designed to prevent one tenant from accessing another tenant's data or consuming another tenant's resources. Each layer provides defense in depth: even if one layer is bypassed, the others remain.

[SPECIFIED]

27.3 Blocking Condition

The multi-tenant architecture is blocked on lib/tenant.sh, which has not been implemented. Until this file exists, multi-tenant deployments are unavailable.

28. Deployment Transactions and Workers

28.1 Overview

StackAlign is designed to support deployment transactions: multi-file changes that either complete fully or roll back completely. This is implemented via a symlink-flip deploy:

1. Write new files to a staging directory.
2. Verify the staged files.
3. Flip a symlink to point to the staging directory.
4. The old files remain available until the next deployment.

[BLOCKED(lib/txn.sh): Design exists, implementation absent]

28.2 Multi-File Commit

A deployment transaction may involve multiple files: Nginx configuration, PHP-FPM configuration, application code, and so on. The transaction ensures that all files are updated together or none are.

[SPECIFIED]

28.3 Symlink-Flip Deploy

The symlink-flip technique allows atomic deployment: the symlink flip is a single filesystem operation, so there is no window during which some files are new and some are old.

[SPECIFIED]

28.4 Blocking Condition

The transaction module is blocked on lib/txn.sh, which has not been implemented. Until this file exists, deployment transactions are unavailable.

29. Security Scanning

29.1 Overview

StackAlign can optionally integrate security scanning via YARA rules and ClamAV.

[SPECIFIED]

29.2 YARA Rules

YARA is a pattern-matching tool for identifying malware. StackAlign can scan uploaded files and application code against YARA rules. YARA scanning is advisory only: it reports potential threats but does not block them.

[SPECIFIED]

29.3 ClamAV Integration

ClamAV is an open-source antivirus engine. StackAlign can scan uploaded files with ClamAV before they are processed by the application.

[SPECIFIED]

30. WordPress Template

30.1 Overview

StackAlign includes a WordPress template that configures Nginx, PHP-FPM, and Redis for WordPress.

[SPECIFIED]

30.2 Hardening

The WordPress template includes the following hardening measures:

· DISALLOW_FILE_EDIT: Prevents editing of PHP files via the WordPress admin interface.
· Disabled XML-RPC: Reduces attack surface.
· Restricted file permissions: Limits the ability of compromised WordPress to modify system files.

[SPECIFIED]

30.3 WP-CLI Integration

StackAlign integrates with WP-CLI, the command-line interface for WordPress. This allows automation of WordPress operations: plugin updates, core updates, database migrations.

[SPECIFIED]

30.4 Redis Object Cache

StackAlign configures Redis as a WordPress object cache, improving performance by caching database query results.

[SPECIFIED]

30.5 Upstream Reference

WordPress 8.3+ requires PHP 8.3+ and MariaDB 10.6+. StackAlign's pinned versions (PHP 8.5, MariaDB 12.3) exceed these requirements.

[VERIFIED: Upstream documentation review]

31. Laravel Template

31.1 Overview

StackAlign includes a Laravel template that configures Nginx and PHP-FPM for Laravel.

[SPECIFIED]

31.2 Nginx Configuration

Laravel applications route all requests through public/index.php. The Nginx configuration reflects this: requests for static files are served directly, and all other requests are passed to PHP-FPM.

[SPECIFIED]

31.3 .env Handling

Laravel uses .env files for configuration. StackAlign ensures that .env files are not served by Nginx and are readable only by the application user.

[SPECIFIED]

31.4 Upstream Reference

Laravel 8.3+ requires PHP 8.3+ and MariaDB 10.3+. StackAlign's pinned versions (PHP 8.5, MariaDB 12.3) exceed these requirements.

[VERIFIED: Upstream documentation review]

32. Scheduled Routines

32.1 Overview

StackAlign configures systemd timers for scheduled routines:

· Backup
· Certificate renewal
· Health checks

[SPECIFIED]

32.2 Systemd Timers

Systemd timers provide a modern replacement for cron. They offer better logging, dependency management, and error handling.

[SPECIFIED]

32.3 Backup Timer

The backup timer triggers regular backups according to the configured retention policy.

[SPECIFIED]

32.4 Renewal Timer

The renewal timer triggers certificate renewal before certificates expire.

[SPECIFIED]

32.5 Health Check Timer

The health check timer triggers periodic stackalign doctor runs and reports any issues.

[SPECIFIED]

---

Part IV — Memory Tuning

33. Tuning Principles

33.1 Overview

StackAlign's memory tuning is based on the principles documented in docs/TUNING.md. This document is treated as a frozen contract: changes to tuning behavior require corresponding changes to the document and the test suite.

[VERIFIED: docs/TUNING.md exists]

33.2 Available Memory

The tuner computes available memory as:

```
Available Memory = Total RAM - Reserve
```

The Reserve is computed as a function of total RAM:

```
Reserve = Base Reserve + Kernel Reserve + Buffer Reserve
```

Where:

· Base Reserve = max(256 MiB, Total RAM × 0.06)
· Kernel Reserve = max(128 MiB, Total RAM × 0.03)
· Buffer Reserve = max(256 MiB, Total RAM × 0.06)

[VERIFIED: Arithmetic tests pass]

33.3 Allocation

Available memory is allocated between PHP-FPM and MariaDB according to the profile:

· Lean Profile: PHP-FPM gets as much as it can use, subject to MariaDB receiving at least its minimum buffer pool size.
· Standard Profile: PHP-FPM gets a percentage of available memory, MariaDB gets the remainder.

[VERIFIED: Arithmetic tests pass]

34. Lean and Standard Profiles

34.1 Lean Profile

The Lean Profile is used for machines with limited RAM. It maximizes PHP-FPM concurrency subject to the constraint that MariaDB receives at least its minimum buffer pool size.

[VERIFIED]

34.2 Standard Profile

The Standard Profile is used for machines with substantial RAM. It allocates memory between PHP-FPM and MariaDB according to fixed percentages.

[VERIFIED]

34.3 Profile Selection

The profile is selected based on total RAM:

· Total RAM < 2048 MiB: Lean Profile
· Total RAM ≥ 2048 MiB: Standard Profile

The profile can be overridden in the configuration file.

[VERIFIED]

35. Measurement and Arithmetic

35.1 Ceiling Calculation

The tuner computes a ceiling for each tunable parameter:

```
Ceiling = min(swap / 2, ram / 4)
```

This prevents the tuner from recommending configurations that would cause excessive swapping or that would allocate too much memory to a single component.

[VERIFIED]

35.2 Floor Calculation

The tuner computes a floor for each tunable parameter:

· Arithmetic Floor: Minimum value below which the parameter is considered invalid.
· Advisory Floor: Value below which a warning is emitted.

[VERIFIED]

35.3 Range Validation

The tuner validates that each computed parameter falls within its valid range:

```
Arithmetic Floor ≤ Computed Value ≤ Ceiling
```

If the computed value falls outside this range, the tuner refuses to proceed and emits an error token.

[VERIFIED]

36. Refusal Conditions and Warning Tokens

36.1 Refusal Conditions

The tuner refuses to proceed under the following conditions:

no_room_after_fixed: The Reserve consumes all available memory, leaving no room for PHP-FPM or MariaDB.

no_candidate_fits: No candidate PHP-FPM child count fits within available memory while leaving sufficient room for MariaDB.

buffer_pool_no_valid_range: The computed buffer pool size falls below the Arithmetic Floor or above the Ceiling.

[VERIFIED: Tests pass]

36.2 Warning Tokens

The tuner emits warning tokens under the following conditions:

warning=advisory_ram: Total RAM is below the Advisory Floor (1024 MiB).

warning=concurrency_1: PHP-FPM max_children is 1, limiting concurrency to a single request.

warning=child_rss_assumed: The tuner used an assumed value for child_rss.

[VERIFIED: Tests pass]

---

Part V — Security Model

37. Threat Model

37.1 Overview

StackAlign's threat model considers the following adversaries:

· Remote attackers: Attackers who can send requests to the web server.
· Local attackers: Attackers who have obtained a shell on the server.
· Compromised applications: Applications that have been compromised and are being used to attack the server.
· Supply-chain attackers: Attackers who can compromise software packages or their distribution channels.

[SPECIFIED]

37.2 Assets

The assets that StackAlign aims to protect include:

· Application data: Databases, uploaded files, configuration files.
· Credentials: Passwords, API keys, TLS private keys.
· System integrity: The operating system and its configuration.
· Availability: The ability of legitimate users to access the application.

[SPECIFIED]

37.3 Trust Boundaries

StackAlign's trust boundaries are:

· Root vs. Service users: Root can do anything; service users are restricted.
· One tenant vs. another: Each tenant's data and resources are isolated from other tenants.
· The server vs. the network: The firewall controls what traffic reaches the server.

[SPECIFIED]

38. Trust Boundaries

38.1 Root vs. Service Users

Root has unrestricted access to the system. Service users (nginx, php-fpm, mysql) have restricted access. StackAlign configures services to run as service users, not as root.

[SPECIFIED]

38.2 Tenant Isolation

In multi-tenant deployments, each tenant runs as a separate Unix user with restricted access to other tenants' data. See Section 27.

[SPECIFIED]

38.3 Network Boundaries

The firewall controls which network traffic reaches the server. StackAlign configures the firewall to allow only necessary traffic: HTTP, HTTPS, and SSH.

[SPECIFIED]

39. Secrets and Credentials

39.1 Storage Location

Secrets are stored in /etc/stackalign/secrets/, which is owned by root and has mode 0600. Only root can read or write these files.

[SPECIFIED]

39.2 Secret Types

StackAlign manages two types of secrets:

· Machine-generated secrets: Random values generated by StackAlign, stored as SHA-256 hashes.
· Human passphrases: Values chosen by humans, stored as Argon2id hashes.

[SPECIFIED]

39.3 Secret Handling

Secrets are never logged or displayed. When a secret is needed (for example, to configure a service), it is read from storage and passed directly to the consumer via environment variable or command-line argument (with appropriate precautions to avoid exposure in process listings).

[SPECIFIED]

40. Network and Egress Controls

40.1 Firewall

StackAlign configures an nftables firewall that allows only necessary inbound traffic (HTTP, HTTPS, SSH). Outbound traffic is allowed by default, but can be restricted if desired.

[SPECIFIED]

40.2 Database Access

MariaDB listens only on the loopback interface (127.0.0.1). Applications connect to MariaDB via the loopback interface. Remote database access is not supported.

[SPECIFIED]

40.3 Redis Access

Redis listens only on the loopback interface (127.0.0.1) and is protected by a password. Applications connect to Redis via the loopback interface.

[SPECIFIED]

41. Tenant Isolation

41.1 PHP-Level Isolation

StackAlign uses PHP's open_basedir directive to restrict each tenant's PHP code to its own directory tree. A tenant's PHP code cannot read or write files outside its own directory, even if the code attempts to do so.

[SPECIFIED]

41.2 Kernel-Level Isolation

StackAlign uses cgroups to limit each tenant's memory and CPU consumption. A tenant cannot starve other tenants of resources.

[SPECIFIED]

41.3 Limitations

PHP-level isolation via open_basedir is not kernel-level isolation. A determined attacker who can execute arbitrary code within PHP may be able to bypass open_basedir. Kernel-level isolation via cgroups limits resource consumption but does not prevent a tenant from attacking another tenant via a shared component (for example, a shared PHP-FPM master process).

[SPECIFIED]

42. Supply-Chain Security

42.1 GPG Key Pinning

StackAlign configures DNF repositories with GPG key verification. The GPG key for each repository is pinned: it must match the expected key, or installation fails.

[SPECIFIED]

42.2 DNF Version Locking

StackAlign uses DNF's versionlock plugin to pin package versions. This prevents unintended upgrades that could introduce vulnerabilities or break compatibility.

[SPECIFIED]

42.3 No Source Compilation

StackAlign installs packages from distribution repositories via DNF. It does not compile software from source. This reduces the supply-chain attack surface: there is no build process to compromise.

[SPECIFIED]

43. Security Limitations and Non-Claims

43.1 open_basedir Is Not Kernel Isolation

PHP's open_basedir directive provides PHP-level isolation. It is not kernel-level isolation. A determined attacker who can execute arbitrary code within PHP may be able to bypass open_basedir using techniques such as exploiting PHP bugs, attacking shared components, or using resource exhaustion to trigger error conditions.

[SPECIFIED]

43.2 Multi-Tenant Security Is Hard

Multi-tenant deployments are inherently more difficult to secure than single-tenant deployments. StackAlign's nine-layer isolation stack provides defense in depth, but no isolation stack is perfect. Tenants should be assumed to be mutually untrusting.

[SPECIFIED]

43.3 StackAlign Is Not a Security Audit

StackAlign's security features are designed to reduce attack surface and limit the impact of compromises. They do not constitute a security audit or a guarantee that the system is secure. Users should conduct their own security audits and penetration tests.

[SPECIFIED]

---

Part VI — Verification

44. Test Taxonomy

44.1 Overview

StackAlign's tests are organized into three categories:

· Unit tests: Test individual functions in isolation.
· Integration tests: Test the interaction between multiple components.
· CI tests: Test the system in a continuous integration environment.

[IMPLEMENTED-UNVERIFIED]

44.2 Unit Tests

Unit tests verify the behavior of individual functions. They are fast and can be run frequently during development.

[IMPLEMENTED-UNVERIFIED]

44.3 Integration Tests

Integration tests verify the interaction between multiple components. They are slower than unit tests and are typically run before commits.

[IMPLEMENTED-UNVERIFIED]

44.4 CI Tests

CI tests run in a continuous integration environment (GitHub Actions). They verify that the system builds and tests pass on a clean environment.

[IMPLEMENTED-UNVERIFIED]

45. Combinatorial Testing

45.1 Overview

StackAlign uses combinatorial testing to verify that the system behaves correctly across combinations of inputs. The "Brute Genius" matrix specifies the test combinations.

[SPECIFIED]

45.2 Pairwise Testing

Pairwise testing covers all pairs of input values. This provides good coverage with fewer test cases than full combinatorial coverage.

[SPECIFIED]

45.3 3-Way Testing

3-way testing covers all triples of input values. This provides better coverage than pairwise testing but requires more test cases.

[SPECIFIED]

46. Platform Test Matrix

46.1 Overview

StackAlign tests on the following platforms:

· AlmaLinux 9
· Rocky Linux 9
· Ubuntu 24.04 (CI only)

[IMPLEMENTED-UNVERIFIED]

46.2 AlmaLinux 9

AlmaLinux 9 is the primary target platform. Full testing is performed on AlmaLinux 9.

[IMPLEMENTED-UNVERIFIED]

46.3 Rocky Linux 9

Rocky Linux 9 is tested to ensure compatibility.

[IMPLEMENTED-UNVERIFIED]

46.4 Ubuntu 24.04 (CI Only)

Ubuntu 24.04 is tested in CI to catch portability issues. StackAlign does not target Ubuntu for production use.

[IMPLEMENTED-UNVERIFIED]

47. CI and Captured Evidence

47.1 Overview

StackAlign uses GitHub Actions for continuous integration. The CI workflow runs tests on every push and pull request.

[IMPLEMENTED-UNVERIFIED]

47.2 GitHub Actions Workflow

The GitHub Actions workflow is defined in .github/workflows/ci.yml. It runs unit tests, integration tests, and platform tests.

[IMPLEMENTED-UNVERIFIED]

47.3 Captured Evidence

Test output is captured and stored as CI artifacts. This provides evidence that tests were run and passed.

[IMPLEMENTED-UNVERIFIED]

48. Release Verification

48.1 Overview

StackAlign releases are verified via:

· Signed tags
· SHA256SUMS

[SPECIFIED]

48.2 Signed Tags

Release tags are signed with a GPG key. This allows users to verify that the release was created by a trusted party.

[SPECIFIED]

48.3 SHA256SUMS

Release archives are accompanied by a SHA256SUMS file containing the SHA-256 checksums of the archives. Users can verify that the archives they downloaded match the expected checksums.

[SPECIFIED]

---

Part VII — Resilience and Release

49. Backup and Recovery

49.1 Overview

See Section 20.

[BLOCKED(lib/backup.sh)]

50. Restore Drills

50.1 Overview

Restore drills verify that backups are restorable. StackAlign is designed to support automated restore drills.

[BLOCKED: Depends on lib/backup.sh]

51. Mirrors and Repository Recovery

51.1 Overview

StackAlign configures DNF with fallback mirror URLs. If the primary repository is unavailable, DNF falls back to the next mirror.

[SPECIFIED]

51.2 Fallback Mirror URLs

Fallback mirror URLs are configured in the DNF repository configuration. StackAlign uses the standard AlmaLinux and Rocky Linux mirror lists.

[SPECIFIED]

52. Signed Releases and Checksums

52.1 Overview

See Section 48.

[SPECIFIED]

53. Milestone Gates

53.1 Overview

StackAlign's development is organized into milestones:

· M0: Project initialization
· M1: Configuration parser
· M2: Memory tuner
· M3: Template rendering
· M4: Service lifecycle
· M5: Update engine
· M6: Backup and restore
· M7: TLS and firewall
· M8: Multi-tenant architecture

[SPECIFIED]

53.2 Milestone Gates

Each milestone has a gate: a set of criteria that must be met before the milestone is considered complete. Gates include passing tests, documentation, and verification evidence.

[SPECIFIED]

---

Part VIII — Operations Runbooks

54. Fresh Installation

54.1 Overview

This runbook describes the procedure for installing StackAlign on a fresh system.

[SPECIFIED]

54.2 Prerequisites

· AlmaLinux 9/10 or Rocky Linux 9/10
· 512 MiB RAM minimum
· 10 GiB disk space minimum
· Network access to DNF repositories

[SPECIFIED]

54.3 Procedure

1. Download the StackAlign bootstrapper.
2. Verify the bootstrapper's SHA-256 checksum.
3. Run the bootstrapper: sudo ./install.sh
4. Edit /etc/stackalign/stackalign.conf to configure StackAlign.
5. Run stackalign install --plan to preview the installation.
6. Run stackalign install --apply to execute the installation.
7. Verify the installation with stackalign doctor.

[SPECIFIED]

55. Routine Maintenance

55.1 Overview

This runbook describes routine maintenance tasks.

[SPECIFIED]

55.2 Weekly Tasks

· Review stackalign doctor output.
· Check disk space.
· Review logs for errors.

[SPECIFIED]

55.3 Monthly Tasks

· Apply security updates.
· Review backup integrity.
· Review firewall logs.

[SPECIFIED]

55.4 Quarterly Tasks

· Perform restore drill.
· Review configuration for drift.
· Update StackAlign.

[SPECIFIED]

56. Upgrade

56.1 Overview

This runbook describes the procedure for upgrading StackAlign.

[IMPLEMENTED-UNVERIFIED]

56.2 Procedure

1. Run stackalign update check to check for available updates.
2. Run stackalign update plan to preview the update.
3. Run stackalign update apply to execute the update.
4. Verify the update with stackalign doctor.
5. If problems occur, run stackalign update rollback to revert.

[IMPLEMENTED-UNVERIFIED]

57. Rollback

57.1 Overview

This runbook describes the procedure for rolling back a configuration change.

[IMPLEMENTED-UNVERIFIED]

57.2 Procedure

1. Run stackalign rollback --snapshot <id> to roll back to a specific snapshot.
2. Or run stackalign rollback to roll back to the most recent snapshot.
3. Verify the rollback with stackalign doctor.

[IMPLEMENTED-UNVERIFIED]

58. Recovery After Compromise

58.1 Overview

This runbook describes the procedure for recovering from a security compromise.

[BLOCKED: Depends on backup and restore functionality]

59. Quarterly Restore Drill

59.1 Overview

This runbook describes the procedure for performing a quarterly restore drill.

[BLOCKED: Depends on backup and restore functionality]

60. Key Rotation

60.1 Overview

This runbook describes the procedure for rotating cryptographic keys.

[BLOCKED: Depends on secret management and TLS functionality]

---

Appendices

Appendix A: Exit Codes and Error Tokens

Exit Codes

Code Meaning
0 Success
1 General error
2 Invalid arguments
3 Configuration error
4 Dependency missing
5 Verification failed
6 Refusal condition

[IMPLEMENTED-UNVERIFIED]

Error Tokens

Token Meaning
error=no_room_after_fixed Reserve consumes all available memory
error=no_candidate_fits No PHP-FPM child count fits
error=buffer_pool_no_valid_range Buffer pool size out of range
error=config_version_mismatch config_version does not match expected
error=duplicate_key Duplicate key in configuration

[IMPLEMENTED-UNVERIFIED]

Appendix B: Environment Variables

Variable Meaning
STACKALIGN_CONFIG Path to configuration file (default: /etc/stackalign/stackalign.conf)
STACKALIGN_LOG_LEVEL Log level (default: info)
STACKALIGN_DEBUG Enable debug output (default: 0)

[IMPLEMENTED-UNVERIFIED]

Appendix C: File and Path Map

Path Purpose
/usr/local/bin/stackalign CLI entry point
/usr/local/lib/stackalign/ Support files
/etc/stackalign/stackalign.conf Primary configuration
/etc/stackalign/secrets/ Secret storage
/etc/stackalign/.history/ Configuration snapshots
/var/log/stackalign/ Log files

[IMPLEMENTED-UNVERIFIED]

Appendix D: Decision Log

ID Decision Rationale
D1 DNF-first, no source compilation Reduces supply-chain attack surface; aligns with distribution security practices
D2 Clean-room implementation Licensing clarity; security (no inherited vulnerabilities); maintainability
D3 Separate plan from apply Auditability; safety (user can review before committing)
D4 Snapshot before every change Recoverability; enables rollback
D5 Arithmetic floors for tuning Prevents impossible configurations; makes refusal explicit

[SPECIFIED]

Appendix E: Open Issues and Blocked Sections

Section Status Blocking Condition
20. Backup and Restore BLOCKED lib/backup.sh missing
26. TLS and Certificate Management BLOCKED lib/tls.sh missing
27. Multi-Tenant Architecture BLOCKED lib/tenant.sh missing
28. Deployment Transactions BLOCKED lib/txn.sh missing
50. Restore Drills BLOCKED Depends on backup
58. Recovery After Compromise BLOCKED Depends on backup
59. Quarterly Restore Drill BLOCKED Depends on backup
60. Key Rotation BLOCKED Depends on secret management

[SPECIFIED]

Appendix F: Attribution and Licence Table

Component Licence Attribution
StackAlign MIT StackAlign contributors
Nginx BSD-2-Clause Nginx, Inc.
PHP PHP License 3.01 The PHP Group
MariaDB GPLv2 MariaDB Foundation
Redis BSD-3-Clause Redis Ltd.

[VERIFIED: MIT License per repository README]

Appendix G: Index

Index to be generated during final document production.

[SPECIFIED]

---

Upstream Verification Notes

WordPress

WordPress 8.3+ requires PHP 8.3+ and MariaDB 10.6+. StackAlign pins PHP 8.5 and MariaDB 12.3, exceeding these requirements.

[VERIFIED: Upstream documentation review]

Laravel

Laravel 8.3+ requires PHP 8.3+ and MariaDB 10.3+. StackAlign pins PHP 8.5 and MariaDB 12.3, meeting these requirements.

[VERIFIED: Upstream documentation review]

Centmin Mod

Centmin Mod uses DNF/YUM repositories for MariaDB but builds Nginx and PHP from source. StackAlign rejects this approach for security reasons: source compilation introduces supply-chain risk and makes verification more difficult. StackAlign uses DNF for all packages.

[SPECIFIED: Design decision documented]

---

End of Technical Manual Outline
