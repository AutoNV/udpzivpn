#!/bin/bash
# ============================================================
# ZIVPN - Setup SSL API dengan Cloudflare + acme.sh + Nginx
# Domain: nexusdev.web.id (Cloudflare managed)
# Email  : ayfa7756@gmail.com
# ============================================================

set -e

# ───────── Kredensial Cloudflare (HARDCODED) ─────────
CF_EMAIL="ayfa7756@gmail.com"
CF_API_KEY="89df648f7990d6d807d6c9ed7dd265d9d4300"
CF_ZONE_ID="beb2618f7705d1b38b2d580ae033a233"
BASE_DOMAIN="nexusdev.web.id"

# ───────── Warna ─────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1;37m'
NC='\033[0m'

CONFIG_DIR="/etc/zivpn"
CF_SUBDOMAIN_FILE="$CONFIG_DIR/cf_subdomain.txt"
DOMAIN_FILE="$CONFIG_DIR/domain.txt"
API_PORT=5888

log()   { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ═══════════════════════════════════════════════════════════
# 1. GENERATE RANDOM SUBDOMAIN
# ═══════════════════════════════════════════════════════════
generate_random_subdomain() {
    local chars='abcdefghijklmnopqrstuvwxyz0123456789'
    local sub=""
    for i in $(seq 1 8); do
        sub="${sub}${chars:RANDOM%${#chars}:1}"
    done
    echo "$sub"
}

# ═══════════════════════════════════════════════════════════
# 2. BUAT DNS RECORD DI CLOUDFLARE
# ═══════════════════════════════════════════════════════════
create_cloudflare_dns() {
    local subdomain="$1"
    local server_ip
    server_ip=$(cat "$CONFIG_DIR/ip.txt")
    local full_domain="${subdomain}.${BASE_DOMAIN}"

    log "Membuat DNS record: ${full_domain} → ${server_ip}"

    # Hapus record lama jika ada
    local old_ids
    old_ids=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${full_domain}&type=A" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json" | jq -r '.result[].id' 2>/dev/null || true)

    for rid in $old_ids; do
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${rid}" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_API_KEY}" \
            -H "Content-Type: application/json" > /dev/null
        log "Record lama dihapus: $rid"
    done

    # Buat record baru (proxy OFF agar acme.sh bisa verifikasi)
    local result
    result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${full_domain}\",\"content\":\"${server_ip}\",\"ttl\":120,\"proxied\":false}")

    local success
    success=$(echo "$result" | jq -r '.success')

    if [ "$success" != "true" ]; then
        echo "$result" | jq '.errors'
        err "Gagal membuat DNS record di Cloudflare!"
    fi

    # Simpan record ID untuk keperluan update/hapus nanti
    local record_id
    record_id=$(echo "$result" | jq -r '.result.id')
    echo "$record_id" > "$CONFIG_DIR/cf_record_id.txt"

    ok "DNS record berhasil dibuat: ${full_domain} (ID: ${record_id})"
    echo "$full_domain"
}

# ═══════════════════════════════════════════════════════════
# 3. TUNGGU DNS PROPAGASI (max 2 menit)
# ═══════════════════════════════════════════════════════════
wait_dns() {
    local domain="$1"
    local server_ip
    server_ip=$(cat "$CONFIG_DIR/ip.txt")
    log "Menunggu propagasi DNS untuk ${domain}..."
    for i in $(seq 1 24); do
        local resolved
        resolved=$(dig +short "$domain" @1.1.1.1 2>/dev/null | head -1 || true)
        if [ "$resolved" = "$server_ip" ]; then
            ok "DNS sudah propagasi: ${domain} → ${server_ip}"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    echo ""
    warn "DNS belum propagasi sepenuhnya, lanjut tetap dicoba..."
}

