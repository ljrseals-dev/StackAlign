# StackAlign Release Artifact Trust

SPDX-License-Identifier: MIT  
Author: Lewis James Seals Jr.

## Scope

This release channel distributes StackAlign's own CLI, shell libraries, installer,
and release tarball. It does not build or redistribute replacement nginx, PHP,
or MariaDB packages. Those remain DNF-managed packages from configured
distribution and upstream repositories, with repository GPG verification and
StackAlign's existing version pins.

An optional disaster-recovery mirror may retain pinned upstream RPMs byte-for-byte.
It must preserve upstream signatures and metadata; it must not rebuild or
re-sign those packages as StackAlign artifacts.

## Trust model

1. A release is a versioned StackAlign tarball accompanied by `SHA256SUMS`
   and a detached signature over that checksum file.
2. The verification keyring and full primary-key fingerprint are provisioned
   independently of the host serving release downloads. A checksum and key
   fetched only from the same origin do not establish authenticity.
3. The release signing key is kept offline. Its full fingerprint is published
   through multiple independently controlled channels.
4. The initial installer trust anchor is established by a signed Git tag and
   an independently published signing-key fingerprint. The installer must not
   trust a key downloaded from the artifact host without this bootstrap.
5. Key rotation and revocation require a documented transition: publish the
   replacement fingerprint out-of-band, sign a transition with the old key
   while it remains trusted, then revoke/retire the old key. If the old key is
   compromised, do not trust an old-key transition; distribute the new trust
   anchor through independently authenticated channels.

## Metadata freshness and rollback

The signed checksum file must include exactly one UTC expiry declaration in
the form `# expires: YYYY-MM-DDTHH:MM:SSZ`. Expired or missing metadata is
rejected.

A future release-manifest revision must include a signed monotonically
increasing release version and expiry. Clients must reject stale or lower
versions by default. Deliberate rollback is a separate, explicit operator
policy and must never be enabled by an ambient environment variable or by
metadata supplied only by the download host.

The current `sa_verify_not_downgrade` helper compares version strings and
rejects downgrades. It is not yet wired to a signed release manifest or update
workflow. Do not describe anti-rollback as end-to-end enforced until that
integration exists.

## Verification contract

`sa_verify_artifact ARTIFACT SHA256SUMS SHA256SUMS.sig KEYRING FINGERPRINT`
must fail closed unless all of the following hold:

- all four input files exist;
- the pinned fingerprint is a valid full fingerprint;
- GnuPG validates exactly one signature and the primary-key fingerprint
  matches the independently provisioned pin;
- expired, revoked, invalid, or unknown signing keys are rejected;
- the signed checksum metadata is unexpired;
- exactly one checksum entry names the artifact; and
- the artifact's SHA-256 matches that entry.

Return codes: 0 verified; 4 signature/key/fingerprint failure; 5 checksum
failure; 6 expired or missing metadata; 7 downgrade refused; 64 invalid usage.

## Explicit non-goals

- No source builds or StackAlign-maintained forks of nginx, PHP, or MariaDB.
- No trust in a checksum, key, or fingerprint delivered solely by the artifact
  download host.
- No self-update or updater replacement in this change.
- No claim of real-host validation from mock or throwaway-key tests.

## Validation status

The throwaway-key suite exercises real `gpg`/`gpgv` verification and
failure cases. CI must install GnuPG on both Ubuntu and AlmaLinux 9 so the
suite cannot silently skip in those jobs. Real-host package-update validation
remains a prerequisite for any future self-update work.
