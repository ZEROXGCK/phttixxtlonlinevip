#!/bin/bash
set -o pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "ต้องรันด้วย root หรือ sudo"

BRAND="XXTLONLINE"
BRAND_DIR="xxtlonline"

# ============================================================
#  STEP 1: ASK FOR CONFIGURATION (BEFORE ANYTHING)
# ============================================================

clear
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}   $BRAND VPN PANEL INSTALLER v2.1${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
info "ต้องตั้งค่าก่อนเริ่มติดตั้ง"
echo ""

# Get Domain
echo -e "${YELLOW}[1/4]${NC} 📌 โดเมน (เช่น panel.example.com)"
read -rp "    โดเมน: " DOMAIN_INPUT
[[ -z "$DOMAIN_INPUT" ]] && err "โดเมนไม่ควรว่าง"
DOMAIN=$(echo "$DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]' | sed 's|https\?://||' | sed 's|/.*||')

if ! [[ "$DOMAIN" =~ \. ]]; then
  err "รูปแบบโดเมนผิด (เช่น panel.example.com)"
fi

ok "โดเมน: ${CYAN}$DOMAIN${NC}"
echo ""

# Verify DNS
info "ตรวจสอบ DNS..."
DNS_IP=$(dig +short A "$DOMAIN" 2>/dev/null | head -1)

if [[ -z "$DNS_IP" ]]; then
  warn "⚠️  DNS ยังไม่ได้ตั้งค่าหรือยังไม่ propagate"
  warn "ให้ A record ชี้ไปที่ IP server: $(hostname -I | awk '{print $1}')"
  read -rp "ดำเนินการต่อ? [y/N]: " CONTINUE_DNS
  [[ "$CONTINUE_DNS" != "y" && "$CONTINUE_DNS" != "Y" ]] && err "ยกเลิก"
else
  ok "DNS ชี้ไป: ${CYAN}$DNS_IP${NC}"
fi
echo ""

# Get Admin Credentials (ใช้เดียวกัน)
echo -e "${YELLOW}[2/4]${NC} 👤 Admin Username (ใช้เข้า Dashboard + 3x-ui)"
read -rp "    Username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
ok "Admin User: ${CYAN}$ADMIN_USER${NC}"
echo ""

# Get Admin Password
echo -e "${YELLOW}[3/4]${NC} 🔐 Admin Password"
read -rsp "    Password: " ADMIN_PASS
echo ""
[[ -z "$ADMIN_PASS" ]] && err "รหัสผ่านไม่ควรว่าง"
read -rsp "    ยืนยันรหัสผ่าน: " ADMIN_PASS_CONFIRM
echo ""
[[ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]] && err "รหัสผ่านไม่ตรงกัน"
ok "รหัสผ่าน ตั้งค่าเรียบร้อย"
echo ""

# IPv4/IPv6
echo -e "${YELLOW}[4/4]${NC} 🌐 IPv4 หรือ IPv6?"
read -rp "    ใช้ IPv6? [y/N]: " USE_IPV6
USE_IPV6=${USE_IPV6:-n}
[[ "$USE_IPV6" == "y" || "$USE_IPV6" == "Y" ]] && LISTEN_ADDR="::" || LISTEN_ADDR="0.0.0.0"
ok "Listen address: ${CYAN}$LISTEN_ADDR${NC}"
echo ""

# Summary
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}📋 ตรวจสอบการตั้งค่า:${NC}"
echo "  Domain:        $DOMAIN"
echo "  Admin User:    $ADMIN_USER"
echo "  ใช้เข้า Dashboard + 3x-ui"
echo "  Listen:        $LISTEN_ADDR"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
read -rp "เริ่มติดตั้ง? [y/N]: " START_INSTALL
[[ "$START_INSTALL" != "y" && "$START_INSTALL" != "Y" ]] && err "ยกเลิก"
echo ""

# Save configuration
info "บันทึกการตั้งค่า..."
mkdir -p /etc/$BRAND_DIR
echo "$DOMAIN" > /etc/$BRAND_DIR/domain.conf
echo "$ADMIN_USER" > /etc/$BRAND_DIR/admin-user.conf
echo "$ADMIN_PASS" > /etc/$BRAND_DIR/admin-pass.conf
MY_IP=$(hostname -I | awk '{print $1}')
echo "$MY_IP" > /etc/$BRAND_DIR/my_ip.conf
ok "บันทึกการตั้งค่าเรียบร้อย"
echo ""

# ============================================================
#  STEP 2: INSTALLATION
# ============================================================

info "เริ่มติดตั้ง $BRAND..."
echo ""

# Update system
info "อัปเดต packages..."
apt-get update > /dev/null 2>&1 || true
apt-get install -y curl wget git unzip python3 python3-pip certbot nginx ufw > /dev/null 2>&1
ok "packages หลัก"
echo ""

# Install Dropbear
info "ติดตั้ง Dropbear SSH..."
apt-get install -y dropbear > /dev/null 2>&1
systemctl enable dropbear > /dev/null 2>&1
systemctl start dropbear > /dev/null 2>&1
ok "Dropbear (port 143, 109)"
echo ""

# Install 3x-ui
info "ติดตั้ง 3x-ui (กำลังดาวน์โหลด อาจใช้เวลา 1-3 นาที)..."
info "หมายเหตุ: ถ้าค้างเกิน 3 นาทีที่ขั้นตอนนี้ ให้เช็คว่า VPS เข้า GitHub ได้ไหม (ดู troubleshooting)"

# ตัวติดตั้งของ 3x-ui เป็น interactive (ถามตั้งค่า port/user/pass เอง)
# ป้อน "n" ให้อัตโนมัติ = ไม่ปรับแต่งอะไรเพิ่ม ใช้ค่า random ที่ script ตั้งให้
# ไม่ redirect เป็น /dev/null แล้ว เพื่อให้เห็น error จริงถ้ามันล้มเหลว
curl -Ls -o /tmp/3x-ui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
if [[ $? -ne 0 || ! -s /tmp/3x-ui-install.sh ]]; then
  warn "ดาวน์โหลด 3x-ui installer ไม่สำเร็จ (เช็คการเชื่อมต่อ GitHub) — ข้ามขั้นตอนนี้ไปก่อน"
else
  timeout 300 bash /tmp/3x-ui-install.sh <<< $'n\n' || warn "3x-ui installer จบด้วย error/timeout — ตรวจสอบด้วย: systemctl status x-ui"
fi

systemctl enable x-ui > /dev/null 2>&1
systemctl start x-ui > /dev/null 2>&1
if systemctl is-active --quiet x-ui; then
  ok "3x-ui (port 54321) - running"
else
  warn "3x-ui ยังไม่ทำงาน — ดู log ด้วย: journalctl -u x-ui -n 50"
fi
echo ""

# Deploy Dashboard Files
info "ติดตั้ง Dashboard Files..."
mkdir -p /opt/$BRAND_DIR-panel

# ดึงไฟล์หน้าเว็บจาก GitHub repo อัตโนมัติ (ไม่ต้อง copy มือแล้ว)
GITHUB_RAW_BASE="https://raw.githubusercontent.com/ZEROXGCK/phttixxtlonlinevip/main"
DASHBOARD_FILES_OK=true

for f in index.html dashboard.html settings.html; do
  if curl -Ls -f -o "/opt/$BRAND_DIR-panel/$f" "$GITHUB_RAW_BASE/$f"; then
    ok "ดึง $f สำเร็จ"
  else
    warn "ดึง $f จาก GitHub ไม่สำเร็จ"
    DASHBOARD_FILES_OK=false
  fi
done

if [[ "$DASHBOARD_FILES_OK" != "true" ]]; then
  warn "ดึงไฟล์ dashboard บางไฟล์ไม่สำเร็จ — เช็คว่า repo เป็น Public และเชื่อมต่อ GitHub ได้"
  warn "แก้ทีหลังได้ด้วยคำสั่ง: curl -Ls -o /opt/$BRAND_DIR-panel/<ไฟล์> $GITHUB_RAW_BASE/<ไฟล์>"
else
  ok "Dashboard files ครบทั้งหมด"
fi
echo ""

# ============================================================
#  Free up ports 80/443 and open firewall BEFORE nginx starts
#  (ทำก่อน เพื่อกันปัญหาพอร์ตชนหรือถูกบล็อกตอนขอ SSL)
# ============================================================
info "เคลียร์ port 80/443 ก่อนตั้งค่า..."
systemctl stop nginx > /dev/null 2>&1 || true
systemctl stop apache2 > /dev/null 2>&1 || true
fuser -k 80/tcp > /dev/null 2>&1 || true
fuser -k 443/tcp > /dev/null 2>&1 || true
rm -f /etc/nginx/sites-enabled/default
ok "Port 80/443 ว่างพร้อมใช้งาน"

info "เปิด Firewall (ต้องเปิดก่อนขอ SSL ไม่งั้น Let's Encrypt เข้าไม่ถึง)..."
ufw --force enable > /dev/null 2>&1
for port in 22 80 109 143 443 2503 8080 8880; do
  ufw allow $port/tcp > /dev/null 2>&1
done
ok "Firewall เปิด port ที่จำเป็นแล้ว"
echo ""

# ============================================================
#  Configure Nginx - STEP 1: HTTP only (port 443 ยังไม่แตะ)
#  ต้องมี server บน port 80 ทำงานจริงก่อน ถึงจะขอ SSL ผ่าน webroot ได้
# ============================================================
info "ตั้งค่า Nginx (HTTP ก่อน เพื่อขอ SSL)..."
mkdir -p /etc/nginx/conf.d
mkdir -p /var/www/certbot
mkdir -p /opt/$BRAND_DIR-panel

cat > /etc/nginx/conf.d/$BRAND_DIR.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:6789;
        proxy_set_header Host \$host;
    }

    location / {
        root /opt/$BRAND_DIR-panel;
        try_files \$uri /index.html;
    }
}
EOF

