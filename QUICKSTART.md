# XXTLONLINE — Quick Start Guide

**Get your VPN panel running in 5 minutes**

---

## 📋 Prerequisites

### Server Requirements
- **OS:** Ubuntu 22.04 / 24.04 / 26.04 LTS
- **RAM:** 1GB minimum (2GB+ recommended)
- **Disk:** 5GB minimum
- **Network:** Public IPv4, outbound port 443 allowed
- **Domain:** A record pointing to server IP

### Local Requirements
- SSH client (or browser)
- Domain with DNS access
- Certbot-compatible domain (for auto SSL)

---

## 🚀 Installation Steps

### **Step 1: Prepare Domain**

1. Buy or use existing domain (e.g., `example.com`)
2. Add A record: `panel.example.com → YOUR_SERVER_IP`
3. Wait 5-10 minutes for DNS to propagate
4. Test: `nslookup panel.example.com` (should show your IP)

### **Step 2: SSH Into Server**

```bash
ssh root@YOUR_SERVER_IP
# Or if you have domain:
ssh root@panel.example.com
```

### **Step 3: Download & Run Installer**

**Option A: One-liner (recommended)**
```bash
curl -Ls https://raw.githubusercontent.com/YOUR_REPO/xxtlonline-setup.sh | sudo bash
```

**Option B: Manual download**
```bash
wget https://raw.githubusercontent.com/YOUR_REPO/xxtlonline-setup.sh
sudo bash xxtlonline-setup.sh
```

**Option C: From local file**
```bash
# Copy xxtlonline-setup.sh to your server
scp xxtlonline-setup.sh root@panel.example.com:/tmp/
ssh root@panel.example.com "bash /tmp/xxtlonline-setup.sh"
```

### **Step 4: Answer Setup Prompts**

```
[INFO] Ubuntu version: 24.04
[INFO] IPv4: 123.45.67.89

════════════════════════════════════════
  ตั้งค่าโดเมน XXTLONLINE
════════════════════════════════════════
  DNS ต้องชี้ A record มาที่ IP: 123.45.67.89 ก่อน
  
  โดเมน (เช่น panel.example.com): panel.example.com
  3x-ui Username [admin]: admin
  3x-ui Password: ••••••••
  Confirm Password: ••••••••
  
  Use IPv6 instead of IPv4? [y/N]: n
  
เริ่มติดตั้ง XXTLONLINE? [y/N]: y
```

### **Step 5: Wait for Installation**

Installation typically takes **3-8 minutes** depending on internet speed.

```
[INFO] อัปเดต packages...
[OK] packages หลักเสร็จ
[INFO] ติดตั้ง Dropbear...
[OK] Dropbear พร้อม (port 143, 109)
[INFO] ติดตั้ง 3x-ui v2.9.4...
[OK] 3x-ui พร้อม (port 54321)
[INFO] ขอ SSL Certificate...
[OK] SSL Certificate พร้อม
[INFO] ติดตั้ง Nginx...
[OK] Nginx พร้อม
...
════════════════════════════════════════
  XXTLONLINE ติดตั้งเสร็จสมบูรณ์
════════════════════════════════════════
  Dashboard : https://panel.example.com
  3x-ui     : https://panel.example.com:2503
  SSH host  : panel.example.com (port 143 / 109, ws-tunnel port 80)
  Username  : admin
════════════════════════════════════════
```

---

## 🎯 First-Time Access

### **1. Open Dashboard**
```
https://panel.example.com
Username: admin
Password: (your password)
```

### **2. Dashboard UI**

