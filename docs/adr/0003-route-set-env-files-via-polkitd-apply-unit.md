# The Route Set lives in root-owned EnvironmentFiles, written by a polkit'd apply unit

The Tool must let the user choose which networks the Tunnel pushes — "not an all-or-nothing connection" — without manual config editing, but the pure-QML plasmoid (ADR 0002) can't write root-owned files and pkexec was dropped with the shape decision. Decided: the **Route Set** lives in `/etc/sshuttle-tray/route-set.env` (`SSHUTTLE_SUBNETS`, space-separated CIDRs, `0/0` allowed; optional `SSHUTTLE_PING_TARGET`) beside a static `/etc/sshuttle-tray/tunnel.env` (`SSHUTTLE_REMOTE`, `SSHUTTLE_REMOTE_SHELL`, install-time). The unit's `ExecStart` references the variables — systemd word-splits expanded vars — so the unit stays generic and no one regenerates an `ExecStart` line. A built-in `Environment=SSHUTTLE_SUBNETS=0/0` with `EnvironmentFile=-` degrades a fresh install to the full tunnel. Edits flow: the plasmoid stages the desired file under `/run/user/<uid>/sshuttle-tray/`, starts the root oneshot template `sshuttle-tray-apply@<uid>.service`, which validates (CIDR parse; warn when the Ping Target is outside the Route Set) and installs atomically (temp+rename). The editing surface is the plasmoid's standard Plasma config dialog.

## Considered Options

- pkexec'd helper script — rejected with the shape decision (ADR 0002): the plasmoid has no pkexec path.
- Custom D-Bus/polkit helper daemon — rejected: a new privileged surface to package, audit, and keep alive, where a oneshot unit reuses systemd itself.
- Passwordless write rule — rejected: changing the tunnel's scope is security-relevant; one password prompt per subnet-set change is the point.
- Drop-in overriding `ExecStart=` with subnets inline — rejected: regenerating an `ExecStart` line is fragile and schema-less; two users' edits collide.
- One combined file the helper rewrites wholesale — rejected: the helper would have to preserve the static keys it doesn't own.

## Consequences

- Both polkit surfaces are the same `org.freedesktop.systemd1.manage-units` action in one rules file, scoped by unit name: `sshuttle-tray-tunnel.service` start/stop is passwordless; `sshuttle-tray-apply@*.service` start costs one `auth_admin` prompt per change — never per tunnel start.
- The apply unit never restarts the Tunnel (ADR 0001): the popup offers "restart to apply" through the passwordless control path, keeping lifecycle ownership with the Tool.
- Hand-editing `/etc/sshuttle-tray/route-set.env` still works; the helper is simply the last writer. Changes take effect on the next Tunnel start.
- The packaged unit supersedes the hand-created `/etc/systemd/system/office-tunnel.service` with its 13 inline subnets; that migration belongs to packaging.

> Amended with the packaging decision ([ADR 0005](0005-github-tarball-distribution-generic-unit.md)): the passwordless block scopes the generic `sshuttle-tray-tunnel.service`, superseding the `office-tunnel` naming in this ADR's narration.