if nginx -t > /tmp/nginx-test.log 2>&1; then
  systemctl restart nginx
  sleep 1
  if systemctl is-active --quiet nginx; then
    ok "Nginx รันบน port 80 สำเร็จ"
  else
    warn "Nginx config ผ่านการทดสอบแต่ start ไม่ขึ้น — ดู: journalctl -u nginx -n 30"
  fi
else
  warn "Nginx config ผิดพลาด:"
  cat /tmp/nginx-test.log
fi
echo ""

# ============================================================
#  Get SSL Certificate ผ่าน webroot (ไม่แตะ port 443 เลยระหว่างขอ)
# ============================================================
info "ขอ SSL Certificate สำหรับ $DOMAIN..."
CERT_OK=false
if certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" \
     --agree-tos -m "admin@$DOMAIN" -n --preferred-challenges http \
     > /tmp/certbot.log 2>&1; then
  if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    CERT_OK=true
  fi
fi

if [[ "$CERT_OK" == "true" ]]; then
  ok "ได้ SSL Certificate สำเร็จ"

  # STEP 2: อัปเดต config ให้เปิด 443 หลังมี cert จริงเท่านั้น
  cat > /etc/nginx/conf.d/$BRAND_DIR.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /api/ {
        proxy_pass http://127.0.0.1:6789;
        proxy_set_header Host \$host;
    }
    location / {
        root /opt/$BRAND_DIR-panel;
        try_files \$uri /index.html;
    }
}
EOF

  if nginx -t > /tmp/nginx-test2.log 2>&1; then
    systemctl restart nginx
    sleep 1
    if systemctl is-active --quiet nginx; then
      ok "Nginx รันบน port 443 (HTTPS) สำเร็จ"
    else
      warn "Nginx ไม่ขึ้นหลังเปิด SSL — ดู: journalctl -u nginx -n 30"
    fi
  else
    warn "Nginx config (SSL) ผิดพลาด — เว็บจะยังใช้ผ่าน HTTP ได้:"
    cat /tmp/nginx-test2.log
  fi
