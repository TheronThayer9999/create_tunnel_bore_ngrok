# SSH over bore — reach a Windows Server VM behind NAT

A small toolkit that automatically sets up **an SSH server + an outbound tunnel** on a VM without a public IP (Windows Server, Linux, Colab, Docker…), then prints the exact SSH command to connect from anywhere.

```
   Windows Server VM                bore relay              Your machine
   (behind NAT, no public IP)       bore.pub                (anywhere)
   ┌──────────────────────┐        ┌──────────┐        ┌──────────────────────┐
   │ sshd :2222           │───────▶│ :51234   │◀───────│ ssh -p 51234         │
   │ bore local 2222 ...  │ out    │ (public) │        │ user@bore.pub        │
   └──────────────────────┘        └──────────┘        └──────────────────────┘
```

The tunnel is **initiated by the VM itself** (outbound), so you don't need port forwarding on the router, a static IP, or a VPN. It runs only while you need it — close the window and the tunnel is gone; no background service is installed.

Each platform has **exactly one entry file**: `bore-ssh.bat` (Windows) or `bore-ssh.sh` (Linux/macOS).

---

## 1. Requirements

| Component | Notes |
|---|---|
| Windows Server VM | Windows Server 2019+ (recommended) or 2016 (falls back to Win32-OpenSSH); outbound internet, Administrator rights |
| PowerShell 5.1 | Ships with Windows |
| `curl.exe`, `tar.exe` | Ships with Windows 10 / Server 2019+ (used to download bore) |
| Client machine | Needs `ssh` (Windows 10+, Linux, macOS) |
| bore | Downloaded automatically into `bin/` |

---

## 2. Quick start on the Windows Server VM

```bat
git clone <repo-url> D:\script_tunnel_ssh
cd D:\script_tunnel_ssh
bore-ssh.bat setup
```

Or simply **double-click `bore-ssh.bat`** and pick `[1] Setup SSH server + mo tunnel` — the script asks for Administrator rights via UAC.

The `setup` command runs, in order:

1. Downloads `bore.exe` into `bin\` (if missing)
2. Installs **OpenSSH Server** (Windows Capability, falls back to Win32-OpenSSH from GitHub)
3. Enables the `sshd` service (Automatic + Start)
4. Opens the firewall for the SSH port
5. Writes `sshd_config`: `Port 2222`, `PasswordAuthentication yes` (with a backup)
6. Sets the account password (generated if `--password` is not given)
7. **Self-checks**: `sshd -T`, service RUNNING, port LISTENING
8. Opens the bore tunnel, reads the public port, prints the SSH command

Final output looks like:

```
[ok] SSH SERVER DA SAN SANG

  User     : Administrator
  Password : Aa1!x8Kp2mQz7

  ============================================================
     TUNNEL DANG MO
  ============================================================
     Cong khai : bore.pub:51234
     SSH vao   : ssh -p 51234 Administrator@bore.pub
  ============================================================

  [i] Tunnel dang chay. Nhan phim bat ky de DUNG tunnel va thoat.
```

> **Note:** the password is generated and shown only once — save it.
> Keep this window open; closing it stops the tunnel.

*(Console messages are in Vietnamese; this README is the English reference.)*

---

## 3. Connecting from another machine

```bash
ssh -p 51234 Administrator@bore.pub
```

The command has three parts:

| Part | Meaning | Where it comes from |
|---|---|---|
| `Administrator` | Windows user **on the VM** | the account you log into Windows with (or `--user NAME`) |
| `bore.pub` | the bore relay, **not** your VM | fixed |
| `-p 51234` | public port assigned by bore | printed when the tunnel opens |

bore has **no UUID or token**: the port number is the only identifier of the tunnel. The password is the password of that Windows account.

> **Don't know the username?** `Administrator` is just the Windows account **on the VM** (bore does not create it). Run `whoami` on the VM to see the exact name. Windows Server defaults to `Administrator`; if you created your own account during install, use that name — or run `bore-ssh.bat setup --user YourName` so the script prints the right command.

### Shortcuts so you don't memorize the port (recommended)

**Option 1 — pin the port** in `tunnel.conf`:

```ini
REMOTE_PORT=51234
```

From then on it is always `ssh -p 51234 user@bore.pub`.

**Option 2 — SSH config alias** (on the client), edit `~/.ssh/config`:

```
Host vm
    HostName bore.pub
    Port 51234
    User Administrator
    ServerAliveInterval 30
