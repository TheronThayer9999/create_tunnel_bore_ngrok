#!/usr/bin/env bash
# =============================================================
#  check-log.sh - phan tich log SSH (Linux) de phat hien
#                 scan / brute-force / flood
#
#  Chay: ./scripts/check-log.sh [--hours 24] [--port 2222]
# =============================================================
set -uo pipefail

HOURS=24
PORT=2222
TOP=10

while [ $# -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --port)  PORT="${2:-22}";  shift 2 ;;
    --top)   TOP="${2:-10}";   shift 2 ;;
    -h|--help)
      echo "usage: check-log.sh [--hours N] [--port N] [--top N]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [ -t 1 ]; then
  RST=$'\033[0m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; BLD=$'\033[1m'
else
  RST=""; GRN=""; YEL=""; RED=""; BLD=""
fi

line() { printf '  %-24s: %s\n' "$1" "$2"; }

collect() {
  if command -v journalctl >/dev/null 2>&1; then
    local out
    out="$(journalctl -u ssh -u sshd --since "-${HOURS}h" --no-pager 2>/dev/null || true)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  fi
  local f
  for f in /var/log/auth.log /var/log/secure /var/log/messages; do
    if [ -r "$f" ]; then tail -n 50000 "$f" 2>/dev/null; fi
  done
}

LOG="$(collect)"

failed=$(printf '%s\n' "$LOG" | grep -c 'Failed password' || true)
invalid=$(printf '%s\n' "$LOG" | grep -c 'Invalid user' || true)
accepted=$(printf '%s\n' "$LOG" | grep -cE 'Accepted (password|publickey)' || true)

maxmin="$(printf '%s\n' "$LOG" | grep -E 'sshd' | awk '{print $1" "$2" "substr($3,1,5)}' \
          | sort | uniq -c | sort -rn | head -n1 | awk '{print $1}')"
[ -n "$maxmin" ] || maxmin=0

est=0
if command -v ss >/dev/null 2>&1; then
  est="$(ss -tn 2>/dev/null | grep -c ":$PORT .*ESTAB" || true)"
elif command -v netstat >/dev/null 2>&1; then
  est="$(netstat -tn 2>/dev/null | grep -c ":$PORT .*ESTABLISHED" || true)"
fi

printf '\n%s\n' "============================================================"
printf '  KIEM TRA LOG SSH - %s gio qua\n' "$HOURS"
printf '%s\n' "============================================================"
line 'Sai mat khau'          "$failed"
line 'User khong ton tai'   "$invalid"
line 'Dang nhap thanh cong' "$accepted"
line 'Ket noi/phut cao nhat' "$maxmin"
line 'Ket noi dang mo'      "$est"

if [ "$failed" -gt 0 ] || [ "$invalid" -gt 0 ]; then
  printf '  ------------------------------------------------------------\n'
  printf '  Top IP bi sai mat khau:\n'
  printf '%s\n' "$LOG" | grep -E 'Failed password|Invalid user' \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "    %-18s %s lan\n", $2, $1}'
  printf '  (qua bore relay nen IP nguon la 127.0.0.1, khong phai IP that)\n'
fi

printf '  ------------------------------------------------------------\n'

verdict="Binh thuong: chua thay dau hieu tan cong."
color="$GRN"
if [ "$failed" -ge 50 ] || [ "$invalid" -ge 25 ]; then
  verdict="CANH BAO: dang bi brute-force / scan manh. Doi mat khau, dung SSH key, tat tunnel khi khong dung."
  color="$RED"
elif [ "$failed" -ge 10 ] || [ "$invalid" -ge 5 ]; then
  verdict="Chu y: co dau hieu do quet. Nen dung mat khau manh hoac SSH key."
  color="$YEL"
fi
if [ "${maxmin:-0}" -ge 60 ]; then
  verdict="CANH BAO: so ket noi/phut rat cao, co the dang bi flood."
  color="$RED"
fi

printf '  Ket luan: %s%s%s\n' "$color" "$verdict" "$RST"
printf '%s\n\n' "============================================================"

printf '  Goi y tang cuong:\n'
printf '    - Dung SSH key thay mat khau (SSH_KEY trong tunnel.conf)\n'
printf '    - Ghim port kho doan: REMOTE_PORT trong tunnel.conf\n'
printf '    - Gioi han user duoc phep dang nhap\n'
printf '    - Chi mo tunnel khi can, dong khi xong\n'
printf '    - KHONG dung fail2ban: qua bore moi ket noi la 127.0.0.1\n\n'
