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



def build_share_link(inbound, client, domain):
    """สร้างลิงก์แชร์ให้ตรงกับที่หน้า x-ui สร้าง (อ่านค่าจริงจาก streamSettings ของ inbound)"""
    import base64
    from urllib.parse import quote, urlencode
    protocol = inbound.get('protocol')
    try:
        stream = json.loads(inbound.get('streamSettings') or '{}')
    except Exception:
        stream = {}
    network = stream.get('network', 'tcp')
    security = stream.get('security', 'none')
    port = inbound.get('port')
    email = client.get('email', '')
    remark = '-'.join([x for x in (str(inbound.get('remark') or ''), email) if x])

    params = {'type': network}
    host = ''
    path = ''
    header_type = ''
    if network == 'tcp':
        header = (stream.get('tcpSettings') or {}).get('header') or {}
        if header.get('type') == 'http':
            header_type = 'http'
            req = header.get('request') or {}
            path = ','.join(req.get('path') or ['/'])
            hosts = (req.get('headers') or {}).get('Host') or []
            host = ','.join(hosts) if isinstance(hosts, list) else str(hosts)
            params['headerType'] = 'http'
            params['path'] = path
            if host:
                params['host'] = host
    elif network in ('ws', 'httpupgrade'):
        ws = stream.get('wsSettings') if network == 'ws' else stream.get('httpupgradeSettings')
        ws = ws or {}
        path = ws.get('path', '/')
        host = (ws.get('headers') or {}).get('Host') or ws.get('host', '')
        params['path'] = path
        if host:
            params['host'] = host
    elif network == 'grpc':
        g = stream.get('grpcSettings') or {}
        params['serviceName'] = g.get('serviceName', '')
        if g.get('multiMode'):
            params['mode'] = 'multi'

    sni = ''
    alpn = ''
    fp = ''
    if security == 'tls':
        tls = stream.get('tlsSettings') or {}
        tls_extra = tls.get('settings') or {}
        sni = tls.get('serverName') or domain
        fp = tls_extra.get('fingerprint') or tls.get('fingerprint') or ''
        alpn = ','.join(tls.get('alpn') or [])
        params['security'] = 'tls'
        if fp:
            params['fp'] = fp
        if alpn:
            params['alpn'] = alpn
        if sni:
            params['sni'] = sni
        if tls_extra.get('allowInsecure') or tls.get('allowInsecure'):
            params['allowInsecure'] = '1'
    elif security == 'reality':
        rl = stream.get('realitySettings') or {}
        rs = rl.get('settings') or {}
        params['security'] = 'reality'
        params['pbk'] = rs.get('publicKey') or rl.get('publicKey', '')
        fp = rs.get('fingerprint') or rl.get('fingerprint') or 'chrome'
        params['fp'] = fp
        names = rl.get('serverNames') or []
        if names:
            sni = names[0]
            params['sni'] = sni
        sids = rl.get('shortIds') or []
        if sids:
            params['sid'] = sids[0]
        spx = rs.get('spiderX') or rl.get('spiderX') or ''
        if spx:
            params['spx'] = spx
    else:
        params['security'] = 'none'

    if protocol == 'vless':
        params['encryption'] = 'none'
        if client.get('flow'):
            params['flow'] = client['flow']
        q = urlencode(params, quote_via=quote, safe='')
        return f"vless://{client.get('id')}@{domain}:{port}?{q}#{quote(remark)}"
    if protocol == 'trojan':
        q = urlencode(params, quote_via=quote, safe='')
        return f"trojan://{client.get('password')}@{domain}:{port}?{q}#{quote(remark)}"
    if protocol == 'vmess':
        obj = {'v': '2', 'ps': remark, 'add': domain, 'port': port, 'id': client.get('id'),
               'aid': client.get('alterId', 0), 'scy': 'auto', 'net': network,
               'type': header_type or 'none', 'host': host, 'path': path,
               'tls': 'tls' if security == 'tls' else 'none', 'sni': sni, 'alpn': alpn, 'fp': fp}
        return 'vmess://' + base64.b64encode(json.dumps(obj, separators=(',', ':')).encode()).decode()
    return None


