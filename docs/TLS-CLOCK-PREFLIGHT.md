# TLS system-clock enforcement

**Status: implemented as a fail-closed preflight gate; real-host NTP behavior remains to be validated.**

StackAlign now checks the host clock before TLS preflight inspects renewal schedulers and before the Certbot HTTP-01 issuance planner emits a command preview.

Run:

```bash
bash bin/stackalign tls preflight
bash bin/stackalign tls plan-issue example.com --client certbot --challenge http-01 \
  --webroot /var/www/html --email admin@example.com
```

The gate calls the trusted `timedatectl` executable and requires `NTPSynchronized=yes`. If the command is unavailable, fails, or reports any other value, StackAlign returns a non-zero clock-preflight result and stops before scheduler inspection or certificate-plan generation. The gate does not set the clock, enable NTP, install a time service, or alter timezone settings.

Timezone is reported separately when it can be read. An unknown timezone is diagnostic rather than a TLS blocker: certificate validity is evaluated against absolute UTC time, not the local timezone display. Operators should still configure an appropriate IANA timezone for understandable logs and maintenance windows.

This gate is defense in depth, not certificate issuance. The CLI continues to block issuance, renewal, migration, and renewal-scheduler activation until protected credential transport, client/lineage ownership, atomic certificate/key activation, crash recovery, scheduler isolation, and real-host acceptance tests are complete.

The regression test `tests/test_tls_clock.sh` covers synchronized time, unsynchronized time, unavailable time state, timezone reporting, and stopping before scheduler inspection. Mock tests do not prove that chronyd/systemd-timesyncd is correctly configured on a live AlmaLinux/Rocky host.
