#!/usr/bin/env bash
# =============================================================
#  setup-ssh-bore.sh
#
#  Tu dong: cai SSH server -> cau hinh -> dat mat khau root
#           -> bat sshd -> tu kiem tra -> mo bore tunnel
#           -> in san lenh SSH de ket noi tu xa.
#
#  Dung cho: Ubuntu/Debian, Alpine, Fedora/RHEL, Arch,
#            Google Colab, Docker container, VPS.
#
#  Chay:  bash setup-ssh-bore.sh
#         bash setup-ssh-bore.sh --port 2222 --password MyPass123
#         bash setup-ssh-bore.sh --ssh-only
#         bash setup-ssh-bore.sh --dry-run
# =============================================================
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BORE_VERSION="${BORE_VERSION:-0.6.0}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
BORE_SECRET="${BORE_SECRET:-}"
LOG="$ROOT/.bore-ssh.log"
STATE="$ROOT/.bore-ssh-last"

SSH_PORT="${SSH_PORT:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
REMOTE_PORT="${REMOTE_PORT:-}"
TUNNEL_USER="${TUNNEL_USER:-root}"
BORE_BIN="${BORE_BIN:-}"
SETUP_ONLY=0
DRY_RUN=0
SSHD_BIN=""
BORE_PID=""

if [ -t 1 ]; then
  RST=$'\033[0m'; BLD=$'\033[1m'; GRN=$'\033[32m'; YEL=$'\033[33m'
  RED=$'\033[31m'; CYN=$'\033[36m'
else
  RST=""; BLD=""; GRN=""; YEL=""; RED=""; CYN=""
fi

ok()   { printf '%s[ok]%s   %s\n'   "$GRN" "$RST" "$*"; }
info() { printf '%s[..]%s   %s\n'   "$CYN" "$RST" "$*"; }
warn() { printf '%s[warn]%s %s\n'   "$YEL" "$RST" "$*"; }
bad()  { printf '%s[fail]%s %s\n'   "$RED" "$RST" "$*"; }
die()  { bad "$*"; exit 1; }
hr()   { printf '%s\n' "============================================================"; }

usage() {
  cat <<EOF
setup-ssh-bore.sh - tu dong setup SSH server + bore tunnel

Cach dung:
  bash setup-ssh-bore.sh [tuy chon]

Tuy chon:
  --port N          cong SSH noi bo (mac dinh: 2222 trong container/Colab, 22 ngoai)
  --password P      mat khau cho user (mac dinh: tu sinh roi in ra)
  --user NAME       user cho phep dang nhap (mac dinh: root)
  --remote-port N   xin bore cap 1 cong cong khai co dinh (mac dinh: ngau nhien)
  --server HOST     bore relay server (mac dinh: bore.pub)
  --secret S        secret neu relay cua ban yeu cau
  --ssh-only        chi setup SSH, khong mo tunnel
  --dry-run         in ra cac buoc, khong thay doi gi
  -h, --help        tro giup

Vi du:
  bash setup-ssh-bore.sh
  bash setup-ssh-bore.sh --port 2222 --password 'MySecurePass123'
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --port)        SSH_PORT="${2:-}"; shift 2 ;;
    --password)    SSH_PASSWORD="${2:-}"; shift 2 ;;
    --user)        TUNNEL_USER="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --server)      BORE_SERVER="${2:-}"; shift 2 ;;
    --secret)      BORE_SECRET="${2:-}"; shift 2 ;;
    --ssh-only)    SETUP_ONLY=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Tuy chon khong hop le: $1  (xem --help)" ;;
  esac
done

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '       %s[dry-run]%s %s\n' "$YEL" "$RST" "$*"
    return 0
  fi
  "$@"
}

# -------------------------------------------------------------
# 0. Quyen + moi truong
# -------------------------------------------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    warn "Khong phai root, se dung sudo."
  else
    die "Can quyen root de cau hinh SSH. Hay chay lai bang root/sudo."
  fi
fi

