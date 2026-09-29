# XXTLONLINE VPN PANEL — Complete Installation Package

**Your complete, production-ready VPN SSH panel — now rebranded from Chaiya scripts**

---

## 📦 Package Contents

### **Core Installer**
- **`xxtlonline-setup.sh`** — Main all-in-one installation script
  - Installs: 3x-ui, Dropbear, BadVPN, Nginx, WS-Stunnel
  - Provisions: SSL certificates, dashboard UI, SSH API
  - Configures: Firewall, network tuning, system optimization
  - Runtime: ~5-10 minutes on 1GB VPS

### **Documentation** (Read First!)
1. **`QUICKSTART.md`** ← **START HERE** (5-minute setup guide)
2. **`README.md`** (Complete feature reference & troubleshooting)
3. **`API.md`** (REST API documentation for developers)
4. **`INSTALL_GUIDE.md`** (This file)

### **Management Tools**
- **`xxtlonline-utils.sh`** — Utilities for daily operations
  - Status checking, user management, backups, logs
  - Service restart, firewall configuration
  - Diagnostics and troubleshooting
  
- **`xxtlonline-patches.sh`** — UI customization & theming
  - Color themes (dark purple, neon pink, forest, ocean)
  - Logo/branding changes
  - Custom CSS support

---

## 🎯 Quick Navigation

| Goal | Start Here |
|------|-----------|
| Install XXTLONLINE in 5 min | `QUICKSTART.md` |
| Full feature reference | `README.md` |
| API integration guide | `API.md` |
| Manage after installation | Run `xxtlonline-utils.sh` |
| Change colors/branding | Run `xxtlonline-patches.sh` |
| Troubleshoot issues | `README.md` → Troubleshooting section |

---

## 📋 Prerequisites Checklist

Before running installer, ensure:

- [ ] **VPS with Ubuntu 22.04/24.04/26.04** (Debian 11/12 may work)
- [ ] **1GB RAM minimum** (2GB+ recommended)
- [ ] **5GB disk space**
- [ ] **Public IPv4 address** (IPv6 optional)
- [ ] **Root or sudo access**
- [ ] **Domain name** with DNS control
  - A record: `panel.yourdomain.com → SERVER_IP`
- [ ] **Outbound port 443 allowed** (for SSL certificate validation)

### Supported Providers
- ✅ DigitalOcean, Linode, AWS, Azure
- ✅ Vultr, Hetzner, OVH
- ✅ Alibaba Cloud, Tencent Cloud
- ✅ Most VPS providers with standard Linux

### Unsupported/Risky
- ❌ Shared hosting (no SSH root access)
- ❌ OpenVZ containers (no full network stack)
- ❌ Network-restricted (no port 443 outbound)

---

## 🚀 Installation Workflow

### **Step 1: Prepare Domain**
```bash
# 1. Buy domain or use existing
# 2. Add DNS A record:
#    Name: panel.yourdomain.com
#    Type: A
#    Value: YOUR_SERVER_IP
# 3. Wait 5-10 minutes for DNS propagation
# 4. Verify:
nslookup panel.yourdomain.com
# Should return: YOUR_SERVER_IP
```

### **Step 2: SSH Into Server**
```bash
ssh root@YOUR_SERVER_IP
# Or using domain (if DNS ready):
ssh root@panel.yourdomain.com
```

### **Step 3: Run Installer**

**Option A: Direct from GitHub (recommended)**
```bash
curl -Ls https://raw.githubusercontent.com/YOUR_REPO/main/xxtlonline-setup.sh | bash
```

**Option B: Download first, then run**
```bash
wget https://raw.githubusercontent.com/YOUR_REPO/main/xxtlonline-setup.sh
bash xxtlonline-setup.sh
```

**Option C: Copy from local machine**
```bash
# On your local machine:
scp xxtlonline-setup.sh root@panel.yourdomain.com:/tmp/

# Then SSH and run:
ssh root@panel.yourdomain.com
bash /tmp/xxtlonline-setup.sh
```

