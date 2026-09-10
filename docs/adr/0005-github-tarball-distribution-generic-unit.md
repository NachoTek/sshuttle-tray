# Distributed from GitHub as a tarball-installable tree; the Tunnel unit ships as `sshuttle-tray-tunnel.service`

The map assumed "PKGBUILD/AUR likely route on Arch-family". Decided instead: **GitHub only, for now** — the repo is the package. A `packaging/` tree in-repo mirrors the install targets exactly, the README carries a `sudo cp -a` install table over that tree, and releases are `v1.0.0`-style tags with GitHub's auto-generated source tarball attached. The plasmoid id is `io.github.nachotek.sshuttle-tray`, installed under `/usr/share/plasma/plasmoids/` (not via `kpackagetool6 --install`). The Tunnel unit ships as the generic `sshuttle-tray-tunnel.service`, superseding the `office-tunnel.service` name used throughout earlier ADRs: a `/usr/lib` unit named `office-tunnel.service` would be **silently shadowed** by any hand-rolled `/etc/systemd/system/office-tunnel.service` (exactly the author's pre-existing situation), and the personal moniker reads oddly in a public package. Config ships as examples inside `/etc/sshuttle-tray/`; a missing `tunnel.env` fails the unit fast (required `EnvironmentFile`, no `-`), while a missing `route-set.env` degrades to the `SSHUTTLE_SUBNETS=0/0` fallback (ADR 0003). License: MIT, everything.

## Considered Options

- AUR/PKGBUILD as primary — deferred, not rejected: Arch-native and the charting-time assumption; deferred to a possible fresh effort once demand exists.
- `kpackagetool6 --install` as the install path — rejected: writes an untracked, per-user `~/.local` copy that collides on upgrade; `kpackagetool6` remains documented for inspect/uninstall only.
- GHNS (store.kde.org) listing — rejected: it can ship the widget but never the polkit rule or units, so every GHNS install is a knowingly broken Tool.
- Keep `office-tunnel.service` — rejected: silent `/etc` shadowing hazard for every hand-roller, plus a private name in a public package.
- Template unit `sshuttle-tray-tunnel@<name>.service` — rejected for v1: multi-Tunnel support is speculative; a fixed name keeps the polkit scope trivial.
- A root `install.sh` in the tarball — rejected: root shell scripts rot; a README `cp` table over a mirror-tree cannot drift from reality.
- Examples under `/usr/share/sshuttle-tray/` — rejected: less discoverable than sitting them in `/etc/sshuttle-tray/` where the root edit happens.

## Consequences

- `packaging/` is the single source of truth for install paths: plasmoid dir, `sshuttle-tray-tunnel.service` + `.d/50-sshuttle-tray-no-restart.conf`, `sshuttle-tray-apply@.service`, `/usr/share/polkit-1/rules.d/50-sshuttle-tray.rules` (both blocks, one file; a same-named `/etc` rule overrides), `tunnel.env.example`, `route-set.env.example`.
- ADR 0001/0003 consequence paths re-target the new unit name (drop-in directory, polkit passwordless block); those amendments land with the scrub pass.
- Migration off a hand-rolled unit is a README checklist (subnets → `route-set.env`, `SSHUTTLE_REMOTE`/`SSHUTTLE_REMOTE_SHELL` → `tunnel.env`, disable the old unit). There is no install hook to warn; Tool-side override detection (`systemctl show` exposes `FragmentPath` unprivileged) stays a possible nicety beyond v1.
- README requirements: `sshuttle`, Plasma 6 with `plasma5support` (tested 6.7.4 / CachyOS), `curl`, `polkit`, `systemd` — no hard version pins.
- **No-leak policy**: no IP observed from the author's network appears anywhere in repo, examples, or tracker. Examples use RFC 5737 placeholders (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) and `SSHUTTLE_REMOTE=relay.example`; ifconfig.me's own infrastructure IP is named, never numbered; the alias `office-tunnel` is non-sensitive and may stand in historical narration. Execution (file edits, tracker-comment redaction, `git filter-repo` history rewrite across branches) is wired as its own task ticket.
