# Internet access setup wizard

**Status: interactive preference capture, guarded persistence, and read-only planning implemented. Provider automation is NOT IMPLEMENTED.**

Run from the repository checkout:

```bash
bash bin/stackalign internet setup
bash bin/stackalign internet plan
bash bin/stackalign internet doctor
```

## What the wizard asks

1. Whether the server needs a public website, private administration, or both.
2. Which DNS provider manages the public domain: Cloudflare, another provider, unknown, or no domain yet.
3. For public websites, whether to use Cloudflare Tunnel, a direct public IP with A/AAAA records, or manual guidance.
4. For private administration, whether to use Tailscale, WireGuard, an existing private VPN, or manual guidance.
5. The domain name and, for direct-origin mode, an optional public IPv4 address.

DNS hosting, public website ingress, and private administrator access are deliberately separate settings. Cloudflare Tunnel is not a direct-origin A-record setup: the hostname route is configured in the authorized Cloudflare zone and maps to the intended local service. If DNS is managed elsewhere, the wizard flags that as a manual compatibility step. Direct-origin mode instead plans A/AAAA records to a verified public IP. Tailscale/WireGuard are private administration paths, not public website DNS providers.

## Saved preferences and validation

The wizard stores only non-secret preferences in `$XDG_CONFIG_HOME/stackalign/internet.conf`, or `~/.config/stackalign/internet.conf` when `XDG_CONFIG_HOME` is unset. The config is versioned, written atomically, and restricted to owner-only directory/file permissions. The reader rejects symlinks, wrong ownership, broad permissions, duplicate/unknown keys, incomplete records, unsupported versions, and invalid domain/public-IPv4 values, including private, loopback, link-local, special-use, and ambiguous leading-zero IPv4 addresses. Relative `XDG_CONFIG_HOME` paths are rejected.

No API tokens, passwords, tunnel credentials, or private keys are requested or stored. The wizard does not prove domain ownership, public address ownership, DNS propagation, or reachability.

## Read-only doctor

`stackalign internet doctor` checks that `ip` and `getent` exist, reads interface addresses and the default route, and performs one DNS lookup for `example.com`. It reports failures instead of hiding failed command exit statuses. This is only a local connectivity smoke check; it does not verify authoritative DNS, public inbound reachability, provider login, firewall/security-group policy, TLS, or tunnel health.

## Security boundaries

- Public website traffic and private administration are separate paths.
- Never publish SSH, database, or administrative panel ports as a tunnel fallback.
- No DNS records, firewall rules, security groups, packages, services, certificates, routes, or tunnel/VPN clients are changed.
- `stackalign internet apply` deliberately fails closed until provider authentication, ownership checks, explicit change review, rollback, and host acceptance are implemented.
- If provider identity, DNS control, router/NAT, cloud firewall, or credentials are unknown, stop and use the manual path rather than guessing.

## Manual setup when StackAlign cannot automate

1. Confirm the domain registration and authoritative DNS provider.
2. For direct-origin mode, set an A record to the verified public IPv4; add an AAAA record only after separately verifying public IPv6 connectivity. Configure only the intended public web ports and HTTPS after reachability checks.
3. For Cloudflare Tunnel, authenticate through Cloudflare's supported login flow, create/authorize the tunnel, configure the hostname route to the intended local web service, and verify zone compatibility. Do not substitute an origin A record for the tunnel route.
4. For Tailscale, install/enroll the node through the official provider workflow and enforce restrictive ACLs.
5. For WireGuard, create keys on the respective endpoints, exchange public keys only, configure allowed IPs/routes and endpoint reachability, and validate firewall policy.
6. Configure TLS using the chosen certificate workflow only after the DNS/ingress prerequisites are satisfied.
7. Verify DNS, HTTPS, private access, and tunnel/VPN health independently.

## Validation boundary

CI tests validate the CLI guards, input/config parsing, permissions, plan output, and doctor failure reporting on the exact CI commit. Provider authentication, DNS mutation, firewall behavior, TLS issuance, tunnel operation, recovery, and real-host end-to-end reachability require disposable-host/provider integration tests and remain **NOT RUN / UNVERIFIED**.
