# Security policy

StackAlign is in a controlled pre-production beta and is **not suitable for production workloads**. The project makes no blanket security guarantee.

## Reporting a suspected vulnerability

Please do not publish an exploitable vulnerability, credentials, private keys, or sensitive host data in a public issue or pull request.

Use GitHub's private vulnerability reporting feature for this repository if it is enabled. If it is not enabled, contact the repository maintainer privately through GitHub before disclosing technical details publicly. Do not assume that a public issue is a private reporting channel.

Include the affected commit or version, environment, impact, reproduction steps, and any safe proof needed to establish the issue. Redact secrets and personal data.

## Scope and expectations

Reports involving privilege boundaries, command execution, package/repository trust, signature verification, path handling, symlinks, rollback, secrets, account management, SSH configuration, and network exposure are especially important.

The project will acknowledge and assess reports as maintainer capacity permits. No response-time SLA or coordinated-disclosure deadline is promised by this beta policy. Please allow maintainers a reasonable opportunity to investigate before public disclosure.

Do not test against systems you do not own or have explicit permission to assess. Use disposable environments.
