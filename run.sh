#!/usr/bin/env bash
set -euo pipefail

start() {
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

  # 3. Allow local connections to X11
  xhost +localhost

  # 4. Start PulseAudio with TCP on port 4713 if not already listening
  if ! lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    echo "Starting PulseAudio..."
    pulseaudio --load="module-native-protocol-tcp auth-anonymous=1" --daemon
  else
    echo "PulseAudio is already running."
  fi

  # 5. Build and run the Firefox container
  docker compose up --build -d
}

stop() {
  # 1. Stop the Firefox container
  echo "Stopping Firefox container..."
  docker compose down

  # 2. Stop PulseAudio
  if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    echo "Stopping PulseAudio..."
    pulseaudio --kill
  else
    echo "PulseAudio is not running."
  fi

  # 3. Revoke local X11 access and stop XQuartz
  if pgrep -q Xquartz; then
    echo "Stopping XQuartz..."
    xhost -localhost 2>/dev/null || true
    osascript -e 'quit app "XQuartz"' 2>/dev/null || true
  else
    echo "XQuartz is not running."
  fi

  # 4. Stop Colima
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
    echo "Colima:     running"
  else
    echo "Colima:     stopped"
    all_ok=false
  fi

  # XQuartz
  if pgrep -q Xquartz; then
    echo "XQuartz:    running"
  else
    echo "XQuartz:    stopped"
    all_ok=false
  fi

  # X11 access
  if xhost 2>/dev/null | grep -q "INET:localhost"; then
    echo "X11 access: localhost allowed"
  else
    echo "X11 access: localhost NOT allowed"
    all_ok=false
  fi

  # PulseAudio
  if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
    echo "PulseAudio: running (TCP :4713)"
  else
    echo "PulseAudio: stopped"
    all_ok=false
  fi

  # Firefox container
  local container_status
  container_status="$(docker compose ps --status running --format '{{.Name}}' 2>/dev/null)"
  if [[ -n "$container_status" ]]; then
    echo "Firefox:    running ($container_status)"
  else
    echo "Firefox:    stopped"
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
