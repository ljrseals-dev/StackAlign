# Oracle Linux migration and update workflow

<!-- SPDX-License-Identifier: MIT -->
<!-- Author: Lewis James Seals Jr. -->

Status: implementation added; real conversion and live package transactions NOT RUN.

## Purpose and safety boundary

`bin/stackalign-oracle` separates a CentOS-to-Oracle-Linux conversion from
subsequent Oracle Linux package updates. It does **not** configure Oracle Linux
repositories directly on CentOS and does not claim that such mixed repositories
are a supported or safe CentOS update channel.

Oracle's `centos2ol.sh` is an operating-system conversion tool. It can replace
distribution packages, repository definitions, and kernel/boot packages. Treat
it as a destructive migration requiring a tested, restorable full-system
snapshot. A snapshot identifier supplied to StackAlign is an operator
attestation; StackAlign does not create or verify the snapshot.

## Obtain and verify the conversion script

Obtain `centos2ol.sh` from Oracle's official
[oracle/centos2ol repository](https://github.com/oracle/centos2ol).
Review the exact script version and its supported source releases. Save it
locally, calculate SHA-256 on the target or trusted staging host, and compare
the digest through an independently trusted channel. The CLI compares the
file to the operator-provided digest; SHA-256 comparison alone does not prove
Oracle authorship or publisher identity.

Example:

```bash
sha256sum centos2ol.sh
bin/stackalign-oracle convert plan \
  --script ./centos2ol.sh \
  --sha256 <64-hex-sha256> \
  --snapshot-id <verified-backup-id>
```

After reviewing the plan, the script, Oracle's own preflight output, and the
restorable backup, run from a local console:

```bash
SA_ORACLE_CONFIRM=CONVERT-CENTOS-TO-ORACLE-LINUX \
  bin/stackalign-oracle convert apply \
  --script ./centos2ol.sh \
  --sha256 <64-hex-sha256> \
  --snapshot-id <verified-backup-id> --apply
```

Supported wrapper detection is CentOS 7 or 8 x86_64. Oracle's script remains
the authority for the exact conversion compatibility checks. CentOS Stream is
not accepted as CentOS Linux by this wrapper.

## Update after conversion

Only a host whose `/etc/os-release` identifies `ID=ol`, major version 7 or
8, and x86_64 is accepted. Enabled repository sections with `gpgcheck=0` are
refused. The package manager retains responsibility for repository metadata,
dependency solving, signatures and transactions.

```bash
bin/stackalign-oracle update plan
SA_ORACLE_CONFIRM=APPLY-ORACLE-LINUX-UPDATES \
  bin/stackalign-oracle update apply --apply
```

The plan uses the package manager's assume-no transaction preview. The apply
command performs a full package update and may require reboot. Validate kernel,
services, application health, repository state and installed package versions
afterward.

## Security and lifecycle claims

- Oracle Linux public YUM repositories and paid Extended Support are different
  channels. Successful access to a public repository is not proof of an ELS
  entitlement or a post-EOL security SLA.
- The wrapper does not enable a paid ULN channel, install credentials, or
  claim CentOS 7/8 receive current free security updates.
- Do not add Oracle Linux repositories to CentOS and blindly run
  `yum update`/ `dnf update --allowerasing`.
- Do not delete CentOS repository files until the conversion tool has completed
  and Oracle Linux repository configuration has been verified.
- UEK versus RHCK selection is an explicit post-conversion kernel decision;
  this wrapper does not change it.
- A passing unit test is not a live conversion test. Real conversion must be
  validated on disposable CentOS 7 and CentOS 8 VMs with console access and
  tested snapshot restore.

## Current validation

The unit tests use fake OS metadata, fake package managers and a temporary
script. They do not run Oracle's conversion script, access yum.oracle.com,
import keys, modify the host package database or establish current security
coverage.