### **Step 4: Follow Prompts & Wait**
Installer will ask for:
- Domain name (e.g., `panel.yourdomain.com`)
- 3x-ui admin username (default: `admin`)
- 3x-ui admin password (create strong password)
- IPv4 or IPv6 preference

⏱️ Installation takes **3-10 minutes** depending on internet speed.

### **Step 5: Access Dashboard**
Once done, visit:
```
https://panel.yourdomain.com
Username: admin
Password: (what you entered)
```

---

## 📊 What Gets Installed

| Component | Purpose | Port | Status |
|-----------|---------|------|--------|
| **3x-ui v2.9.4** | VLESS/VMess proxy panel | 54321 | ✅ Locked version |
| **Dropbear SSH** | Lightweight SSH server | 143, 109 | ✅ Auto-started |
| **WS-Stunnel** | HTTP-CONNECT tunnel | 80 | ✅ Python-based |
| **BadVPN UDP** | UDP relay gateway | 7300 | ✅ Localhost only |
| **Nginx** | Reverse proxy + dashboard | 80, 443 | ✅ SSL auto |
| **OpenSSH** | Standard SSH | 22 | ✅ Pre-existing |
| **Dashboard UI** | Minimal white/pastel | 443 | ✅ Custom-built |
| **SSH API** | REST API for user mgmt | 6789 | ✅ Localhost only |

---

## 🔧 Post-Installation Tasks

### **1. Create First SSH User**

**Via Dashboard (Easy):**
1. Open `https://panel.yourdomain.com`
2. Go to "สร้างบัญชี SSH" section
3. Enter username, password, days (e.g., 30)
4. Click **+ สร้างบัญชี**

**Via Command Line:**
```bash
sudo bash xxtlonline-utils.sh user-create
```

### **2. Test SSH Connection**
```bash
ssh -p 143 your_username@panel.yourdomain.com
# Enter password when prompted
```

### **3. Create Backup**
```bash
sudo bash xxtlonline-utils.sh backup
# Creates: /root/xxtlonline-backup-TIMESTAMP.tar.gz
```

### **4. Verify All Services**
```bash
sudo bash xxtlonline-utils.sh status
# Should show all services as "active"
```

---

## 📂 File Deployment Guide

### **For Single VPS**
```bash
# Copy all files to VPS:
scp xxtlonline-*.sh README.md QUICKSTART.md API.md root@panel.yourdomain.com:~/

# SSH in and make executable:
ssh root@panel.yourdomain.com
chmod +x ~/*.sh

# Run installer:
bash ~/xxtlonline-setup.sh

# Keep utilities accessible:
sudo cp ~/xxtlonline-utils.sh /usr/local/bin/
sudo cp ~/xxtlonline-patches.sh /usr/local/bin/
```

### **For Multiple VPS (Template)**
```bash
# Create template directory
mkdir -p ~/xxtlonline-deploy/{docs,scripts}

# Copy files
cp xxtlonline-setup.sh ~/xxtlonline-deploy/scripts/
cp xxtlonline-utils.sh ~/xxtlonline-deploy/scripts/
cp xxtlonline-patches.sh ~/xxtlonline-deploy/scripts/
cp *.md ~/xxtlonline-deploy/docs/

# Create deployment script
cat > ~/xxtlonline-deploy/deploy.sh << 'EOF'
#!/bin/bash
VPS_IP=$1
scp -r ./scripts root@$VPS_IP:~/xxtlonline-scripts/
scp -r ./docs root@$VPS_IP:~/xxtlonline-docs/
ssh root@$VPS_IP "bash ~/xxtlonline-scripts/xxtlonline-setup.sh"
EOF
chmod +x ~/xxtlonline-deploy/deploy.sh

# Deploy to multiple VPS:
./deploy.sh 123.45.67.89
./deploy.sh 456.78.90.12
./deploy.sh 789.01.23.45
```

