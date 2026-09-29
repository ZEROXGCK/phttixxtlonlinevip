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

# สำคัญ: ต้องตั้งพอร์ตเอง ไม่งั้น dropbear จะใช้ port 22 default
# ซึ่งชนกับ OpenSSH ที่ครองพอร์ตนี้อยู่แล้ว ทำให้ dropbear start ไม่ขึ้น
cat > /etc/default/dropbear << 'DBEOF'
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
DBEOF

# Dropbear ปฏิเสธ user ที่ shell ไม่อยู่ใน /etc/shells — ต้องเพิ่ม nologin ไม่งั้นบัญชี SSH ที่สร้างจาก Dashboard ล็อกอินไม่ได้
grep -qx '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

systemctl enable dropbear > /dev/null 2>&1
systemctl restart dropbear > /dev/null 2>&1
sleep 1
if systemctl is-active --quiet dropbear; then
  ok "Dropbear (port 143, 109) - running"
else
  warn "Dropbear ยังไม่ทำงาน — ดู log: journalctl -u dropbear -n 30"
fi
echo ""

# Install 3x-ui
info "ติดตั้ง 3x-ui (กำลังดาวน์โหลด อาจใช้เวลา 1-3 นาที)..."
info "หมายเหตุ: ถ้าค้างเกิน 3 นาทีที่ขั้นตอนนี้ ให้เช็คว่า VPS เข้า GitHub ได้ไหม (ดู troubleshooting)"

# ตัวติดตั้งของ 3x-ui เป็น interactive (ถามตั้งค่า port/user/pass เอง)
# ป้อน "n" ให้อัตโนมัติ = ไม่ปรับแต่งอะไรเพิ่ม ใช้ค่า random ที่ script ตั้งให้
# ไม่ redirect เป็น /dev/null แล้ว เพื่อให้เห็น error จริงถ้ามันล้มเหลว
curl -Ls -o /tmp/3x-ui-install.sh https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh
if [[ $? -ne 0 || ! -s /tmp/3x-ui-install.sh ]]; then
  warn "ดาวน์โหลด 3x-ui installer ไม่สำเร็จ (เช็คการเชื่อมต่อ GitHub) — ข้ามขั้นตอนนี้ไปก่อน"
else
  timeout 300 bash /tmp/3x-ui-install.sh <<< $'n\n' || warn "3x-ui installer จบด้วย error/timeout — ตรวจสอบด้วย: systemctl status x-ui"
fi

systemctl enable x-ui > /dev/null 2>&1
systemctl start x-ui > /dev/null 2>&1
sleep 2

# ============================================================
# สำคัญ: 3x-ui รุ่นปัจจุบันสุ่ม username/password/port/webBasePath
# ให้เองทุกครั้งที่ติดตั้งใหม่ ถ้าไม่บังคับตั้งค่าตรงนี้
# username/password จะไม่ตรงกับ Dashboard ของเรา และ URL จะเดาไม่ได้
# ต้องบังคับตั้งค่าที่แน่นอนด้วยคำสั่ง `x-ui setting` เอง
# ============================================================
XUI_PORT=8081
XUI_WEBPATH="/xui/"

if command -v x-ui > /dev/null 2>&1; then
  x-ui setting -username "$ADMIN_USER" -password "$ADMIN_PASS" \
    -port "$XUI_PORT" -webBasePath "$XUI_WEBPATH" > /tmp/xui-setting.log 2>&1
  systemctl restart x-ui
  sleep 2
  echo "$XUI_PORT" > /etc/$BRAND_DIR/xui-port.conf
  echo "$XUI_WEBPATH" > /etc/$BRAND_DIR/xui-path.conf
  if systemctl is-active --quiet x-ui; then
    ok "3x-ui (port $XUI_PORT$XUI_WEBPATH) - ใช้ username/password เดียวกับ Dashboard แล้ว"
  else
    warn "3x-ui ไม่ยอมสตาร์ทหลังตั้งค่าใหม่ — ดู: journalctl -u x-ui -n 30 และ cat /tmp/xui-setting.log"
  fi

  ok "x-ui ใช้ username/password เดียวกับ Dashboard — API จะ login เองอัตโนมัติ ไม่ต้องตั้ง token"
