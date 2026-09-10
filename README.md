# sshuttle-tray

A KDE Plasma 6 tray Tool that starts, stops, and **truth-checks** an sshuttle
tunnel (`sshuttle-tray-tunnel.service`).

systemd's state can lie: the service reports `active` while traffic silently
bypasses a dead tunnel — after network loss, roaming, or an sshuttle crash.
sshuttle-tray judges the **Effective state** from evidence the outside world
produces: IP-echo endpoints whose reported **Local Gateway** differs from
that endpoint's own **Baseline**, and — for scoped Route Sets — an optional
**Ping Target**. Echo silence (**No-answer**) is never treated as "IP
unchanged". A tunnel that is active but has no in-scope evidence shows
**On + Unverified** rather than a false Alert. See [`CONTEXT.md`](CONTEXT.md)
for the vocabulary and [`docs/adr/`](docs/adr/) for the decisions.

The tray icon shows **Off / Starting / On / Alert**; the popup carries the
state word, the cause (Revert, never-effective, service failed, Ping Target
unreachable), the Local Gateway with a freshness chip (LIVE / STALE /
NO ANS), and the Remote Gateway as its configured SSH alias.

## Requirements

- **sshuttle** (tested 1.3.2 — ships `sd_notify` support, which the unit's
  `Type=notify` relies on)
- **KDE Plasma 6** with the **plasma5support** compat layer
  (`plasma_engine_executable.so`; verified on Plasma 6.7.4 / CachyOS).
  No other Plasma pieces are required. Re-verify on major Plasma upgrades —
  plasma5support is a compat layer and its retirement is a known accepted
  risk (ADR 0002).
- **curl** (IPv4-pinned HTTPS queries to public IP-echo endpoints)
- **polkit** (one rules file) and **systemd** (Tunnel unit + apply unit)

No version pins beyond the above. Everything runs as your user except the two
system units and the root apply helper.

## Install

The repo is the package (ADR 0005): releases are `v1.0.0`-style tags; download
the source tarball, extract it, and copy the `packaging/` tree over the
filesystem. There is no build step and no install script. Run, as root, from
the extracted tree (`sudo cp -a` preserves the executable bit on the helper):

| copy from (under the tarball root) | to | then |
|---|---|---|
| `packaging/usr/share/plasma/plasmoids/io.github.nachotek.sshuttle-tray` | `/usr/share/plasma/plasmoids/` | add the widget to your system tray (see below) |
| `packaging/usr/lib/systemd/system/sshuttle-tray-tunnel.service` | `/usr/lib/systemd/system/` | `sudo systemctl daemon-reload` |
| `packaging/usr/lib/systemd/system/sshuttle-tray-tunnel.service.d` | `/usr/lib/systemd/system/` | (drop-in: `Restart=no`) |
| `packaging/usr/lib/systemd/system/sshuttle-tray-apply@.service` | `/usr/lib/systemd/system/` | (same daemon-reload) |
| `packaging/usr/lib/sshuttle-tray/apply-route-set.sh` | `/usr/lib/sshuttle-tray/` | must stay executable (`cp -a` handles it) |
| `packaging/usr/share/polkit-1/rules.d/50-sshuttle-tray.rules` | `/usr/share/polkit-1/rules.d/` | (polkit picks it up automatically) |
| `packaging/etc/sshuttle-tray/tunnel.env.example` | `/etc/sshuttle-tray/tunnel.env` | **edit it** (see Configuration) |
| `packaging/etc/sshuttle-tray/route-set.env.example` | `/etc/sshuttle-tray/route-set.env` | optional — a missing file means the full `0/0` tunnel |

Or as one shot:

```sh
sudo cp -a packaging/usr/. /usr/
sudo mkdir -p /etc/sshuttle-tray
sudo cp -a packaging/etc/sshuttle-tray/tunnel.env.example /etc/sshuttle-tray/tunnel.env
sudo cp -a packaging/etc/sshuttle-tray/route-set.env.example /etc/sshuttle-tray/route-set.env
sudo systemctl daemon-reload
$EDITOR /etc/sshuttle-tray/tunnel.env   # set SSHUTTLE_REMOTE (see below)
```

Then right-click the panel → *Add Widgets…* → search **sshuttle-tray** → drag
it into the System Tray. Tray click opens the popup; the power icon in the
popup header is the sole start/stop toggle (passwordless via the polkit rule).
The widget's settings (panel tray entry → configure) hold the sampling
cadences, the Route Set editor, and the Ping Target.

`kpackagetool6` is for inspecting and uninstalling only — never install:

