# Research: tray shape options on Plasma 6.7 Wayland — plasmoid vs StatusNotifier app

Ticket: NachoTek/sshuttle-tray#2 (wayfinder research)
Date: 2026-09-09. Research only; nothing built.

Target stack (verified on the actual machine): KDE Plasma 6.7.4 (`plasma-workspace 6.7.4-3.1`, `polkit-kde-agent 6.7.4-1.1`), Frameworks 6.29 (`kpackage 6.29.0`, `kstatusnotifieritem 6.29.0` — both installed), Qt 6.11.2, systemd 261, CachyOS (Arch-based), Python 3.14.7 (`python 3.14.7-2` in repos), Wayland session with `plasmashell` running.

## Recommendation

**Standalone Python app exposing a StatusNotifierItem (SNI) icon.** Every functional requirement — pkexec systemctl, systemd state watching, timed HTTPS fetch, clickable tray presence, autostart, PKGBUILD/AUR packaging — maps to a proven capability with dependencies already in official repos (most already installed on this box). The Plasma plasmoid route is hard-blocked for pure QML: Plasma 6 ships **no dataengines at all**, so a QML plasmoid cannot spawn `pkexec` or talk D-Bus to systemd; fixing that requires a compiled per-arch C++ extension, which forfeits the plasmoid's main advantage (drop-in, arch-independent package via kpackagetool6 / "Get New Widgets"). The one trade-off: the SNI "popup" is idiomatic as a DBusMenu (ON/OFF entries + an IP row) with the IP also in the tooltip, not a bespoke QML popup with a big button.

## Option A — Plasma system-tray applet (plasmoid, QML)

