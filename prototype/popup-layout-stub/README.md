# Popup layout prototype — THROWAWAY

Three structurally different popup variants for the office-tunnel tray tool,
switchable in-place, driven by the real `plasma5support` executable engine.
This is a wayfinder prototype for [ticket #7](https://github.com/NachoTek/sshuttle-tray/issues/7).
Not the real plasmoid. Do not build on it.

- **Variant A — Status hero**: big state ring + word, gateway IP secondary, fat button.
- **Variant B — Switch-first terminal**: big switch, dark monospace readout, sample-budget dots.
- **Variant C — Dense rows**: compact key/value grid, alert banner, tooltip carries the cause.

**SIM** (default) runs a scripted timeline: off → activating → verifying → on →
no-answer → revert-grace → alert → off. The power control jumps to the next
service change in the timeline.
**LIVE** polls the real `office-tunnel` service and `curl -4` IP echoes
(ifconfig.me with icanhazip fallback) and shows engine telemetry (latency, exit
code, stderr) in the footer. The power button is a no-op unless "live control"
is checked in the footer — note it may prompt for polkit and WILL toggle your
real tunnel.

## Run

    ./install.sh

Then add it to the system tray: right-click the panel → *Enter Edit Mode* →
*Add Widgets…* → search "sshuttle-tray PROTOTYPE" → drag into *System Tray*
(or System Tray settings → Entries → Add). Click the ring icon to open the
popup, flip variants with ◀ ▶ in the footer bar.

Reload after edits: `./install.sh` again (updates the package), then the
plasmoid re-loads on popup reopen; if stale, restart plasmashell.

## Remove

    kpackagetool6 -t "Plasma/Applet" -r org.nachotek.sshuttletray.proto