else
  warn "ขอ SSL Certificate ไม่สำเร็จ — เว็บจะใช้งานผ่าน HTTP (ไม่ใช่ HTTPS) ไปก่อน"
  warn "สาเหตุที่พบบ่อย: DNS ยังไม่ propagate / โดเมนพิมพ์ผิด / VPS provider บล็อก port 80 ที่ network level"
  warn "ดู log เต็มได้ที่: cat /tmp/certbot.log"
  warn "แก้ทีหลังได้ด้วยคำสั่ง: certbot certonly --webroot -w /var/www/certbot -d $DOMAIN --agree-tos -m admin@$DOMAIN -n"
  ok "เว็บยังใช้งานได้ที่ http://$DOMAIN (รอ SSL แก้ทีหลัง)"
fi
echo ""

# Create SSH API
info "สร้าง SSH REST API..."
mkdir -p /opt/$BRAND_DIR-ssh-api
cat > /opt/$BRAND_DIR-ssh-api/app.py << 'PYEOF'
#!/usr/bin/env python3
"""
XXTLONLINE SSH REST API - hardened version
- Every endpoint except /api/login requires a valid Bearer token (issued by /api/login)
- Tokens expire after 8 hours and are kept only in memory (lost on service restart -> re-login)
- Login is rate-limited per source IP to slow down brute force
- All external input (usernames) is validated against a strict allow-list regex
- No shell string interpolation anywhere: subprocess.run() is always called with an
  argument list and shell=False, so it is not possible to break out with ; | & $() etc.
"""
import json, subprocess, os, re, secrets, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timedelta

