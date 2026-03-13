#!/bin/bash
set -e

C='\033[0;36m'
G='\033[1;32m'
W='\033[1;37m'
Y='\033[1;33m'
N='\033[0m'

progress() {
  local label="$1"
  local width=28
  local i bar filled empty
  for ((i=0; i<=100; i++)); do
    filled=$(( i * width / 100 ))
    empty=$(( width - filled ))
    bar=""
    for ((j=0; j<filled; j++)); do bar+="█"; done
    for ((j=0; j<empty; j++)); do bar+="░"; done
    printf "\r${W}  %-18s ${C}[${G}%s${C}]${W} %3d%% ${N}" "$label" "$bar" "$i"
    sleep 0.15
  done
  printf "\r${W}  %-18s ${C}[${G}%s${C}]${W} %3d%% ${N}\n" "$label" "$bar" "100"
}

ok() { printf "  ${G}✔  %s${N}\n" "$1"; }

clear

# ─── Welcome Banner ───────────────────────────────
echo -e "${C}--------------------------------------------${N}"
echo -e "${W}    Welcome to ZiVPN Manager Installer${N}"
echo -e "${C}--------------------------------------------${N}"
echo -e "${Y}    Thank you for using SC UDP ZiVPN${N}"
echo -e "${Y}    Powered by  N E X U S D E V${N}"
echo -e "${C}--------------------------------------------${N}"
echo ""
sleep 1.2

# ─── Detect IP & ISP ──────────────────────────────
echo -e "${C}--------------------------------------------${N}"
echo -e "${W}  Detecting server information...${N}"
echo -e "${C}--------------------------------------------${N}"

CACHE_DIR="/etc/zivpn"
IP_FILE="$CACHE_DIR/ip.txt"
ISP_FILE="$CACHE_DIR/isp.txt"
mkdir -p "$CACHE_DIR"

progress "Checking IP"
IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)
IP=${IP:-N/A}
echo "$IP" > "$IP_FILE"
chmod 644 "$IP_FILE"
ok "IP : $IP"

progress "Checking ISP"
ISP=$(curl -s ipinfo.io/org | cut -d " " -f 2-10)
ISP=${ISP:-N/A}
echo "$ISP" > "$ISP_FILE"
chmod 644 "$ISP_FILE"
ok "ISP : $ISP"

echo ""
sleep 0.3

# ─── Install ──────────────────────────────────────
echo -e "${C}--------------------------------------------${N}"
echo -e "${W}  Installing ZiVPN Manager...${N}"
echo -e "${C}--------------------------------------------${N}"

progress "Downloading"
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn-manager \
  -O /usr/local/bin/zivpn-manager
chmod +x /usr/local/bin/zivpn-manager
ok "zivpn-manager installed"

echo ""
sleep 0.4

# ─── Done ─────────────────────────────────────────
echo -e "${C}--------------------------------------------${N}"
echo -e "${G}  ✔  Installation completed successfully!${N}"
echo -e "${C}--------------------------------------------${N}"
echo ""
sleep 1

/usr/local/bin/zivpn-manager
