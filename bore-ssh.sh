#!/usr/bin/env bash
# =============================================================
#  bore-ssh.sh - SSH tunnel qua bore (Linux / macOS)
#
#  server : expose SSH cua may nay ra internet qua bore
#  client : SSH vao tunnel da duoc expose
#  install: tai bore ve ./bin/bore
#
#  Chay: ./bore-ssh.sh            (menu)
#        ./bore-ssh.sh server
#        ./bore-ssh.sh client
# =============================================================
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/bin/bore"
CONF="$ROOT/tunnel.conf"
LOG="$ROOT/.bore-ssh.log"
STATE="$ROOT/.bore-ssh-last"
BORE_VERSION="${BORE_VERSION:-0.6.0}"
BORE_PID=""

if [ -t 1 ]; then
  RST=$'\033[0m'; BLD=$'\033[1m'; GRN=$'\033[32m'; YEL=$'\033[33m'
  RED=$'\033[31m'; CYN=$'\033[36m'
else
  RST=""; BLD=""; GRN=""; YEL=""; RED=""; CYN=""
fi

ok()   { printf '%s[ok]%s   %s\n' "$GRN" "$RST" "$*"; }
info() { printf '%s[..]%s   %s\n' "$CYN" "$RST" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YEL" "$RST" "$*"; }
die()  { printf '%s[fail]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

MODE=""
DRYRUN=0
for a in "$@"; do
  case "$a" in
    setup|st) MODE=setup ;;
    server|s) MODE=server ;;
    client|c) MODE=client ;;
    install|i) MODE=install ;;
    logs|l)   MODE=logs ;;
    help)     MODE=help ;;
    -h|--help) MODE="help" ;;
    --dry-run) DRYRUN=1 ;;
    *) die "Tuy chon khong hop le: $a" ;;
  esac
done

# ---------- config ----------
load_conf() {
  [ -f "$CONF" ] || return 0
  local line k v
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    k="${line%%=*}"
    v="${line#*=}"
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    [ -n "$k" ] || continue
    v="${v#\"}"; v="${v%\"}"
    export "$k=$v"
  done < "$CONF"
}

load_conf
: "${BORE_SERVER:=bore.pub}"
: "${SSH_PORT:=22}"
: "${SSH_USER:=}"
: "${SSH_KEY:=}"
: "${REMOTE_PORT:=}"
: "${BORE_BIN:=}"
: "${BORE_ARGS:=}"

SERVER_HOST="${BORE_SERVER%%:*}"

[ -x "$BIN" ] || { [ -n "$BORE_BIN" ] && [ -x "$BORE_BIN" ] || BORE_BIN="$BIN"; }
[ -n "$BORE_BIN" ] || BORE_BIN="$BIN"

# ---------- tunnel ----------
parse_port() {
  local line tail
  line="$(grep -a 'listening at ' "$LOG" 2>/dev/null | tail -n1)"
  [ -n "$line" ] || return 0
  tail="${line##*listening at }"
  tail="${tail##*:}"
  case "$tail" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$tail"
}

stop_tunnel() {
  if [ -n "$BORE_PID" ] && kill -0 "$BORE_PID" 2>/dev/null; then
    kill "$BORE_PID" 2>/dev/null || true
  fi
  BORE_PID=""
}

ensure_bore() {
  if [ -x "$BORE_BIN" ]; then return 0; fi
  if command -v bore >/dev/null 2>&1; then BORE_BIN="$(command -v bore)"; return 0; fi
  return 1
}

do_install() {
  case "$(uname -s)" in
    Darwin) os="apple-darwin" ;;
    Linux)  os="unknown-linux-musl" ;;
    *) die "He dieu hanh khong duoc ho tro, tai bore thu cong." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    armv7l)        arch="armv7" ;;
    i386|i686)     arch="i686" ;;
    *) die "Kien truc khong duoc ho tro: $(uname -m)" ;;
  esac
  [ "$os" = "apple-darwin" ] && [ "$arch" = "armv7" ] && die "Khong ho tro armv7 tren macOS"

  asset="${arch}-${os}"
  [ "$os" = "unknown-linux-musl" ] && [ "$arch" = "armv7" ] && asset="armv7-unknown-linux-musleabihf"
  url="https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/bore-v${BORE_VERSION}-${asset}.tar.gz"

  info "Tai bore v${BORE_VERSION} (${asset})..."
  mkdir -p "$ROOT/bin"
  tmpd="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$tmpd/bore.tar.gz" "$url" || { rm -rf "$tmpd"; die "Tai that bai: $url"; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmpd/bore.tar.gz" "$url" || { rm -rf "$tmpd"; die "Tai that bai: $url"; }
  else
    die "Can curl hoac wget de tai bore."
  fi
  tar -xzf "$tmpd/bore.tar.gz" -C "$tmpd" bore || { rm -rf "$tmpd"; die "Giai nen that bai."; }
  mv -f "$tmpd/bore" "$BIN"
  chmod +x "$BIN"
  rm -rf "$tmpd"
  BORE_BIN="$BIN"
  ok "Da cai: $BIN"
}

# ---------- setup ----------
run_setup() {
  local s="$ROOT/scripts/setup-ssh-linux.sh"
  [ -f "$s" ] || die "Thieu file: $s"
  bash "$s"
}

# ---------- logs ----------
run_logs() {
  local s="$ROOT/scripts/check-log.sh"
  [ -f "$s" ] || die "Thieu file: $s"
  bash "$s" --hours "${LOG_HOURS:-24}" --port "$SSH_PORT"
  printf '\n'
  read -r -p '  Enter de tiep tuc...' _ || true
}