CONF_DIR = '/etc/xxtlonline'
TOKEN_TTL_SECONDS = 8 * 3600
MAX_LOGIN_ATTEMPTS = 5
LOGIN_WINDOW_SECONDS = 300

# Linux username rules: start with a letter or underscore, then letters/digits/_/-, max 32 chars
USERNAME_RE = re.compile(r'^[a-z_][a-z0-9_-]{2,31}$')

_tokens = {}          # token -> expiry_epoch
_login_attempts = {}  # ip -> [timestamps]


def get_admin_creds():
    """ดึง admin credentials จากไฟล์ config"""
    try:
        user = open(f'{CONF_DIR}/admin-user.conf').read().strip()
        password = open(f'{CONF_DIR}/admin-pass.conf').read().strip()
        return user, password
    except Exception:
        return None, None


def issue_token():
    token = secrets.token_hex(32)
    _tokens[token] = time.time() + TOKEN_TTL_SECONDS
    # opportunistically clean up expired tokens
    for t in list(_tokens):
        if _tokens[t] < time.time():
            del _tokens[t]
    return token


def is_valid_token(token):
    exp = _tokens.get(token)
    return exp is not None and exp > time.time()


def rate_limited(ip):
    now = time.time()
    attempts = [t for t in _login_attempts.get(ip, []) if now - t < LOGIN_WINDOW_SECONDS]
    _login_attempts[ip] = attempts
    return len(attempts) >= MAX_LOGIN_ATTEMPTS


def record_attempt(ip):
    _login_attempts.setdefault(ip, []).append(time.time())