is_container=0
if [ -f /.dockerenv ] || [ ! -d /run/systemd/system ] || [ -n "${COLAB_RELEASE_TAG:-}${COLAB_GPU:-}" ]; then
  is_container=1
fi

on_colab=0
if [ -n "${COLAB_RELEASE_TAG:-}${COLAB_GPU:-}${COLAB_TPU_ADDR:-}" ] || [ -d /content/.config ]; then
  on_colab=1
fi

hr
printf '%s  SETUP SSH SERVER + BORE TUNNEL%s\n' "$BLD" "$RST"
hr
if [ "$on_colab" = "1" ]; then
  info "Moi truong: Google Colab"
elif [ "$is_container" = "1" ]; then
  info "Moi truong: container / khong co systemd"
else
  info "Moi truong: may chu binh thuong"
fi

[ "$DRY_RUN" = "1" ] && warn "DRY-RUN: khong thay doi he thong, chi in cac buoc."

# -------------------------------------------------------------
# 1. Cai openssh-server
# -------------------------------------------------------------
hr
printf '  1. CAI DAT SSH SERVER\n'
hr

detect_sshd() {
  if command -v sshd >/dev/null 2>&1; then
    SSHD_BIN="$(command -v sshd)"
  elif [ -x /usr/sbin/sshd ]; then
    SSHD_BIN=/usr/sbin/sshd
  elif [ -x /usr/local/sbin/sshd ]; then
    SSHD_BIN=/usr/local/sbin/sshd
  fi
}

detect_sshd

if [ -n "$SSHD_BIN" ]; then
  ok "openssh-server da co: $SSHD_BIN"
else
  info "Chua co sshd, dang cai dat..."
  if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] bo qua cai dat"
  elif command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq && DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq openssh-server
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y -q openssh-server
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y -q openssh-server
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache openssh
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm openssh
  else
    die "Khong tim thay package manager. Cai openssh-server thu cong roi chay lai."
  fi
  detect_sshd
  [ -n "$SSHD_BIN" ] && ok "Da cai: $SSHD_BIN" || die "Cai dat that bai."
fi

# -------------------------------------------------------------
# 2. Chon cong SSH
# -------------------------------------------------------------
port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

if [ -z "$SSH_PORT" ]; then
  if [ "$is_container" = "1" ]; then SSH_PORT=2222; else SSH_PORT=22; fi
fi

if port_open "$SSH_PORT"; then
  warn "Cong $SSH_PORT dang duoc dung, thu cong khac..."
  found=""
  for p in 2222 2223 2224 2225 2200 2022; do
    if ! port_open "$p"; then SSH_PORT="$p"; found=1; break; fi
  done
  [ -n "$found" ] || die "Khong tim duoc cong trong."
  info "Dung cong $SSH_PORT"
fi

# -------------------------------------------------------------
# 3. Cau hinh sshd
# -------------------------------------------------------------
hr
printf '  2. CAU HINH SSH\n'
hr

SSHD_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
DROPIN="$DROPIN_DIR/99-bore-tunnel.conf"

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] ghi $DROPIN voi Port $SSH_PORT, PermitRootLogin yes, PasswordAuthentication yes"
else
  [ -f "$SSHD_CONFIG" ] || run $SUDO mkdir -p /etc/ssh
  if [ -f "$SSHD_CONFIG" ] && [ ! -f "${SSHD_CONFIG}.bore-ssh.bak" ]; then
    $SUDO cp -a "$SSHD_CONFIG" "${SSHD_CONFIG}.bore-ssh.bak"
    info "Da backup: ${SSHD_CONFIG}.bore-ssh.bak"
  fi

  $SUDO mkdir -p "$DROPIN_DIR"
  $SUDO tee "$DROPIN" >/dev/null <<EOF
