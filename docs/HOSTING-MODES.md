# StackAlign hosting modes

**Status:** The EL9 LEMP bootstrap is implemented as a beta. Hosting-mode planning and inspection are read-only. Apache/hybrid apply and independent-user shared-hosting isolation are separate, gated capabilities.

StackAlign is a CLI web-hosting and server-administration tool. It supports the web-hosting use case: installing and operating a LEMP stack and managing websites through web-server virtual hosts. It is not a browser-based commercial control panel, but that does not mean vhosts or ordinary web hosting are outside its scope.

## Hosting models

Do not conflate these two models:

| Model | Meaning | Scope |
|---|---|---|
| Administrator-managed web hosting | One administrator operates a server and manages multiple websites/vhosts | Within StackAlign's intended web-hosting use |
| Independent-user shared hosting | Multiple mutually untrusted end users receive separate accounts and must be isolated from one another | Additional isolation capability; do not claim it is complete without the required controls and tests |

A limitation on independent-user isolation is not a prohibition on administrator-managed web hosting, multiple websites, or virtual hosts.

## PHP-FPM pool behavior

The default LEMP configuration uses the shared PHP-FPM `www` pool. Additional PHP-FPM pools are available as an operator-selectable CLI configuration choice; they are not enabled automatically by default.

Important distinctions:

- The shared `www` pool is the default, not a statement that vhosts are unsupported.
- Operators may select additional pools through the CLI where the pool configuration workflow is available.
- A separate pool is a configuration boundary, not by itself proof of independent-user isolation.
- Before making isolation claims, verify the pool's Unix user/group, socket owner/group/mode, filesystem permissions, process limits, and relevant service/resource boundaries.
- Do not silently change the default pool behavior during unrelated work.

## Modes

| Mode | Edge | Application server | Intended use |
|---|---|---|---|
| `nginx` | Nginx | PHP-FPM | Default LEMP/web-hosting path |
| `apache` | Apache HTTP Server | Apache + PHP-FPM | Apache compatibility |
| `hybrid` | Nginx | Apache + PHP-FPM | Nginx edge with Apache upstream |

The existing LEMP install path configures Nginx, PHP-FPM, and MariaDB on supported EL9 x86_64 systems. Its documented default listener is `127.0.0.1:8080`; it does not automatically configure public DNS, public ingress, TLS, or firewall policy.

The `hosting plan` command is read-only. The Apache and hybrid modes describe optional architectures; their runtime apply path remains separately gated. That gate must not be used to describe the existing Nginx/PHP-FPM LEMP beta as absent or nonfunctional.

## Apache requirements and hybrid routing

The intended EL-family Apache package is `httpd`. Required module capabilities include:

- `mod_proxy`
- `mod_proxy_fcgi`
- `mpm_event`

The intended hybrid topology is:

1. Nginx owns the public-facing edge when public ingress is configured by the operator.
2. Nginx proxies to Apache on a private loopback backend such as `127.0.0.1:8081`.
3. Apache is not exposed as an unintended public backend.
4. PHP requests are forwarded to the selected PHP-FPM pool/socket.
5. Pool ownership and filesystem permissions are validated against the intended operator model.

The backend address is a design default, not proof that an active listener or firewall rule exists.

## Operator scope selection

The `hosting setup` prompt distinguishes a single administrator managing multiple accounts from multiple independent end users. The second model requires stronger isolation. Do not interpret that warning as saying a single administrator cannot host multiple websites or vhosts.

Where the CLI reports a selection without persisting it, document that persistence limitation accurately. Do not imply that a choice was saved when it was only displayed.

## CLI inspection

Read-only plans:

```bash
stackalign hosting plan nginx
stackalign hosting plan apache
stackalign hosting plan hybrid
stackalign hosting setup
```

Inspect installed server binaries and Apache proxy-module availability:

```bash
stackalign hosting doctor [nginx|apache|hybrid]
```

The LEMP install workflow is separate:

```bash
sudo stackalign install
sudo stackalign install --apply
```

The second command is mutating and must be used only on a supported, disposable EL9 test host until the beta's real-host acceptance work is complete.

## Separate acceptance gates

### Existing LEMP beta

- Run the repository lint, header, and test checks on the exact release commit.
- Run clean EL9 install tests on supported distributions.
- Verify PHP execution, MariaDB local access, service activation, reboot behavior, and failure recovery.
- Record the exact environment and output. Mock tests do not substitute for host tests.

### Apache/hybrid runtime apply

- Verify package availability and module selection on supported EL9 hosts.
- Validate generated Apache configuration with `httpd -t`.
- Verify private backend binding and Nginx-to-Apache routing.
- Verify selected PHP-FPM pool/socket ownership and permissions.
- Inject failures and verify configuration/service recovery.

### Independent-user shared hosting

- Verify distinct Unix identities and ownership.
- Verify dedicated PHP-FPM pools/sockets with restrictive permissions.
- Verify filesystem, process, resource, and service boundaries.
- Run adversarial tests with two live untrusted test accounts.

Until the relevant checks run, report each capability separately as implemented, tested, blocked, or not run. Do not let the independent-user gate erase the existing web-hosting and vhost scope.
