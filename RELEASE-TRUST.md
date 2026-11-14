# StackAlign Release Trust Model

Status: **[SPECIFIED]** design. `lib/verify.sh` is **[IMPLEMENTED-UNVERIFIED]**: it passes its own
tests with throwaway keys (`tests/test_verify.sh`), and has not run on a real release or a real host.

## 1. Principle

StackAlign never trusts an artifact because StackAlign (or its web server) published it.
Trust comes from a signing key whose fingerprint is **pinned somewhere the download server cannot
change**, and every check runs offline and fails closed.

## 2. What we host, and what we do not

| Hosted by the project | Not hosted by the project |
|---|---|
| StackAlign releases: CLI, `lib/`, templates, `install.sh` (a tarball) | nginx, PHP, MariaDB, Redis, and every other distro package |
| `SHA256SUMS`, `SHA256SUMS.sig`, signed git tag | Rebuilt or repackaged copies of upstream software |

Third-party software keeps coming from distro and upstream repos through DNF, with the version pins in
`vendor/versions.toml` and GPG verification. Hosting our own builds would make StackAlign a Linux
distribution (rebuilds, security patches, an ops burden). An optional later step is a plain *mirror* of
pinned upstream RPMs for outage recovery; mirrored RPMs keep their upstream signatures and are never rebuilt.

## 3. Release bundle

```
stackalign-<version>.tar.gz
SHA256SUMS         first line:  # expires: YYYY-MM-DDTHH:MM:SSZ   (UTC), then "<sha256>  <filename>"
SHA256SUMS.sig     detached signature over SHA256SUMS
```
The git tag `v<version>` is signed with the same key. `<version>` is plain dotted numbers (no pre-release tags).

## 4. Keys

- The release signing key lives **offline** (hardware token or an air-gapped machine). CI never holds it.
- Its 40-hex **primary-key fingerprint** is published in at least two independent places (the repo
  README and a signed tag annotation at minimum; a third, such as a personal site, is better).
- Operators pin the fingerprint themselves and keep the public key in a **local keyring file** installed
  with the tool or supplied on the command line. The keyring and fingerprint are never taken from the bundle.

## 5. Verification (`sa_verify_artifact`), in this order

1. Detached signature over `SHA256SUMS` verifies with `gpgv` against the local keyring only.
2. Exactly one valid signature, no revoked/expired-key or error status, and its **primary** key
   fingerprint equals the pin (a signing subkey is fine; a different primary is not).
3. `# expires:` is present, well formed, and in the future.
4. The artifact name has exactly one entry, and its sha256 equals the computed hash.
5. Only then is the path printed. Return codes: 4 signature/key, 6 expired/no expiry, 5 checksum, 64 usage.

Expiry sits **inside the signed file**, so an attacker cannot strip it. This stops "freeze" attacks, where
a mirror keeps serving an old but validly signed release. The cost: someone must re-sign `SHA256SUMS`
before it expires (a 90-day window is a reasonable starting point; the choice is yours).

## 6. Bootstrap

`install.sh` already refuses placeholder checksums. Target flow: the operator obtains the fingerprint from
two places, imports the public key into a local keyring, and passes both to `install.sh`, which runs
`sa_verify_artifact` before extracting anything. A one-line `curl | bash` cannot establish trust on first use
and is not supported as a trusted path.

## 7. Downgrade and rollback

- `sa_verify_not_downgrade <installed> <candidate>` refuses an older candidate (numeric comparison, so 1.10 > 1.9).
- A deliberate downgrade requires `SA_ALLOW_DOWNGRADE=1` and prints a warning.
- Normal rollback after a failed update does **not** download an older release: it flips back to the
  previous version kept on disk (see 9).

## 8. Rotation and revocation

- Rotation: publish the new fingerprint in all places, sign a transition notice with the **old** key, and
  ship the new public key; operators re-pin by hand.
- Compromise: revoke the key, publish the revocation certificate, cut a new key, tell users to re-pin.
  `gpgv` reports revoked keys and `sa_verify_artifact` refuses them if the operator has imported the revocation.
- There is no automatic key update over the network. That is deliberate.

## 9. Self-update (not built)

Order of work: the package update path (`update apply`) must pass a run on a real host first. Then the
self-updater: unpack to `/usr/local/lib/stackalign/<version>/`, verify before unpacking, swap a symlink
atomically, keep the previous version, run `stackalign doctor`, and flip back on failure. **[SPECIFIED]**

## 10. Threats

| Threat | Mitigation | Remaining risk |
|---|---|---|
| Tampered tarball or checksums | Signature + hash | None if the pin is right |
| Compromised download server | Pin and keyring stored elsewhere | Operator must obtain the pin honestly |
| Old vulnerable release replayed | Signed expiry + downgrade refusal | Needs re-signing discipline |
| Stolen CI credentials | Signing key is offline | Key custody is now the weak point |
| Wrong key trusted on first install | Fingerprint from 2+ places | Human error |
| Lost or expired signing key | Documented rotation | Users must re-pin manually |

## 11. Open questions

- Which hardware token or signing workflow? (Decision needed before the first release.)
- Sigstore/transparency-log support as an optional second signature.
- Reproducible release tarballs so third parties can rebuild and compare hashes.
- The GnuPG 2.4 `VALIDSIG` field layout is assumed from its documentation; confirm on the EL9/EL10 `gnupg2` packages.
