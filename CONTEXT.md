# office-tunnel tray

A tray tool for KDE Plasma that starts, stops, and truth-checks the `office-tunnel` sshuttle systemd service. Exists because service state alone can lie: only the outside world can confirm the tunnel actually carries traffic.

## Language

**Tool**:
The Plasma plasmoid itself. Owns no networking; it drives the Tunnel and observes evidence.
_Avoid_: app (when ambiguous), client, standalone app

**Tunnel**:
The `sshuttle-tray-tunnel.service` systemd unit running `sshuttle` over the current Route Set.
_Avoid_: VPN, connection, office-tunnel (when the service is meant)

**Route Set**:
The set of subnets the Tunnel pushes traffic for (`0/0` = everything), held root-owned and edited through the Tool's settings with one password prompt per change.
_Avoid_: subnet list, scope, routes

**Service state**:
What systemd reports for the Tunnel: inactive, activating, active, failed. Cheap to read, but says nothing about traffic.
_Avoid_: status, running state

**Effective state**:
Whether traffic actually routes through the Tunnel, judged by evidence: any endpoint's Local Gateway differing from its own Baseline, or — with no echo path in scope — the Ping Target answering. The only trustworthy "it works" signal.
_Avoid_: real status, actual status

**Local Gateway**:
The public IPv4 an IP-echo endpoint reports for this machine — its WAN egress address, not the LAN router. Queried IPv4-pinned (v6 leaks around a `0/0` tunnel); each endpoint keeps its own value, and under a scoped Route Set endpoints may legitimately disagree (an in-scope endpoint reports the office egress). Formerly "Gateway IP".
_Avoid_: Gateway IP, public IP, external IP, ISP gateway, default-route/lan-router address

**Remote Gateway**:
The sshuttle relay the Tunnel routes through — the `-r` SSH endpoint, displayed as its configured alias. Informational; not an Effective-state signal by itself.
_Avoid_: VPN gateway, VPN server, exit node

**Baseline**:
The Local Gateway per echo endpoint, captured while the Tunnel is confirmed stopped; the reference for detecting change and Revert. Re-captured whenever the Tunnel is stopped.
_Avoid_: pre-start value, home IP

**Revert**:
An in-scope endpoint's Local Gateway returning to its Baseline while the Tunnel is active — the Tunnel died or is bypassed; the Tool raises a warning.
_Avoid_: drop, disconnect

**Alert**:
The one attention icon state, covering Revert, a failed Tunnel, a start that never became effective, and a Ping Target gone unreachable. The cause is named in the popup, not carried by the icon.
_Avoid_: warning state, failed state (as separate icons)

**Verifying**:
The grace window after the service reports active while no endpoint's Local Gateway has diverged from its Baseline. Shown as Starting; escalates to Alert only after the window closes.
_Avoid_: pending, connecting

**No-answer**:
A sample where every echo endpoint timed out. Carries no evidence about the Effective state; never treated as "IP unchanged" and never moves the icon.
_Avoid_: timeout error, sample failure (as evidence)

**Ping Target**:
An optional host inside the Route Set that must answer a ping while the Tunnel is active; sustained silence is evidence the Tunnel is defunct.
_Avoid_: probe, probe host, health check

**Unverified**:
The honest qualifier when the Tunnel is active but no in-scope evidence exists (no endpoint diverged, no Ping Target configured). Shown as On; never an Alert.
_Avoid_: unknown, uncertain
