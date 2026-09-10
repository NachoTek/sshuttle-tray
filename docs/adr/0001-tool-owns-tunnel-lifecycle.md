# The Tool owns the Tunnel lifecycle; the unit never auto-restarts

`office-tunnel.service` originally carried `Restart=on-failure`: on network loss or roaming, sshuttle died and systemd restart-looped it endlessly while offline — hiding failure from the tray tool and fighting its state display. We decided the Tool owns the Tunnel's lifecycle instead: the unit runs `Restart=no`, retry is manual only (the ON button, via `pkexec systemctl start office-tunnel`), and a dead Tunnel surfaces honestly as the warning/failed icon rather than being papered over by systemd.

## Considered Options

- Keep `Restart=on-failure`, Tool observes only — rejected: the restart loop makes Service state lie even harder, which is exactly what the Tool exists to correct.
- `Restart=no` with Tool-driven timed auto-retry — rejected for v1: adds a retry scheduler, repeated silent pkexec calls while offline, and a "retrying…" icon concept. May return later as a config-gated enhancement.

## Consequences

- The package ships `/usr/lib/systemd/system/sshuttle-tray-tunnel.service.d/50-sshuttle-tray-no-restart.conf` (`[Service]` / `Restart=no`) rather than touching user units in `/etc`. systemd stacks drop-ins across directories, so it augments the user's own unit; a same-named `/etc` drop-in outranks it for users who want auto-restart back. The Tool itself never writes to `/etc` at runtime.
- Failure is a single clean `failed` state — no restart loop — which the icon state machine builds on.
- Don't "fix" the unit by re-adding `Restart=on-failure`: that removal is deliberate (see [the lifecycle ticket](https://github.com/NachoTek/sshuttle-tray/issues/4)).

> Amended with the packaging decision ([ADR 0005](0005-github-tarball-distribution-generic-unit.md)): the drop-in targets the generic `sshuttle-tray-tunnel.service`, superseding the `office-tunnel` naming in this ADR's narration.

> Amended 2026-09-10 — logout binding is the user's call, opt-in per install. The original stance ("survives restarts") holds against *process* lifetime (plasmashell crashes), but the Tunnel should not outlive the user's *login*: an office machine nobody is logged into should not keep routing through the relay. Rejected alternatives: a `--user` unit (sshuttle needs root on the client regardless — it would just wrap sudo), and PAM/session-teeardown hooks (racy polkit `subject.active` at teardown, invasive packaging). Chosen: an `/etc` drop-in binding the system Tunnel to the user manager — `BindsTo=user@<uid>.service` + `After=` — which stops the Tunnel cleanly when the last session of that uid ends. Opt-in because the uid cannot ship in a generic package; inert when `loginctl enable-linger` keeps the user manager alive. See the README ("Tie the Tunnel to your login").