### What it is
A QML/JS package (`metadata.json` + `contents/ui/main.qml`) installed as `Plasma/Applet`, embedded in the systemtray containment. Root item must be `PlasmoidItem` (Plasma 6). `metadata.json` needs `"KPackageStructure": "Plasma/Applet"` and `"X-Plasma-API-Minimum-Version": "6.0"` (without the latter the widget is treated as Plasma 5 and hidden). Sources: [develop.kde.org widget setup](https://develop.kde.org/docs/plasma/widget/setup/), [widget index](https://develop.kde.org/docs/plasma/widget/).

Tray membership keys (source: [Widget Properties](https://develop.kde.org/docs/plasma/widget/properties/#x-plasma-notificationarea-system-tray)):
- `"X-Plasma-NotificationArea": "true"` — makes the systemtray find the widget
- `"X-Plasma-NotificationAreaCategory": "SystemServices"` (allowed: `ApplicationStatus`, `Hardware`, `SystemServices`)
- `"KPlugin": { "EnabledByDefault": true }` — enabled in the tray on install

### Per-requirement facts

**Popup on click — the plasmoid's one clear win.** Default compact representation draws the icon and toggles `plasmoid.expanded` (`activationTogglesExpanded` defaults to true since KF 5.76); the full representation renders inside a `PlasmaQuick.Dialog` — an anchored Plasma-styled popup that can hold an ON/OFF `Button` and IP `Label` exactly as ticketed. Caveat: "The system tray has a fixed hardcoded size for its popups" ([setup doc](https://develop.kde.org/docs/plasma/widget/setup/)). ToolTip via `Plasmoid.toolTipMainText`/`toolTipSubText`. Sources: [setup](https://develop.kde.org/docs/plasma/widget/setup/), [properties](https://develop.kde.org/docs/plasma/widget/properties/).

**Running `pkexec systemctl …` — HARD BLOCKER for pure QML.** QML/JS has no process-execution API, and Plasma 6 removed the escape hatches that existed in Plasma 5:
- Verified on the target box: `plasma-workspace 6.7.4` ships **zero** dataengines — `/usr/lib/qt6/plugins/plasma/dataengines/` does not exist, `/usr/share/plasma/dataengines/` does not exist, and `pacman -Ql plasma-workspace | grep dataengines` returns nothing.
- Upstream: the old `dataengines/executable` source path 404s in plasma-workspace master (invent.kde.org), and the dataengines path itself is gone.
- D-Bus from pure QML is likewise unavailable (no QtDBus in QML, no DBus dataengine). So both pkexec-spawning *and* systemd-watching are blocked by the same fact.

Only fix: a compiled C++ (or Rust) QML extension plugin wrapping QProcess/QtDBus — a CMake build producing a per-arch `.so`, loaded inside plasmashell.

**Reading/watching systemd state** — blocked as above without the C++ extension; with it, QtDBus `PropertiesChanged`/`JobRemoved` would work (see Option B facts for the API).

**HTTPS fetch + timing** — pure QML *can* do this: `XMLHttpRequest` in QML is a partial W3C XHR Level 1 implementation with **no same-origin policy** (source: [Qt QML XMLHttpRequest docs](https://doc.qt.io/qt-6/qml-qtqml-xmlhttprequest.html)). GET https://ifconfig.me works; timing must be a `Date.now()` delta around `onreadystatechange` (ms resolution; the QML XHR object has no `timeout` property, only `abort()`, so a hung request needs a manual watchdog Timer).

**Polkit prompting** — if the C++ extension existed, `pkexec` from inside plasmashell would use the session's registered agent; the Plasma agent (`/usr/lib/polkit-kde-authentication-agent-1`) is running on this box (PID verified via the user bus). With the planned passwordless rule there is no prompt at all (rule below).

**Install/autostart** — no autostart concept needed: the applet lives inside plasmashell and is always alive once installed and enabled. Install routes:
- User: `kpackagetool6 -t Plasma/Applet -i <pkg>` (`kpackagetool6` ships in `kpackage` 6.29, present at `/usr/bin/kpackagetool6`) into `~/.local/share/plasma/plasmoids/`.
- System: copy to `/usr/share/plasma/plasmoids/` (what a PKGBUILD would do).
- "Get New Widgets" GUI: backed by `/usr/share/knsrcfiles/plasmoids.knsrc` (`Categories=Plasma 6 Extensions`, `Uncompress=kpackage`, `KPackageStructure=Plasma/Applet`) — i.e. publishing a `.plasmoid` payload to store.kde.org. Note the knsrc advertises `ContentWarning=Executables`, and compiled extension `.so`s do not fit the GHNS drop-in model (per-arch, trusted-executable concerns).

**Packaging precedent** — AUR has 60 packages named `plasma6-applets-*` (AUR RPC search, 2026-09-09), so an AUR plasmoid package is conventional.

**Python?** No. Plasmoids are QML/JS only, with C++ as the sole native escape (develop.kde.org Plasma widget docs cover exactly these two; there is no Python applet scripting in Plasma 6).

## Option B — standalone app exposing a StatusNotifierItem

### What it is
A normal user process registering an SNI icon on the session bus; Plasma (kded6's `org.kde.StatusNotifierWatcher`, verified live on this box) hosts the icon, menu, tooltip and balloon notifications.

### Per-requirement facts

**Tray icon from Python 3.14 — fully solved, two ways:**
1. **PySide6 `QSystemTrayIcon`.** Qt 6.11.2 docs: QSystemTrayIcon supports "All Linux desktop environments that implement the D-Bus StatusNotifierItem specification, including KDE, Gnome, Xfce, LXQt, and DDE" ([Qt docs](https://doc.qt.io/qt-6/qsystemtrayicon.html)). Gives `setIcon`, `setToolTip`, `setContextMenu(QMenu)`, `activated(Trigger/MiddleClick/Context)` signal, `showMessage()` balloons, `isSystemTrayAvailable()`. Availability: PyPI `pyside6 6.11.2` ships `cp310-abi3` wheels with `requires_python <3.15,>=3.10` (works on 3.14); Arch/CachyOS repo package `pyside6 6.11.2-1` is built against repo Python 3.14.
2. **KDE's own `KStatusNotifierItem` binding.** KDE now ships official KF6 Python bindings; the binding list includes KStatusNotifierItem, with Arch install instructions `sudo pacman -S … kstatusnotifieritem` ([develop.kde.org Python bindings](https://develop.kde.org/docs/getting-started/python/python-bindings/)). Verified on this box: `kstatusnotifieritem 6.29.0-1.1` (installed, a Plasma dependency) contains `/usr/lib/python3.14/site-packages/KStatusNotifierItem.cpython-314-x86_64-linux-gnu.so`. Richer SNI features (title, overlay/attention icon, toolTip struct) with zero extra install.

PyQt6 `6.11.0` is equally available (PyPI `cp310-abi3`, `>=3.10`; repo `python-pyqt6 6.11.0-3`). PySide6 is the safer default (LGPL, exact 6.11.2 version match).

**Popup on click — the one compromise.** On Wayland a client cannot anchor a custom window to its tray icon (no global coordinates from the compositor; Qt notes tray tooltip QHelpEvents and wheel events are X11-only — [Qt docs](https://doc.qt.io/qt-6/qsystemtrayicon.html)). The idiomatic SNI shape: right-click → DBusMenu rendered by Plasma (a QMenu with "Tunnel ON", "Tunnel OFF", and a disabled "IP: x.x.x.x" row), tooltip carries the current IP, left-click (`activated(Trigger)`) toggles the tunnel. A custom QML popup is *not* reachable from a plain Python app without layer-shell bindings, which PySide6 does not ship.

**Running `pkexec systemctl start/stop office-tunnel`** — trivial: `QProcess`/`subprocess`. `pkexec(1)` (local man page): "pkexec, like any other polkit application, will use the authentication agent registered for the calling process or session." The Plasma agent is running (verified on the user bus). With the passwordless rule below, no dialog appears at all.

**Passwordless polkit rule (planned) — exact working pattern.** Arch Wiki polkit page, section "Allow management of individual systemd units by regular users": match `action.id == "org.freedesktop.systemd1.manage-units"`, gate on `action.lookup("unit") == "office-tunnel.service"` and `action.lookup("verb")` in `start/stop/restart`, return `polkit.Result.YES` (source: [wiki.archlinux.org/title/Polkit](https://wiki.archlinux.org/title/Polkit)). This scopes the grant to exactly the one unit and verbs; ship as `/etc/polkit-1/rules.d/*.rules` in the package. Confirmed relevant actions exist under systemd 261 on this box.

**Reading/watching systemd state — first-class.** Verified live on this box via `busctl introspect org.freedesktop.systemd1 /org/freedesktop/systemd1`: the Manager implements `Subscribe()`/`Unsubscribe()`, emits `JobRemoved(uoss)` when queued jobs finish, and implements `org.freedesktop.DBus.Properties` with a `PropertiesChanged` signal (units emit it when `ActiveState` changes; `ActiveState` is a documented unit property). This matches `man org.freedesktop.systemd1` (StartUnit is specified to be used "in a race-free manner by first subscribing to the JobRemoved() signal, then calling StartUnit()"). Python access options, all in official repos: PySide6 ships `QtDBus` (verified: `PySide6/QtDBus.cpython-314-x86_64-linux-gnu.so` in the Arch pyside6 package file list) and `QtNetwork`; or `python-dasbus 1.7-5`; or `python-gobject 3.56.3-1`. A dumb fallback (poll `systemctl is-active` on a QTimer) also works and is what many tray apps do.

**HTTPS fetch + timing — full control.** `QtNetwork`'s QNetworkAccessManager, or stdlib `urllib`/`httpx`, with `time.monotonic()` deltas, real timeouts, retries, and fallback endpoints. No Wayland/Plasma constraints apply.

**Install/autostart** — XDG autostart: ship a `.desktop` in `/etc/xdg/autostart/` (system-wide, from the package). Working precedent on this exact box: `/etc/xdg/autostart/arch-update-tray.desktop` autostarts an SNI tray app.

**Live proof on the target machine** — the user's Plasma 6.7.4 session currently runs two SNI tray apps registered through `org.kde.StatusNotifierWatcher` (owned by kded6): `arch-update-tray` and `shelly-notifications`. The SNI-app shape demonstrably works in this exact environment today.

**Packaging** — standard AUR/PKGBUILD: `depends=(pyside6 kstatusnotifieritem)` (or add `python-dasbus`), plus installed artifacts: program, `office-tunnel.service`, the polkit `.rules` file, and the autostart `.desktop`. Everything is in official repos (no AUR deps). PyPI is also viable given the abi3 wheels, but AUR keeps the systemd/polkit/autostart integration in one package.

## Option C — hybrid (plasmoid + helper daemon), rejected

A pure-QML plasmoid could render the popup while a tiny standalone helper does pkexec/DBus/network, talking over the session bus. This buys the plasmoid's popup at the price of two codebases, two packaging units, and an IPC protocol — strictly worse than either single shape for this scope.

## Hard blockers / risks summary

| Requirement | A: plasmoid (pure QML) | B: Python SNI app |
| --- | --- | --- |
| Spawn `pkexec systemctl` | **Blocked** (no dataengines in Plasma 6; needs compiled C++ ext) | Trivial (QProcess/subprocess) |
| Watch systemd via D-Bus | **Blocked** (same; no D-Bus from pure QML) | Native (QtDBus/dasbus; live-verified API) |
| Timed HTTPS to ifconfig.me | Works (QML XHR; ms timing, no timeout prop) | Full control |
| Rich popup (button + label) | **Best** (fullRepresentation in PlasmaQuick.Dialog) | Degrades to DBusMenu + tooltip (Wayland) |
| Autostart | N/A (lives in plasmashell) | XDG autostart (.desktop), precedent on box |
| Packaging | Drop-in / GHNS / `plasma6-applets-*` AUR precedent — **only while pure QML**; C++ ext breaks GHNS, needs per-arch builds | Plain PKGBUILD, all deps in official repos |
| Language | QML/JS (+C++ to unblock) | Python 3.14 (PySide6 6.11.2 / PyQt6 6.11.0, abi3 + repo pkgs) |

Decision inputs for #5: if the fixed-size tray popup with a real button is deemed essential, the plasmoid route forces the C++ extension (per-arch builds, no GHNS purity) — decide that consciously. If menu-shaped UX suffices, Option B dominates on every other axis.

## Sources

- KDE developer docs: [Plasma Widget tutorial](https://develop.kde.org/docs/plasma/widget/), [Setup](https://develop.kde.org/docs/plasma/widget/setup/), [Widget Properties (tray keys)](https://develop.kde.org/docs/plasma/widget/properties/), [Python bindings for KDE Frameworks (KStatusNotifierItem)](https://develop.kde.org/docs/getting-started/python/python-bindings/)
- Qt 6.11.2 docs: [QSystemTrayIcon](https://doc.qt.io/qt-6/qsystemtrayicon.html), [QML XMLHttpRequest](https://doc.qt.io/qt-6/qml-qtqml-xmlhttprequest.html)
- Arch Wiki: [polkit](https://wiki.archlinux.org/title/Polkit) (single-unit passwordless rule pattern)
- systemd: `man org.freedesktop.systemd1` (StartUnit/Subscribe/JobRemoved/ActiveState), live `busctl introspect` on the target box
- PyPI JSON API: `pyside6 6.11.2` (`<3.15,>=3.10`, cp310-abi3), `pyqt6 6.11.0` (`>=3.10`, cp310-abi3)
- AUR RPC v5: `plasma6-applets*` naming precedent (60 hits)
- Local target-box evidence (CachyOS, Plasma 6.7.4 / KF 6.29 / Qt 6.11.2 / systemd 261 / Python 3.14.7): `pacman -Q/-Si/-Ql` for plasma-workspace, kpackage, kstatusnotifieritem (incl. the cpython-314 binding `.so`), pyside6 file list (QtDBus/QtNetwork `.so`s), python-dasbus, python-gobject, polkit-kde-agent; absence of any dataengines; live session bus state (StatusNotifierWatcher on kded6, plasmashell, polkit agent, two running SNI apps); `/etc/xdg/autostart/` entries; `/usr/share/knsrcfiles/plasmoids.knsrc`; `pkexec(1)` man page.
- invent.kde.org plasma-workspace: 404 on `dataengines/executable/*` at master (removal confirmation).
