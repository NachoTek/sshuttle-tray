# Tunnel key auth — setting up the ssh relay

The Tunnel runs as a **system service**: sshuttle, and the `ssh` it spawns,
run as **root**, non-interactively. Nobody can type a password or accept a
host-key prompt from inside a systemd unit, so the relay must accept **root's
SSH key** without interaction. This guide walks that setup end to end: one
dedicated key, an SSH config alias, the public key deployed on the relay
(Linux or Windows), and a non-interactive verification before you touch
`tunnel.env`.

All hostnames, users, and addresses below are placeholders (RFC 5737 /
`relay.example`); substitute your own.

## 1. Generate a dedicated key for root

On the machine running sshuttle-tray:

```sh
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_sshuttle -N ""
```

- A **dedicated key** (not your login key) keeps the Tunnel's access easy to
  revoke independently.
- `-N ""` (no passphrase) is required: a passphrase-protected key can never
  be answered from the unit. The key file lives in `/root/.ssh/` with root-only
  permissions — treat it like a password that grants SSH access to the relay.

## 2. Give root an SSH config alias for the relay (recommended)

`sudo tee /root/.ssh/config` (then `sudo chmod 600 /root/.ssh/config`):

```
Host relay.example
    HostName 192.0.2.10
    User me
    Port 22
    IdentityFile /root/.ssh/id_ed25519_sshuttle
    IdentitiesOnly yes
```

With this, `SSHUTTLE_REMOTE=relay.example` in `tunnel.env` is enough — host,
user, port, and key all resolve from root's SSH config. (You can equally set
`SSHUTTLE_REMOTE=me@192.0.2.10:22` and skip the alias; the key still has to
be root's.)

## 3. Deploy the public key on the relay

The public key to deploy is `/root/.ssh/id_ed25519_sshuttle.pub` on the
sshuttle machine.

### Linux relay

```sh
sudo ssh-copy-id -i /root/.ssh/id_ed25519_sshuttle.pub me@relay.example
```

(one password prompt, never needed again), or by hand:

```sh
sudo cat /root/.ssh/id_ed25519_sshuttle.pub \
  | ssh me@relay.example 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Optional hardening — on the relay, prefix the line in `~/.ssh/authorized_keys`
with:

```
no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... sshuttle-tunnel
```

sshuttle needs to run its python helper and open TCP channels through this
key, so do **not** use `restrict` or `no-port-forwarding` — the Tunnel would
break.

### Windows relay (OpenSSH Server)

On the Windows box first (Administrator PowerShell):

```powershell
# OpenSSH server as an optional feature
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
```

sshuttle also runs a python helper on the relay, so install Python on the
Windows box (from python.org or the Microsoft Store) and make sure `python`
is in PATH for SSH sessions.

Then deploy the key — the location depends on the account:

- **Standard user account** → append the public key line to
  `C:\Users\<user>\.ssh\authorized_keys` (create the `.ssh` folder if needed).
- **Administrator account** → Windows OpenSSH deliberately ignores per-user
  `authorized_keys` for admins; the file is
  `C:\ProgramData\ssh\administrators_authorized_keys`. Append the public key
  line, then repair its ACL (OpenSSH rejects the file if group inheritance
  leaks through):

  ```powershell
  icacls "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:F" /grant "BUILTIN\Administrators:F"
  ```

Caveat, stated honestly: sshuttle's supported target is a unix relay. A
Windows relay with `cmd.exe` as the OpenSSH default shell can mangle the
quoting of sshuttle's python bootstrap. If key auth verifies (next section)
but the Tunnel then dies with a python/stager error, switch the default shell
to PowerShell:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

## 4. Verify non-interactively, as root, before wiring the unit

```sh
sudo ssh -o BatchMode=yes relay.example true && echo KEY AUTH OK
```

`BatchMode=yes` forbids every interactive fallback (password, host-key
prompt), so a passing `KEY AUTH OK` proves exactly what the unit needs. The
first-ever connection also records the relay's host key for root; do that
with this command (answer the fingerprint prompt once) if you skipped the
alias and use a bare `user@host`.

## 5. Point the Tunnel at it

`/etc/sshuttle-tray/tunnel.env`:

```ini
SSHUTTLE_REMOTE=relay.example     # or me@192.0.2.10:22
SSHUTTLE_REMOTE_SHELL=ssh         # the ssh binary ON THIS MACHINE — not the relay's shell
```

Then start the Tunnel once from a terminal where you can watch it:

```sh
sudo systemctl start sshuttle-tray-tunnel.service
journalctl -u sshuttle-tray-tunnel.service -f
```

and finish with the tray Tool: the popup should leave **Starting** for **On**
within its ~30 s verification window (echo endpoints reporting a Local
Gateway different from the captured Baseline).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Failed to find '<word>' in path …` | `SSHUTTLE_REMOTE_SHELL` isn't a real ssh binary on this machine (e.g. `cmd`) — set it to `ssh` |
| ssh falls through to a password prompt; `ssh -vvv` shows only default identities and **no `Offering public key` line** | root's `/root/.ssh/config` is missing or its `Host` pattern doesn't match the address you connect to, so the custom-named key is never offered — recreate the step 2 config and check the `Host` line matches `SSHUTTLE_REMOTE` exactly |
| Unit fails, journal shows `Permission denied (publickey)` | key not deployed for the account you connect as, wrong file/ACL on the relay, or root's config doesn't pick the key (`IdentityFile`/`IdentitiesOnly`) |
| Key deploys but is refused from an *admin* account on a domain-joined Windows relay | AD-nested group membership can fail the sshd `Match Group administrators` check — put the key in the user-profile `authorized_keys` as well, and make sure the file isn't UTF-16 (`Format-Hex`, no `FF FE` lead-in) |
| First start hangs then fails, journal mentions host key | host key never accepted for root — run the step 4 command once |
| Key auth OK but Tunnel fails with a python error | relay has no `python3` in PATH (Linux), or Windows default-shell quoting (see above) |
