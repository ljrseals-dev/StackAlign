# Contributing to StackAlign

Thank you for helping test StackAlign. This repository is in a **controlled pre-production beta**. Contributions are welcome; this status is not a claim that StackAlign is safe for production workloads.

## Before you start

1. Read README.md, the beta testing guide, and the Technical Manual.
2. Check existing issues and pull requests before opening a duplicate.
3. Use a disposable AlmaLinux 9 or Rocky Linux 9 VM/container. Never use a production host, valuable data, or real credentials.
4. Keep reports reproducible and redact secrets, private keys, tokens, personal data, and sensitive host details.

## Report a bug

Use the Bug Report issue form. Include:

- StackAlign commit SHA (git rev-parse HEAD)
- Distribution/version, kernel, architecture, and VM/container runtime
- Exact commands and complete relevant output
- Expected and actual behavior
- Minimal reproduction steps
- Whether the test changed files, accounts, packages, services, firewall state, or network configuration

Do not attach private keys, credential files, unredacted logs, or production configuration.

## Request a feature

Use the Feature Request issue form. Describe the problem, desired outcome, constraints, and how acceptance can be tested. Avoid prescribing a broad rewrite when a focused change would solve the problem.

## Submit a pull request

1. Fork the repository or create a focused feature branch. Do not commit directly to main.
2. Keep changes narrow and explain the user-visible behavior.
3. Add or update tests for changed behavior. Prefer deterministic tests and fake system tools for unit tests; add disposable-environment integration coverage when host behavior is involved.
4. Update the Technical Manual and relevant user documentation when behavior or guarantees change. Preserve explicit [SPECIFIED], [IMPLEMENTED-UNVERIFIED], [VERIFIED], and [BLOCKED] distinctions.
5. Run the checks locally:
   ```bash
   make lint
   make test
   ```
   The Python tuner test is part of make test; run it in an isolated development environment with Python 3 available.
6. Open a PR against main and complete the pull-request template. State what was tested, the exact environment, results, and what was not tested.
7. Respond to review feedback with follow-up commits. Do not force-push shared branches or rewrite project history.

## Merge expectations

- A PR is not accepted merely because it was opened or because one local test passed.
- Required CI checks must pass on the proposed PR head. A maintainer must review the diff, tests, documentation, and scope before merging.
- Changes that affect privileged operations, package sources, authentication, SSH, firewall behavior, rollback, secrets, or filesystem ownership require explicit safety review and focused failure-path tests.
- Do not merge a change that turns an assumption into a security or production claim without evidence.
- Maintainers may request changes, defer a feature, or close a PR that is out of scope or cannot be validated.

These are the project's contribution rules. GitHub branch-protection enforcement is a repository setting and must not be assumed unless it is visibly configured.

## What beta feedback does and does not mean

Beta reports help identify defects and prioritize work. They do not make the software production-ready, establish supported-host compatibility, or substitute for independent security review and real-host validation.

## License

By submitting a contribution, you agree that it is submitted under the repository's MIT license. Keep author attribution and third-party notices accurate; do not submit code or documentation copied from projects without the required provenance and license review.