### **For GitHub Repository**
```bash
# Create repo
git init xxtlonline-public
cd xxtlonline-public
git add xxtlonline-setup.sh xxtlonline-utils.sh xxtlonline-patches.sh
git add README.md QUICKSTART.md API.md INSTALL_GUIDE.md
git commit -m "Initial XXTLONLINE release v1.0"
git remote add origin git@github.com:yourname/xxtlonline.git
git push -u origin main

# Then users can install via:
curl -Ls https://raw.githubusercontent.com/yourname/xxtlonline/main/xxtlonline-setup.sh | bash
```

---

## 🎯 Common Workflows

### **Workflow 1: Single VPS Setup**
```bash
# 1. Prepare
# - Buy domain, add A record
# - Rent VPS, get IP

# 2. Install
ssh root@domain.com
curl -Ls https://...xxtlonline-setup.sh | bash

# 3. Configure
# - Create users via dashboard
# - Test SSH connections
# - Backup config

# 4. Maintain
# Run utils weekly:
sudo xxtlonline-utils.sh status
sudo xxtlonline-utils.sh logs x-ui  # Check for issues
```

### **Workflow 2: Backup & Restore**
```bash
# Backup on Monday
sudo xxtlonline-utils.sh backup

# Restore if needed
sudo xxtlonline-utils.sh restore /root/xxtlonline-backup-20250721.tar.gz
```

### **Workflow 3: Theme Customization**
```bash
# Change theme
sudo xxtlonline-patches.sh color-neon-pink

# Change branding
sudo xxtlonline-patches.sh logo-change "COMPANY VPN"

# Reload dashboard (Ctrl+F5 in browser)
```

### **Workflow 4: User Lifecycle**
```bash
# Create user for 30 days
sudo xxtlonline-utils.sh user-create

# List users
sudo xxtlonline-utils.sh user-list

# Extend 30 more days
sudo xxtlonline-utils.sh user-extend alice 30

# Delete expired user
sudo xxtlonline-utils.sh user-delete bob
```

---

## 🔐 Security Hardening (Post-Install)

### **1. Change Root Password**
```bash
passwd root
# Enter strong password (20+ chars, mixed case, numbers, symbols)
```

### **2. Setup SSH Keys (Optional but recommended)**
```bash
# On your local machine:
ssh-keygen -t ed25519 -f ~/.ssh/xxtlonline_key

# Copy to server:
ssh-copy-id -i ~/.ssh/xxtlonline_key root@panel.yourdomain.com

# Test and disable password auth (optional):
# Edit /etc/ssh/sshd_config
# PasswordAuthentication no
# systemctl restart ssh
```

### **3. Review Firewall Rules**
```bash
sudo ufw status
# Should show only required ports open (22, 80, 109, 143, 443, etc)
```

### **4. Rotate Admin Password Quarterly**
```bash
# Update 3x-ui password in dashboard
# Update SSH API credentials
```

### **5. Monitor Logs Regularly**
```bash
# Weekly review
sudo journalctl -u xxtlonline-ssh-api --since "7 days ago" | grep -i error
sudo journalctl -u x-ui --since "7 days ago" | grep -i error
```

---

## 📈 Performance Tuning (Optional)

### **Check Current Performance**
```bash
sudo xxtlonline-utils.sh speedtest

# Output:
# {
#   "ping": 12.5,
#   "download": 450.75,
#   "upload": 89.2,
#   "server": "Bangkok, Thailand"
# }
```

### **Optimize for High Traffic**
```bash
# Already applied by default installer, but can manually tune:

# Increase max connections
sudo sysctl -w net.core.somaxconn=8192

# Increase TCP buffer
sudo sysctl -w net.ipv4.tcp_rmem="4096 4194304 67108864"

# Verify BBR enabled
sudo sysctl net.ipv4.tcp_congestion_control
# Should output: bbr
```

---

