set -euo pipefail
echo "🔄 Updating ZiVPN Manager..."
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/install.sh \
-O /usr/local/bin/install.sh
chmod +x /usr/local/bin/install.sh
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn-manager \
-O /usr/local/bin/zivpn-manager
chmod +x /usr/local/bin/zivpn-manager
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/zivpn_helper.sh \
-O /usr/local/bin/zivpn_helper.sh
chmod +x /usr/local/bin/zivpn_helper.sh
wget -q https://raw.githubusercontent.com/AutoNV/udpzivpn/main/update.sh \
-O /usr/local/bin/update-manager
chmod +x /usr/local/bin/update-manager
echo "🎉 ZiVPN Update completed successfully."
echo "🧩 Checking ZiVPN NAT rule..."
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y iptables-persistent netfilter-persistent >/dev/null 2>&1 || true
systemctl enable netfilter-persistent >/dev/null 2>&1 || true
IFACE="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [ -z "${IFACE:-}" ]; then
echo "⚠️  No default interface detected. Skip NAT."
else
if iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; then
echo "✅ NAT rule already exists."
else
echo "➕ NAT rule missing. Adding..."
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
fi
echo "🧹 Cleaning duplicate NAT rules (keep one)..."
while true; do
COUNT="$(iptables -t nat -S PREROUTING 2>/dev/null | grep -c -- "--dport 6000:19999" || true)"
if [ "${COUNT:-0}" -le 1 ]; then
break
fi
iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || break
done
if netfilter-persistent save >/dev/null 2>&1; then
echo "✅ netfilter-persistent saved."
else
echo "⚠️  Failed to save netfilter-persistent (check permission/service)."
fi
fi
/usr/local/bin/zivpn-manager