![Screenshot](terminal)
```
┌─────────────────────────────────────┐
│   XXTLONLINE  [Logout]              │
│   panel.example.com                 │
├─────────────────────────────────────┤
│   Active Connections: 0             │
│   SSH Users: 0                      │
├─────────────────────────────────────┤
│   Services                          │
│   ✓ SSH        ✓ Nginx             │
│   ✓ Dropbear   ✓ 3x-ui             │
│   ✓ WS-Stunnel ✓ BadVPN            │
├─────────────────────────────────────┤
│   Create SSH Account                │
│   [Username ________________]        │
│   [Password ________________]        │
│   [Days ___] [+ Create Account]     │
├─────────────────────────────────────┤
│   SSH Users (0)                     │
│   (no users yet)                    │
├─────────────────────────────────────┤
│   [Open 3x-ui Control Panel]        │
└─────────────────────────────────────┘
```

---

## 👤 Create Your First SSH User

### **Via Dashboard (Easy)**
1. Fill in username, password, days (e.g., 30)
2. Click **+ Create Account**
3. User appears below in the list

### **Via Command Line (Advanced)**
```bash
# SSH into server
ssh root@panel.example.com

# Create user using utility script
sudo ./xxtlonline-utils.sh user-create

# Follow prompts:
Username: myuser
Password: ••••••••
Confirm Password: ••••••••
Days valid [30]: 30
[OK] User created: myuser (expires: 2025-08-20)
```

---

## 🔗 Connect as SSH Client

### **Desktop (Linux/Mac)**
```bash
# Port 143 (Dropbear - SSH)
ssh -p 143 myuser@panel.example.com

# Or port 109 (alternate)
ssh -p 109 myuser@panel.example.com
```

### **Android (Termux or ConnectBot)**
```
Host: panel.example.com
Port: 143
Username: myuser
Password: (your password)
```

### **iPhone (SSH Files app)**
1. Add host: `panel.example.com`
2. Port: `143`
3. Auth: Password
4. Username: `myuser`

### **Windows (PuTTY)**
1. Host: `panel.example.com`
2. Port: `143`
3. Connection → SSH → Auth → Username: `myuser`
4. (PuTTY will prompt for password)

### **Port 80 Tunnel (HTTP-CONNECT)**
For systems that only allow port 80:
- Proxy host: `panel.example.com`
- Proxy port: `80`
- Target: `127.0.0.1:22` or `localhost:143`
- Type: HTTP-CONNECT

---

## 🔧 Common Tasks

### **Check System Status**
```bash
sudo ./xxtlonline-utils.sh status

# Output:
# ✓ ssh: active
# ✓ dropbear: active
# ✓ nginx: active
# ...
```

### **List All SSH Users**
```bash
sudo ./xxtlonline-utils.sh user-list

# Output:
#   alice            2025-12-31
#   bob              2025-06-15
#   charlie          no expiry
```

### **Extend User Expiry**
```bash
sudo ./xxtlonline-utils.sh user-extend alice 60
# [OK] Extended user alice from 2025-08-20 to 2025-10-19
```

### **Delete User**
```bash
sudo ./xxtlonline-utils.sh user-delete olduser
# [OK] User deleted: olduser
```

### **Backup Configuration**
```bash
sudo ./xxtlonline-utils.sh backup
# [OK] Backup created: /root/xxtlonline-backup-20250821-143022.tar.gz (45.2M)
```

### **Restart Services**
```bash
# Restart all
sudo ./xxtlonline-utils.sh restart

# Restart specific service
sudo systemctl restart xxtlonline-ssh-api
sudo systemctl restart nginx
sudo systemctl restart x-ui
```

### **View Logs**
```bash
# SSH API logs
sudo journalctl -u xxtlonline-ssh-api -n 50

# Dropbear SSH logs
sudo journalctl -u dropbear -n 50

# 3x-ui logs
sudo journalctl -u x-ui -n 50

# Follow logs in real-time
sudo journalctl -u xxtlonline-ssh-api -f
```

---

## 🎨 Customize Dashboard

### **Change Theme**

**Dark Purple (default):**
```bash
sudo bash xxtlonline-patches.sh color-dark-purple
```

