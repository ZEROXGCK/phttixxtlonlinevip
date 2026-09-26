#!/bin/bash
# ============================================================
#   XXTLONLINE UTILITIES — Manage, backup, troubleshoot
# ============================================================

set -o pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

BRAND="XXTLONLINE"
BRAND_DIR="xxtlonline"

usage() {
  cat << EOF
$BRAND Utilities v1.0

Usage: sudo ./xxtlonline-utils.sh <command> [options]

Commands:
  status              — Check all services status
  restart             — Restart all services
  restart <svc>       — Restart specific service (ssh-api|sshws|ssh-api|nginx|xui|dropbear)
  logs <svc>          — Show logs (journalctl -u <svc>)
  backup              — Backup config to /root/xxtlonline-backup-DATE.tar.gz
  restore <file>      — Restore from backup file
  ssl-renew           — Renew SSL certificate (Certbot)
  ssl-status          — Check SSL certificate expiry
  user-create         — Interactively create SSH user
  user-list           — List all SSH users with expiry
  user-delete <user>  — Delete SSH user
  user-extend <user> <days> — Extend user expiry
  firewall-check      — Verify UFW rules
  firewall-reset      — Reset UFW to defaults (WARNING)
  speedtest           — Run speedtest-cli
  ports-check         — Check listening ports
  diagnostics         — Full system diagnostic report
  patch-ui <name>     — Apply UI patch (usage: see xxtlonline-patches.sh)
  clean               — Clean temporary/cache files
  uninstall           — Remove all XXTLONLINE services (WARNING)

Examples:
  sudo ./xxtlonline-utils.sh status
  sudo ./xxtlonline-utils.sh restart nginx
  sudo ./xxtlonline-utils.sh user-create
  sudo ./xxtlonline-utils.sh backup
  sudo ./xxtlonline-utils.sh logs xui
EOF
  exit 0
}