```

Then just:

```bash
ssh vm
```

If the port changes, edit that single `Port` line. On Windows the file is `%USERPROFILE%\.ssh\config`.

**Option 3 — the client helper** (asks host/port/user the first time, then connects directly):

```bat
bore-ssh.bat c        :: Windows
```
```bash
./bore-ssh.sh c       # Linux / macOS
```

Details are cached in `.bore-ssh-last`, so from the second run on it is a single action.

### A note on usage time

The script **does not** install a service or scheduled task: the tunnel lives only in the running window. Using it for a few hours and closing is perfectly fine, nothing to clean up. You only need Task Scheduler / `nohup` / `tmux` if you want long-running background tunnels.

---

## 4. Reopening the tunnel later

No need to re-run setup — just open the tunnel:

```bat
bore-ssh.bat s        :: Windows (s = server)
```
```bash
./bore-ssh.sh s       # Linux / macOS
```

Print the command without running it:

```bat
bore-ssh.bat s --dry-run
```

---

## 5. Configuration — `tunnel.conf`

`bore-ssh.bat setup` creates `tunnel.conf` from the example and fills in `SSH_PORT` + `SSH_USER`. To edit it manually:

```bat
copy tunnel.conf.example tunnel.conf
```

| Key | Meaning | Default |
|---|---|---|
| `BORE_SERVER` | Relay server: `bore.pub` or `host:7835` | `bore.pub` |
| `SSH_PORT` | Internal SSH port on the server machine | `2222` |
| `SSH_USER` | User printed in the SSH command | empty |
| `SSH_KEY` | Private key for client mode | empty |
| `REMOTE_PORT` | Request a fixed public port from bore | empty = random |
| `BORE_BIN` | Path to the `bore` binary | `bin/bore(.exe)` |
| `BORE_ARGS` | Extra arguments for `bore local` | empty |

Expose the SSH of **another machine on the LAN** through the machine running the script:

```ini
BORE_ARGS=--local-host 192.168.1.50
```

Use your own relay with a secret:

```ini
BORE_SERVER=bore.example.com:7835
BORE_ARGS=--secret my-secret
```

---

## 6. Command-line options — `bore-ssh.bat setup`

| Option | Effect |
|---|---|
| `--port N` | Internal SSH port (default 2222) |
| `--password P` | Set a password instead of generating one |
| `--user NAME` | User used for SSH (default: current user) |
| `--ssh-only` | Only set up SSH, don't open the tunnel |
| `--skip-password` | Leave the current password unchanged |
| `--dry-run` | Print the steps without changing anything |

Short commands: `st` = setup, `s` = server, `c` = client, `i` = install, `l` = logs.

---

## 7. Linux / Colab / Docker

```bash
chmod +x bore-ssh.sh
./bore-ssh.sh setup
```

Same behaviour as the Windows version: installs `openssh-server` for the detected distro, writes the drop-in `/etc/ssh/sshd_config.d/99-bore-tunnel.conf`, sets the password, starts sshd, self-checks, then opens bore and prints the SSH command.

```bash
./bore-ssh.sh setup --port 2222 --password 'MySecurePass123'
./bore-ssh.sh setup --ssh-only          # only enable SSH
./bore-ssh.sh setup --dry-run           # preview
```

On Colab/Docker (no systemd) the script starts `sshd` directly and uses port `2222`.

---

## 8. Security — read before use

- `bore.pub` is a **public relay**: anyone who knows `bore.pub:PORT` can reach your `sshd`. SSH still requires a login, but you should:
  - use a strong password (the script generates a 16-character one), or better, **SSH keys**;
  - avoid leaving the tunnel open 24/7 when unused;
  - a random public port is an extra layer against scanning.
- The script **enables** `PermitRootLogin yes` and `PasswordAuthentication yes` (Linux) / opens the firewall and enables password auth (Windows) for convenience. That is a security trade-off — for production, use keys and disable password auth.
- Want more privacy: self-host `bore server --secret ...` and configure `BORE_SERVER` + `BORE_ARGS=--secret ...`.
- Every config change is backed up: `sshd_config.bore-ssh.bak` (Windows: `C:\ProgramData\ssh\sshd_config.bore-ssh.bak`).

---

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Pressing `1` makes the window disappear | It self-elevates via UAC into a new Administrator window. If the result isn't visible, run `bore-ssh.bat setup` from an Administrator terminal and read the output there |
| Windows Defender flags `bore.exe` as a virus and deletes it | Common false positive for Rust tunnel binaries. `setup` (as Admin) adds `bin\` to Defender exclusions automatically; or run `Add-MpPreference -ExclusionPath "<repo>\bin"` in an Admin PowerShell, then `bore-ssh.bat install` |
| `Khong mo duoc tunnel` and the log says port in use | The `REMOTE_PORT` is taken → pick another number or leave it empty |
| `sshd` is not running | Windows: `Get-Service sshd` / `Restart-Service sshd`; Linux: check `/tmp/sshd-bore.log` |
| Connection works but `Permission denied` | Check the user exists and is enabled, the password is correct, `PasswordAuthentication yes` |
| The public port keeps changing | Set a fixed `REMOTE_PORT` in `tunnel.conf` |
| Closing the window kills the tunnel | By design. For background use: Task Scheduler (Windows) or `nohup`/`tmux` (Linux) |
| Leftover bore process | Windows: `taskkill /IM bore.exe /F` — Linux: `pkill -x bore` |
| Need to debug the connection | `ssh -vvv -p PORT user@bore.pub` |

Quick checks on the server side:

```bat
sshd -T | findstr /I "port passwordauth"
netstat -ano | findstr :2222
```

---

## 10. Logs & attack detection

Because the public port lives on `bore.pub`, **bots will scan it**. The script enables logging and ships a check command.

| Log location | Content |
|---|---|
| Windows: Event Log `OpenSSH/Operational` | every connection, failed login, unknown user |
| `sshd_config` → `LogLevel VERBOSE` | records the usernames being tried |
| `.bore-ssh.log` | bore's own log (relay connections) |

Quick check:

```bat
bore-ssh.bat logs              :: last 24 hours
bore-ssh.bat logs --hours 6    :: last 6 hours
```
```bash
./bore-ssh.sh logs
```

The report shows: failed password count, usernames probed, top IPs, **peak connections per minute** (flood indicator), and a verdict: normal / being scanned / being flooded.

> ⚠️ **Important:** through bore, every connection to sshd comes from `127.0.0.1`, so logs **cannot reveal the attacker's real IP**. You still get counts, probed usernames and rate — enough to know whether the machine is being scanned or flooded.

Real risk reduction (not just watching logs):

- use **SSH keys** instead of passwords;
- keep the port hard to guess (`REMOTE_PORT`) and rotate it;
- restrict which users may log in;
- only open the tunnel while you need it;
- **do not** use fail2ban here — it sees `127.0.0.1` and would ban your own tunnel.

To see real IPs you would need to self-host bore behind a reverse proxy with PROXY protocol, or use Cloudflare Tunnel.

---

## 11. Repository layout

```
.
├── bore-ssh.bat                  # [Windows] single entry: menu + setup + tunnel + client
├── bore-ssh.sh                   # [Linux]   single entry: menu + setup + tunnel + client
├── scripts/
│   ├── setup-sshd-windows.ps1    #   install/configure OpenSSH Server (Windows)
│   ├── setup-ssh-linux.sh        #   install/configure sshd (Linux/Colab/Docker)
│   ├── check-log.ps1             #   log analysis + attack detection (Windows)
│   └── check-log.sh              #   log analysis + attack detection (Linux)
├── tunnel.conf.example           # config template (copy to tunnel.conf)
└── bin/                          # bore binary, downloaded automatically (gitignored)
```

Execution flow:

```
bore-ssh.bat setup
  └─ scripts/setup-sshd-windows.ps1   (install + configure + self-check)
  └─ open tunnel, read port, print SSH command
```

---

## License

MIT — use it freely, but you are responsible for the security configuration of your own machine.