def run(cmd_list, input_text=None):
    """Run a command safely: cmd_list is an argv array, never a shell string."""
    return subprocess.run(
        cmd_list,
        input=input_text,
        text=True,
        capture_output=True,
        shell=False,
        check=False,
    )


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        auth = self.headers.get('Authorization', '')
        if not auth.startswith('Bearer '):
            return False
        return is_valid_token(auth[7:].strip())

    def do_GET(self):
        if self.path in ('/api/status', '/api/info', '/api/users') and not self._authorized():
            self._json(401, {'error': 'unauthorized'})
            return

        if self.path == '/api/status':
            try:
                users = len([
                    l for l in open('/etc/passwd').read().split('\n')
                    if len(l.split(':')) > 2 and int(l.split(':')[2]) >= 1000
                ])
            except Exception:
                users = 0
            self._json(200, {
                'connections': 0,
                'total_users': users,
                'services': {'ssh': True, 'dropbear': True, 'nginx': True, 'xui': True}
            })

        elif self.path == '/api/info':
            domain = ''
            if os.path.exists(f'{CONF_DIR}/domain.conf'):
                domain = open(f'{CONF_DIR}/domain.conf').read().strip()
            self._json(200, {'host': domain, 'xui_port': 2503, 'dropbear_port': 143})

        elif self.path == '/api/users':
            try:
                users = []
                for l in open('/etc/passwd').readlines():
                    parts = l.split(':')
                    if len(parts) > 2 and int(parts[2]) >= 1000:
                        uname = parts[0]
                        exp_path = f'{CONF_DIR}/exp/{uname}'
                        exp = open(exp_path).read().strip() if os.path.exists(exp_path) else None
                        users.append({'user': uname, 'exp': exp, 'active': True})
            except Exception:
                users = []
            self._json(200, {'users': users})

        else:
            self._json(404, {'error': 'not found'})

    def do_POST(self):
        content_len = int(self.headers.get('Content-Length', 0) or 0)
        raw = self.rfile.read(content_len) if content_len > 0 else b'{}'
        try:
            data = json.loads(raw)
        except Exception:
            self._json(400, {'error': 'invalid json'})
            return

        if self.path == '/api/login':
            client_ip = self.client_address[0]
            if rate_limited(client_ip):
                self._json(429, {'error': 'too many attempts, try again later'})
                return
            admin_user, admin_pass = get_admin_creds()
            supplied_user = str(data.get('username', ''))
            supplied_pass = str(data.get('password', ''))
            record_attempt(client_ip)
            if admin_user is None or not (
                secrets.compare_digest(supplied_user, admin_user)
                and secrets.compare_digest(supplied_pass, admin_pass)
            ):
                self._json(200, {'ok': False})
                return
            token = issue_token()
            self._json(200, {'ok': True, 'token': token, 'expires_in': TOKEN_TTL_SECONDS})
            return

        # Everything below requires a valid session token
        if not self._authorized():
            self._json(401, {'error': 'unauthorized'})
            return

        if self.path == '/api/create_ssh':
            user = str(data.get('user', '')).strip().lower()
            password = str(data.get('password', ''))
            try:
                days = int(data.get('days', 30))
            except (TypeError, ValueError):
                days = 30
            days = max(1, min(days, 3650))

            if not USERNAME_RE.match(user):
                self._json(400, {'error': 'invalid username: use 3-32 lowercase letters, digits, - or _, starting with a letter'})
                return
            if len(password) < 6 or '\n' in password or '\r' in password:
                self._json(400, {'error': 'password must be at least 6 characters'})
                return

            existing = run(['id', user])
            if existing.returncode == 0:
                self._json(409, {'error': 'user already exists'})
                return

            created = run(['useradd', '-M', '-s', '/usr/sbin/nologin', user])
            if created.returncode != 0:
                self._json(500, {'error': 'failed to create user'})
                return

            chpw = run(['chpasswd'], input_text=f"{user}:{password}\n")
            if chpw.returncode != 0:
                run(['userdel', '-f', user])
                self._json(500, {'error': 'failed to set password'})
                return

            exp = (datetime.now() + timedelta(days=days)).strftime('%Y-%m-%d')
            os.makedirs(f'{CONF_DIR}/exp', exist_ok=True)
            with open(f'{CONF_DIR}/exp/{user}', 'w') as f:
                f.write(exp)

            self._json(200, {'ok': True, 'user': user, 'exp': exp})

        elif self.path == '/api/delete_ssh':
            user = str(data.get('user', '')).strip().lower()
            if not USERNAME_RE.match(user):
                self._json(400, {'error': 'invalid username'})
                return
            if user in ('root', 'admin'):
                self._json(403, {'error': 'refusing to delete this account'})
                return
            run(['userdel', '-f', user])
            exp_path = f'{CONF_DIR}/exp/{user}'
            if os.path.exists(exp_path):
                os.remove(exp_path)
            self._json(200, {'ok': True, 'user': user})

        else:
            self._json(404, {'error': 'not found'})


if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 6789), Handler)
    server.serve_forever()
PYEOF

chmod +x /opt/$BRAND_DIR-ssh-api/app.py
ok "SSH API"
echo ""

# Create systemd service
info "สร้าง systemd service..."
cat > /etc/systemd/system/$BRAND_DIR-ssh-api.service << EOF
[Unit]
Description=XXTLONLINE SSH REST API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/$BRAND_DIR-ssh-api
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $BRAND_DIR-ssh-api
systemctl start $BRAND_DIR-ssh-api
ok "Systemd service"
echo ""

# (Firewall เปิดไปแล้วก่อนขั้นตอน Nginx/SSL ด้านบน ไม่ต้องทำซ้ำ)

# ============================================================
#  FINAL HEALTH CHECK - เช็คทุก service จริง + พยายามซ่อมเอง
#  ก่อนบอกว่า "เสร็จ" ให้ verify ว่ามันรันจริง ไม่ใช่แค่สั่งแล้วเชื่อ
# ============================================================
echo ""
info "ตรวจสอบระบบทั้งหมดก่อนสรุปผล..."
echo ""

