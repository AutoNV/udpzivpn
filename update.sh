#!/bin/bash
set -euo pipefail

C='\033[0;36m'
G='\033[1;32m'
R='\033[0;31m'
W='\033[1;37m'
Y='\033[1;33m'
N='\033[0m'

progress() {
  local label="$1"
  local start="$2"
  local end="$3"
  local width=28
  local i bar filled empty
  for ((i=start; i<=end; i++)); do
    filled=$(( i * width / 100 ))
    empty=$(( width - filled ))
    bar=""
    for ((j=0; j<filled; j++)); do bar+="█"; done
    for ((j=0; j<empty; j++)); do bar+="░"; done
    printf "\r${C}│${W}  %-18s ${C}[${G}%s${C}]${W} %3d%% ${N}" "$label" "$bar" "$i"
    sleep 0.012
  done
  printf "\r${C}│${W}  %-18s ${C}[${G}%s${C}]${W} %3d%% ${N}\n" "$label" "$bar" "$end"
}

ok()   { printf "${C}│  ${G}✔  %-40s${N}\n" "$1"; }
warn() { printf "${C}│  ${Y}⚠  %-40s${N}\n" "$1"; }

clear

echo -e "${C}┌────────────────────────────────────────────┐"
echo -e "${C}│${W}      ⚡  ZiVPN Update Manager  ⚡         ${C}│"
echo -e "${C}└────────────────────────────────────────────┘${N}"
echo ""
sleep 0.4

# ─── Download Files ───────────────────────────────
echo -e "${C}┌────────────────────────────────────────────"
printf  "${C}│${W}  [ 1/3 ] Mengunduh file komponen...${N}\n"
echo -e "${C}├────────────────────────────────────────────${N}"

progress "install.sh" 0 25
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/install.sh \
  -O /usr/local/bin/install.sh 2>/dev/null && chmod +x /usr/local/bin/install.sh
progress "install.sh" 25 100
ok "install.sh"

progress "zivpn-manager" 0 25
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn-manager \
  -O /usr/local/bin/zivpn-manager 2>/dev/null && chmod +x /usr/local/bin/zivpn-manager
progress "zivpn-manager" 25 100
ok "zivpn-manager"

progress "zivpn_helper.sh" 0 25
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn_helper.sh \
  -O /usr/local/bin/zivpn_helper.sh 2>/dev/null && chmod +x /usr/local/bin/zivpn_helper.sh
progress "zivpn_helper.sh" 25 100
ok "zivpn_helper.sh"

progress "update-manager" 0 25
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/update.sh \
  -O /usr/local/bin/update-manager 2>/dev/null && chmod +x /usr/local/bin/update-manager
progress "update-manager" 25 100
ok "update-manager"

echo ""
sleep 0.3

# ─── Update Sistem ────────────────────────────────
echo -e "${C}┌────────────────────────────────────────────"
printf  "${C}│${W}  [ 2/3 ] Memperbarui sistem...${N}\n"
echo -e "${C}├────────────────────────────────────────────${N}"

progress "apt-get update" 0 50
apt-get update -y >/dev/null 2>&1 || true
progress "apt-get update" 50 100
ok "apt-get update"

progress "iptables-persistent" 0 50
apt-get install -y iptables-persistent netfilter-persistent >/dev/null 2>&1 || true
systemctl enable netfilter-persistent >/dev/null 2>&1 || true
progress "iptables-persistent" 50 100
ok "iptables-persistent"

echo ""
sleep 0.3

# ─── NAT Rule ─────────────────────────────────────
echo -e "${C}┌────────────────────────────────────────────"
printf  "${C}│${W}  [ 3/3 ] Memeriksa NAT rule...${N}\n"
echo -e "${C}├────────────────────────────────────────────${N}"

IFACE="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

if [ -z "${IFACE:-}" ]; then
  warn "Interface tidak ditemukan, skip NAT"
else
  if iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; then
    ok "NAT rule sudah ada"
  else
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    ok "NAT rule ditambahkan"
  fi
  while true; do
    COUNT="$(iptables -t nat -S PREROUTING 2>/dev/null | grep -c -- "--dport 6000:19999" || true)"
    [ "${COUNT:-0}" -le 1 ] && break
    iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || break
  done
  ok "Duplikat NAT dibersihkan"
  if netfilter-persistent save >/dev/null 2>&1; then
    ok "netfilter-persistent tersimpan"
  else
    warn "Gagal menyimpan netfilter-persistent"
  fi
fi

echo ""
sleep 0.4

# ─── Selesai ──────────────────────────────────────
echo -e "${C}┌────────────────────────────────────────────┐"
echo -e "${C}│  ${G}✔  Update ZiVPN selesai!                 ${C}│"
echo -e "${C}└────────────────────────────────────────────┘${N}"
echo ""
sleep 1

/usr/local/bin/zivpn-manager