def enrich_inbound(ib, domain):
    """เติมรายละเอียดผู้ใช้ + ลิงก์ ให้ Dashboard แสดงครบเหมือนหน้า x-ui"""
    try:
        settings = json.loads(ib.get('settings') or '{}')
    except Exception:
        settings = {}
    try:
        stream = json.loads(ib.get('streamSettings') or '{}')
    except Exception:
        stream = {}
    stats = {s.get('email'): s for s in (ib.get('clientStats') or [])}
    details = []
    for c in settings.get('clients') or []:
        st = stats.get(c.get('email'), {})
        try:
            link = build_share_link(ib, c, domain)
        except Exception:
            link = None
        details.append({
            'email': c.get('email', ''), 'enable': c.get('enable', True),
            'totalGB': c.get('totalGB', 0), 'expiryTime': c.get('expiryTime', 0),
            'up': st.get('up', 0), 'down': st.get('down', 0), 'link': link,
        })
    ib['clients_detail'] = details
    ib['net'] = stream.get('network', 'tcp')
    ib['sec'] = stream.get('security', 'none')
    tls = stream.get('tlsSettings') or {}
    ib['sni'] = tls.get('serverName', '')
    return ib


_xui_disc = {'t': 0.0}


def _xui_cli(args):
    """Run the x-ui CLI; returns stdout or '' if the binary is missing/fails."""
    for exe in ('/usr/local/x-ui/x-ui', 'x-ui'):
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
    return f'{xui_scheme()}://127.0.0.1:{port}{path}'


_xui_scheme_cache = {'t': 0.0, 'v': 'http'}


def xui_scheme():
    """http หรือ https: อ่านจาก xui-scheme.conf ถ้ามี ไม่งั้นตรวจเองว่า x-ui เปิด SSL อยู่ไหม"""
    v = _read_conf('xui-scheme.conf')
    if v in ('http', 'https'):
        return v
    now = time.time()
    if now - _xui_scheme_cache['t'] < 30:
        return _xui_scheme_cache['v']
    scheme = 'http'
    try:
        import ssl, socket
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        with socket.create_connection(('127.0.0.1', get_xui_port()), timeout=3) as s:
            with ctx.wrap_socket(s):
                scheme = 'https'
    except Exception:
        scheme = 'http'
    _xui_scheme_cache.update({'t': now, 'v': scheme})
    return scheme


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
    import ssl
    # เรียก x-ui ผ่าน 127.0.0.1 ซึ่งไม่ตรงกับชื่อโดเมนในใบรับรอง จึงข้ามการตรวจชื่อ (เฉพาะการเชื่อมต่อภายในเครื่อง)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_xui_cookiejar),
                                       urllib.request.HTTPSHandler(context=ctx))