**Neon Pink + Cyan:**
```bash
sudo bash xxtlonline-patches.sh color-neon-pink
```

**Forest Green:**
```bash
sudo bash xxtlonline-patches.sh color-forest
```

**Ocean Blue:**
```bash
sudo bash xxtlonline-patches.sh color-ocean
```

### **Change Brand Name**
```bash
sudo bash xxtlonline-patches.sh logo-change "MY VPN PANEL"
```

Then reload dashboard in browser (Ctrl+F5).

---

## 🔒 Security Checklist

- [ ] Domain DNS configured
- [ ] SSL certificate issued (check: https://panel.example.com should show lock icon)
- [ ] Firewall rules applied (UFW active)
- [ ] SSH admin password changed
- [ ] Backup created
- [ ] SSH public key uploaded (optional but recommended)

---

## ⚠️ Troubleshooting

### **Can't reach dashboard**
```bash
# Check if HTTPS working
curl -I https://panel.example.com

# Check nginx status
sudo systemctl status nginx

# Restart nginx
sudo systemctl restart nginx
```

### **SSL certificate errors**
```bash
# Check cert status
sudo certbot certificates

# Renew manually
sudo certbot renew --force-renewal

# Restart nginx after renew
sudo systemctl restart nginx
```

### **SSH can't connect**
```bash
# Check Dropbear status
sudo systemctl status dropbear

# Test connection
ssh -vvv -p 143 myuser@panel.example.com

# Check port listening
sudo ss -tlnp | grep :143
```

### **3x-ui not loading**
```bash
# Check x-ui status
sudo systemctl status x-ui

# Restart x-ui
sudo systemctl restart x-ui

# View logs
sudo journalctl -u x-ui -n 30
```

### **Run diagnostics**
```bash
sudo ./xxtlonline-utils.sh diagnostics
```

---

## 📞 Getting Help

### **Support Resources**
1. **Full Documentation:** `README.md`
2. **API Reference:** `API.md`
3. **Utilities Reference:** `xxtlonline-utils.sh --help`
4. **Logs:** `journalctl -u <service-name> -n 50`

### **Common Issues**
- Port already in use → `sudo fuser -k 80/tcp`
- DNS not resolving → Wait 10 mins and retry
- Certbot timeout → Check outbound port 443 allowed
- High memory usage → Check `x-ui` process or reduce inbounds

---

## 🚀 Next Steps

1. ✅ **Install** — Done!
2. 📝 **Create users** — Add via dashboard or CLI
3. 🔗 **Test connections** — SSH from different clients
4. 📊 **Monitor usage** — Check dashboard regularly
5. 🔄 **Backup data** — `sudo ./xxtlonline-utils.sh backup`
6. 🎨 **Customize** — Change theme/branding
7. 📈 **Scale** — Add more users/inbounds as needed

---

## 📚 File Structure

After installation:
```
/etc/xxtlonline/                    — Config files
├── xui-user.conf                   — 3x-ui username
├── xui-pass.conf                   — 3x-ui password
├── domain.conf                      — Your domain
├── my_ip.conf                       — Server IP
└── exp/                             — User expiry dates

/opt/xxtlonline-panel/              — Dashboard UI
├── index.html                       — Login page
├── dashboard.html                   — Dashboard
└── config.js                        — Config

/opt/xxtlonline-ssh-api/            — SSH API
└── app.py                           — Python app

/etc/systemd/system/                — Services
├── xxtlonline-sshws.service        — WS-Stunnel
├── xxtlonline-ssh-api.service      — SSH API
└── xxtlonline-badvpn.service       — BadVPN
```

---

## 📝 Version Info

- **XXTLONLINE:** v1.0
- **3x-ui:** v2.9.4 (locked)
- **Dropbear:** Latest
- **Nginx:** Latest
- **Python:** 3.10+

---

**Happy tunneling! 🎉**

For updates and support, visit the repository or documentation.
