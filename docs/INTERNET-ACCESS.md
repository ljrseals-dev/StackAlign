# Internet access setup wizard

**Status: interactive preference capture and read-only planning implemented; provider automation NOT IMPLEMENTED.**

Run:

```bash
stackalign internet setup
stackalign internet plan
stackalign internet doctor
```

The setup wizard asks whether the operator needs a public website, private administration, or both; asks which provider is in use (Cloudflare Tunnel, Tailscale, WireGuard, none, or unknown); and optionally collects a domain and public IPv4 address. It validates those inputs and saves only non-secret preferences under `$XDG_CONFIG_HOME/stackalign/internet.conf` (or `~/.config/stackalign/internet.conf`) with a private directory/file mode.

## Security model

- Public website traffic and private administration are separate access paths.
- Do not publish SSH, database, or administrative panel ports to the public internet.
- Cloudflare Tunnel is a public web-ingress option; Tailscale is intended for private administration; WireGuard is a self-managed VPN requiring explicit peer/key/routing work.
- No provider credentials, API tokens, private keys, or enrollment secrets are requested or stored.
- No DNS records, firewall rules, security groups, packages, services, certificates, routes, or tunnel clients are changed.
- No remote-IP lookup or external DNS query is performed by setup.
- Saved values are treated as operator input, not proof of DNS ownership or reachability.

## Manual steps when StackAlign cannot automate

1. Confirm the domain is registered and its authoritative DNS provider is known.
2. Create the required A/AAAA or provider-specific CNAME record at the DNS provider.
3. If using Cloudflare Tunnel, authenticate using the provider's supported login flow, create/authorize the tunnel, and map only the intended hostname/service. Do not paste tokens into CLI arguments or commit them.
4. If using Tailscale, install/enroll the node using the official provider workflow and enforce restrictive ACLs; do not expose SSH publicly as a fallback.
5. If using WireGuard, create keys on the respective endpoints, exchange public keys only, configure allowed IPs/routes and endpoint reachability, and validate firewall policy.
6. Configure TLS using the chosen certificate workflow only after DNS and reachability prerequisites are satisfied.
7. Verify DNS, HTTPS, tunnel health, and private access independently.

If provider identity, DNS control, router/NAT, cloud security-group access, or credentials are unknown, StackAlign must stop and display manual instructions rather than guess. A successful plan is not proof of public reachability.

## Validation boundary

Shell tests cover input validation and plan output only. Provider authentication, live DNS, internet reachability, firewall behavior, TLS issuance, and tunnel operation require disposable-host/provider integration testing and remain **NOT RUN / UNVERIFIED**.
