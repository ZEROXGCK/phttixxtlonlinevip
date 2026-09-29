#!/bin/bash
# ============================================================
#   XXTLONLINE UI PATCHES — Customize dashboard & branding
# ============================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

BRAND_DIR="xxtlonline"
PANEL_DIR="/opt/${BRAND_DIR}-panel"
DASHBOARD="$PANEL_DIR/dashboard.html"

[[ ! -d "$PANEL_DIR" ]] && err "Panel directory not found: $PANEL_DIR"

usage() {
  cat << EOF
XXTLONLINE UI Patches v1.0

Usage: sudo bash xxtlonline-patches.sh <patch-name> [options]

Available Patches:
  color-dark-purple   — Change theme to dark purple (default)
  color-neon-pink     — Neon pink + cyan (cyber theme)
  color-forest        — Forest green + cream
  color-ocean         — Ocean blue + teal
  
  logo-change <name>  — Change logo text (e.g., "MY VPN PANEL")
  
  custom-css <file>   — Apply custom CSS file
  
  list                — Show installed patches
  restore             — Restore default theme
  backup              — Backup current theme

Examples:
  sudo bash xxtlonline-patches.sh color-neon-pink
  sudo bash xxtlonline-patches.sh logo-change "COMPANY VPN"
  sudo bash xxtlonline-patches.sh custom-css ./my-theme.css
EOF
  exit 0
}