# Quan ly boi setup-ssh-bore.sh
Port $SSH_PORT
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
UsePAM yes
PermitEmptyPasswords no
AllowTcpForwarding yes
LogLevel VERBOSE
X11Forwarding no
ClientAliveInterval 60
ClientAliveCountMax 3
EOF

  # Drop-in chi co hieu luc khi sshd_config co Include
  if ! grep -qE "^[[:space:]]*Include[[:space:]]+$DROPIN_DIR/\*\.conf" "$SSHD_CONFIG" 2>/dev/null; then
    tmpf="$(mktemp)"
    printf 'Include %s/*.conf\n\n' "$DROPIN_DIR" > "$tmpf"
    cat "$SSHD_CONFIG" >> "$tmpf" 2>/dev/null
    $SUDO cat "$tmpf" > "$SSHD_CONFIG"
    rm -f "$tmpf"
  fi

  # Vo hieu cac dong trung lap trong sshd_config de drop-in quyet dinh
  $SUDO sed -i -E 's/^([[:space:]]*)(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitEmptyPasswords|UsePAM)[[:space:]]+/\1#\2 /I' "$SSHD_CONFIG"

  mkdir -p /run/sshd 2>/dev/null
  $SUDO mkdir -p /run/sshd
  $SUDO chmod 0755 /run/sshd

  # Host keys bat buoc trong container / Colab
  if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    info "Tao host keys..."
    $SUDO ssh-keygen -A >/dev/null 2>&1
  fi
  ok "Da ghi cau hinh: $DROPIN"
fi

if [ "$DRY_RUN" != "1" ]; then
  if $SUDO "$SSHD_BIN" -t 2>/tmp/sshd-test.err; then
    ok "Cau hinh hop le (sshd -t)"
  else
    bad "Cau hinh loi:"
    sed 's/^/       /' /tmp/sshd-test.err
    [ -f "${SSHD_CONFIG}.bore-ssh.bak" ] && $SUDO cp -a "${SSHD_CONFIG}.bore-ssh.bak" "$SSHD_CONFIG" \
      && warn "Da khoi phuc sshd_config tu backup."
    die "Dung lai de tranh lam hong SSH cua may."
  fi
fi

# -------------------------------------------------------------
# 4. Mat khau cho user
# -------------------------------------------------------------
hr
printf '  3. MAT KHAU DANG NHAP\n'
hr

gen_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 16
}

if [ -z "$SSH_PASSWORD" ]; then
  SSH_PASSWORD="$(gen_password)"
  while [ "${#SSH_PASSWORD}" -lt 12 ]; do SSH_PASSWORD="$(gen_password)"; done
fi

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] dat mat khau cho $TUNNEL_USER"
else
  if id "$TUNNEL_USER" >/dev/null 2>&1; then
    if printf '%s:%s\n' "$TUNNEL_USER" "$SSH_PASSWORD" | $SUDO chpasswd 2>/dev/null; then
      ok "Da dat mat khau cho user: $TUNNEL_USER"
    else
      warn "chpasswd that bai, thu usermod..."
      hash="$(printf '%s' "$SSH_PASSWORD" | openssl passwd -6 -stdin 2>/dev/null)"
      [ -n "$hash" ] && $SUDO usermod --password "$hash" "$TUNNEL_USER" \
        && ok "Da dat mat khau bang usermod" \
        || die "Khong dat duoc mat khau cho $TUNNEL_USER"
    fi
  else
    die "User '$TUNNEL_USER' khong ton tai."
  fi
fi

# -------------------------------------------------------------
# 5. Khoi dong sshd
# -------------------------------------------------------------
hr
printf '  4. KHOI DONG SSH SERVER\n'
hr