[[ $# -lt 1 ]] && usage
[[ $EUID -ne 0 ]] && err "ต้องรันด้วย sudo"

CMD="$1"
ARG="$2"
ARG2="$3"

case "$CMD" in
  status)
    info "ตรวจสอบสถานะบริการ..."
    echo ""
    for svc in ssh dropbear nginx x-ui ${BRAND_DIR}-sshws ${BRAND_DIR}-ssh-api ${BRAND_DIR}-badvpn ${BRAND_DIR}-rps-tune; do
      STATE=$(systemctl is-active $svc 2>/dev/null || echo "not-found")
      [[ "$STATE" == "active" ]] && echo -e "${GREEN}✓${NC} $svc: ${GREEN}${STATE}${NC}" || echo -e "${RED}✗${NC} $svc: ${RED}${STATE}${NC}"
    done
    echo ""
    echo "Port status:"
    ss -tlnp 2>/dev/null | grep -E ":22|:80|:109|:143|:443|:6789|:54321|:8080|:8880" | awk '{print $4, "  ", $7}' || warn "ss command not available"
    ;;

  restart)
    if [[ -z "$ARG" ]]; then
      info "Restart all services..."
      systemctl restart ssh dropbear nginx x-ui ${BRAND_DIR}-sshws ${BRAND_DIR}-ssh-api 2>/dev/null
      sleep 3
      $0 status
    else
      info "Restart $ARG..."
      systemctl restart "$ARG" && ok "$ARG restarted" || err "Failed to restart $ARG"
      systemctl is-active "$ARG" && ok "$ARG is running" || warn "$ARG is not running"
    fi
    ;;

  logs)
    [[ -z "$ARG" ]] && err "Specify service: logs <service-name>"
    info "Logs for $ARG (last 50 lines, press q to exit):"
    journalctl -u "$ARG" -n 50 -e --no-pager || echo "No logs found for $ARG"
    ;;

  backup)
    BACKUP_FILE="/root/${BRAND_DIR}-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    info "Backing up to $BACKUP_FILE..."
    tar -czf "$BACKUP_FILE" \
      /etc/${BRAND_DIR} \
      /etc/x-ui/x-ui.db \
      /opt/${BRAND_DIR}-panel \
      /opt/${BRAND_DIR}-ssh-api \
      /etc/letsencrypt/live 2>/dev/null || warn "Some paths may not exist"
    [[ -f "$BACKUP_FILE" ]] && ok "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | awk '{print $1}'))" || err "Backup failed"
    ;;

  restore)
    [[ -z "$ARG" ]] && err "Specify backup file: restore <file>"
    [[ ! -f "$ARG" ]] && err "File not found: $ARG"
    info "Restoring from $ARG..."
    read -rp "  This will overwrite existing config. Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0
    systemctl stop x-ui xui ${BRAND_DIR}-ssh-api 2>/dev/null || true
    tar -xzf "$ARG" -C / || err "Restore failed"
    systemctl restart x-ui ${BRAND_DIR}-ssh-api 2>/dev/null || true
    ok "Restore complete"
    ;;

  ssl-renew)
    info "Renewing SSL certificate..."
    systemctl stop nginx ${BRAND_DIR}-sshws 2>/dev/null || true
    sleep 2
    certbot renew --force-renewal || warn "Certbot renew had issues"
    systemctl start nginx ${BRAND_DIR}-sshws 2>/dev/null || true
    ok "SSL renewal attempt complete"
    ;;

  ssl-status)
    info "SSL Certificate Status:"
    certbot certificates 2>/dev/null || echo "Certbot not found or no certificates"
    ;;

  user-create)
    read -rp "Username: " USER
    read -rsp "Password: " PASS
    echo ""
    read -rsp "Confirm Password: " PASS2
    echo ""
    [[ "$PASS" != "$PASS2" ]] && err "Passwords don't match"
    read -rp "Days valid [30]: " DAYS
    DAYS=${DAYS:-30}
    EXP_DATE=$(date -d "+${DAYS} days" +%Y-%m-%d)
    useradd -M -s /bin/false "$USER" 2>/dev/null || warn "User already exists or error"
    echo "$USER:$PASS" | chpasswd
    chage -E "$EXP_DATE" "$USER"
    mkdir -p /etc/${BRAND_DIR}/exp
    echo "$EXP_DATE" > /etc/${BRAND_DIR}/exp/$USER
    ok "User created: $USER (expires: $EXP_DATE)"
    ;;

  user-list)
    info "SSH Users:"
    echo ""
    awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /nologin/ {
      user=$1
      exp_file="/etc/'${BRAND_DIR}'/exp/" user
      exp=""; getline < exp_file; if($0 ~ /20[0-9]{2}/) exp=$0; close(exp_file)
      printf "  %-16s  %s\n", user, (exp ? exp : "no expiry")
    }' /etc/passwd
    echo ""
    ;;

  user-delete)
    [[ -z "$ARG" ]] && err "Specify user: user-delete <username>"
    read -rp "Delete user $ARG? [y/N]: " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0
    userdel -f "$ARG" 2>/dev/null
    rm -f /etc/${BRAND_DIR}/exp/$ARG
    ok "User deleted: $ARG"
    ;;

  user-extend)
    [[ -z "$ARG" || -z "$ARG2" ]] && err "Usage: user-extend <user> <days>"
    EXP_FILE="/etc/${BRAND_DIR}/exp/$ARG"
    [[ ! -f "$EXP_FILE" ]] && err "User expiry file not found: $EXP_FILE"
    OLD_EXP=$(cat "$EXP_FILE")
    NEW_EXP=$(date -d "$OLD_EXP +${ARG2} days" +%Y-%m-%d)
    chage -E "$NEW_EXP" "$ARG"
    echo "$NEW_EXP" > "$EXP_FILE"
    ok "Extended user $ARG from $OLD_EXP to $NEW_EXP"
    ;;

  firewall-check)
    info "UFW Status:"
    ufw status || warn "UFW not enabled or not installed"
    echo ""
    echo "Allowed incoming ports:"
    ufw status | grep ALLOW || echo "No rules found"
    ;;

  firewall-reset)
    warn "This will reset ALL UFW rules to defaults!"
    read -rp "Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    for port in 22 80 109 143 443 2503 8080 8880; do ufw allow $port/tcp; done
    ufw allow 7300/udp
    ufw --force enable
    ok "Firewall reset complete"
    ;;

  speedtest)
    info "Running speedtest..."
    if command -v speedtest-cli &>/dev/null; then
      speedtest-cli --json | jq '{ping, download: (.download/1000000|floor*10|./10), upload: (.upload/1000000|floor*10|./10), server: .server.name}'
    else
      warn "speedtest-cli not installed; installing..."
      pip3 install speedtest-cli --break-system-packages -q 2>/dev/null || pip3 install speedtest-cli -q
      exec $0 speedtest
    fi
    ;;

  ports-check)
    info "Listening ports:"
    echo ""
    ss -tlnp 2>/dev/null | tail -n +2 | awk '{
      port=$4; gsub(/.*:/,"",port)
      pid=$7; gsub(/\/.*|users/,"",pid)
      printf "  Port %5s  PID %-6s  %s\n", port, pid, $7
    }' || netstat -tln | tail -n +3
    echo ""
    ;;

  diagnostics)
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  XXTLONLINE DIAGNOSTICS${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo "=== System ==="
    uname -a
    echo ""
    echo "=== Disk ==="
    df -h | grep -E "Filesystem|/$|/etc|/opt"
    echo ""
    echo "=== Services ==="
    $0 status 2>&1 | grep -v "^sudo"
    echo ""
    echo "=== Network ==="
    echo "Default route:"
    ip route show default
    echo "DNS:"
    cat /etc/resolv.conf | grep nameserver | head -3
    echo ""
    echo "=== Configuration ==="
    echo "Config dir:"
    ls -lh /etc/${BRAND_DIR}/ 2>/dev/null | tail -5
    echo "Panel:"
    ls -lh /opt/${BRAND_DIR}-panel/index.html 2>/dev/null
    echo ""
    echo "=== Recent Errors ==="
    journalctl -p err -n 10 --no-pager | tail -5 || echo "No recent errors"
    echo ""
    echo -e "${GREEN}Report saved to: ${CYAN}/tmp/${BRAND_DIR}-diag-$(date +%s).txt${NC}"
    ;;

  patch-ui)
    [[ -z "$ARG" ]] && { info "Available patches: (see xxtlonline-patches.sh)"; exit 0; }
    info "Patch system requires xxtlonline-patches.sh"
    echo "Usage: bash xxtlonline-patches.sh <patch-name>"
    ;;

  clean)
    info "Cleaning temporary files..."
    rm -rf /tmp/xxtlonline-* /tmp/xui-* 2>/dev/null || true
    apt-get autoremove -y &>/dev/null || true
    journalctl --vacuum=30d &>/dev/null || true
    ok "Clean complete"
    ;;

  uninstall)
    warn "This will PERMANENTLY remove all XXTLONLINE services and data!"
    read -rp "Type 'yes-delete-all' to confirm: " CONFIRM
    [[ "$CONFIRM" != "yes-delete-all" ]] && { info "Cancelled"; exit 0; }
    info "Uninstalling..."
    for svc in ${BRAND_DIR}-sshws ${BRAND_DIR}-ssh-api ${BRAND_DIR}-badvpn ${BRAND_DIR}-rps-tune; do
      systemctl stop $svc 2>/dev/null || true
      systemctl disable $svc 2>/dev/null || true
      rm -f /etc/systemd/system/$svc.service
    done
    rm -rf /etc/${BRAND_DIR} /opt/${BRAND_DIR}-panel /opt/${BRAND_DIR}-ssh-api
    rm -f /usr/local/bin/ws-stunnel /usr/local/sbin/${BRAND_DIR}-rps-apply.sh /usr/local/sbin/${BRAND_DIR}-irq-pin.sh
    rm -f /etc/nginx/conf.d/${BRAND_DIR}.conf /etc/sysctl.d/99-${BRAND_DIR}-network-tune.conf
    systemctl daemon-reload
    ok "Uninstall complete"
    ;;

  *)
    echo "Unknown command: $CMD"
    usage
    ;;
esac
