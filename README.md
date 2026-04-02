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

```
$ bash run.sh status

Colima:     running
XQuartz:    running
X11 access: localhost allowed
PulseAudio: running (TCP :4713)
Firefox:    running (sandfox-firefox-1)

All services are running.
```

---

## Security Hardening

### Container Lockdown

```
  ╔══════════════════════════════════════════════════════╗
  ║               CONTAINER SECURITY                    ║
  ╠══════════════════════════════════════════════════════╣
  ║                                                     ║
  ║   Filesystem ····· read-only rootfs                 ║
  ║   Capabilities ··· ALL dropped                      ║
  ║   Privileges ····· no-new-privileges                ║
  ║   User ··········· non-root (uid 999)               ║
  ║   Storage ········ volatile tmpfs only              ║
  ║   Resources ······ capped at 6 CPU / 6 GB RAM      ║
  ║                                                     ║
  ╚══════════════════════════════════════════════════════╝
```

Only `SYS_CHROOT` and `SYS_ADMIN` are added back — required by Firefox's own content sandbox.

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
- Google Safe Browsing enabled (phishing + malware lists)
- Flash and OpenH264 codec plugins disabled
- All telemetry and data reporting disabled

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
  │         │                 │                 │             │
  │         ▼                 ▼                 ▼             │
  │  ┌───────────────────────────────────────────────────┐    │
  │  │             Docker Container                      │    │
  │  │                                                   │    │
  │  │   ┌───────────────────────────────────────────┐   │    │
  │  │   │  Firefox (non-root, uid 999)              │   │    │
  │  │   │                                           │   │    │
  │  │   │  ► Read-only rootfs                       │   │    │
  │  │   │  ► tmpfs for all writable paths           │   │    │
  │  │   │  ► Hardened user.js profile               │   │    │
  │  │   │  ► uBlock Origin + filter lists           │   │    │
  │  │   │  ► All capabilities dropped               │   │    │
  │  │   └───────────────────────────────────────────┘   │    │
  │  │                                                   │    │
  │  └───────────────────────────────────────────────────┘    │
  └──────────────────────────────────────────────────────────┘
```

| Connection | Method | Detail |
|------------|--------|--------|
| Display | X11 | Forwarded to XQuartz via `DISPLAY=host.docker.internal:0` |
| Audio | TCP | PulseAudio on port `4713`, anonymous auth |
| Rendering | Software | `LIBGL_ALWAYS_SOFTWARE=1`, no GPU passthrough |

### Volatile Storage (tmpfs)

All writable paths are RAM-backed and **destroyed when the container stops**:

```
  /tmp ··················· 256 MB   General temp files
  /run ···················  64 MB   Runtime files
  /home/firefox/.cache ··· 128 MB   Browser cache
  /home/firefox/.mozilla · 256 MB   Firefox profile
  /home/firefox/.config ··   8 MB   PulseAudio config
  /dev/shm ··············· 256 MB   Shared memory (IPC)
```

---

## Project Structure

```
sandfox/
├── run.sh               # Service manager — start, stop, status
├── Dockerfile           # Image build (Ubuntu 22.04 + Mozilla PPA)
├── docker-compose.yml   # Security hardening & resource limits
├── entrypoint.sh        # Profile setup, audio config, Firefox launch
├── user.js              # Hardened about:config preferences
└── policies.json        # Enterprise policies (uBlock Origin config)
```

---

## Troubleshooting

<details>
<summary><strong>Firefox window doesn't appear</strong></summary>

XQuartz needs `xhost +localhost` run after every restart. `bash run.sh start` handles this automatically. If running manually, make sure XQuartz is open before running `xhost`.

</details>

<details>
<summary><strong>No audio</strong></summary>

Verify PulseAudio is listening:
```bash
lsof -iTCP:4713 -sTCP:LISTEN
```
If not running, `bash run.sh start` will start it.

</details>

<details>
<summary><strong>Container exits immediately</strong></summary>

Check logs:
```bash
docker compose logs sandfox
```
Most common cause is X11 connection refused — re-run `bash run.sh start`.

</details>

<details>
<summary><strong>libGL or DBus warnings in logs</strong></summary>

Both are expected and harmless. Software rendering is intentional (`LIBGL_ALWAYS_SOFTWARE=1`), and no DBus daemon runs in the container.

</details>

> [!TIP]
> When in doubt, run `bash run.sh status` to see what's up and what's not.

---

## License

MIT
