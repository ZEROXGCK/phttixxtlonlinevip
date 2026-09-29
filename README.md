# XXTLONLINE VPN PANEL — All-in-One Installer

**Modern, minimal design • Secure SSH panel • Clean white/pastel UI**

---

## 📋 What's Included

- **3x-ui** (v2.9.4 locked) — VLESS/VMess/Trojan proxy panel
- **Dropbear SSH** — Lightweight SSH server (ports 143, 109)
- **WS-Stunnel** — HTTP-CONNECT tunnel (port 80 → Dropbear:143)
- **BadVPN UDP Gateway** — UDP streaming support
- **Nginx** — SSL reverse proxy & dashboard hosting
- **Python SSH API** — Manage SSH users via REST
- **Network Tuning** — BBR congestion control, FQ qdisc, RPS/RFS, IRQ balancing
- **Minimal UI** — White/pastel theme, responsive dashboard

---

## 🚀 Quick Start

### 1. **Prepare VPS**
- Ubuntu 22.04, 24.04, or 26.04
- IPv4 + optional IPv6
- Domain with A record pointing to server IP
- Firewall allows ports: 22, 80, 109, 143, 443, 8080, 8880

### 2. **Run Installer**
```bash
curl -Ls https://example.com/xxtlonline-setup.sh | bash
# OR
bash xxtlonline-setup.sh
```

### 3. **Follow Prompts**
- Enter domain (e.g., `panel.example.com`)
- Set 3x-ui admin username/password
- Choose IPv4 or IPv6 (if available)
- Installer does rest automatically

### 4. **Access Dashboard**
```
https://panel.example.com
Username: (your 3x-ui admin user)
Password: (your 3x-ui admin password)
```

---

## 📊 Port Map

| Port | Service | Purpose |
|------|---------|---------|
| 22 | OpenSSH | Standard SSH (root login enabled) |
| 80 | WS-Stunnel | HTTP-CONNECT tunnel → Dropbear:143 |
| 109 | Dropbear SSH | Secondary SSH port |
| 143 | Dropbear SSH | Primary SSH port (ws-stunnel target) |
| 443 | Nginx | HTTPS dashboard & panel |
| 2503 | Nginx | 3x-ui panel reverse proxy (SSL) |
| 6789 | SSH API | Internal REST API (localhost only) |
| 7300 | BadVPN | UDP gateway (localhost only) |
| 8080 | 3x-ui | VLESS-WS inbound (WS path: /vless) |
| 8880 | 3x-ui | VLESS-WS inbound (WS path: /vless) |
| 54321 | 3x-ui | Internal panel port |

---

## 🎨 Dashboard Features

### Login Page
- Minimal white design with purple/teal accents
- Smooth glassmorphic elements
- Responsive mobile-first layout

### Dashboard
- **System Status** — Active connections, SSH user count
- **Service Monitor** — SSH, Dropbear, Nginx, BadVPN, WS-Stunnel, 3x-ui health
- **Create SSH Users** — Username, password, expiry (days)
- **User Management** — List, delete, extend expiry
- **3x-ui Link** — Quick access to VLESS/VMess panel

---

## 🔐 Security Features