# ═══════════════════════════════════════════════════════════
# 4. INSTALL ACME.SH & ISSUE SERTIFIKAT SSL
# ═══════════════════════════════════════════════════════════
setup_ssl() {
    local domain="$1"

    # Install acme.sh jika belum ada
    if [ ! -f "/root/.acme.sh/acme.sh" ]; then
        log "Menginstall acme.sh..."
        curl -sS https://get.acme.sh | sh -s email="${CF_EMAIL}" || err "Gagal install acme.sh"
        source /root/.acme.sh/acme.sh.env 2>/dev/null || true
    fi

    local ACME="/root/.acme.sh/acme.sh"

    # Set default CA ke ZeroSSL
    "$ACME" --set-default-ca --server zerossl 2>/dev/null || true

    # Register ZeroSSL account
    "$ACME" --register-account -m "${CF_EMAIL}" --server zerossl 2>/dev/null || true

    log "Menerbitkan sertifikat SSL untuk ${domain} via DNS Cloudflare..."

    # Issue cert menggunakan DNS API Cloudflare
    export CF_Key="${CF_API_KEY}"
    export CF_Email="${CF_EMAIL}"

    "$ACME" --issue \
        --dns dns_cf \
        -d "$domain" \
        --keylength 2048 \
        --force 2>&1 || {
        # Fallback ke Let's Encrypt jika ZeroSSL gagal
        warn "ZeroSSL gagal, mencoba Let's Encrypt..."
        "$ACME" --set-default-ca --server letsencrypt 2>/dev/null || true
        "$ACME" --issue \
            --dns dns_cf \
            -d "$domain" \
            --keylength 2048 \
            --force 2>&1 || err "Gagal menerbitkan sertifikat SSL!"
    }

    # Install cert ke direktori zivpn
    mkdir -p "$CONFIG_DIR/ssl"
    "$ACME" --install-cert -d "$domain" \
        --key-file   "$CONFIG_DIR/ssl/${domain}.key" \
        --fullchain-file "$CONFIG_DIR/ssl/${domain}.crt" \
        --reloadcmd  "systemctl reload nginx 2>/dev/null || true"

    ok "Sertifikat SSL berhasil diterbitkan untuk ${domain}"
}

