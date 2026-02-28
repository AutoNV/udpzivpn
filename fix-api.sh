#!/bin/bash

# ============================================================
#   ZIVPN API FIX SCRIPT
#   Fix: Internal Server Error pada endpoint /create/zivpn
#   Author: AutoNV
#   Issue: Missing shebang + sudo conflict di api.js
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

MANAGER_PATH="/usr/local/bin/zivpn-manager"
API_PATH="/etc/zivpn/api/api.js"

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}        ZIVPN API FIX - Internal Server Error   ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# ── Root check ──────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[✗] Script harus dijalankan sebagai root!${NC}"
    exit 1
fi

# ── Cek file ada ────────────────────────────────────────────
if [ ! -f "$MANAGER_PATH" ]; then
    echo -e "${RED}[✗] File $MANAGER_PATH tidak ditemukan!${NC}"
    exit 1
fi

if [ ! -f "$API_PATH" ]; then
    echo -e "${RED}[✗] File $API_PATH tidak ditemukan!${NC}"
    exit 1
fi

# ── FIX 1: Tambah shebang #!/bin/bash ke zivpn-manager ──────
echo -e "${YELLOW}[*] Mengecek shebang di $MANAGER_PATH ...${NC}"
FIRST_LINE=$(head -1 "$MANAGER_PATH")

if [[ "$FIRST_LINE" == "#!/bin/bash" ]]; then
    echo -e "${GREEN}[✓] Shebang sudah benar, skip.${NC}"
elif [[ "$FIRST_LINE" == "#!/bin/sh" ]]; then
    echo -e "${YELLOW}[*] Shebang #!/bin/sh ditemukan, mengganti ke #!/bin/bash ...${NC}"
    sed -i '1s|#!/bin/sh|#!/bin/bash|' "$MANAGER_PATH"
    echo -e "${GREEN}[✓] Shebang berhasil diganti ke #!/bin/bash${NC}"
else
    echo -e "${YELLOW}[*] Tidak ada shebang, menambahkan #!/bin/bash di baris pertama ...${NC}"
    sed -i '1i #!/bin/bash' "$MANAGER_PATH"
    echo -e "${GREEN}[✓] Shebang #!/bin/bash berhasil ditambahkan${NC}"
fi

chmod +x "$MANAGER_PATH"

# ── FIX 2: Perbaiki error message di api.js ─────────────────
echo ""
echo -e "${YELLOW}[*] Memperbaiki error handling di $API_PATH ...${NC}"

# Backup dulu
cp "$API_PATH" "${API_PATH}.bak"
echo -e "${GREEN}[✓] Backup disimpan di ${API_PATH}.bak${NC}"

# Fix: ganti error message agar tampilkan stderr/stdout asli
if grep -q "An internal server error occurred." "$API_PATH"; then
    sed -i "s/const errorMessage = stderr.includes('Error:') ? stderr : 'An internal server error occurred.';/const errorMessage = stderr || stdout || 'An internal server error occurred.';/" "$API_PATH"
    echo -e "${GREEN}[✓] Error handling diperbaiki (tampilkan pesan asli)${NC}"
else
    echo -e "${CYAN}[i] Error handling sudah diperbaiki sebelumnya, skip.${NC}"
fi

# ── FIX 3: Hapus sudo di execFile (API sudah jalan sebagai root) ──
echo ""
echo -e "${YELLOW}[*] Memperbaiki execFile (hapus sudo) di $API_PATH ...${NC}"

if grep -q "execFile('sudo'" "$API_PATH"; then
    # Ganti: execFile('sudo', [SCRIPT, command, ...args] → execFile('/bin/bash', [SCRIPT, command, ...args]
    sed -i "s|execFile('sudo', \[ZIVPN_MANAGER_SCRIPT, command, \.\.\.args\]|execFile('/bin/bash', [ZIVPN_MANAGER_SCRIPT, command, ...args]|g" "$API_PATH"
    echo -e "${GREEN}[✓] sudo dihapus, diganti execFile dengan /bin/bash${NC}"
elif grep -q "execFile(ZIVPN_MANAGER_SCRIPT" "$API_PATH"; then
    # Kalau sudo sudah dihapus tapi belum pakai bash
    sed -i "s|execFile(ZIVPN_MANAGER_SCRIPT, \[command, \.\.\.args\]|execFile('/bin/bash', [ZIVPN_MANAGER_SCRIPT, command, ...args]|g" "$API_PATH"
    echo -e "${GREEN}[✓] execFile diperbaiki untuk pakai /bin/bash${NC}"
elif grep -q "execFile('/bin/bash'" "$API_PATH"; then
    echo -e "${CYAN}[i] execFile sudah menggunakan /bin/bash, skip.${NC}"
else
    echo -e "${YELLOW}[!] Tidak bisa auto-patch execFile. Patch manual mungkin diperlukan.${NC}"
fi

# ── Restart service ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}[*] Merestart zivpn-api.service ...${NC}"
systemctl restart zivpn-api.service

sleep 2

STATUS=$(systemctl is-active zivpn-api.service)
if [ "$STATUS" = "active" ]; then
    echo -e "${GREEN}[✓] zivpn-api.service berjalan normal${NC}"
else
    echo -e "${RED}[✗] zivpn-api.service gagal start! Cek: journalctl -u zivpn-api.service -n 20${NC}"
fi

# ── Selesai ─────────────────────────────────────────────────
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  Fix selesai! Silakan test API endpoint:${NC}"
echo -e "${CYAN}  curl \"http://<IP>:5888/create/zivpn?password=test&exp=30&auth=<KEY>\"${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