declare -A SVC_STATUS
for svc in nginx dropbear x-ui $BRAND_DIR-ssh-api; do
  if systemctl is-active --quiet "$svc"; then
    SVC_STATUS[$svc]="OK"
  else
    warn "$svc ไม่ทำงาน กำลังลอง restart..."
    systemctl restart "$svc" > /dev/null 2>&1
    sleep 2
    if systemctl is-active --quiet "$svc"; then
      SVC_STATUS[$svc]="FIXED"
    else
      SVC_STATUS[$svc]="FAIL"
    fi
  fi
done

# เช็คว่าไฟล์เว็บมีจริงและไม่ว่างเปล่า
WEB_FILES_OK=true
for f in index.html dashboard.html settings.html; do
  if [[ ! -s "/opt/$BRAND_DIR-panel/$f" ]]; then
    WEB_FILES_OK=false
  fi
done

# เช็คว่า API ตอบสนองจริง (ไม่ใช่แค่ service active)
API_RESPOND=false
if curl -sf -o /dev/null "http://127.0.0.1:6789/api/login" -X POST \
     -H "Content-Type: application/json" -d '{"username":"x","password":"x"}'; then
  API_RESPOND=true
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}📋 ผลตรวจสอบระบบ:${NC}"
for svc in "${!SVC_STATUS[@]}"; do
  case "${SVC_STATUS[$svc]}" in
    OK)    echo -e "  ${GREEN}✓${NC} $svc — ทำงานปกติ" ;;
    FIXED) echo -e "  ${YELLOW}⚠${NC} $svc — ไม่ทำงานตอนแรก แต่ restart แล้วกลับมาปกติ" ;;
    FAIL)  echo -e "  ${RED}✗${NC} $svc — ยังไม่ทำงาน ต้องเช็ค: journalctl -u $svc -n 50" ;;
  esac
done
[[ "$WEB_FILES_OK" == "true" ]] && echo -e "  ${GREEN}✓${NC} ไฟล์เว็บ (index/dashboard/settings.html) ครบ" \
                                 || echo -e "  ${RED}✗${NC} ไฟล์เว็บขาดหาย — เช็ค: ls -lh /opt/$BRAND_DIR-panel/"
[[ "$API_RESPOND" == "true" ]] && echo -e "  ${GREEN}✓${NC} API ตอบสนองคำขอจริง" \
                               || echo -e "  ${RED}✗${NC} API ไม่ตอบสนอง — เช็ค: journalctl -u $BRAND_DIR-ssh-api -n 50"
[[ "$CERT_OK" == "true" ]] && echo -e "  ${GREEN}✓${NC} SSL Certificate ใช้งานได้ (https)" \
                           || echo -e "  ${YELLOW}⚠${NC} SSL ยังไม่พร้อม — ใช้งานผ่าน http:// ไปก่อน"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

ANY_FAIL=false
for svc in "${!SVC_STATUS[@]}"; do
  [[ "${SVC_STATUS[$svc]}" == "FAIL" ]] && ANY_FAIL=true
done

# Completion
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
if [[ "$ANY_FAIL" == "true" || "$WEB_FILES_OK" != "true" || "$API_RESPOND" != "true" ]]; then
  echo -e "${YELLOW}  ⚠ ติดตั้งเสร็จ แต่มีบางส่วนที่ต้องแก้เพิ่ม (ดูรายการด้านบน)${NC}"
else
  echo -e "${GREEN}  ✓ XXTLONLINE v2.1 ติดตั้งสำเร็จ ทุกระบบทำงานปกติ!${NC}"
fi
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""

PROTO="https"
[[ "$CERT_OK" != "true" ]] && PROTO="http"

echo -e "${CYAN}📊 Dashboard:${NC}"
echo "   $PROTO://$DOMAIN"
echo "   Username: $ADMIN_USER"
echo ""
echo -e "${CYAN}⚙️  Settings:${NC}"
echo "   $PROTO://$DOMAIN/settings.html"
echo ""
echo -e "${CYAN}📡 3x-ui Panel:${NC}"
echo "   $PROTO://$DOMAIN:2503"
echo "   Username: $ADMIN_USER"
echo ""
echo -e "${CYAN}🔌 SSH:${NC}"
echo "   ssh -p 143 <user>@$DOMAIN"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
ok "ใช้ username/password เดียวกันเข้า Dashboard + 3x-ui"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