# ═══════════════════════════════════════════════════════════
# 5. INSTALL & KONFIGURASI NGINX REVERSE PROXY
# ═══════════════════════════════════════════════════════════
setup_nginx() {
    local domain="$1"

    log "Menginstall Nginx..."
    apt-get install -y nginx > /dev/null 2>&1

    # Matikan default site
    rm -f /etc/nginx/sites-enabled/default

    log "Membuat konfigurasi Nginx untuk ${domain}..."
    cat > "/etc/nginx/sites-available/zivpn-api" <<NGINXEOF
# ZIVPN API - Auto Generated
# Domain: ${domain}

# Redirect HTTP ke HTTPS
server {
    listen 80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}

# HTTPS + Reverse Proxy ke Node.js API
server {
    listen 443 ssl http2;
    server_name ${domain};

    ssl_certificate     ${CONFIG_DIR}/ssl/${domain}.crt;
    ssl_certificate_key ${CONFIG_DIR}/ssl/${domain}.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Sembunyikan versi Nginx
    server_tokens off;

    # Proxy langsung ke Node.js (semua path diteruskan)
    location ~ ^/(create|delete|renew|trial)$ {
        proxy_pass         http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
        proxy_connect_timeout 10s;
    }

    # Halaman status sederhana
    location /status {
        return 200 'ZIVPN API OK';
        add_header Content-Type text/plain;
    }

    # Tolak akses selain endpoint di atas
    location / {
        return 404;
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/zivpn-api /etc/nginx/sites-enabled/zivpn-api

    # Test konfigurasi Nginx
    nginx -t || err "Konfigurasi Nginx tidak valid!"

    systemctl enable nginx
    systemctl restart nginx

    ok "Nginx berhasil dikonfigurasi untuk ${domain}"
}

# ═══════════════════════════════════════════════════════════
# 6. BUKA PORT 80 & 443 DI FIREWALL
# ═══════════════════════════════════════════════════════════
setup_firewall() {
    log "Membuka port 80 (HTTP) dan 443 (HTTPS) di firewall..."
    iptables -I INPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    # Tutup akses langsung ke port API dari luar (hanya lewat Nginx)
    # Hanya izinkan akses lokal ke port 5888
    iptables -D INPUT -p tcp --dport "${API_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport "${API_PORT}" -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport "${API_PORT}" ! -s 127.0.0.1 -j DROP 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
    ok "Firewall dikonfigurasi"
}

# ═══════════════════════════════════════════════════════════
# 7. UPDATE Node.js API - Bind ke localhost saja
# ═══════════════════════════════════════════════════════════
update_api_bind() {
    log "Mengupdate route dan bind API Node.js..."
    local api_file="/etc/zivpn/api/api.js"
    if [ -f "$api_file" ]; then
        # Update route dari /create/zivpn → /create dst
        sed -i "s|'/create/zivpn'|'/create'|g" "$api_file" 2>/dev/null || true
        sed -i "s|'/delete/zivpn'|'/delete'|g" "$api_file" 2>/dev/null || true
        sed -i "s|'/renew/zivpn'|'/renew'|g"   "$api_file" 2>/dev/null || true
        sed -i "s|'/trial/zivpn'|'/trial'|g"   "$api_file" 2>/dev/null || true
        # Bind ke localhost saja
        if ! grep -q "127.0.0.1" "$api_file" 2>/dev/null; then
            sed -i "s/app\.listen(PORT,/app.listen(PORT, '127.0.0.1',/" "$api_file" 2>/dev/null || true
        fi
        systemctl restart zivpn-api.service 2>/dev/null || true
    fi
    ok "API diperbarui: route /create, /delete, /renew, /trial — listen 127.0.0.1:${API_PORT}"
}

# ═══════════════════════════════════════════════════════════
# 8. AUTO RENEW SERTIFIKAT (cron)
# ═══════════════════════════════════════════════════════════
setup_auto_renew() {
    local domain="$1"
    log "Mengatur auto-renew sertifikat..."
    # acme.sh sudah menambahkan cron sendiri saat install
    # Pastikan reload nginx setelah renew
    /root/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file   "$CONFIG_DIR/ssl/${domain}.key" \
        --fullchain-file "$CONFIG_DIR/ssl/${domain}.crt" \
        --reloadcmd  "systemctl reload nginx" 2>/dev/null || true
    ok "Auto-renew dikonfigurasi"
}

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════
main() {
    if [ "$(id -u)" -ne 0 ]; then
        err "Harus dijalankan sebagai root!"
    fi

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║     ZIVPN - Setup SSL API + Cloudflare Domain        ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    mkdir -p "$CONFIG_DIR/ssl"

    # Cek apakah sudah ada domain sebelumnya
    local SUBDOMAIN FULL_DOMAIN
    if [ -f "$CF_SUBDOMAIN_FILE" ] && [ -f "$DOMAIN_FILE" ]; then
        SUBDOMAIN=$(cat "$CF_SUBDOMAIN_FILE")
        FULL_DOMAIN=$(cat "$DOMAIN_FILE")
        warn "Domain sebelumnya ditemukan: ${FULL_DOMAIN}"
        read -rp "Gunakan domain ini? (y/n): " use_old
        if [[ "$use_old" =~ ^[Nn]$ ]]; then
            SUBDOMAIN=$(generate_random_subdomain)
            FULL_DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"
        fi
    else
        SUBDOMAIN=$(generate_random_subdomain)
        FULL_DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"
    fi

    echo -e "${BOLD}Domain yang akan digunakan: ${CYAN}${FULL_DOMAIN}${NC}"
    echo ""

    # Simpan subdomain dan domain
    echo "$SUBDOMAIN" > "$CF_SUBDOMAIN_FILE"
    echo "$FULL_DOMAIN" > "$DOMAIN_FILE"

    # Install dependensi
    log "Menginstall dependensi (curl, jq, dig, nginx)..."
    apt-get update -qq
    apt-get install -y curl jq dnsutils nginx socat > /dev/null 2>&1
    ok "Dependensi terinstall"

    # Step 1: Buat DNS Record
    create_cloudflare_dns "$SUBDOMAIN"

    # Step 2: Tunggu DNS
    wait_dns "$FULL_DOMAIN"

    # Step 3: Issue SSL
    setup_ssl "$FULL_DOMAIN"

    # Step 4: Setup Nginx
    setup_nginx "$FULL_DOMAIN"

    # Step 5: Firewall
    setup_firewall

    # Step 6: Update API bind
    update_api_bind

    # Step 7: Auto renew
    setup_auto_renew "$FULL_DOMAIN"

    # Step 8: Tampilkan hasil
    local API_KEY=""
    [ -f "$CONFIG_DIR/api_auth.key" ] && API_KEY=$(cat "$CONFIG_DIR/api_auth.key")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ SETUP BERHASIL!                           ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Domain  : ${CYAN}${FULL_DOMAIN}${NC}"
    echo -e "${GREEN}║${NC}  SSL     : ${CYAN}ZeroSSL / Let's Encrypt (Auto Renew)${NC}"
    echo -e "${GREEN}║${NC}  API Key : ${CYAN}${API_KEY}${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Endpoint API:${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}https://${FULL_DOMAIN}/create?auth=${API_KEY}&password=USER&exp=30${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}https://${FULL_DOMAIN}/delete?auth=${API_KEY}&password=USER${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}https://${FULL_DOMAIN}/renew?auth=${API_KEY}&password=USER&exp=30${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}https://${FULL_DOMAIN}/trial?auth=${API_KEY}&exp=60${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