- **Firewall** — UFW automatically configured (block API ports)
- **SSH Hardening** — Password auth enabled, root login allowed
- **File Limits** — 1M+ open files per process
- **TCP Tuning** — BBR + FQ qdisc for optimal throughput
- **SSL/TLS** — Auto-provisioned via Certbot (Let's Encrypt)

---

## 📝 SSH User Management

### Via Dashboard
1. Go to **"สร้างบัญชี SSH"** section
2. Enter username, password, duration (days)
3. Click **+ สร้างบัญชี**
4. User appears in list below

### Via API (curl)
```bash
# Create user (30 days)
curl -X POST http://localhost:6789/api/create_ssh \
  -H "Content-Type: application/json" \
  -d '{"user":"newuser","password":"pass123","days":30}'

# List users
curl http://localhost:6789/api/users

# Delete user
curl -X POST http://localhost:6789/api/delete_ssh \
  -H "Content-Type: application/json" \
  -d '{"user":"olduser"}'

# Extend expiry
curl -X POST http://localhost:6789/api/extend_ssh \
  -H "Content-Type: application/json" \
  -d '{"user":"username","days":60}'
```

### Via Command Line
```bash
# Create user (expiry: 30 days from today)
sudo useradd -M -s /bin/false newuser
echo "newuser:password123" | sudo chpasswd
sudo chage -E $(date -d "+30 days" +%Y-%m-%d) newuser
mkdir -p /etc/xxtlonline/exp
echo "2024-08-20" | sudo tee /etc/xxtlonline/exp/newuser

# List users with expiry
awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | while read u; do
  exp=$(cat /etc/xxtlonline/exp/$u 2>/dev/null); echo "$u | $exp"
done
```

---

## 🔗 Connection Methods

### SSH via Dropbear
```bash
ssh -p 143 username@panel.example.com
# or
ssh -p 109 username@panel.example.com
```

### WS-Tunnel (port 80)
Use reverse proxy tools (e.g., Termux, ProxyDroid) pointing to:
- **Host:** `panel.example.com`
- **Port:** `80`
- **Target:** `127.0.0.1:22` (or `143` for Dropbear)
- **Type:** HTTP-CONNECT

### 3x-ui VLESS
Access via dashboard → **3x-ui panel** → create inbound → get link

```
vless://uuid@panel.example.com:8080?type=ws&security=none&path=%2Fvless&host=...
```

---

## 🔧 Troubleshooting

### SSL Certificate Not Working
```bash
# Retry Certbot
sudo certbot certonly --standalone -d panel.example.com

# Check cert status
sudo certbot certificates

# Renew manually
sudo certbot renew --force-renewal
```

### Port Already in Use
```bash
# Find process using port (e.g., 80)
sudo lsof -i :80

# Kill it
sudo kill -9 <PID>

# Or restart service
sudo systemctl restart xxtlonline-sshws
```

### SSH API not responding
```bash
sudo systemctl restart xxtlonline-ssh-api
sudo journalctl -u xxtlonline-ssh-api -n 20
```

### 3x-ui not loading
```bash
sudo systemctl status x-ui
sudo journalctl -u x-ui -n 50
sqlite3 /etc/x-ui/x-ui.db "SELECT * FROM users LIMIT 1;"
```

### Dropbear not accepting connections
```bash
sudo systemctl restart dropbear
sudo ss -tlnp | grep :143
sudo journalctl -u dropbear -n 20
```

### Dashboard login fails
- Check credentials file:
  ```bash
  cat /etc/xxtlonline/xui-user.conf
  cat /etc/xxtlonline/xui-pass.conf
  ```
- Verify API endpoint: `curl http://localhost:6789/api/status`

---

## 📈 Performance Monitoring

### Check Active Connections
```bash
ss -tn state established | wc -l
```

### Monitor Service Health
```bash
sudo journalctl -u xxtlonline-ssh-api -f
sudo journalctl -u x-ui -f
sudo journalctl -u dropbear -f
```

### Network Tuning Status
```bash
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
tc qdisc show
ethtool -k eth0 | grep -E "gro|gso|tso"
```

### Speedtest (if installed)
```bash
speedtest-cli --json
```

---

## 🔄 Maintenance

### Update 3x-ui (manual, locked version)
```bash
# Current version is v2.9.4 (locked to prevent auto-update breaking changes)
# To manually update to newer version:
systemctl stop x-ui
sudo /usr/local/x-ui/x-ui -update
# But recommended to keep locked version for stability
```

### Backup Configuration
```bash
sudo tar -czf xxtlonline-backup.tar.gz \
  /etc/xxtlonline \
  /etc/x-ui/x-ui.db \
  /opt/xxtlonline-panel \
  /opt/xxtlonline-ssh-api
```

### Renew SSL Certificate (auto-renewal via cron)
```bash
sudo systemctl list-timers | grep certbot
# or manual
sudo certbot renew
```

---

## 📞 Support & Logs

### Log Locations
```
/var/log/xxtlonline-xui-install.log
/var/log/syslog  # General system logs
journalctl -u <service-name> -n 100  # Last 100 lines
```

### Check All Services Status
```bash
sudo systemctl status ssh dropbear nginx x-ui xxtlonline-sshws xxtlonline-ssh-api
```

### Full System Diagnostics
```bash
#!/bin/bash
echo "=== System Info ==="
uname -a
echo "=== Disk Space ==="
df -h
echo "=== Port Status ==="
sudo ss -tlnp | grep -E ":22|:80|:143|:443|:8080"
echo "=== Services ==="
sudo systemctl status ssh dropbear nginx x-ui
echo "=== Connections ==="
ss -tn state established | wc -l
```

---

## 🎯 Customization

### Change Brand Name (for forks)
Edit script before running:
```bash
BRAND="YOURBRAND"
BRAND_DIR="yourbrand"
```

### Change Color Theme
Edit `/opt/xxtlonline-panel/index.html` & `dashboard.html`:
```css
:root {
  --primary: #7c6cf6;        /* Purple */
  --primary-dark: #5b4fd6;   /* Dark Purple */
  --accent: #8fe3d0;         /* Teal */
  --bg: #f6f5fb;             /* Light background */
}
```

### Change SSH Ports
Edit `/etc/systemd/system/dropbear.service`:
```bash
ExecStart=/usr/sbin/dropbear -F -p 2222 -p 2223
```
Then restart: `sudo systemctl restart dropbear`

---

## ⚠️ Known Issues & Limitations

1. **IPv6** — Only tested on dual-stack VPS; enable at install prompt
2. **3x-ui UI** — Original 3x-ui panel not themed; use reverse proxy at `:2503`
3. **WS-Tunnel** — Uses Python (not compiled); requires Python 3.6+
4. **Certbot** — Requires outbound port 443 + domain DNS configured
5. **BadVPN** — UDP only; no TCP relay (for gaming VPN overlay)

---

## 📄 License & Attribution

- **3x-ui**: [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) (AGPL)
- **Dropbear**: [Matt Johnston](https://matt.ucc.asn.au/dropbear/) (MIT)
- **BadVPN**: [Ambrop72/badvpn](https://github.com/ambrop72/badvpn) (GPL)
- **XXTLONLINE Panel**: Original installation wrapper (minimal)

---

## 🚀 What's Next?

1. Create SSH users via dashboard
2. Test connections from mobile/desktop
3. Monitor usage via 3x-ui panel
4. Configure firewall rules as needed
5. Set up automated renewal (Certbot handles SSL auto-renewal)

---

**Version**: 1.0  
**Last Updated**: 2026-07-21  
**Author**: XXTLONLINE Installer Team