if [ "$DRY_RUN" != "1" ]; then
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    info "Dung systemd..."
    $SUDO systemctl enable ssh >/dev/null 2>&1 || $SUDO systemctl enable sshd >/dev/null 2>&1 || true
    $SUDO systemctl restart ssh 2>/dev/null || $SUDO systemctl restart sshd 2>/dev/null || true
  else
    info "Khong co systemd, chay sshd truc tiep..."
    if [ "$is_container" = "1" ] || [ "$on_colab" = "1" ]; then
      pkill -x sshd 2>/dev/null || true
      sleep 1
    elif pgrep -x sshd >/dev/null 2>&1; then
      # May that dang co phien SSH: chi reload, khong kill
      master="$(pgrep -x sshd | head -n1)"
      info "sshd dang chay (pid $master), gui SIGHUP de nap cau hinh..."
      $SUDO kill -HUP "$master" 2>/dev/null || true
      sleep 1
    fi
    if ! pgrep -x sshd >/dev/null 2>&1; then
      $SUDO mkdir -p /run/sshd
      $SUDO "$SSHD_BIN" -E /tmp/sshd-bore.log || die "Khong khoi dong duoc sshd."
    fi
  fi

  # Cho cong mo
  listening=0
  for _ in $(seq 1 20); do
    if port_open "$SSH_PORT"; then listening=1; break; fi
    sleep 0.5
  done
  [ "$listening" = "1" ] || die "sshd khong listen tren cong $SSH_PORT. Xem /tmp/sshd-bore.log"
  ok "sshd dang listen tren cong $SSH_PORT"
fi

# -------------------------------------------------------------
# 6. Tu kiem tra
# -------------------------------------------------------------
hr
printf '  5. KIEM TRA TU DONG\n'
hr

CHECKS_FAIL=0
if [ "$DRY_RUN" != "1" ]; then
  probe="$($SUDO "$SSHD_BIN" -T 2>/dev/null)"

  echo "$probe" | grep -qi '^permitrootlogin yes' \
    && ok "PermitRootLogin = yes" || { bad "PermitRootLogin != yes"; CHECKS_FAIL=1; }
  echo "$probe" | grep -qi '^passwordauthentication yes' \
    && ok "PasswordAuthentication = yes" || { bad "PasswordAuthentication != yes"; CHECKS_FAIL=1; }
  echo "$probe" | grep -qx "port $SSH_PORT" \
    && ok "Port = $SSH_PORT" || { warn "Port trong config khac $SSH_PORT"; }

  if ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    ok "Host keys san sang"
  else
    bad "Thieu host keys"; CHECKS_FAIL=1
  fi

  port_open "$SSH_PORT" && ok "Cong $SSH_PORT dang mo" || { bad "Cong $SSH_PORT dong"; CHECKS_FAIL=1; }
else
  info "[dry-run] bo qua kiem tra"
fi

# -------------------------------------------------------------
# 7. Mo bore tunnel
# -------------------------------------------------------------
find_bore() {
  if [ -n "$BORE_BIN" ] && [ -x "$BORE_BIN" ]; then return 0; fi
  if [ -x "$ROOT/bin/bore" ]; then BORE_BIN="$ROOT/bin/bore"; return 0; fi
  if command -v bore >/dev/null 2>&1; then BORE_BIN="$(command -v bore)"; return 0; fi

  case "$(uname -m)" in
    x86_64|amd64)  asset="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) asset="aarch64-unknown-linux-musl" ;;
    armv7l|armv7)  asset="armv7-unknown-linux-musleabihf" ;;
    i386|i686)     asset="i686-unknown-linux-musl" ;;
    *) return 1 ;;
  esac

  url="https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/bore-v${BORE_VERSION}-${asset}.tar.gz"
  info "Tai bore v${BORE_VERSION} (${asset})..."
  mkdir -p "$ROOT/bin"
  tmpd="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$tmpd/bore.tar.gz" "$url" || { rm -rf "$tmpd"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmpd/bore.tar.gz" "$url" || { rm -rf "$tmpd"; return 1; }
  else
    rm -rf "$tmpd"; return 1
  fi
  tar -xzf "$tmpd/bore.tar.gz" -C "$tmpd" bore 2>/dev/null || { rm -rf "$tmpd"; return 1; }
  mv -f "$tmpd/bore" "$ROOT/bin/bore" 2>/dev/null || { rm -rf "$tmpd"; return 1; }
  chmod +x "$ROOT/bin/bore"
  rm -rf "$tmpd"
  BORE_BIN="$ROOT/bin/bore"
  return 0
}