def xui_reset_session():
    """ล้าง session/แคชของ x-ui หลังเปลี่ยนค่าเชื่อมต่อ ให้ login ใหม่ทันที"""
    global _xui_cookiejar, _xui_session_at
    _xui_cookiejar = None
    _xui_session_at = 0.0
    _xui_scheme_cache['t'] = 0.0


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
        protected = ('/api/status', '/api/info', '/api/users', '/api/xui/inbounds', '/api/xui/config',
                     '/api/profiles', '/api/ssh_config')
        if self.path in protected and not self._authorized():
            self._json(401, {'error': 'unauthorized'})
            return

        if self.path == '/api/ssh_config':
            domain = get_domain() or '-'
            services = {
                'dropbear': service_active('dropbear'),
                'ws_ssh': service_active('xxtlonline-ws-ssh'),
                'ws_ovpn': service_active('xxtlonline-ws-ovpn'),
            }
            self._json(200, {'ok': True, 'domain': domain, 'services': services, 'ports': {
                'dropbear_143': 143, 'dropbear_109': 109, 'openssh_22': 22,
                'ssh_ws_8880': 8880, 'openvpn_ws_2086': 2086,
            }})
            return

        if self.path == '/api/profiles':
            self._json(200, {'ok': True, 'profiles': load_profiles()})
            return

        if self.path == '/api/xui/config':
            mode = _read_conf('xui-scheme.conf')
            self._json(200, {'ok': True, 'port': get_xui_port(), 'path': get_xui_webpath(),
                             'scheme_mode': mode if mode in ('http', 'https') else 'auto',
                             'scheme': xui_scheme(), 'user': get_admin_creds()[0]})
            return

        if self.path == '/api/xui/inbounds':
            data, err = xui_request('POST', 'xui/inbound/list')
            if err:
                self._json(502, {'ok': False, 'error': err})
                return
            dom = get_domain() or '127.0.0.1'
            lst = [enrich_inbound(i, dom) for i in (data.get('obj', []) if data else [])]
            self._json(200, {'ok': True, 'inbounds': lst})
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
        elif self.path == '/api/xui/test':
            self._xui_test()
        elif self.path == '/api/xui/inbounds/update_client':
            self._xui_update_client(data)
        elif self.path == '/api/xui/inbounds/delete_client':
            self._xui_delete_client(data)
        elif self.path == '/api/ssh_config/restart':
            self._ssh_config_restart(data)
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
        mode = str(data.get('scheme', '')).strip().lower()
        if mode in ('http', 'https'):
            with open(f'{CONF_DIR}/xui-scheme.conf', 'w') as f:
                f.write(mode)
        elif mode == 'auto':
            try:
                os.remove(f'{CONF_DIR}/xui-scheme.conf')
            except OSError:
                pass
        xui_reset_session()
        self._json(200, {'ok': True})

    def _xui_test(self):
        """ทดสอบ login + ดึงรายการ inbound ด้วยค่าที่ตั้งไว้ตอนนี้"""
        t0 = time.time()
        xui_reset_session()
        url = xui_base_url()
        if not xui_login(force=True):
            self._json(200, {'ok': False, 'url': url, 'error': 'login ไม่สำเร็จ — ตรวจพอต/path/http-https และ user/password ให้ตรงกับ x-ui'})
            return
        data, err = xui_request('POST', 'xui/inbound/list')
        if err:
            self._json(200, {'ok': False, 'url': url, 'error': err})
            return
        self._json(200, {'ok': True, 'url': url, 'inbounds': len((data or {}).get('obj') or []),
                         'ms': int((time.time() - t0) * 1000)})

    def _xui_add_client(self, data):
        import uuid as uuidlib
        try:
            inbound_id = int(data.get('inbound_id'))
        except (TypeError, ValueError):
            self._json(400, {'ok': False, 'error': 'invalid inbound_id'})
            return

        listing, err = xui_request('POST', 'xui/inbound/list')
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
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True,
                      'tgId': '', 'subId': secrets.token_hex(8)}
        elif protocol == 'vmess':
            client = {'id': client_uuid, 'alterId': 0, 'email': email, 'limitIp': 0,
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True,
                      'tgId': '', 'subId': secrets.token_hex(8)}
        else:  # vless and everything else that uses uuid-based clients
            client = {'id': client_uuid, 'flow': '', 'email': email, 'limitIp': 0,
                      'totalGB': total_bytes, 'expiryTime': expiry_ms, 'enable': True,
                      'tgId': '', 'subId': secrets.token_hex(8)}

        # x-ui 1.x ไม่มี addClient endpoint: เพิ่ม client ลงใน settings แล้ว update inbound ทั้งก้อน
        try:
            cur_settings = json.loads(inbound.get('settings') or '{}')
        except Exception:
            cur_settings = {}
        cur_settings.setdefault('clients', []).append(client)
        inbound['settings'] = json.dumps(cur_settings)
        result, err = xui_request('POST', f'xui/inbound/update/{inbound_id}', inbound)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        if result and result.get('success') is False:
            self._json(400, {'ok': False, 'error': result.get('msg', 'x-ui ปฏิเสธคำขอ')})
            return

        domain = get_domain() or '127.0.0.1'
        share_link = build_share_link(inbound, client, domain)

        self._json(200, {
            'ok': True, 'remark': remark, 'email': email, 'protocol': protocol,
            'client_uuid': client_uuid if protocol != 'trojan' else None,
            'trojan_password': trojan_password if protocol == 'trojan' else None,
            'gb': gb, 'days': days, 'share_link': share_link,
        })

    def _xui_load_inbound(self, inbound_id):
        listing, err = xui_request('POST', 'xui/inbound/list')
        if err:
            return None, None, err
        inbound = next((i for i in (listing.get('obj') or []) if int(i.get('id', -1)) == inbound_id), None)
        if not inbound:
            return None, None, 'ไม่พบ inbound นี้'
        try:
            settings = json.loads(inbound.get('settings') or '{}')
        except Exception:
            settings = {}
        return inbound, settings, None

    def _xui_save_inbound(self, inbound, settings):
        inbound['settings'] = json.dumps(settings)
        result, err = xui_request('POST', f"xui/inbound/update/{inbound['id']}", inbound)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return False
        if result and result.get('success') is False:
            self._json(400, {'ok': False, 'error': result.get('msg', 'x-ui ปฏิเสธคำขอ')})
            return False
        return True

    def _xui_update_client(self, data):
        try:
            inbound_id = int(data.get('inbound_id'))
        except (TypeError, ValueError):
            self._json(400, {'ok': False, 'error': 'invalid inbound_id'})
            return
        email = str(data.get('email', ''))
        inbound, settings, err = self._xui_load_inbound(inbound_id)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        cl = next((c for c in settings.get('clients', []) if c.get('email') == email), None)
        if not cl:
            self._json(404, {'ok': False, 'error': 'ไม่พบผู้ใช้นี้'})
            return
        try:
            cl['totalGB'] = int(max(0.0, float(data.get('gb', 0))) * 1024 ** 3)
        except (TypeError, ValueError):
            pass
        exp = str(data.get('expiry', '')).strip()
        if exp == '':
            cl['expiryTime'] = 0
        else:
            try:
                d = datetime.strptime(exp, '%Y-%m-%d') + timedelta(hours=23, minutes=59)
                cl['expiryTime'] = int(d.timestamp() * 1000)
            except ValueError:
                self._json(400, {'ok': False, 'error': 'รูปแบบวันที่ไม่ถูกต้อง'})
                return
        if 'enable' in data:
            cl['enable'] = bool(data.get('enable'))
        if not self._xui_save_inbound(inbound, settings):
            return
        self._json(200, {'ok': True})

    def _xui_delete_client(self, data):
        try:
            inbound_id = int(data.get('inbound_id'))
        except (TypeError, ValueError):
            self._json(400, {'ok': False, 'error': 'invalid inbound_id'})
            return
        email = str(data.get('email', ''))
        inbound, settings, err = self._xui_load_inbound(inbound_id)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        before = len(settings.get('clients', []))
        settings['clients'] = [c for c in settings.get('clients', []) if c.get('email') != email]
        if len(settings['clients']) == before:
            self._json(404, {'ok': False, 'error': 'ไม่พบผู้ใช้นี้'})
            return
        if not self._xui_save_inbound(inbound, settings):
            return
        self._json(200, {'ok': True})

    def _ssh_config_restart(self, data):
        svc = str(data.get('service', '')).strip()
        allowed = {'dropbear': 'dropbear', 'ws_ssh': 'xxtlonline-ws-ssh', 'ws_ovpn': 'xxtlonline-ws-ovpn'}
        unit = allowed.get(svc)
        if not unit:
            self._json(400, {'ok': False, 'error': 'service ต้องเป็น dropbear, ws_ssh หรือ ws_ovpn เท่านั้น'})
            return
        r = run(['systemctl', 'restart', unit], timeout=20)
        active = service_active(unit)
        if r.returncode != 0 or not active:
            self._json(500, {'ok': False, 'error': f'restart {unit} ไม่สำเร็จ — เช็ค: journalctl -u {unit} -n 50'})
            return
        self._json(200, {'ok': True})

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
        reserved_ports = {22, 80, 109, 143, 6789, 7300, 8443, get_xui_port()}
        if port < 1 or port > 65535:
            self._json(400, {'ok': False, 'error': 'port ต้องอยู่ระหว่าง 1-65535'})
            return
        if port in reserved_ports:
            self._json(400, {'ok': False, 'error': f'port {port} ถูกใช้งานโดยระบบอื่นอยู่แล้ว (เช่น dashboard/ssh/x-ui panel) เลือกพอร์ตอื่น'})
            return

        network = str(data.get('network', 'tcp')).strip().lower()
        if network not in ('tcp', 'ws', 'grpc', 'httpupgrade'):
            self._json(400, {'ok': False, 'error': 'network ต้องเป็น tcp, ws, grpc หรือ httpupgrade'})
            return

        security = str(data.get('security', 'tls')).strip().lower()
        if security not in ('tls', 'none'):
            self._json(400, {'ok': False, 'error': 'security ต้องเป็น tls หรือ none'})
            return

        base_name = re.sub(r'[^a-zA-Z0-9_-]', '', str(data.get('client_name', '')).strip().replace(' ', '_')) or remark.replace(' ', '_')
        client_email = base_name + '_' + secrets.token_hex(2)
        client_uuid = str(uuidlib.uuid4())
        trojan_password = secrets.token_urlsafe(12)

        if protocol == 'vless':
            settings = {
                'clients': [{'id': client_uuid, 'flow': '', 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True,
                             'tgId': '', 'subId': secrets.token_hex(8)}],
                'decryption': 'none', 'fallbacks': [],
            }
        elif protocol == 'vmess':
            settings = {
                'clients': [{'id': client_uuid, 'alterId': 0, 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True,
                             'tgId': '', 'subId': secrets.token_hex(8)}],
            }
        else:  # trojan
            settings = {
                'clients': [{'password': trojan_password, 'email': client_email,
                             'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'enable': True,
                             'tgId': '', 'subId': secrets.token_hex(8)}],
            }

        stream_settings = {'network': network}
        if security == 'tls':
            domain = get_domain()
            cert, key = get_cert_paths(domain)
            if not cert:
                self._json(400, {'ok': False, 'error': f'ยังไม่มี SSL certificate สำหรับ {domain} — ขอ SSL ก่อน (Settings > Renew Certificate) หรือเลือก security เป็น none'})
                return
            stream_settings['security'] = 'tls'
            sni = str(data.get('sni', '')).strip() or domain
            fp = str(data.get('fingerprint', '')).strip()
            alpn = [a.strip() for a in str(data.get('alpn', 'h2,http/1.1')).split(',') if a.strip()]
            stream_settings['tlsSettings'] = {
                'serverName': sni, 'minVersion': '1.2', 'maxVersion': '1.3',
                'cipherSuites': '', 'rejectUnknownSni': False, 'disableSystemRoot': False,
                'enableSessionResumption': False,
                'certificates': [{'certificateFile': cert, 'keyFile': key, 'ocspStapling': 3600}],
                'alpn': alpn,
                'settings': {'allowInsecure': False, 'fingerprint': fp},
            }
        else:
            stream_settings['security'] = 'none'

        ws_path = str(data.get('ws_path', '')).strip() or f'/{secrets.token_hex(4)}'
        grpc_service = str(data.get('grpc_service', '')).strip() or f'svc{secrets.token_hex(3)}'
        if network == 'tcp':
            stream_settings['tcpSettings'] = {'acceptProxyProtocol': False, 'header': {'type': 'none'}}
        elif network == 'ws':
            stream_settings['wsSettings'] = {'acceptProxyProtocol': False, 'path': ws_path,
                                            'headers': {'Host': str(data.get('host', '')).strip()} if data.get('host') else {}}
        elif network == 'grpc':
            stream_settings['grpcSettings'] = {'serviceName': grpc_service, 'multiMode': False}
        elif network == 'httpupgrade':
            stream_settings['httpupgradeSettings'] = {'path': ws_path, 'host': str(data.get('host', '')).strip()}

        payload = {
            'enable': True, 'remark': remark, 'listen': '', 'port': port,
            'protocol': protocol, 'expiryTime': 0, 'total': 0,
            'settings': settings, 'streamSettings': stream_settings,
            'sniffing': {'enabled': True, 'destOverride': ['http', 'tls', 'quic']},
        }

        # x-ui รับ settings/streamSettings/sniffing เป็น JSON string
        for _k in ('settings', 'streamSettings', 'sniffing'):
            if not isinstance(payload[_k], str):
                payload[_k] = json.dumps(payload[_k])
        payload.update({'up': 0, 'down': 0})
        result, err = xui_request('POST', 'xui/inbound/add', payload)
        if err:
            self._json(502, {'ok': False, 'error': err})
            return
        if result and result.get('success') is False:
            self._json(400, {'ok': False, 'error': result.get('msg', 'x-ui ปฏิเสธคำขอ ไม่ทราบสาเหตุ')})
            return

        # Build a client share link so the admin can copy/QR it immediately
        domain = get_domain() or '127.0.0.1'
        first = settings['clients'][0]
        share_link = build_share_link({'protocol': protocol, 'port': port, 'remark': remark,
                                       'streamSettings': json.dumps(stream_settings)}, first, domain)

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
        result, err = xui_request('POST', f'xui/inbound/del/{inbound_id}')
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
