# Egress firewall and passive LAN audit

The `egress` CLI is an opt-in Linux/nftables control for a studio host. It is separate from `lib/firewall.sh`, which manages StackAlign's existing inbound firewall table. The egress table is named `inet stackalign_egress` by default and has an OUTPUT chain with a default-drop policy.

## Commands

All state-changing commands require `--apply`. `egress apply` without it prints a plan.

```bash
# Render and inspect; no firewall state changes
stackalign egress plan studio.allow 9.9.9.9 192.168.1.0/24

# Plan by default; still no changes
stackalign egress apply studio.allow 9.9.9.9 192.168.1.0/24 120

# From a local console, explicitly apply with a 120-second revert timer
sudo stackalign egress apply studio.allow 9.9.9.9 192.168.1.0/24 120 --apply

# Keep the rules only after confirming the host remains usable
sudo stackalign egress confirm --apply

# Remove only StackAlign's egress table
sudo stackalign egress remove --apply

# Read the existing neighbour cache; this does not scan the LAN
stackalign egress audit known-devices.txt
```

The allowlist format is one destination, protocol, and port per line:

```text
# comments may be whole-line or trailing
updates.example.com tcp 443
203.0.113.0/24 tcp 443
2001:db8::1 udp 123
```

DNS resolvers must be literal IPv4 or IPv6 addresses. Hostname allowlist entries are resolved to up to 16 unique IPv4 addresses when the rules are rendered; that mapping can become stale and is not automatically refreshed. `/0` destinations are refused unless `SA_EGRESS_ALLOW_ANY=1` is explicitly set. The optional LAN list accepts IPv4 and IPv6 ranges.

## Safety boundary

- The module does not install nftables/systemd, enable services, persist rules across reboot, or change router configuration.
- It does not run automatically during install, update, boot, or `doctor`.
- The `apply` path validates the complete allowlist, runs `nft -c`, schedules the optional transient systemd revert before loading, then loads one nft batch. Scheduling failure prevents loading.
- Use the revert timer and a local console for initial testing. Default-deny egress can interrupt updates, license checks, DNS, audio software activation, and other services not represented in the allowlist. Never test over an SSH-only session.
- The passive audit reads `ip -o neigh show` only. It cannot discover silent/offline devices; randomized MACs can make a known phone appear unknown.
- Mock tests verify emitted rules and command order only. They do not prove nftables parser acceptance, kernel behavior, IPv6 neighbour discovery, timer execution, or recovery on a real host.
- A disposable EL-family VM test with IPv6 enabled is still required before production use. In particular, verify nft syntax against the target version, systemd transient timer behavior, timer replacement, expiry/recovery, and DNS/network behavior.
- No real-host command, firewall application, package installation, or VM test is performed by CI.

Do not treat a passing mock suite as evidence that the host remains reachable. The feature remains opt-in and non-persistent.