else
  warn "หาคำสั่ง x-ui ไม่เจอ — ข้ามการบังคับตั้งค่า username/password"
  warn "3x-ui จะใช้ค่า random ของตัวเอง เช็คได้ด้วยคำสั่ง: x-ui setting -show true"
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
for port in 22 80 109 143 8443 8081 8080 8880; do
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
    location / {
        return 301 https://\$server_name:8443\$request_uri;
    }
}
server {
    listen 8443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/xxtlonline/selfsigned.crt;
    ssl_certificate_key /etc/xxtlonline/selfsigned.key;

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
mkdir -p /etc/xxtlonline /var/www/certbot
if [[ ! -f /etc/xxtlonline/selfsigned.crt ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/xxtlonline/selfsigned.key -out /etc/xxtlonline/selfsigned.crt \
    -subj "/CN=$DOMAIN" > /dev/null 2>&1
fi

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
if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && \
   openssl x509 -checkend 604800 -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" > /dev/null 2>&1; then
  ok "มี SSL certificate ของ $DOMAIN อยู่แล้วและยังไม่ใกล้หมดอายุ — ข้ามการขอใหม่ (กัน rate limit ของ Let's Encrypt)"
  CERT_OK=true
elif certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" \
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
    listen 8443 ssl http2;
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
# port 80 เปิดถาวรสำหรับ Let's Encrypt renew (webroot method) + redirect ไป 8443

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
XXTLONLINE SSH REST API - hardened + full-featured version
- Every endpoint except /api/login requires a valid Bearer token (issued by /api/login)
- Tokens expire after 8 hours and are kept only in memory (lost on service restart -> re-login)
- Login is rate-limited per source IP to slow down brute force
- All external input (usernames/domains) is validated against strict allow-list regexes
- No shell string interpolation anywhere: subprocess.run() is always called with an
  argument list and shell=False, so it is not possible to break out with ; | & $() etc.
- ThreadingHTTPServer so a slow request (e.g. renewing a certificate) does not block
  every other request (dashboard polling, other users logging in, etc.)
"""
import json, subprocess, os, re, secrets, time, threading, socketserver
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timedelta

CONF_DIR = '/etc/xxtlonline'
PANEL_DIR = '/opt/xxtlonline-panel'
WEBROOT_DIR = '/var/www/certbot'
TOKEN_TTL_SECONDS = 8 * 3600
MAX_LOGIN_ATTEMPTS = 5
LOGIN_WINDOW_SECONDS = 300

USERNAME_RE = re.compile(r'^[a-z_][a-z0-9_-]{2,31}$')
DOMAIN_RE = re.compile(r'^(?=.{1,253}$)([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,}$')

_lock = threading.Lock()
_tokens = {}          # token -> expiry_epoch
_login_attempts = {}  # ip -> [timestamps]


def get_admin_creds():
    try:
        user = open(f'{CONF_DIR}/admin-user.conf').read().strip()
        password = open(f'{CONF_DIR}/admin-pass.conf').read().strip()
        return user, password
    except Exception:
        return None, None


def get_domain():
    try:
        return open(f'{CONF_DIR}/domain.conf').read().strip()
    except Exception:
        return ''


_xui_disc = {'t': 0.0}


def _xui_cli(args):
    """Run the x-ui CLI; returns stdout or '' if the binary is missing/fails."""
    for exe in ('x-ui', '/usr/local/x-ui/x-ui'):
        try:
            r = run([exe] + args, timeout=20)
            if r.returncode == 0 and r.stdout:
                return r.stdout
        except OSError:
            continue
    return ''


def xui_discover():
    """
    Fill in the x-ui port / webBasePath / API token from the x-ui CLI when our
    config files don't exist yet (e.g. x-ui was installed before this panel).
    Never overwrites values that are already saved. Throttled to once a minute.
    """
    with _lock:
        if time.time() - _xui_disc['t'] < 60:
            return
        _xui_disc['t'] = time.time()
    os.makedirs(CONF_DIR, exist_ok=True)

    def missing(name):
        return not os.path.exists(f'{CONF_DIR}/{name}')

    def write(name, value, mode=0o644):
        fd = os.open(f'{CONF_DIR}/{name}', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
        with os.fdopen(fd, 'w') as f:
            f.write(value)

    if missing('xui-port.conf') or missing('xui-path.conf'):
        out = _xui_cli(['setting', '-show', 'true'])
        m_port = re.search(r'port:\s*(\d+)', out)
        m_path = re.search(r'webBasePath:\s*(\S+)', out)
        if m_port and missing('xui-port.conf'):
            write('xui-port.conf', m_port.group(1))
        if m_path and missing('xui-path.conf'):
            write('xui-path.conf', m_path.group(1))


def _read_conf(name):
    try:
        return open(f'{CONF_DIR}/{name}').read().strip()
    except Exception:
        return None


def get_xui_port():
    val = _read_conf('xui-port.conf')
    if val is None:
        xui_discover()
        val = _read_conf('xui-port.conf')
    try:
        return int(val)
    except (TypeError, ValueError):
        return 8081


def get_xui_webpath():
    val = _read_conf('xui-path.conf')
    if val is None:
        xui_discover()
        val = _read_conf('xui-path.conf')
    return val or '/xui/'


def xui_base_url():
    port = get_xui_port()
    path = get_xui_webpath()
    if not path.endswith('/'):
        path += '/'
    return f'http://127.0.0.1:{port}{path}'


# alireza0/x-ui uses a session-cookie login (no API token) — log in once with the
# same admin username/password as the Dashboard and cache the cookie in memory.
_xui_cookiejar = None
_xui_session_at = 0.0
XUI_SESSION_TTL = 3000  # a bit under the panel's usual 1-hour session length


def _xui_opener():
    global _xui_cookiejar
    import http.cookiejar, urllib.request
    if _xui_cookiejar is None:
        _xui_cookiejar = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_xui_cookiejar))


def xui_login(force=False):
    global _xui_session_at
    import urllib.request, urllib.parse
    if not force and (time.time() - _xui_session_at) < XUI_SESSION_TTL and _xui_cookiejar is not None and len(_xui_cookiejar) > 0:
        return True
    admin_user, admin_pass = get_admin_creds()
    if not admin_user:
        return False
    data = urllib.parse.urlencode({'username': admin_user, 'password': admin_pass}).encode()
    req = urllib.request.Request(xui_base_url() + 'login', data=data, method='POST')
    try:
        with _xui_opener().open(req, timeout=10) as resp:
            body = json.loads(resp.read().decode() or '{}')
            if body.get('success'):
                _xui_session_at = time.time()
                return True
    except Exception:
        pass
    return False


def xui_request(method, path, json_body=None, _retry=True):
    """
    Proxy a request to the local x-ui panel using a logged-in session cookie
    (auto-login with the shared admin username/password — no manual token needed).
    Returns (data_dict_or_None, error_string_or_None). Never raises.
    """
    import urllib.request, urllib.error
    if not xui_login():
        return None, 'เข้าสู่ระบบ x-ui ไม่สำเร็จ — เช็คว่า x-ui ทำงานอยู่ (systemctl status x-ui) และ username/password ตรงกับ Dashboard'

    url = xui_base_url() + path.lstrip('/')
    headers = {'Accept': 'application/json'}
    data = None
    if json_body is not None:
        data = json.dumps(json_body).encode()
        headers['Content-Type'] = 'application/json'

    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with _xui_opener().open(req, timeout=15) as resp:
            raw = resp.read().decode()
            return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        if e.code in (401, 403) and _retry:
            xui_login(force=True)
            return xui_request(method, path, json_body, _retry=False)
        body = e.read().decode()[:500]
        return None, f'x-ui ตอบ HTTP {e.code}: {body}'
    except Exception as e:
        return None, f'เชื่อมต่อ x-ui ไม่ได้: {e}'


def get_cert_paths(domain):
    cert = f'/etc/letsencrypt/live/{domain}/fullchain.pem'
    key = f'/etc/letsencrypt/live/{domain}/privkey.pem'
    if os.path.exists(cert) and os.path.exists(key):
        return cert, key
    return None, None


def issue_token():
    token = secrets.token_hex(32)
    with _lock:
        _tokens[token] = time.time() + TOKEN_TTL_SECONDS
        for t in list(_tokens):
            if _tokens[t] < time.time():
                del _tokens[t]
    return token


def is_valid_token(token):
    with _lock:
        exp = _tokens.get(token)
        return exp is not None and exp > time.time()


def rate_limited(ip):
    with _lock:
        now = time.time()
        attempts = [t for t in _login_attempts.get(ip, []) if now - t < LOGIN_WINDOW_SECONDS]
        _login_attempts[ip] = attempts
        return len(attempts) >= MAX_LOGIN_ATTEMPTS


def record_attempt(ip):
    with _lock:
        _login_attempts.setdefault(ip, []).append(time.time())


def run(cmd_list, input_text=None, timeout=30):
    """Run a command safely: cmd_list is an argv array, never a shell string."""
    try:
        return subprocess.run(
            cmd_list, input=input_text, text=True, capture_output=True,
            shell=False, check=False, timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        class FakeResult:
            returncode = -1
            stdout = ''
            stderr = f'timeout after {timeout}s'
        return FakeResult()


def service_active(name):
    return run(['systemctl', 'is-active', '--quiet', name]).returncode == 0


def get_uptime_seconds():
    try:
        with open('/proc/uptime') as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return None


def get_kernel():
    r = run(['uname', '-r'])
    return r.stdout.strip() if r.returncode == 0 else 'unknown'


def get_cert_expiry(domain):
    cert_path = f'/etc/letsencrypt/live/{domain}/fullchain.pem'
    if not os.path.exists(cert_path):
        return None
    r = run(['openssl', 'x509', '-enddate', '-noout', '-in', cert_path])
    if r.returncode != 0:
        return None
    # output like: notAfter=Jan  1 00:00:00 2027 GMT
    m = re.search(r'notAfter=(.+)', r.stdout)
    return m.group(1).strip() if m else None


# ---- Real system metrics (no mock/random data anywhere) ----
_prev_cpu = {'total': 0, 'idle': 0}
_prev_net = {'time': 0.0, 'rx': 0, 'tx': 0}


def get_cpu_percent():
    """Non-blocking CPU% using the delta between this call and the previous one."""
    try:
        with open('/proc/stat') as f:
            parts = f.readline().split()[1:8]
        vals = [int(x) for x in parts]
        idle = vals[3] + vals[4]  # idle + iowait
        total = sum(vals)
        with _lock:
            prev_total = _prev_cpu['total']
            prev_idle = _prev_cpu['idle']
            _prev_cpu['total'] = total
            _prev_cpu['idle'] = idle
        dt = total - prev_total
        di = idle - prev_idle
        if dt <= 0 or prev_total == 0:
            return 0.0
        return round(max(0.0, min(100.0, (1 - di / dt) * 100)), 1)
    except Exception:
        return None


def get_ram_percent():
    try:
        meminfo = {}
        with open('/proc/meminfo') as f:
            for line in f:
                k, v = line.split(':', 1)
                meminfo[k] = int(v.strip().split()[0])
        total = meminfo.get('MemTotal', 0)
        available = meminfo.get('MemAvailable', 0)
        if total == 0:
            return None
        return round((1 - available / total) * 100, 1)
    except Exception:
        return None


def get_disk_percent():
    try:
        import shutil
        usage = shutil.disk_usage('/')
        return round(usage.used / usage.total * 100, 1)
    except Exception:
        return None


def _read_net_bytes():
    rx = tx = 0
    try:
        with open('/proc/net/dev') as f:
            for line in f.readlines()[2:]:
                iface, rest = line.split(':', 1)
                iface = iface.strip()
                if iface == 'lo':
                    continue
                fields = rest.split()
                rx += int(fields[0])
                tx += int(fields[8])
    except Exception:
        pass
    return rx, tx


def get_network_mbps():
    """Real throughput computed from the delta between polls (no random numbers)."""
    now = time.time()
    rx, tx = _read_net_bytes()
    with _lock:
        prev_time = _prev_net['time']
        prev_rx = _prev_net['rx']
        prev_tx = _prev_net['tx']
        _prev_net['time'] = now
        _prev_net['rx'] = rx
        _prev_net['tx'] = tx
    dt = now - prev_time
    if prev_time == 0 or dt <= 0:
        return {'download_mbps': 0.0, 'upload_mbps': 0.0}
    download = max(0.0, (rx - prev_rx) * 8 / dt / 1_000_000)
    upload = max(0.0, (tx - prev_tx) * 8 / dt / 1_000_000)
    return {'download_mbps': round(download, 2), 'upload_mbps': round(upload, 2)}


def get_active_connections():
    """Count real ESTABLISHED TCP connections on the SSH/VPN ports (109, 143)."""
    count = 0
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                lines = f.readlines()[1:]
            for line in lines:
                cols = line.split()
                if len(cols) < 4:
                    continue
                local = cols[1]
                state = cols[3]
                port_hex = local.split(':')[-1]
                try:
                    port = int(port_hex, 16)
                except ValueError:
                    continue
                if state == '01' and port in (109, 143):  # 01 = ESTABLISHED
                    count += 1
        except Exception:
            pass
    return count


PROFILES_MAX = 50
HOSTLIKE_RE = re.compile(r'^[A-Za-z0-9.\-:\[\]]{0,260}$')
_prof_lock = threading.Lock()


def load_profiles():
    try:
        with open(f'{CONF_DIR}/profiles.json') as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_profiles(profiles):
    os.makedirs(CONF_DIR, exist_ok=True)
    tmp = f'{CONF_DIR}/profiles.json.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(profiles, f, ensure_ascii=False, indent=2)
    os.replace(tmp, f'{CONF_DIR}/profiles.json')


def clean_profile(data):
    """Validate one saved config profile. Returns (profile, error)."""
    name = re.sub(r'[\x00-\x1f\x7f]', '', str(data.get('name', '')).strip())[:40]
    if not name:
        return None, 'ต้องตั้งชื่อโปรไฟล์'
    if name == '__all__':
        return None, 'ชื่อนี้ถูกสงวนไว้ เลือกชื่ออื่น'
    host = str(data.get('host', '')).strip()
    sni = str(data.get('sni', '')).strip()
    proxy = str(data.get('proxy', '')).strip()
    for label, val in (('host', host), ('sni', sni), ('proxy', proxy)):
        if not HOSTLIKE_RE.match(val):
            return None, f'{label} มีตัวอักษรที่ไม่อนุญาต (ใช้ได้เฉพาะ a-z 0-9 . - : [ ])'
    try:
        port = int(data.get('port', 143))
    except (TypeError, ValueError):
        return None, 'port ไม่ถูกต้อง'
    if not 1 <= port <= 65535:
        return None, 'port ต้องอยู่ระหว่าง 1-65535'
    payload = str(data.get('payload', '')).replace('\x00', '').strip()
    if len(payload) > 2000:
        return None, 'payload ยาวเกิน 2000 ตัวอักษร'
    return {'name': name, 'host': host, 'port': port, 'sni': sni,
            'proxy': proxy, 'payload': payload}, None


def is_expired(exp_str):
    try:
        return datetime.strptime(exp_str, '%Y-%m-%d').date() < datetime.now().date()
    except Exception:
        return False


def read_exp(user):
    try:
        return open(f'{CONF_DIR}/exp/{user}').read().strip()
    except Exception:
        return None


def reaper_loop():
    """Enforce expiry for real: lock expired accounts and kick their live sessions."""
    while True:
        try:
            exp_dir = f'{CONF_DIR}/exp'
            if os.path.isdir(exp_dir):
                for uname in os.listdir(exp_dir):
                    if not USERNAME_RE.match(uname):
                        continue
                    if is_expired(read_exp(uname) or ''):
                        run(['usermod', '-L', uname])
                        run(['pkill', '-KILL', '-u', uname])
        except Exception:
            pass
        time.sleep(300)


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

    def _read_json(self):
        content_len = int(self.headers.get('Content-Length', 0) or 0)
        raw = self.rfile.read(content_len) if content_len > 0 else b'{}'
        return json.loads(raw)

    # ---------------------------------------------------------------- GET
    def do_GET(self):
        protected = ('/api/status', '/api/info', '/api/users', '/api/xui/inbounds', '/api/xui/config', '/api/profiles')
        if self.path in protected and not self._authorized():
            self._json(401, {'error': 'unauthorized'})
            return

        if self.path == '/api/profiles':
            self._json(200, {'ok': True, 'profiles': load_profiles()})
            return

        if self.path == '/api/xui/config':
            self._json(200, {'ok': True, 'port': get_xui_port(), 'path': get_xui_webpath()})
            return

        if self.path == '/api/xui/inbounds':
            data, err = xui_request('GET', 'panel/api/inbounds/list')
            if err:
                self._json(502, {'ok': False, 'error': err})
                return
            self._json(200, {'ok': True, 'inbounds': data.get('obj', []) if data else []})
            return

        if self.path == '/api/status':
            try:
                users = len([
                    l for l in open('/etc/passwd').read().split('\n')
                    if len(l.split(':')) > 2 and int(l.split(':')[2]) >= 1000
                ])
            except Exception:
                users = 0
            domain = get_domain()
            net = get_network_mbps()
            self._json(200, {
                'connections': get_active_connections(),
                'total_users': users,
                'services': {
                    'ssh': True,
                    'dropbear': service_active('dropbear'),
                    'nginx': service_active('nginx'),
                    'xui': service_active('x-ui'),
                    'ssh_api': True,
                },
                'uptime_seconds': get_uptime_seconds(),
                'kernel': get_kernel(),
                'cert_expiry': get_cert_expiry(domain) if domain else None,
                'cpu_percent': get_cpu_percent(),
                'ram_percent': get_ram_percent(),
                'disk_percent': get_disk_percent(),
                'download_mbps': net['download_mbps'],
                'upload_mbps': net['upload_mbps'],
            })

        elif self.path == '/api/info':
            domain = get_domain()
            admin_user, _ = get_admin_creds()
            self._json(200, {
                'host': domain,
                'xui_port': get_xui_port(),
                'xui_path': get_xui_webpath(),
                'dropbear_port': 143,
                'admin_user': admin_user or '',
            })

        elif self.path == '/api/users':
            try:
                users = []
                for l in open('/etc/passwd').readlines():
                    parts = l.split(':')
                    if len(parts) > 2 and int(parts[2]) >= 1000:
                        uname = parts[0]
                        exp_path = f'{CONF_DIR}/exp/{uname}'
                        exp = open(exp_path).read().strip() if os.path.exists(exp_path) else None
                        users.append({'user': uname, 'exp': exp, 'active': not is_expired(exp or '')})
            except Exception:
                users = []
            self._json(200, {'users': users})

        else:
            self._json(404, {'error': 'not found'})

    # --------------------------------------------------------------- POST
    def do_POST(self):
        try:
            data = self._read_json()
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
            self._create_ssh(data)
        elif self.path == '/api/delete_ssh':
            self._delete_ssh(data)
        elif self.path == '/api/renew_ssh':
            self._renew_ssh(data)
        elif self.path == '/api/change_ssh_password':
            self._change_ssh_password(data)
        elif self.path == '/api/change_password':
            self._change_password(data)
        elif self.path == '/api/renew_cert':
            self._renew_cert(data)
        elif self.path == '/api/update_domain':
            self._update_domain(data)
        elif self.path == '/api/profiles':
            self._save_profile(data)
        elif self.path == '/api/profiles/delete':
            self._delete_profile(data)
        elif self.path == '/api/xui/config':
            self._xui_save_config(data)
        elif self.path == '/api/xui/inbounds':
            self._xui_create_inbound(data)
        elif self.path == '/api/xui/inbounds/add_client':
            self._xui_add_client(data)
        elif self.path == '/api/xui/inbounds/delete':
            self._xui_delete_inbound(data)
        else:
            self._json(404, {'error': 'not found'})

    # ------------------------------------------------------------ actions
    def _create_ssh(self, data):
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

        if run(['id', user]).returncode == 0:
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

    def _delete_ssh(self, data):
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

    def _renew_ssh(self, data):
        user = str(data.get('user', '')).strip().lower()
        try:
            days = int(data.get('days', 30))
        except (TypeError, ValueError):
            days = 30
        days = max(1, min(days, 3650))
        if not USERNAME_RE.match(user) or run(['id', user]).returncode != 0:
            self._json(404, {'error': 'user not found'})
            return
        # extend from the later of (today, current expiry) so renewing early doesn't lose days
        base = datetime.now().date()
        cur = read_exp(user)
        try:
            cur_date = datetime.strptime(cur, '%Y-%m-%d').date()
            if cur_date > base:
                base = cur_date
        except Exception:
            pass
        exp = (datetime.combine(base, datetime.min.time()) + timedelta(days=days)).strftime('%Y-%m-%d')
        os.makedirs(f'{CONF_DIR}/exp', exist_ok=True)
        with open(f'{CONF_DIR}/exp/{user}', 'w') as f:
            f.write(exp)
        run(['usermod', '-U', user])  # unlock if the reaper had locked it
        self._json(200, {'ok': True, 'user': user, 'exp': exp})

    def _change_ssh_password(self, data):
        user = str(data.get('user', '')).strip().lower()
        password = str(data.get('password', ''))
        if not USERNAME_RE.match(user) or run(['id', user]).returncode != 0:
            self._json(404, {'error': 'user not found'})
            return
        if len(password) < 6 or '\n' in password or '\r' in password:
            self._json(400, {'error': 'password must be at least 6 characters'})
            return
        r = run(['chpasswd'], input_text=f"{user}:{password}\n")
        if r.returncode != 0:
            self._json(500, {'error': 'failed to set password'})
            return
        self._json(200, {'ok': True, 'user': user})

    def _change_password(self, data):
        current = str(data.get('current_password', ''))
        new = str(data.get('new_password', ''))
        admin_user, admin_pass = get_admin_creds()
        if admin_pass is None or not secrets.compare_digest(current, admin_pass):
            self._json(403, {'error': 'current password is incorrect'})
            return
        if len(new) < 8:
            self._json(400, {'error': 'new password must be at least 8 characters'})
            return
        with open(f'{CONF_DIR}/admin-pass.conf', 'w') as f:
            f.write(new)
        # invalidate all existing sessions so old tokens can't be reused
        with _lock:
            _tokens.clear()
        self._json(200, {'ok': True})

    def _renew_cert(self, data):
        domain = get_domain()
        if not domain:
            self._json(400, {'error': 'no domain configured'})
            return
        r = run(['certbot', 'renew', '--cert-name', domain], timeout=180)
        ok = r.returncode == 0
        if ok:
            run(['systemctl', 'reload', 'nginx'])
        self._json(200 if ok else 500, {
            'ok': ok,
            'output': (r.stdout[-2000:] + r.stderr[-2000:]) if not ok else 'renewed',
        })

    def _update_domain(self, data):
        new_domain = str(data.get('domain', '')).strip().lower()
        if not DOMAIN_RE.match(new_domain):
            self._json(400, {'error': 'invalid domain format'})
            return

        with open(f'{CONF_DIR}/domain.conf', 'w') as f:
            f.write(new_domain)
        os.makedirs(WEBROOT_DIR, exist_ok=True)

        cert_ok = False
        existing = f'/etc/letsencrypt/live/{new_domain}/fullchain.pem'
        if os.path.exists(existing) and run(['openssl', 'x509', '-checkend', '604800', '-noout', '-in', existing]).returncode == 0:
            cert_ok = True
        else:
            cert = run(['certbot', 'certonly', '--webroot', '-w', WEBROOT_DIR, '-d', new_domain,
                        '--agree-tos', '-m', f'admin@{new_domain}', '-n'], timeout=180)
            cert_ok = cert.returncode == 0 and os.path.exists(existing)

        if cert_ok:
            https_conf = f"""server {{
    listen 80;
    server_name {new_domain};
    location /.well-known/acme-challenge/ {{
        root {WEBROOT_DIR};
    }}
    location / {{
        return 301 https://$server_name:8443$request_uri;
    }}
}}
server {{
    listen 8443 ssl http2;
    server_name {new_domain};
    ssl_certificate /etc/letsencrypt/live/{new_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{new_domain}/privkey.pem;
    location /api/ {{
        proxy_pass http://127.0.0.1:6789;
        proxy_set_header Host $host;
    }}
    location / {{
        root {PANEL_DIR};
        try_files $uri /index.html;
    }}
}}
"""
            with open('/etc/nginx/conf.d/xxtlonline.conf', 'w') as f:
                f.write(https_conf)
            test2 = run(['nginx', '-t'])
            if test2.returncode == 0:
                run(['systemctl', 'restart', 'nginx'])
                self._json(200, {'ok': True, 'https': True, 'domain': new_domain})
                return
            else:
                self._json(200, {'ok': True, 'https': False, 'domain': new_domain,
                                  'warning': 'SSL obtained but nginx https config failed, serving http only'})
                return

        self._json(200, {
            'ok': True, 'https': False, 'domain': new_domain,
            'warning': 'domain updated but SSL could not be issued yet (check DNS propagation), site is live on http:// for now',
        })

    def _save_profile(self, data):
        prof, err = clean_profile(data)
        if err:
            self._json(400, {'ok': False, 'error': err})
            return
        old_name = str(data.get('old_name', '')).strip()
        error = None
        with _prof_lock:
            profiles = load_profiles()
            names = [p.get('name') for p in profiles]
            idx = names.index(old_name) if old_name and old_name in names else None
            if idx is None and prof['name'] in names:
                idx = names.index(prof['name'])
            if idx is not None:
                # renaming onto a different existing profile would create a duplicate
                if prof['name'] in names and names.index(prof['name']) != idx:
                    error = 'มีโปรไฟล์ชื่อนี้อยู่แล้ว'
                else:
                    profiles[idx] = prof
            elif len(profiles) >= PROFILES_MAX:
                error = f'สร้างโปรไฟล์ได้สูงสุด {PROFILES_MAX} ชุด'
            else:
                profiles.append(prof)
            if not error:
                save_profiles(profiles)
        if error:
            self._json(400, {'ok': False, 'error': error})
            return
        self._json(200, {'ok': True, 'profile': prof})

    def _delete_profile(self, data):
        name = str(data.get('name', '')).strip()
        with _prof_lock:
            profiles = load_profiles()
            remaining = [p for p in profiles if p.get('name') != name]
            if len(remaining) != len(profiles):
                save_profiles(remaining)
        self._json(200, {'ok': True})

    def _xui_save_config(self, data):
        """แก้เองได้เลยถ้าดึง port/path อัตโนมัติไม่สำเร็จ (ไม่ต้องใช้ token แล้ว — login ด้วย user/pass เดียวกับ Dashboard)"""
        port = data.get('port')
        path = data.get('path')
        try:
            if port:
                port = int(port)
                assert 1 <= port <= 65535
                with open(f'{CONF_DIR}/xui-port.conf', 'w') as f:
                    f.write(str(port))
        except Exception:
            self._json(400, {'ok': False, 'error': 'port ไม่ถูกต้อง'})
            return
        if path:
            path = str(path).strip()
            if not path.startswith('/'):
                path = '/' + path
            if not path.endswith('/'):
                path += '/'
            with open(f'{CONF_DIR}/xui-path.conf', 'w') as f:
                f.write(path)
        self._json(200, {'ok': True})

    def _xui_add_client(self, data):
        import uuid as uuidlib
        try:
            inbound_id = int(data.get('inbound_id'))
        except (TypeError, ValueError):
            self._json(400, {'ok': False, 'error': 'invalid inbound_id'})
            return

        listing, err = xui_request('GET', 'panel/api/inbounds/list')
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        inbound = next((i for i in (listing.get('obj') or []) if int(i.get('id', -1)) == inbound_id), None)
        if not inbound:
            self._json(404, {'ok': False, 'error': 'ไม่พบ inbound นี้'})
            return
        protocol = inbound.get('protocol')

        remark = re.sub(r'[^a-zA-Z0-9 _-]', '', str(data.get('remark', '')).strip())[:64] or f'client-{secrets.token_hex(3)}'
        try:
            gb = float(data.get('gb', 0))
        except (TypeError, ValueError):
            gb = 0
        try:
            days = int(data.get('days', 0))
        except (TypeError, ValueError):
            days = 0
        total_bytes = int(max(0, gb) * 1024 * 1024 * 1024)
        expiry_ms = int((datetime.now() + timedelta(days=days)).timestamp() * 1000) if days > 0 else 0

        client_uuid = str(uuidlib.uuid4())
        trojan_password = secrets.token_urlsafe(12)
        email = remark.replace(' ', '_') + '_' + secrets.token_hex(2)

        if protocol == 'trojan':
            client = {'password': trojan_password, 'email': email, 'limitIp': 0,
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True}
        elif protocol == 'vmess':
            client = {'id': client_uuid, 'alterId': 0, 'email': email, 'limitIp': 0,
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True}
        else:  # vless and everything else that uses uuid-based clients
            client = {'id': client_uuid, 'flow': '', 'email': email, 'limitIp': 0,
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True}

        payload = {'id': inbound_id, 'settings': json.dumps({'clients': [client]})}
        result, err = xui_request('POST', 'panel/api/inbounds/addClient', payload)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        if result and result.get('success') is False:
            self._json(400, {'ok': False, 'error': result.get('msg', 'x-ui ปฏิเสธคำขอ')})
            return

        domain = get_domain() or '127.0.0.1'
        port = inbound.get('port')
        stream = {}
        try:
            stream = json.loads(inbound.get('streamSettings') or '{}')
        except Exception:
            pass
        network = stream.get('network', 'tcp')
        security = stream.get('security', 'none')
        params = f'type={network}&security={security}'
        if network == 'ws':
            params += f"&path={(stream.get('wsSettings') or {}).get('path', '/')}"
        elif network == 'grpc':
            params += f"&serviceName={(stream.get('grpcSettings') or {}).get('serviceName', '')}"
        if security == 'tls':
            params += f'&sni={domain}'

        if protocol == 'trojan':
            share_link = f'trojan://{trojan_password}@{domain}:{port}?{params}#{remark}'
        elif protocol == 'vless':
            share_link = f'vless://{client_uuid}@{domain}:{port}?{params}#{remark}'
        else:
            share_link = None  # vmess needs base64 json; view/QR in the x-ui panel

        self._json(200, {
            'ok': True, 'remark': remark, 'email': email, 'protocol': protocol,
            'client_uuid': client_uuid if protocol != 'trojan' else None,
            'trojan_password': trojan_password if protocol == 'trojan' else None,
            'gb': gb, 'days': days, 'share_link': share_link,
        })

    def _xui_create_inbound(self, data):
        import uuid as uuidlib

        protocol = str(data.get('protocol', '')).strip().lower()
        if protocol not in ('vless', 'vmess', 'trojan'):
            self._json(400, {'ok': False, 'error': 'protocol ต้องเป็น vless, vmess หรือ trojan เท่านั้น'})
            return

        remark = str(data.get('remark', '')).strip()[:64]
        remark = re.sub(r'[^a-zA-Z0-9 _-]', '', remark) or f'{protocol}-inbound'

        try:
            port = int(data.get('port', 0))
        except (TypeError, ValueError):
            port = 0
        reserved_ports = {22, 80, 109, 143, 443, 6789, 7300, get_xui_port()}
        if port < 1 or port > 65535:
            self._json(400, {'ok': False, 'error': 'port ต้องอยู่ระหว่าง 1-65535'})
            return
        if port in reserved_ports:
            self._json(400, {'ok': False, 'error': f'port {port} ถูกใช้งานโดยระบบอื่นอยู่แล้ว (เช่น dashboard/ssh/xui panel) เลือกพอร์ตอื่น เช่น 8080 หรือ 8880'})
            return

        network = str(data.get('network', 'tcp')).strip().lower()
        if network not in ('tcp', 'ws', 'grpc'):
            self._json(400, {'ok': False, 'error': 'network ต้องเป็น tcp, ws หรือ grpc'})
            return

        security = str(data.get('security', 'tls')).strip().lower()
        if security not in ('tls', 'none'):
            self._json(400, {'ok': False, 'error': 'security ต้องเป็น tls หรือ none'})
            return

        client_email = remark.replace(' ', '_')
        client_uuid = str(uuidlib.uuid4())
        trojan_password = secrets.token_urlsafe(12)

        if protocol == 'vless':
            settings = {
                'clients': [{'id': client_uuid, 'flow': '', 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True}],
                'decryption': 'none', 'fallbacks': [],
            }
        elif protocol == 'vmess':
            settings = {
                'clients': [{'id': client_uuid, 'alterId': 0, 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True}],
            }
        else:  # trojan
            settings = {
                'clients': [{'password': trojan_password, 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True}],
            }

        stream_settings = {'network': network}
        if security == 'tls':
            domain = get_domain()
            cert, key = get_cert_paths(domain)
            if not cert:
                self._json(400, {'ok': False, 'error': f'ยังไม่มี SSL certificate สำหรับ {domain} — ขอ SSL ก่อน (Settings > Renew Certificate) หรือเลือก security เป็น none'})
                return
            stream_settings['security'] = 'tls'
            stream_settings['tlsSettings'] = {
                'serverName': domain,
                'certificates': [{'certificateFile': cert, 'keyFile': key}],
            }
        else:
            stream_settings['security'] = 'none'

        ws_path = str(data.get('ws_path', '')).strip() or f'/{secrets.token_hex(4)}'
        grpc_service = str(data.get('grpc_service', '')).strip() or f'svc{secrets.token_hex(3)}'
        if network == 'ws':
            stream_settings['wsSettings'] = {'path': ws_path}
        elif network == 'grpc':
            stream_settings['grpcSettings'] = {'serviceName': grpc_service}

        payload = {
            'enable': True, 'remark': remark, 'listen': '', 'port': port,
            'protocol': protocol, 'expiryTime': 0, 'total': 0,
            'settings': settings, 'streamSettings': stream_settings,
            'sniffing': {'enabled': True, 'destOverride': ['http', 'tls']},
        }

        result, err = xui_request('POST', 'panel/api/inbounds/add', payload)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        if result and result.get('success') is False:
            self._json(400, {'ok': False, 'error': result.get('msg', 'x-ui ปฏิเสธคำขอ ไม่ทราบสาเหตุ')})
            return

        # Build a client share link so the admin can copy/QR it immediately
        domain = get_domain() or '127.0.0.1'
        share_link = None
        if protocol == 'vless':
            params = f'type={network}&security={security}'
            if network == 'ws':
                params += f'&path={ws_path}'
            elif network == 'grpc':
                params += f'&serviceName={grpc_service}'
            if security == 'tls':
                params += f'&sni={domain}'
            share_link = f'vless://{client_uuid}@{domain}:{port}?{params}#{remark}'
        elif protocol == 'trojan':
            params = f'type={network}&security={security}'
            if network == 'ws':
                params += f'&path={ws_path}'
            share_link = f'trojan://{trojan_password}@{domain}:{port}?{params}#{remark}'
        # vmess link needs base64-encoded JSON; leave to the 3x-ui panel's own QR/export for that one

        self._json(200, {
            'ok': True, 'remark': remark, 'protocol': protocol, 'port': port,
            'client_uuid': client_uuid if protocol != 'trojan' else None,
            'trojan_password': trojan_password if protocol == 'trojan' else None,
            'share_link': share_link,
        })

    def _xui_delete_inbound(self, data):
        try:
            inbound_id = int(data.get('id'))
        except (TypeError, ValueError):
            self._json(400, {'ok': False, 'error': 'invalid inbound id'})
            return
        result, err = xui_request('POST', f'panel/api/inbounds/del/{inbound_id}')
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        self._json(200, {'ok': True})


class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == '__main__':
    threading.Thread(target=reaper_loop, daemon=True).start()
    server = ThreadingHTTPServer(('127.0.0.1', 6789), Handler)
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

if [[ "$CERT_OK" == "true" ]]; then
  echo -e "${CYAN}📊 Dashboard:${NC}"
  echo "   https://$DOMAIN:8443"
else
  echo -e "${YELLOW}📊 Dashboard (ยังไม่มี SSL จริง ใช้ cert ชั่วคราว เบราว์เซอร์จะเตือน 'ไม่ปลอดภัย' ไปก่อน):${NC}"
  echo "   https://$DOMAIN:8443"
fi
echo "   Username: $ADMIN_USER"
echo ""
echo -e "${CYAN}⚙️  Settings:${NC}"
echo "   https://$DOMAIN:8443/settings.html"
echo ""
echo -e "${CYAN}📡 3x-ui Panel:${NC}"
echo "   http://$DOMAIN:$XUI_PORT$XUI_WEBPATH"
echo "   Username: $ADMIN_USER"
echo ""
echo -e "${CYAN}🔌 SSH:${NC}"
echo "   ssh -p 143 <user>@$DOMAIN"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
ok "ใช้ username/password เดียวกันเข้า Dashboard + 3x-ui"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
