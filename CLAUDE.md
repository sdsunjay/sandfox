# Sandfox

Hardened Firefox browser running in a Docker container on macOS with X11 display forwarding and PulseAudio for audio.

## Prerequisites

- **Colima** — lightweight Docker runtime (`brew install colima docker docker-compose docker-buildx`)
- **XQuartz** — X11 server for macOS (`brew install --cask xquartz`). Requires logout/login after first install.
- **PulseAudio** — audio server (`brew install pulseaudio`)

## Starting all services

The easiest way to start everything is with `run.sh`, which handles all prerequisites automatically:

```bash
bash run.sh start
```

`run.sh` performs these steps in order, skipping any service that is already running:

1. Starts Colima (Docker runtime)
2. Starts XQuartz (X11 display server)
3. Runs `xhost +localhost` to allow container X11 connections
4. Starts PulseAudio with anonymous TCP auth on port 4713
5. Runs `docker compose up --build -d`

### Manual startup

If you prefer to run each step manually:

```bash
# 1. Start Colima (Docker runtime)
colima start

# 2. Start XQuartz and allow local connections
open -a XQuartz
xhost +localhost

# 3. Start PulseAudio with TCP on port 4713 (if not already running)
#    Check with: lsof -iTCP:4713 -sTCP:LISTEN
#    If not running:
pulseaudio --load="module-native-protocol-tcp auth-anonymous=1" --daemon

# 4. Build and run the Firefox container
docker compose up --build -d
```

## Stopping services

```bash
bash run.sh stop
```

## Checking status

```bash
bash run.sh status
```

## Architecture

### Container setup

- **Base image**: Ubuntu 22.04
- **Firefox**: Installed from Mozilla PPA (not the snap stub)
- **User**: Non-root `firefox` user (UID/GID 999), member of `audio` and `video` groups
- **Filesystem**: Read-only rootfs with tmpfs mounts for writable paths
- **Entrypoint**: `entrypoint.sh` copies the hardened profile from `/opt/firefox-profile` into the writable tmpfs at `~/.mozilla`, creates a PulseAudio client config to disable cookie auth, then launches Firefox

### Display (X11)

- `DISPLAY=host.docker.internal:0` forwards to XQuartz on the host
- `LIBGL_ALWAYS_SOFTWARE=1` forces software rendering (no GPU passthrough)
- `MOZ_ENABLE_WAYLAND=0` ensures X11 mode
- `xhost +localhost` must be run after XQuartz starts to allow container connections

### Audio (PulseAudio)

- `PULSE_SERVER=tcp:host.docker.internal:4713` connects to the host PulseAudio over TCP
- PulseAudio must be started with `module-native-protocol-tcp auth-anonymous=1`
- The entrypoint creates `~/.config/pulse/client.conf` with `cookie-file = /dev/null` to suppress cookie auth warnings (anonymous TCP auth is used instead)

### Security hardening

- `read_only: true` — immutable root filesystem
- `cap_drop: ALL`, then selectively adds `SYS_CHROOT` and `SYS_ADMIN` (required by Firefox sandbox)
- `no-new-privileges: true` — prevents privilege escalation
- `seccomp: unconfined` — Firefox sandbox needs clone/unshare syscalls
- Resource limits: 6 CPUs, 6 GB memory

### tmpfs mounts

| Mount                      | Size  | Purpose                        |
|----------------------------|-------|--------------------------------|
| `/tmp`                     | 256m  | General temp files             |
| `/run`                     | 64m   | Runtime files                  |
| `/home/firefox/.cache`     | 128m  | Browser cache                  |
| `/home/firefox/.mozilla`   | 256m  | Firefox profile (copied from image on start) |
| `/home/firefox/.config`    | 8m    | PulseAudio client config       |
| `/dev/shm`                 | 256m  | Shared memory (Firefox IPC)    |

### Pre-installed extensions and policies

- **uBlock Origin** installed via `distribution/extensions/` at build time
- **Enterprise policies** (`policies.json`) configure Firefox settings at the distribution level
- **Hardened profile** (`user.js`) sets privacy/security-focused `about:config` prefs

## Key files

| File               | Purpose                                              |
|--------------------|------------------------------------------------------|
| `Dockerfile`       | Builds the Firefox image (Ubuntu 22.04 + Mozilla PPA)|
| `docker-compose.yml` | Service definition with security and resource config |
| `entrypoint.sh`    | Copies profile into tmpfs, configures PulseAudio, launches Firefox |
| `user.js`          | Hardened Firefox preferences                         |
| `policies.json`    | Firefox enterprise policies (extension config, etc.) |
| `run.sh`           | Manages all services — start, stop, status           |

## Troubleshooting

### Quick diagnostic commands

Run these to check the state of all services at a glance:

```bash
bash run.sh status
```

Or manually:

```bash
# Colima / Docker status
colima status
docker info 2>&1 | head -5

# XQuartz running?
pgrep -l Xquartz

# X11 access control (should list "INET:localhost")
xhost

# PulseAudio listening on TCP 4713?
lsof -iTCP:4713 -sTCP:LISTEN

# Container status and logs
docker compose ps
docker compose logs sandfox
```

### Common problems

- **"Cannot connect to the Docker daemon"** or **Docker socket not found**: Colima is not running. Run `colima start` and wait for it to finish before retrying.
- **No display / Firefox window doesn't appear**:
  1. Check that XQuartz is running: `pgrep -l Xquartz`. If not, run `open -a XQuartz` and wait a couple of seconds.
  2. Check that localhost is authorized: run `xhost` and look for `INET:localhost`. If missing, run `xhost +localhost`. This must be re-run every time XQuartz restarts.
- **No audio**:
  1. Verify PulseAudio is listening: `lsof -iTCP:4713 -sTCP:LISTEN`.
  2. If not listening, start it: `pulseaudio --load="module-native-protocol-tcp auth-anonymous=1" --daemon`.
- **PulseAudio cookie warnings**: The entrypoint creates `~/.config/pulse/client.conf` with `cookie-file = /dev/null`. If warnings persist, ensure the `.config` tmpfs mount exists in `docker-compose.yml`.
- **Container exits immediately**: Check logs with `docker compose logs sandfox`. Common causes:
  - X11 connection refused — fix `xhost` (see above).
  - Out of tmpfs space — the container uses tmpfs for all writable paths; heavy browsing can fill them.
- **libGL errors**: Expected and harmless — software rendering is used (`LIBGL_ALWAYS_SOFTWARE=1`), there is no GPU passthrough.
- **DBus warnings**: Harmless — no dbus daemon runs in the container; the accessibility bus is unavailable.

### When helping a user who is stuck

If the user says "it's not working" without more detail, run the diagnostic commands above to identify which service is down. The most common issue is that `xhost +localhost` was not run after XQuartz started — this is required every time XQuartz restarts and is easy to forget. The simplest fix is to just run `bash run.sh start`, which is idempotent and will start any missing services.
