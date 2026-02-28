#!/bin/bash
set -e

# ───────── Warna ─────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

CACHE_DIR="/etc/zivpn"
IP_FILE="$CACHE_DIR/ip.txt"
ISP_FILE="$CACHE_DIR/isp.txt"

mkdir -p "$CACHE_DIR"

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}     ZIVPN Installer + SSL Auto Setup      ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# Deteksi IP dan ISP
IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)
ISP=$(curl -s ipinfo.io/org | cut -d " " -f 2-10)
IP=${IP:-N/A}
ISP=${ISP:-N/A}

echo "$IP"  > "$IP_FILE"
echo "$ISP" > "$ISP_FILE"
chmod 644 "$IP_FILE" "$ISP_FILE"

echo -e "${GREEN}IP  : $IP${NC}"
echo -e "${GREEN}ISP : $ISP${NC}"
echo ""

# Download & jalankan zivpn-manager (instalasi utama)
echo -e "${YELLOW}[1/3] Mengunduh dan menjalankan ZIVPN manager...${NC}"
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn-manager -O /usr/local/bin/zivpn-manager
chmod +x /usr/local/bin/zivpn-manager
/usr/local/bin/zivpn-manager

# Setelah instalasi selesai, jalankan setup SSL
echo ""
echo -e "${YELLOW}[2/3] Memulai setup SSL + Cloudflare Domain...${NC}"
sleep 2

# Download setup-ssl-api.sh dari repo
SSL_SETUP_URL="https://raw.githubusercontent.com/AutoNV/udpzivpn/main/setup-ssl-api.sh"
wget -q "$SSL_SETUP_URL" -O /usr/local/bin/setup-ssl-api.sh 2>/dev/null || {
    # Fallback: buat dari inline jika tidak ada di repo
    echo -e "${YELLOW}Script SSL tidak ditemukan di repo, membuat lokal...${NC}"
    cat > /usr/local/bin/setup-ssl-api.sh << 'SSLEOF'
#!/bin/bash
# Placeholder - akan diisi oleh file setup-ssl-api.sh dari repo
echo "Setup SSL script tidak tersedia, jalankan manual: setup-ssl-api.sh"
SSLEOF
}
chmod +x /usr/local/bin/setup-ssl-api.sh
/usr/local/bin/setup-ssl-api.sh

echo ""
echo -e "${GREEN}[3/3] Instalasi selesai!${NC}"
echo ""

# Tampilkan info domain dan API
if [ -f "$CACHE_DIR/domain.txt" ] && [ -f "$CACHE_DIR/api_auth.key" ]; then
    DOMAIN=$(cat "$CACHE_DIR/domain.txt")
    API_KEY=$(cat "$CACHE_DIR/api_auth.key")
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Domain API : https://${DOMAIN}${NC}"
    echo -e "${CYAN}  API Key    : ${API_KEY}${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Contoh penggunaan API:"
    echo -e "${GREEN}  https://${DOMAIN}/create?auth=${API_KEY}&password=user1&exp=30${NC}"
    echo -e "${GREEN}  https://${DOMAIN}/delete?auth=${API_KEY}&password=user1${NC}"
    echo -e "${GREEN}  https://${DOMAIN}/renew?auth=${API_KEY}&password=user1&exp=30${NC}"
    echo -e "${GREEN}  https://${DOMAIN}/trial?auth=${API_KEY}&exp=60${NC}"
fi
