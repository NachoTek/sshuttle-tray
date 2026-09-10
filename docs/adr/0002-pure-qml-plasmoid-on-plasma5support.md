# The Tool is a pure-QML plasmoid on the plasma5support executable engine

The shape research concluded pure-QML plasmoids were hard-blocked in Plasma 6 — no dataengines remained in plasma-workspace, so QML could neither spawn processes nor talk D-Bus — and recommended a standalone Python StatusNotifier app, accepting that the popup degrades to a DBusMenu plus tooltip. Challenged by "text command" widgets that visibly still run commands, we re-checked: the executable dataengine was moved, not removed. It lives in plasma5support (`plasma_engine_executable.so` plus the `org.kde.plasma.plasma5support` QML module), both verified on the target box, with a working third-party precedent installed on it (`org.rpa.codexbar`). The Tool is therefore a pure-QML/JS plasmoid: it runs `systemctl` and `curl` through `Plasma5Support.DataSource { engine: "executable" }` (connect → `onNewData` → `disconnectSource`), passwordless via the scoped polkit rule, and renders the charted ON/OFF button + Gateway-IP popup as a native `fullRepresentation`.

## Considered Options

- Standalone Python SNI app (PySide6 shell + KStatusNotifierItem binding) — rejected: every capability checks out, but Wayland forbids anchoring a bespoke popup at the tray icon, so the popup degrades to DBusMenu + tooltip; a standalone app also forfeits native integration (panel/tray/desktop embedding, free-floating).
- Plasmoid with a per-arch compiled C++/QML extension — rejected: CMake builds per architecture, a weaker drop-in/AUR story, and real maintenance weight. The original research's blocker stands for this route.
- Pure-QML plasmoid + localhost HTTP companion daemon — rejected: viable (QML `XMLHttpRequest` reaches `127.0.0.1`), but two moving parts where the executable engine needs none.

## Consequences

- Control path simplifies: plain `systemctl start/stop office-tunnel` under the scoped passwordless polkit rule. pkexec is dropped entirely (supersedes the pkexec mention in ADR 0001).
- No event-driven systemd watching: the Tool polls (`systemctl show -p ActiveState,SubState`, `curl -4` IP echoes) on the charted cadences; each poll spawns short-lived processes, acceptable at 5 s / 60 s.
- The popup is the charting-time design intact: ON/OFF Button oriented to Service state, live Gateway-IP label, 12-sample cap. The DBusMenu compromise is dead.
- Packaging: kpackagetool6 drop-in (GHNS-able) plasmoid; PKGBUILD ships plasmoid + polkit rule + service unit. Zero per-arch artifacts, zero Python app shell.
- Accepted risk: plasma5support is a compat layer and Plasma 7 may retire it. A whole ecosystem of command widgets depends on it, so removal would be loud and migrate-able. Re-verify on major Plasma upgrades.