## 🆘 Troubleshooting Matrix

| Problem | Quick Fix | Full Guide |
|---------|-----------|-----------|
| Can't reach dashboard | Check DNS, wait 10min | README.md → SSL Certificate section |
| SSH won't connect | Check firewall, test port 143 | README.md → Dropbear section |
| 3x-ui not loading | Restart service: `sudo systemctl restart x-ui` | README.md → 3x-ui section |
| Services failing | Run diagnostics | `sudo xxtlonline-utils.sh diagnostics` |
| High CPU usage | Check processes | `top`, then `journalctl -u <service>` |
| Disk space low | Check log size | `du -sh /var/log/` |

---

## 📞 Support & Documentation

### **Resources in This Package**
- `QUICKSTART.md` — 5-minute setup (read first!)
- `README.md` — Full features, troubleshooting, API overview
- `API.md` — REST API endpoints and examples
- `xxtlonline-utils.sh --help` — Command reference

### **Finding Answers**
1. **Simple question?** → Check `QUICKSTART.md`
2. **Feature question?** → Check `README.md` table of contents
3. **API question?** → Check `API.md`
4. **Broken service?** → Run `sudo xxtlonline-utils.sh status`
5. **Need logs?** → Run `sudo xxtlonline-utils.sh logs <service-name>`

### **Getting Help**
```bash
# Run diagnostics (generates complete system report)
sudo xxtlonline-utils.sh diagnostics

# Copy output and include in support request
```

---

## 🔄 Updating & Maintenance

### **Weekly**
```bash
# Check service health
sudo xxtlonline-utils.sh status

# Review logs
sudo journalctl -u xxtlonline-ssh-api -n 50
```

### **Monthly**
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Verify SSL cert (auto-renews, but worth checking)
sudo certbot certificates

# Create backup
sudo xxtlonline-utils.sh backup
```

### **Quarterly**
```bash
# Change admin password
# (Update via 3x-ui web panel)

# Review firewall rules
sudo ufw status

# Clean temporary files
sudo xxtlonline-utils.sh clean
```

---

## 📜 File Manifest

```
xxtlonline-setup.sh         ~2500 lines   Main installer (all-in-one)
xxtlonline-utils.sh         ~600 lines    Management utilities
xxtlonline-patches.sh       ~350 lines    UI customization
README.md                   ~1000 lines   Complete reference
QUICKSTART.md               ~500 lines    5-min setup guide
API.md                      ~600 lines    API documentation
INSTALL_GUIDE.md            ~600 lines    This file
```

**Total package size:** ~50-100 MB (after installation)

---

## ✅ Installation Verification Checklist

After installation, verify all components:

```bash
sudo bash xxtlonline-utils.sh status

# Expected output:
# ✓ ssh: active
# ✓ dropbear: active
# ✓ nginx: active
# ✓ x-ui: active
# ✓ xxtlonline-sshws: active
# ✓ xxtlonline-ssh-api: active
# ✓ xxtlonline-badvpn: active
# ✓ xxtlonline-rps-tune: active
```

If any show as failed, check logs:
```bash
sudo journalctl -u <service-name> -n 50
```

---

## 🎉 Congratulations!

Your XXTLONLINE VPN panel is now **live and ready to use**!

### Next Steps:
1. ✅ Create users via dashboard
2. 📱 Test from mobile/desktop
3. 💾 Create regular backups
4. 🎨 Customize branding/theme (optional)
5. 📊 Monitor dashboard stats

---

## 📝 License & Credits

**XXTLONLINE** — Production VPN panel installer
- Based on Chaiya VPN scripts (rebranded)
- 3x-ui: [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui)
- Dropbear: [Matt Johnston](https://matt.ucc.asn.au/dropbear/)
- BadVPN: [ambrop72/badvpn](https://github.com/ambrop72/badvpn)

---

**Version:** 1.0  
**Last Updated:** 2026-07-21  
**Status:** Production Ready ✅
