#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SANDFOX_DIR="$HOME/.config/sandfox"
SANDFOX_XAUTH="$SANDFOX_DIR/xauth"
SANDFOX_PULSE_COOKIE="$SANDFOX_DIR/pulse-cookie"
SANDFOX_LOG_DIR="$SANDFOX_DIR/logs"

# --- Helper functions ---

# colima ssh tries to cd to $CWD in the VM, which may not exist (e.g., /Volumes/Data/...).
# Run all colima ssh commands from /tmp to avoid this.
_colima_ssh() {
  pushd /tmp >/dev/null
  colima ssh -- "$@"
  local rc=$?
  popd >/dev/null
  return $rc
}

setup_dirs() {
  mkdir -p "$SANDFOX_DIR" "$SANDFOX_LOG_DIR"
}

# C3 fix: Replace xhost +localhost with MIT-MAGIC-COOKIE Xauth
setup_x11_auth() {
  echo "Configuring X11 authentication..."
  rm -f "$SANDFOX_XAUTH"
  touch "$SANDFOX_XAUTH"

  # Extract the MIT-MAGIC-COOKIE from the host's xauth database and rewrite
  # it with FamilyWild (ffff) so it matches any hostname the container uses.
  # On macOS, DISPLAY is often a unix socket path — fall back to :0 for xauth lookup.
  local xauth_display="${DISPLAY:-:0}"
  if [[ "$xauth_display" == /* ]]; then
    # DISPLAY is a socket path (macOS) — xauth needs :0 format instead
    xauth_display=":0"
  fi
  xauth nlist "$xauth_display" 2>/dev/null \
    | head -1 \
    | sed 's/^..../ffff/' \
    | xauth -f "$SANDFOX_XAUTH" nmerge - 2>/dev/null

  if [[ -s "$SANDFOX_XAUTH" ]]; then
    chmod 644 "$SANDFOX_XAUTH"
    # Revoke any blanket xhost access left from previous sessions
    xhost -localhost 2>/dev/null || true
    echo "  X11 auth: cookie-based (secure)"
  else
    echo "  WARNING: Could not extract X11 auth cookie."
    echo "  This usually means XQuartz is not fully initialized."
    echo "  Falling back to xhost +localhost (less secure)."
    xhost +localhost 2>/dev/null || true
    # Create a placeholder so the bind mount doesn't fail
    touch "$SANDFOX_XAUTH"
    chmod 644 "$SANDFOX_XAUTH"
  fi
}

# H1 fix: Replace PulseAudio anonymous TCP with cookie-based auth.
# On macOS, PulseAudio auto-spawns and can't be cleanly restarted via --daemon.
# Instead, we use pactl to reconfigure the running instance's TCP module.
setup_pulseaudio() {
  # Remove stale cookie so PulseAudio generates a fresh one
  rm -f "$SANDFOX_PULSE_COOKIE"

  if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    echo "Reconfiguring PulseAudio with cookie authentication..."
    # Unload existing TCP module, then reload with cookie auth
    pactl unload-module module-native-protocol-tcp 2>/dev/null || true
    pactl load-module module-native-protocol-tcp \
      "auth-cookie=$SANDFOX_PULSE_COOKIE" auth-anonymous=0 >/dev/null
  else
    echo "Starting PulseAudio with cookie authentication..."
    # Start PulseAudio (may auto-spawn), then configure TCP module
    pulseaudio --start 2>/dev/null || true
    sleep 1
    pactl load-module module-native-protocol-tcp \
      "auth-cookie=$SANDFOX_PULSE_COOKIE" auth-anonymous=0 >/dev/null
  fi

  # Wait for PulseAudio to create the cookie file
  local retries=10
  while [[ ! -f "$SANDFOX_PULSE_COOKIE" ]] && (( retries > 0 )); do
    sleep 0.5
    (( retries-- ))
  done

  if [[ -f "$SANDFOX_PULSE_COOKIE" ]]; then
    chmod 644 "$SANDFOX_PULSE_COOKIE"
    echo "  PulseAudio: cookie auth on TCP :4713"
  else
    echo "  WARNING: PulseAudio cookie not found. Audio may not work."
    # Create a placeholder so the bind mount doesn't fail
    touch "$SANDFOX_PULSE_COOKIE"
    chmod 644 "$SANDFOX_PULSE_COOKIE"
  fi
}

# C4 fix: Network egress filtering via iptables in the Colima VM.
# Only allows HTTP (80), HTTPS (443), and DNS (53) outbound.
# Blocks all RFC 1918 / link-local ranges (prevents LAN scanning).
# Allows X11 (6000) and PulseAudio (4713) to host gateway only.
setup_egress_rules() {
  echo "Configuring network egress filtering..."

  # Determine the host gateway IP inside the Colima VM
  local gw_ip
  gw_ip=$(_colima_ssh ip route show default 2>/dev/null | awk '{print $3}')

  if [[ -z "$gw_ip" ]]; then
    echo "  WARNING: Could not determine gateway IP. Skipping egress rules."
    echo "  The container will have unrestricted network access."
    return
  fi

  # Clean up any existing sandfox rules from prior runs
  _colima_ssh sudo iptables -D DOCKER-USER -j SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -D FORWARD -j SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -F SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -X SANDFOX-FILTER 2>/dev/null || true

  # Create the SANDFOX-FILTER chain
  _colima_ssh sudo iptables -N SANDFOX-FILTER

  # Allow already-established connections (return traffic for browsing)
  _colima_ssh sudo iptables -A SANDFOX-FILTER \
    -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

  # Allow X11 (TCP 6000) to host gateway — display forwarding
  _colima_ssh sudo iptables -A SANDFOX-FILTER \
    -d "$gw_ip" -p tcp --dport 6000 -j RETURN

  # Allow PulseAudio (TCP 4713) to host gateway — audio
  _colima_ssh sudo iptables -A SANDFOX-FILTER \
    -d "$gw_ip" -p tcp --dport 4713 -j RETURN

  # Block ALL other traffic to the host gateway (H2 fix)
  _colima_ssh sudo iptables -A SANDFOX-FILTER \
    -d "$gw_ip" -j DROP

  # Block RFC 1918 private address ranges — prevent LAN scanning
  _colima_ssh sudo iptables -A SANDFOX-FILTER -d 10.0.0.0/8 -j DROP
  _colima_ssh sudo iptables -A SANDFOX-FILTER -d 172.16.0.0/12 -j DROP
  _colima_ssh sudo iptables -A SANDFOX-FILTER -d 192.168.0.0/16 -j DROP
  _colima_ssh sudo iptables -A SANDFOX-FILTER -d 169.254.0.0/16 -j DROP

  # Allow DNS (needed for browsing)
  _colima_ssh sudo iptables -A SANDFOX-FILTER -p udp --dport 53 -j RETURN
  _colima_ssh sudo iptables -A SANDFOX-FILTER -p tcp --dport 53 -j RETURN

  # Allow HTTP and HTTPS only
  _colima_ssh sudo iptables -A SANDFOX-FILTER -p tcp --dport 80 -j RETURN
  _colima_ssh sudo iptables -A SANDFOX-FILTER -p tcp --dport 443 -j RETURN

  # Drop everything else
  _colima_ssh sudo iptables -A SANDFOX-FILTER -j DROP

  # Insert into DOCKER-USER (preferred) or FORWARD (fallback)
  if _colima_ssh sudo iptables -L DOCKER-USER -n &>/dev/null 2>&1; then
    _colima_ssh sudo iptables -I DOCKER-USER -j SANDFOX-FILTER
  else
    _colima_ssh sudo iptables -I FORWARD -j SANDFOX-FILTER
  fi

  echo "  Egress: HTTP/HTTPS/DNS only, LAN/host blocked"
}

remove_egress_rules() {
  echo "Removing network egress rules..."
  _colima_ssh sudo iptables -D DOCKER-USER -j SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -D FORWARD -j SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -F SANDFOX-FILTER 2>/dev/null || true
  _colima_ssh sudo iptables -X SANDFOX-FILTER 2>/dev/null || true
}

# --- Commands ---

start() {
  setup_dirs

  # 1. Start Colima if not already running
  if ! colima status &>/dev/null; then
    echo "Starting Colima..."
    colima start
  else
    echo "Colima is already running."
  fi

  # 2. Start XQuartz if not already running
  if ! pgrep -q Xquartz; then
    echo "Starting XQuartz..."
    open -a XQuartz
    sleep 2
  fi

  # 3. Configure X11 authentication (cookie-based, replaces xhost +localhost)
  setup_x11_auth

  # 4. Configure PulseAudio with cookie auth (replaces anonymous TCP)
  setup_pulseaudio

  # 5. Configure network egress filtering in Colima VM
  setup_egress_rules

  # 6. Build and run the Firefox container
  docker compose up --build -d

  # 7. Start session logging in background (L3 fix)
  local log_file="$SANDFOX_LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
  docker compose logs -f sandfox > "$log_file" 2>&1 &
  disown

  echo ""
  echo "Sandfox is running. Session log: $log_file"
}

stop() {
  # 1. Stop the Firefox container
  echo "Stopping Firefox container..."
  docker compose down

  # 2. Remove network egress rules from Colima VM
  if colima status &>/dev/null; then
    remove_egress_rules
  fi

  # 3. Stop PulseAudio
  if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    echo "Stopping PulseAudio..."
    pulseaudio --kill
  else
    echo "PulseAudio is not running."
  fi

  # 4. Revoke X11 access and stop XQuartz
  if pgrep -q Xquartz; then
    echo "Stopping XQuartz..."
    xhost -localhost 2>/dev/null || true
    osascript -e 'quit app "XQuartz"' 2>/dev/null || true
  else
    echo "XQuartz is not running."
  fi

  # 5. Clean up auth material
  rm -f "$SANDFOX_XAUTH" "$SANDFOX_PULSE_COOKIE"

  # 6. Stop Colima
  if colima status &>/dev/null; then
    echo "Stopping Colima..."
    colima stop
  else
    echo "Colima is not running."
  fi

  echo "All services stopped."
}

status() {
  local all_ok=true

  # Colima
  if colima status &>/dev/null; then
    echo "Colima:      running"
  else
    echo "Colima:      stopped"
    all_ok=false
  fi

  # XQuartz
  if pgrep -q Xquartz; then
    echo "XQuartz:     running"
  else
    echo "XQuartz:     stopped"
    all_ok=false
  fi

  # X11 authentication
  if [[ -s "$SANDFOX_XAUTH" ]]; then
    echo "X11 auth:    cookie-based (secure)"
  elif xhost 2>/dev/null | grep -q "INET:localhost"; then
    echo "X11 auth:    xhost +localhost (INSECURE fallback)"
  else
    echo "X11 auth:    not configured"
    all_ok=false
  fi

  # PulseAudio
  if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    if [[ -f "$SANDFOX_PULSE_COOKIE" ]] && [[ -s "$SANDFOX_PULSE_COOKIE" ]]; then
      echo "PulseAudio:  running (TCP :4713, cookie auth)"
    else
      echo "PulseAudio:  running (TCP :4713, WARNING: no cookie)"
    fi
  else
    echo "PulseAudio:  stopped"
    all_ok=false
  fi

  # Network egress filtering
  if colima status &>/dev/null && \
     _colima_ssh sudo iptables -L SANDFOX-FILTER -n &>/dev/null 2>&1; then
    echo "Egress:      filtered (HTTP/HTTPS/DNS only)"
  elif colima status &>/dev/null; then
    echo "Egress:      UNFILTERED (run '$0 start' to apply rules)"
  else
    echo "Egress:      unknown (Colima not running)"
  fi

  # Firefox container
  local container_status
  container_status="$(docker compose ps --status running --format '{{.Name}}' 2>/dev/null)"
  if [[ -n "$container_status" ]]; then
    echo "Firefox:     running ($container_status)"
  else
    echo "Firefox:     stopped"
    all_ok=false
  fi

  echo ""
  if $all_ok; then
    echo "All services are running."
  else
    echo "Some services are not running. Use '$0 start' to start them."
  fi
}

case "${1:-}" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  status)
    status
    ;;
  "")
    # Default to start for backwards compatibility
    start
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