parse_bore_port() {
  local line tail
  line="$(grep -a 'listening at ' "$LOG" 2>/dev/null | tail -n1)"
  [ -n "$line" ] || return 0
  tail="${line##*listening at }"
  tail="${tail##*:}"
  case "$tail" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$tail"
}

cleanup() {
  if [ -n "$BORE_PID" ] && kill -0 "$BORE_PID" 2>/dev/null; then
    kill "$BORE_PID" 2>/dev/null || true
  fi
}

if [ "$SETUP_ONLY" = "1" ]; then
  hr
  printf '%s  SSH DA SAN SANG (khong mo tunnel)%s\n' "$GRN" "$RST"
  hr
  printf '  Host : 127.0.0.1 (hoac IP may nay)\n  Port : %s\n  User : %s\n  Pass : %s\n' \
    "$SSH_PORT" "$TUNNEL_USER" "$SSH_PASSWORD"
  hr
  [ "$CHECKS_FAIL" = "0" ] && exit 0 || exit 1
fi

hr
printf '  6. MO BORE TUNNEL\n'
hr

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] bore local $SSH_PORT --to $BORE_SERVER"
  exit 0
fi

find_bore || die "Khong tai duoc bore. Cai thu cong vao $ROOT/bin/bore"
ok "bore: $BORE_BIN"

args=(local "$SSH_PORT" --to "$BORE_SERVER")
[ -n "$REMOTE_PORT" ] && args+=(--port "$REMOTE_PORT")
[ -n "$BORE_SECRET" ] && args+=(--secret "$BORE_SECRET")

: > "$LOG"
"$BORE_BIN" "${args[@]}" >"$LOG" 2>&1 &
BORE_PID=$!
trap cleanup EXIT INT TERM

PUBLIC_PORT=""
for _ in $(seq 1 30); do
  PUBLIC_PORT="$(parse_bore_port)"
  [ -n "$PUBLIC_PORT" ] && break
  if grep -qiE 'error|failed' "$LOG" 2>/dev/null; then break; fi
  sleep 1
done

if [ -z "$PUBLIC_PORT" ]; then
  bad "Khong mo duoc tunnel. Log:"
  sed 's/^/       /' "$LOG"
  [ -n "$REMOTE_PORT" ] && warn "REMOTE_PORT=$REMOTE_PORT co the da bi dung, thu cong khac."
  exit 1
fi

PUBLIC_HOST="${BORE_SERVER%%:*}"
ok "Tunnel dang mo: ${PUBLIC_HOST}:${PUBLIC_PORT}"

# Kiem tra duong di that su qua relay (khong bat buoc)
if (exec 3<>"/dev/tcp/${PUBLIC_HOST}/${PUBLIC_PORT}") 2>/dev/null; then
  ok "Ket noi thu qua relay thanh cong"
else
  warn "Chua ket noi thu duoc qua relay (DNS/firewall?), nhung tunnel da dang ky."
fi

printf 'HOST=%s\nPORT=%s\n' "$PUBLIC_HOST" "$PUBLIC_PORT" > "$STATE"

SSH_CMD="ssh -p ${PUBLIC_PORT} ${TUNNEL_USER}@${PUBLIC_HOST}"

hr
printf '%s  SSH SERVER DA SAN SANG%s\n' "$GRN" "$RST"
hr
printf '  Public host : %s\n' "$CYN$PUBLIC_HOST$RST"
printf '  Public port : %s\n' "$CYN$PUBLIC_PORT$RST"
printf '  User        : %s\n' "$TUNNEL_USER"
printf '  Password    : %s\n' "$BLD$SSH_PASSWORD$RST"
hr
printf '%s  %s%s\n' "$BLD" "$SSH_CMD" "$RST"
hr
printf '  Tu Windows:  bore-ssh.bat client\n'
printf '  Dung tunnel: Ctrl+C\n'
hr

if [ "$CHECKS_FAIL" != "0" ]; then
  warn "Mot so buoc kiem tra chua dat, xem phan [fail] o tren."
fi

wait "$BORE_PID"
bad "Tunnel da dung."