# ---------- server ----------
run_server() {
  ensure_bore || die "Chua co bore. Chay: ./bore-ssh.sh install"

  local args=(local "$SSH_PORT" --to "$BORE_SERVER")
  [ -n "$REMOTE_PORT" ] && args+=(--port "$REMOTE_PORT")
  [ -n "$BORE_ARGS" ] && args+=($BORE_ARGS)   # tach tu co chu dich

  if [ "$DRYRUN" = "1" ]; then
    info "Lenh se chay: $BORE_BIN ${args[*]}"
    return 0
  fi

  info "Mo tunnel: $BORE_BIN ${args[*]}"
  : > "$LOG"
  "$BORE_BIN" "${args[@]}" >"$LOG" 2>&1 &
  BORE_PID=$!
  trap stop_tunnel EXIT INT TERM

  local port=""
  for _ in $(seq 1 25); do
    port="$(parse_port)"
    [ -n "$port" ] && break
    grep -qiE 'error|failed' "$LOG" 2>/dev/null && break
    sleep 1
  done
  if [ -z "$port" ]; then
    cat "$LOG" >&2
    die "Khong mo duoc tunnel. Xem log: $LOG"
  fi

  printf 'HOST=%s\nPORT=%s\n' "$SERVER_HOST" "$port" > "$STATE"

  local who="${SSH_USER:-YOUR_USER}"
  printf '\n'
  printf '  ============================================================\n'
  printf '     TUNNEL DANG MO\n'
  printf '  ============================================================\n'
  printf '     Cong khai : %s:%s\n' "$SERVER_HOST" "$port"
  printf '     SSH vao   : ssh -p %s %s@%s\n' "$port" "$who" "$SERVER_HOST"
  printf '  ============================================================\n\n'
  printf '  Nhan Enter de dung tunnel...'
  read -r _ || true
  stop_tunnel
  ok "Da dong tunnel."
}

# ---------- client ----------
run_client() {
  local lh="" lp="" luser="$SSH_USER"
  if [ -f "$STATE" ]; then
    lh="$(sed -n 's/^HOST=//p' "$STATE" | tail -n1)"
    lp="$(sed -n 's/^PORT=//p' "$STATE" | tail -n1)"
  fi
  [ -n "$lh" ] || lh="$SERVER_HOST"

  printf '\n  --- SSH vao tunnel ---\n'
  printf '  Tunnel phai duoc mo truoc do tren may chu.\n\n'

  local in_host in_port in_user
  read -r -p "  Host [$lh]: " in_host || true
  in_host="${in_host:-$lh}"
  if [ -n "$lp" ]; then
    read -r -p "  Port [$lp]: " in_port || true
    in_port="${in_port:-$lp}"
  else
    read -r -p "  Port: " in_port || true
  fi
  [ -n "$in_port" ] || die "Chua co port."
  read -r -p "  User [${luser:-$USER}]: " in_user || true
  in_user="${in_user:-${luser:-$USER}}"

  local sshargs=(-p "$in_port" -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)
  [ -n "$SSH_KEY" ] && sshargs+=(-i "$SSH_KEY")
  sshargs+=("$in_user@$in_host")

  printf '\n  $ ssh %s\n\n' "${sshargs[*]}"
  if [ "$DRYRUN" = "1" ]; then return 0; fi
  ssh "${sshargs[@]}"
}

# ---------- menu ----------
menu() {
  while true; do
    clear 2>/dev/null || true
    printf '\n'
    printf '  ============================================================\n'
    printf '     SSH over bore  -  tunnel helper\n'
    printf '  ============================================================\n'
    printf '     Relay server : %s\n' "$BORE_SERVER"
    printf '     SSH port     : %s\n' "$SSH_PORT"
    printf '     Bore binary  : %s\n' "$BORE_BIN"
    printf '  ------------------------------------------------------------\n'
    printf '     [1] Setup SSH server + mo tunnel   (lan dau)\n'
    printf '     [2] Mo tunnel                      (SSH da cai san)\n'
    printf '     [3] SSH vao tunnel                 (tu may khac)\n'
    printf '     [4] Cai dat / cap nhat bore\n'
    printf '     [5] Xem log / kiem tra tan cong\n'
    printf '     [6] Thoat\n\n'
    read -r -p '  Chon 1-6: ' c || exit 0
    case "$c" in
      1) run_setup ;;
      2) run_server ;;
      3) run_client ;;
      4) do_install ;;
      5) run_logs ;;
      6|q) break ;;
    esac
  done
}

case "$MODE" in
  setup)   run_setup ;;
  server)  run_server ;;
  client)  run_client ;;
  install) do_install ;;
  logs)    run_logs ;;
  help)
    cat <<EOF

bore-ssh.sh - SSH tunnel qua bore

  ./bore-ssh.sh              mo menu
  ./bore-ssh.sh setup        cai SSH server + mo tunnel (lan dau)
  ./bore-ssh.sh server       chi mo tunnel
  ./bore-ssh.sh client       SSH vao tunnel da expose
  ./bore-ssh.sh install      tai bore vao ./bin/bore
  ./bore-ssh.sh help         tro giup
  --dry-run                  chi in lenh, khong chay

Cau hinh: tunnel.conf  (xem tunnel.conf.example)
EOF
    ;;
  "") menu ;;
esac