[[ $# -lt 1 ]] && usage
[[ $EUID -ne 0 ]] && err "Run with sudo"

PATCH="$1"
PARG="$2"

# ── BACKUP CURRENT ──────────────────────────────────
backup_theme() {
  local backup_file="${PANEL_DIR}/theme-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$backup_file" "$DASHBOARD" "/opt/${BRAND_DIR}-panel/index.html" 2>/dev/null || true
  ok "Backup created: $backup_file"
}

# ── RESTORE DEFAULT ────────────────────────────────
restore_default() {
  info "Restoring default XXTLONLINE theme..."
  # Restore from package (or regenerate if not possible)
  # For now, reset to shipped version
  cat > "$DASHBOARD" << 'DASHEOF'
<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>XXTLONLINE — Dashboard</title>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@500;600;700;800&family=Sarabun:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  :root{--primary:#7c6cf6;--primary-dark:#5b4fd6;--accent:#8fe3d0;--bg:#f6f5fb;--card:#fff;--text:#2d2a45;--muted:#8b87a3;--border:#ece9f7;--good:#3dcf8e;--bad:#f2607a;}
  *{margin:0;padding:0;box-sizing:border-box;}
  body{font-family:'Sarabun',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;padding-bottom:40px;}
  .wrap{max-width:480px;margin:0 auto;}
  .hdr{background:linear-gradient(135deg,var(--primary),var(--primary-dark));padding:22px 20px 26px;color:#fff;border-radius:0 0 24px 24px;}
  .hdr-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;}
  .hdr-brand{font-family:'Poppins',sans-serif;font-weight:800;font-size:1.2rem;}
  .logout{background:rgba(255,255,255,.18);border:none;border-radius:8px;padding:6px 12px;font-size:.72rem;color:#fff;cursor:pointer;}
  .hdr-sub{font-size:.78rem;opacity:.85;}
  .content{padding:16px;}
  .card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:16px;margin-bottom:12px;box-shadow:0 4px 16px rgba(90,80,180,.06);}
  .card-title{font-family:'Poppins',sans-serif;font-size:.72rem;letter-spacing:1.5px;color:var(--muted);text-transform:uppercase;margin-bottom:12px;}
  .grid2{display:grid;grid-template-columns:1fr 1fr;gap:10px;}
  .stat{background:#faf9ff;border-radius:12px;padding:12px;text-align:center;}
  .stat-val{font-family:'Poppins',sans-serif;font-weight:700;font-size:1.3rem;color:var(--text);}
  .stat-lbl{font-size:.68rem;color:var(--muted);margin-top:2px;}
  .svc-row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid var(--border);font-size:.85rem;}
  .svc-row:last-child{border-bottom:none;}
  .dot{width:8px;height:8px;border-radius:50%;background:var(--good);display:inline-block;margin-right:8px;}
  .dot.off{background:var(--bad);}
  .btn{width:100%;padding:12px;border:none;border-radius:12px;font-size:.9rem;font-weight:600;cursor:pointer;font-family:'Sarabun',sans-serif;}
  .btn-primary{background:linear-gradient(135deg,var(--primary),var(--primary-dark));color:#fff;}
  .btn-outline{background:#faf9ff;border:1px solid var(--border);color:var(--text);}
  .field-input{width:100%;background:#faf9ff;border:1.5px solid var(--border);border-radius:10px;padding:10px 12px;font-size:.85rem;margin-bottom:8px;font-family:'Sarabun',sans-serif;}
  .user-item{display:flex;justify-content:space-between;align-items:center;padding:10px;background:#faf9ff;border-radius:10px;margin-bottom:8px;font-size:.82rem;}
  .badge{font-size:.65rem;padding:2px 8px;border-radius:20px;font-weight:600;}
  .badge-ok{background:rgba(61,207,142,.12);color:var(--good);}
  .badge-exp{background:rgba(242,96,122,.12);color:var(--bad);}
  .del-btn{background:none;border:none;color:var(--bad);cursor:pointer;font-size:.8rem;}
</style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <div class="hdr-top">
      <div class="hdr-brand">XXTLONLINE</div>
      <button class="logout" onclick="doLogout()">ออกจากระบบ</button>
    </div>
    <div class="hdr-sub" id="hostLabel">กำลังโหลด...</div>
  </div>
  <div class="content">
    <div class="card">
      <div class="card-title">สถานะระบบ</div>
      <div class="grid2">
        <div class="stat"><div class="stat-val" id="connCount">-</div><div class="stat-lbl">Active Connections</div></div>
        <div class="stat"><div class="stat-val" id="userCount">-</div><div class="stat-lbl">SSH Users</div></div>
      </div>
    </div>
    <div class="card">
      <div class="card-title">บริการ</div>
      <div id="svcList"></div>
    </div>
    <div class="card">
      <div class="card-title">สร้างบัญชี SSH</div>
      <input class="field-input" id="newUser" placeholder="Username">
      <input class="field-input" id="newPass" type="password" placeholder="Password">
      <input class="field-input" id="newDays" type="number" placeholder="จำนวนวัน (เช่น 30)" value="30">
      <button class="btn btn-primary" onclick="createUser()">+ สร้างบัญชี</button>
    </div>
    <div class="card">
      <div class="card-title">รายชื่อผู้ใช้ SSH</div>
      <div id="userList">กำลังโหลด...</div>
    </div>
    <button class="btn btn-outline" onclick="openXui()">เปิดแผงควบคุม 3x-ui</button>
  </div>
</div>
<script>
function doLogout(){ sessionStorage.removeItem('xxtl_auth'); location.replace('index.html'); }
(function checkAuth(){
  const raw = sessionStorage.getItem('xxtl_auth');
  if(!raw){ location.replace('index.html'); return; }
  try{ const d = JSON.parse(raw); if(Date.now() > d.exp){ location.replace('index.html'); } }
  catch(e){ location.replace('index.html'); }
})();
async function loadInfo(){
  try{
    const r = await fetch('/api/info'); const d = await r.json();
    document.getElementById('hostLabel').textContent = d.host || '';
  }catch(e){}
}
async function loadStatus(){
  try{
    const r = await fetch('/api/status'); const d = await r.json();
    document.getElementById('connCount').textContent = d.connections ?? 0;
    document.getElementById('userCount').textContent = d.total_users ?? 0;
    const svc = d.services || {};
    const names = {ssh:'SSH',dropbear:'Dropbear',nginx:'Nginx',badvpn:'BadVPN',sshws:'WS-Stunnel',xui:'3x-ui'};
    let html = '';
    for(const k in names){
      const on = !!svc[k];
      html += `<div class="svc-row"><span><span class="dot ${on?'':'off'}"></span>${names[k]}</span><span>${on?'ทำงาน':'หยุด'}</span></div>`;
    }
    document.getElementById('svcList').innerHTML = html;
  }catch(e){}
}
async function loadUsers(){
  try{
    const r = await fetch('/api/users'); const d = await r.json();
    const list = d.users || [];
    if(list.length === 0){ document.getElementById('userList').innerHTML = '<div style="color:var(--muted);font-size:.82rem">ยังไม่มีผู้ใช้</div>'; return; }
    let html = '';
    list.forEach(u => {
      html += `<div class="user-item"><span>${u.user}<br><span class="badge ${u.active?'badge-ok':'badge-exp'}">${u.exp || '-'}</span></span><button class="del-btn" onclick="delUser('${u.user}')">ลบ</button></div>`;
    });
    document.getElementById('userList').innerHTML = html;
  }catch(e){}
}
async function createUser(){
  const user = document.getElementById('newUser').value.trim();
  const pass = document.getElementById('newPass').value.trim();
  const days = parseInt(document.getElementById('newDays').value || '30');
  if(!user || !pass){ alert('กรุณากรอก Username และ Password'); return; }
  try{
    const r = await fetch('/api/create_ssh', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({user, password: pass, days})});
    const d = await r.json();
    if(d.ok){ document.getElementById('newUser').value=''; document.getElementById('newPass').value=''; loadUsers(); loadStatus(); }
    else alert('สร้างไม่สำเร็จ: ' + (d.error || ''));
  }catch(e){ alert('ผิดพลาด: ' + e.message); }
}
async function delUser(user){
  if(!confirm(`ลบผู้ใช้ ${user}?`)) return;
  try{ await fetch('/api/delete_ssh', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({user})}); loadUsers(); loadStatus(); }
  catch(e){ alert('ผิดพลาด: ' + e.message); }
}
function openXui(){ window.open('/xui-api/', '_blank'); }
loadInfo(); loadStatus(); loadUsers();
setInterval(loadStatus, 15000);
</script>
</body>
</html>
DASHEOF
  ok "Default theme restored"
}

case "$PATCH" in
  color-dark-purple)
    backup_theme
    info "Applying dark purple theme..."
    python3 << 'PYEOF'
import re
dashboard = open("/opt/xxtlonline-panel/dashboard.html").read()
theme = {
  "--primary": "#7c6cf6",
  "--primary-dark": "#5b4fd6",
  "--accent": "#8fe3d0",
  "--bg": "#f6f5fb",
  "--card": "#fff",
}
root = dashboard[dashboard.find(":root{"):dashboard.find("}",dashboard.find(":root{"))+1]
for k,v in theme.items():
  root = re.sub(f"{k}:#[0-9a-f]+", f"{k}:{v}", root)
dashboard = dashboard.replace(dashboard[dashboard.find(":root{"):dashboard.find("}",dashboard.find(":root{"))+1], root)
open("/opt/xxtlonline-panel/dashboard.html", "w").write(dashboard)
PYEOF
    ok "Dark purple theme applied"
    ;;

  color-neon-pink)
    backup_theme
    info "Applying neon pink + cyan theme..."
    sed -i 's/--primary:#7c6cf6/--primary:#ff006e/g; s/--primary-dark:#5b4fd6/--primary-dark:#c2185b/g; s/--accent:#8fe3d0/--accent:#00d9ff/g; s/--bg:#f6f5fb/--bg:#0a0e27/g; s/--card:#fff/--card:#1a1f3a/g; s/--text:#2d2a45/--text:#f0f0f0/g; s/--muted:#8b87a3/--muted:#b0b0b0/g; s/--border:#ece9f7/--border:#2a2f4a/g' "$DASHBOARD"
    ok "Neon pink + cyan theme applied"
    ;;

  color-forest)
    backup_theme
    info "Applying forest green theme..."
    sed -i 's/--primary:#7c6cf6/--primary:#2d5016/g; s/--primary-dark:#5b4fd6/--primary-dark:#1a3a0a/g; s/--accent:#8fe3d0/--accent:#a8dadc/g; s/--bg:#f6f5fb/--bg:#f0efed/g; s/--card:#fff/--card:#fefdf9/g; s/--text:#2d2a45/--text:#1b5e20/g; s/--muted:#8b87a3/--muted:#558b2f/g; s/--border:#ece9f7/--border:#c5e1a5/g' "$DASHBOARD"
    ok "Forest green theme applied"
    ;;

  color-ocean)
    backup_theme
    info "Applying ocean blue theme..."
    sed -i 's/--primary:#7c6cf6/--primary:#0277bd/g; s/--primary-dark:#5b4fd6/--primary-dark:#01579b/g; s/--accent:#8fe3d0/--accent:#80deea/g; s/--bg:#f6f5fb/--bg:#e0f2f1/g; s/--card:#fff/--card:#ffffff/g; s/--text:#2d2a45/--text:#00695c/g; s/--muted:#8b87a3/--muted:#00897b/g; s/--border:#ece9f7/--border:#b2dfdb/g' "$DASHBOARD"
    ok "Ocean blue theme applied"
    ;;

  logo-change)
    [[ -z "$PARG" ]] && err "Usage: logo-change <new-logo-text>"
    backup_theme
    info "Changing logo to: $PARG"
    sed -i "s/<div class=\"hdr-brand\">XXTLONLINE<\/div>/<div class=\"hdr-brand\">$PARG<\/div>/g" "$DASHBOARD"
    sed -i "s/<div class=\"brand-name\">XXTL<span>ONLINE<\/span><\/div>/<div class=\"brand-name\">$PARG<\/div>/g" "$PANEL_DIR/index.html"
    ok "Logo changed to: $PARG"
    ;;

  custom-css)
    [[ -z "$PARG" ]] && err "Usage: custom-css <css-file>"
    [[ ! -f "$PARG" ]] && err "CSS file not found: $PARG"
    backup_theme
    info "Applying custom CSS from: $PARG"
    CUSTOM=$(cat "$PARG")
    python3 << PYEOF
import re
html = open("$DASHBOARD").read()
style_start = html.find("<style>") + 7
style_end = html.find("</style>")
html = html[:style_end] + "\n$CUSTOM\n" + html[style_end:]
open("$DASHBOARD", "w").write(html)
PYEOF
    ok "Custom CSS applied"
    ;;

  list)
    info "Installed patches / themes:"
    echo ""
    echo "  color-dark-purple   — Purple & teal (default)"
    echo "  color-neon-pink     — Neon pink & cyan"
    echo "  color-forest        — Forest green"
    echo "  color-ocean         — Ocean blue"
    echo ""
    echo "Current theme:"
    grep -o "^[[:space:]]*--primary:[^;]*" "$DASHBOARD" | head -1 | xargs
    ;;

  restore)
    restore_default
    ;;

  backup)
    backup_theme
    ;;

  *)
    echo "Unknown patch: $PATCH"
    usage
    ;;
esac

echo ""
ok "Reload dashboard in browser (Ctrl+F5) to see changes"