```sh
kpackagetool6 -t Plasma/Applet -l                 # inspect
sudo rm -rf /usr/share/plasma/plasmoids/io.github.nachotek.sshuttle-tray   # uninstall
```

## Configuration

**`/etc/sshuttle-tray/tunnel.env`** (required, install-time, root-owned):

```ini
SSHUTTLE_REMOTE=relay.example     # the sshuttle -r: SSH alias or user@host[:port]
SSHUTTLE_REMOTE_SHELL=ssh         # one word: the --ssh-cmd sshuttle runs
```

The unit's ssh runs as root and non-interactively, so the relay must accept
root's SSH key — see [`docs/key-auth.md`](docs/key-auth.md) for the full
walkthrough (dedicated key, deploy on a Linux or Windows relay,
non-interactive verification).

**`/etc/sshuttle-tray/route-set.env`** (optional; the settings dialog
installs it through the root apply unit with exactly one password prompt per
change; hand edits are equally valid and apply on the next Tunnel start):

```ini
SSHUTTLE_SUBNETS=192.0.2.0/24 198.51.100.0/24
SSHUTTLE_PING_TARGET=192.0.2.55    # optional: a host inside the Route Set
```

Behaviour notes:

- Missing `tunnel.env` fails the unit **fast** — a half-configured install
  should be loud. Missing `route-set.env` degrades to the full `0/0` tunnel.
- The apply unit validates CIDRs (garbage is rejected, nothing is written)
  and warns when a literal-IP Ping Target lies outside the Route Set. The
  settings dialog shows the same warning client-side before you apply.
- Changing the Route Set while the Tunnel runs never restarts it; the popup
  offers **Restart** through the normal passwordless path.
- The Tunnel unit ships `Restart=no` by design (ADR 0001): failure surfaces
  as the tray's Alert, retry is a manual press. To restore auto-restart, drop
  a same-named file in `/etc/systemd/system/sshuttle-tray-tunnel.service.d/`
  — `/etc` outranks the packaged `/usr/lib` drop-in. The Tool never writes
  to `/etc` at runtime.
- A hand-rolled `/etc/systemd/system/sshuttle-tray-tunnel.service` would
  silently shadow the packaged unit — the fixed name is deliberate (ADR 0005).

## Migrating from a hand-rolled `office-tunnel.service`

Mechanical cut-over:

1. **Subnets** — lift the inline CIDRs from your old unit's `ExecStart` into
   `/etc/sshuttle-tray/route-set.env` as the space-separated
   `SSHUTTLE_SUBNETS=` value (or `0/0` if you routed everything).
2. **Remote settings** — put your `-r` value into `SSHUTTLE_REMOTE` and your
   ssh command into `SSHUTTLE_REMOTE_SHELL` in
   `/etc/sshuttle-tray/tunnel.env`.
3. **Disable the old unit** — `sudo systemctl disable --now office-tunnel`
   (and remove its file if you like; keep a copy of its subnets first).
4. **Migrate auto-restart policy** — if you *want* the old `Restart=on-failure`
   back, add the `/etc` drop-in described above; otherwise the Tool owns the
   lifecycle from here on.

## Manual verification

Everything above the two tested seams (the JS decision core and the apply
validator — `node --test tests/`) is verified on the target box by hand:

1. **Tray**: widget appears in the system tray; ring shows Off / Starting /
   On / Alert; tooltip carries the state word, Local Gateway, staleness.
2. **Control path**: power icon starts/stops the Tunnel with no password
   (polkit rule); the failed-service case shows the service-failed Alert.
3. **Evidence**: with a `0/0` Route Set the icon reaches On after an endpoint
   reports a Local Gateway different from its Baseline; stopping sshuttle
   mid-flight (e.g. `sudo systemctl kill -s KILL sshuttle-tray-tunnel`)
   flips it to Revert within the grace window.
4. **Route Set apply**: settings dialog → edit CIDRs → Apply → one password
   prompt; `cat /etc/sshuttle-tray/route-set.env` shows the new set; popup
   offers Restart.
5. **Ping Target**: configure one, confirm `ping -4 -c1 -W2` runs every ~60 s
   while the Tunnel is active and three losses raise the Alert.

## Privacy / no-leak policy

No IP observed from any real network appears in this repo. Examples use RFC
5737 documentation addresses (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) and
the `relay.example` alias. The Tool queries public IP-echo endpoints
(`ifconfig.me/ip`, `ipv4.icanhazip.com`, `api.ipify.org`) over HTTPS,
IPv4-pinned, cookie-less, rotating; peak client rate is 0.2 req/s.

## License

MIT — everything in this repository. See [LICENSE](LICENSE).
