<div align="center">
<pre>
┌────────────────────────────────────────────────┐
│  ____                    _  _____              │
│ / ___|   __ _  _ __   __| ||  ___|___  __  __ │
│ \___ \  / _` || '_ \ / _` || |_  / _ \ \ \/ / │
│  ___) || (_| || | | || (_| ||  _|| (_) | >  < │
│ |____/  \__,_||_| |_| \__,_||_|   \___/ /_/\_\│
│                                                │
│      Sandboxed Firefox for Security Work       │
└────────────────────────────────────────────────┘
</pre>
</div>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/container-Docker-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/browser-Firefox-FF7139?style=flat-square&logo=firefox&logoColor=white" alt="Firefox">
  <img src="https://img.shields.io/badge/security-hardened-green?style=flat-square" alt="Hardened">
</p>

<p align="center">
  A hardened, disposable Firefox browser in a Docker container.<br>
  Open suspicious links. Investigate phishing. Analyze malware sites.<br>
  <strong>Nothing persists. Nothing touches your host.</strong>
</p>

---

## Why?

Security teams, IT professionals, and researchers routinely need to open links they don't trust — phishing URLs from reported emails, suspicious domains from threat intel feeds, or sketchy attachments with embedded links. Doing this on your daily-driver machine is risky, even with a VM.

Sandfox gives you a **disposable, hardened browser** you can spin up in seconds on macOS:

> - **Investigate phishing links** without exposing your host browser, cookies, or credentials
> - **Analyze suspicious websites** in an isolated environment that is destroyed on exit
> - **Triage reported emails** by safely opening every link an end user forwarded to you
> - **Browse hostile content** with aggressive tracking protection, fingerprinting resistance, and ad blocking pre-configured

No state leaks between sessions. No data persists. Nothing touches your host filesystem.

> [!NOTE]
> This project has been under development since **May 2024**, evolving from a basic containerized Firefox into a fully hardened, security-focused sandbox with privacy-tuned browser profiles, enterprise policy enforcement, and pre-configured ad/malware blocking.

---

## Quick Start

### Prerequisites

Install via [Homebrew](https://brew.sh):

```bash
brew install colima docker docker-compose docker-buildx
brew install --cask xquartz
brew install pulseaudio
```

> [!NOTE]
> After installing XQuartz for the first time, you must **log out and log back in** for it to work.

### Usage

```bash
bash run.sh start     # Start everything
bash run.sh status    # Check all services
bash run.sh stop      # Tear it all down
```

Running `bash run.sh` without a command defaults to `start`. The script is idempotent — it skips any service that is already running.

> [!IMPORTANT]
> Always use `bash run.sh start` — do not run `docker compose up` directly. The run script generates auth files and configures network filtering that the container depends on.

```
$ bash run.sh status

Colima:      running
XQuartz:     running
X11 auth:    cookie-based (secure)
PulseAudio:  running (TCP :4713, cookie auth)
Egress:      filtered (HTTP/HTTPS/DNS only)
Firefox:     running (docker-firefox-sandfox-1)

All services are running.
```

---

## Security Hardening

### Threat Model

Sandfox assumes that every visited URL **will** contain malware. The sandbox is designed to contain browser exploits, prevent container escape, block data exfiltration, and protect the host even if Firefox is fully compromised.

### Container Lockdown

```
  ╔══════════════════════════════════════════════════════╗
  ║               CONTAINER SECURITY                    ║
  ╠══════════════════════════════════════════════════════╣
  ║                                                     ║
  ║   Filesystem ····· read-only rootfs                 ║
  ║   Capabilities ··· ALL dropped (+SYS_CHROOT only)   ║
  ║   Privileges ····· no-new-privileges                ║
  ║   Seccomp ········ custom default-deny profile      ║
  ║   User ··········· non-root (uid 999)               ║
  ║   Storage ········ volatile tmpfs (noexec)          ║
  ║   Network ········ egress filtered (HTTP/S/DNS)     ║
  ║   Resources ······ 6 CPU / 6 GB RAM / 512 PIDs     ║
  ║   Core dumps ····· disabled                         ║
  ║                                                     ║
  ╚══════════════════════════════════════════════════════╝
```

### Seccomp Profile

A custom **default-deny** seccomp profile (`seccomp-firefox.json`) allowlists only the syscalls Firefox needs. Blocked syscalls include:

- `io_uring` — exploit payload vector
- `syslog` — kernel information disclosure
- `name_to_handle_at` — container escape vector (CVE-2015-1335)
- `kexec_load`, `reboot`, `init_module` — kernel manipulation
- `ptrace` — process tracing / escape

### Network Egress Filtering

`run.sh` configures iptables rules in the Colima VM to restrict container traffic:

| Allowed | Blocked |
|---------|---------|
| HTTP (TCP 80) | All RFC 1918 private ranges |
| HTTPS (TCP 443) | Host gateway (except X11 + audio) |
| DNS (UDP/TCP 53) | All other ports and protocols |
| X11 to host (TCP 6000) | LAN scanning |
| PulseAudio to host (TCP 4713) | C2 / exfiltration channels |

### Authentication

All host-facing services use **cookie-based authentication** instead of open access:

- **X11**: MIT-MAGIC-COOKIE via Xauth (replaces `xhost +localhost`)
- **PulseAudio**: Cookie-based TCP auth (replaces `auth-anonymous=1`)

Auth credentials are generated fresh on each `run.sh start` and stored at `~/.config/sandfox/`.

### Browser Hardening

The Firefox profile ships with a hardened [`user.js`](user.js) that locks down `about:config`:

<details>
<summary><strong>Privacy & Anti-Tracking</strong></summary>

- Tracking protection (trackers, cryptominers, fingerprinters, social tracking)
- First-party isolation — prevents cross-site cookie tracking
- Session-only cookies — destroyed when Firefox closes
- Fingerprinting resistance enabled

</details>

<details>
<summary><strong>Network Hardening</strong></summary>

- HTTPS-only mode — refuses insecure connections
- DNS-over-HTTPS (mode 3) via Cloudflare's malware-blocking resolver (`security.cloudflare-dns.com`)
- WebRTC disabled — prevents real IP address leaks
- DNS/link prefetching disabled — no speculative requests to untrusted domains
- Punycode shown — reveals IDN homograph phishing (e.g. `xn--pple-43d.com`)
- Speculative connections disabled

</details>

<details>
<summary><strong>Attack Surface Reduction</strong></summary>

- Geolocation, battery API, clipboard events disabled
- Built-in PDF viewer disabled — prevents PDF-based exploits
- No saved passwords, no form autofill, no disk cache
- Flash and OpenH264 codec plugins disabled
- All telemetry and data reporting disabled
- Google Safe Browsing disabled (OPSEC — prevents leaking investigated URLs to Google; uBlock Origin + URLhaus provides equivalent malware URL blocking locally)

</details>

### Pre-installed Extensions

- **uBlock Origin** — force-installed via enterprise policy with aggressive filter lists:
  EasyList, EasyPrivacy, URLhaus (malware URLs), Peter Lowe's ad/tracking list, AdAway, and anti-popup filters

---

## Architecture

```
  ┌──────────────────────────────────────────────────────────┐
  │  macOS Host                                              │
  │                                                          │
  │  ┌────────────┐   ┌────────────┐   ┌──────────────┐     │
  │  │   Colima    │   │  XQuartz   │   │  PulseAudio  │     │
  │  │  (Docker)   │   │   (X11)    │   │   (Audio)    │     │
  │  └──────┬──────┘   └──────┬─────┘   └──────┬───────┘     │
  │         │          Xauth  │  cookie  │             │
  │         ▼                 ▼                 ▼             │
  │  ┌───────────────────────────────────────────────────┐    │
  │  │             Docker Container                      │    │
  │  │                                                   │    │
  │  │   ┌───────────────────────────────────────────┐   │    │
  │  │   │  Firefox 149.0 (non-root, uid 999)        │   │    │
  │  │   │                                           │   │    │
  │  │   │  ► Read-only rootfs + noexec tmpfs        │   │    │
  │  │   │  ► Custom seccomp (default-deny)          │   │    │
  │  │   │  ► Hardened user.js + DoH                 │   │    │
  │  │   │  ► uBlock Origin + filter lists           │   │    │
  │  │   │  ► All caps dropped (+SYS_CHROOT only)    │   │    │
  │  │   │  ► Egress: HTTP/HTTPS/DNS only            │   │    │
  │  │   └───────────────────────────────────────────┘   │    │
  │  │                                                   │    │
  │  │   iptables: block LAN, host (except X11+audio)   │    │
  │  └───────────────────────────────────────────────────┘    │
  └──────────────────────────────────────────────────────────┘
```

| Connection | Method | Auth |
|------------|--------|------|
| Display | X11 via `DISPLAY=host.docker.internal:0` | MIT-MAGIC-COOKIE (Xauth) |
| Audio | TCP via PulseAudio on port 4713 | Cookie-based |
| Rendering | Software (`LIBGL_ALWAYS_SOFTWARE=1`) | N/A |
| DNS | DNS-over-HTTPS (Cloudflare malware-blocking) | N/A |

### Volatile Storage (tmpfs)

All writable paths are RAM-backed and **destroyed when the container stops**:

```
  /tmp ··················· 256 MB   noexec   General temp files
  /run ···················  64 MB   noexec   Runtime files
  /home/firefox/.cache ··· 128 MB   noexec   Browser cache
  /home/firefox/.mozilla · 256 MB            Firefox profile
  /home/firefox/.config ··   8 MB   noexec   PulseAudio config
  /dev/shm ··············· 256 MB   noexec   Shared memory (IPC)
```

---

## Project Structure

```
sandfox/
├── run.sh                 # Service manager — start, stop, status
├── Dockerfile             # Image build (Ubuntu 22.04 + Mozilla PPA)
├── docker-compose.yml     # Security hardening & resource config
├── seccomp-firefox.json   # Custom seccomp profile (default-deny)
├── entrypoint.sh          # Profile setup, audio config, Firefox launch
├── user.js                # Hardened about:config preferences
└── policies.json          # Enterprise policies (uBlock Origin config)
```

---

## Troubleshooting

<details>
<summary><strong>Firefox window doesn't appear</strong></summary>

Check X11 auth: `ls -la ~/.config/sandfox/xauth`. If empty or missing, re-run `bash run.sh start`. If XQuartz just started, it may need a moment to initialize before the auth cookie can be extracted.

</details>

<details>
<summary><strong>No audio</strong></summary>

Verify PulseAudio is listening with cookie auth:
```bash
lsof -iTCP:4713 -sTCP:LISTEN
ls -la ~/.config/sandfox/pulse-cookie
```
If not running or cookie missing, `bash run.sh start` will reconfigure it.

</details>

<details>
<summary><strong>Container exits immediately</strong></summary>

Check logs:
```bash
docker compose logs sandfox
```
Common causes:
- X11 connection refused — re-run `bash run.sh start`
- Seccomp violation — check logs for `SECCOMP` and consider adding the syscall to `seccomp-firefox.json`
- Out of tmpfs space — heavy browsing can fill the RAM-backed mounts

</details>

<details>
<summary><strong>Firefox sandbox warnings</strong></summary>

If Firefox logs sandbox-related errors, this is because `SYS_ADMIN` capability is not granted. The container itself is the sandbox boundary. If you need Firefox's internal content sandbox, add `SYS_ADMIN` to `cap_add` in `docker-compose.yml`.

</details>

<details>
<summary><strong>libGL or DBus warnings in logs</strong></summary>

Both are expected and harmless. Software rendering is intentional (`LIBGL_ALWAYS_SOFTWARE=1`), and `dbus-x11` is intentionally not installed to reduce attack surface.

</details>

> [!TIP]
> When in doubt, run `bash run.sh status` to see what's up and what's not.

---

## License

MIT
