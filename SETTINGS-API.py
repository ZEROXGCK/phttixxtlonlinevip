# ============================================================
# SETTINGS API ENDPOINTS — Add to xxtlonline-ssh-api/app.py
# ============================================================
# Copy these endpoints into the existing POST handler in app.py
# (Replace or merge with existing endpoints)
# ============================================================

# Add these imports at top of app.py:
# import hashlib, subprocess, time, psutil (if available)

# Add to do_GET handler:

elif self.path == '/api/settings/server':
    try:
        domain = open('/etc/xxtlonline/domain.conf').read().strip() if os.path.exists('/etc/xxtlonline/domain.conf') else ''
        my_ip = open('/etc/xxtlonline/my_ip.conf').read().strip() if os.path.exists('/etc/xxtlonline/my_ip.conf') else ''
        xui_port = open('/etc/xxtlonline/xui-port.conf').read().strip() if os.path.exists('/etc/xxtlonline/xui-port.conf') else ''
        xui_path = open('/etc/xxtlonline/xui-path.conf').read().strip() if os.path.exists('/etc/xxtlonline/xui-path.conf') else '/'
        respond(self, 200, {
            'domain': domain, 'server_ip': my_ip, 'xui_port': int(xui_port) if xui_port else 0,
            'xui_path': xui_path, 'ssh_port_1': 143, 'ssh_port_2': 109, 'udpgw_port': 7300
        })
    except Exception as e:
        respond(self, 200, {'error': str(e)})

elif self.path == '/api/settings/system':
    try:
        _, uptime_out, _ = run_cmd("uptime -p | sed 's/up //'")
        _, kernel, _ = run_cmd("uname -r")
        _, disk_usage, _ = run_cmd("df -h / | tail -1 | awk '{print $5}'")
        respond(self, 200, {
            'uptime': uptime_out.strip(), 'kernel': kernel.strip(), 
            'disk_usage': disk_usage.strip(),
            'installed_services': ['ssh', 'dropbear', 'nginx', 'x-ui', 'badvpn', 'sshws', 'ssh-api']
        })
    except Exception as e:
        respond(self, 200, {'error': str(e)})

elif self.path == '/api/settings/network':
    try:
        _, sysctl_bbr, _ = run_cmd("sysctl net.ipv4.tcp_congestion_control | awk -F= '{print $2}' | xargs")
        _, sysctl_qdisc, _ = run_cmd("sysctl net.core.default_qdisc | awk -F= '{print $2}' | xargs")
        _, sysctl_rmem, _ = run_cmd("sysctl net.core.rmem_max | awk -F= '{print $2}' | xargs")
        respond(self, 200, {
            'congestion_control': sysctl_bbr.strip() or 'bbr',
            'qdisc': sysctl_qdisc.strip() or 'fq',
            'rmem_max': sysctl_rmem.strip() or '67108864',
            'tuning_profile': 'optimized-for-tunneling'
        })
    except Exception as e:
        respond(self, 200, {'error': str(e)})

elif self.path == '/api/settings/ssl':
    try:
        cert_info = {}
        r = subprocess.run(['certbot', 'certificates', '--format', 'json'], 
                          capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            import json as jsonlib
            certs = jsonlib.loads(r.stdout).get('certificates', [])
            if certs:
                cert = certs[0]
                cert_info = {
                    'domain': cert.get('domains', [None])[0],
                    'expiry': cert.get('expiry_date', ''),
                    'issued': cert.get('issued_date', ''),
                    'auto_renewal': True
                }
        respond(self, 200, cert_info or {'status': 'no_certificate', 'auto_renewal': False})
    except Exception as e:
        respond(self, 200, {'error': str(e)})

elif self.path == '/api/settings/firewall':
    try:
        _, ufw_status, _ = run_cmd("ufw status | head -1")
        _, rules, _ = run_cmd("ufw status numbered 2>/dev/null | grep ALLOW | awk '{print $2}' | cut -d'/' -f1 | sort -u | tr '\\n' ','")
        respond(self, 200, {
            'status': 'enabled' if 'active' in ufw_status.lower() else 'disabled',
            'allowed_ports': [p for p in rules.strip(',').split(',') if p],
            'default_incoming': 'deny',
            'default_outgoing': 'allow'
        })
    except Exception as e:
        respond(self, 200, {'error': str(e)})

elif self.path == '/api/settings/backup':
    try:
        _, backups, _ = run_cmd("ls -1 /root/xxtlonline-backup-*.tar.gz 2>/dev/null | head -10")
        backup_list = [{'file': os.path.basename(b), 'path': b, 'size': os.path.getsize(b)} 
                      for b in backups.strip().split('\n') if os.path.exists(b)]
        respond(self, 200, {'backups': backup_list})
    except Exception as e:
        respond(self, 200, {'error': str(e)})

# Add to do_POST handler:

elif self.path == '/api/settings/password-change':
    user = data.get('user', '').strip()
    new_pass = data.get('new_password', '').strip()
    old_pass = data.get('old_password', '').strip()
    if not user or not new_pass:
        return respond(self, 400, {'error': 'user and new_password required'})
    # Verify old password if changing admin
    if user == 'admin':
        su = open('/etc/xxtlonline/xui-user.conf').read().strip() if os.path.exists('/etc/xxtlonline/xui-user.conf') else ''
        sp = open('/etc/xxtlonline/xui-pass.conf').read().strip() if os.path.exists('/etc/xxtlonline/xui-pass.conf') else ''
        if old_pass != sp:
            return respond(self, 401, {'error': 'incorrect old password'})
    # Update password
    with open('/etc/xxtlonline/xui-pass.conf', 'w') as f:
        f.write(new_pass)
    respond(self, 200, {'ok': True, 'message': 'Password changed successfully'})

elif self.path == '/api/settings/domain-change':
    new_domain = data.get('domain', '').strip()
    if not new_domain:
        return respond(self, 400, {'error': 'domain required'})
    with open('/etc/xxtlonline/domain.conf', 'w') as f:
        f.write(new_domain)
    respond(self, 200, {'ok': True, 'domain': new_domain})

elif self.path == '/api/settings/backup-now':
    try:
        backup_file = f"/root/xxtlonline-backup-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz"
        cmd = f"tar -czf {backup_file} /etc/xxtlonline /etc/x-ui/x-ui.db /opt/xxtlonline-panel /opt/xxtlonline-ssh-api /etc/letsencrypt/live 2>/dev/null || true"
        ok, _, err = run_cmd(cmd)
        if os.path.exists(backup_file):
            size = os.path.getsize(backup_file)
            respond(self, 200, {'ok': True, 'file': backup_file, 'size': size})
        else:
            respond(self, 200, {'ok': False, 'error': 'backup failed'})
    except Exception as e:
        respond(self, 200, {'ok': False, 'error': str(e)})

elif self.path == '/api/settings/service-action':
    service = data.get('service', '').strip()
    action = data.get('action', '').strip()  # start, stop, restart
    if not service or action not in ['start', 'stop', 'restart']:
        return respond(self, 400, {'error': 'service and action (start/stop/restart) required'})
    ok, out, err = run_cmd(f"sudo systemctl {action} {service}")
    time.sleep(2)
    state = subprocess.run(['systemctl', 'is-active', service], capture_output=True, text=True).stdout.strip()
    respond(self, 200, {'ok': ok, 'service': service, 'action': action, 'state': state})

elif self.path == '/api/settings/network-tuning':
    param = data.get('param', '').strip()
    value = data.get('value', '').strip()
    if not param or not value:
        return respond(self, 400, {'error': 'param and value required'})
    # Whitelist safe parameters
    safe_params = [
        'net.ipv4.tcp_rmem',
        'net.ipv4.tcp_wmem',
        'net.core.rmem_max',
        'net.core.wmem_max',
        'net.core.netdev_max_backlog',
        'net.ipv4.tcp_fastopen',
    ]
    if param not in safe_params:
        return respond(self, 400, {'error': f'param {param} not allowed'})
    ok, out, err = run_cmd(f"sysctl -w {param}={value}")
    if ok:
        # Persist to /etc/sysctl.d/
        run_cmd(f"echo '{param}={value}' >> /etc/sysctl.d/99-xxtlonline-network-tune.conf")
    respond(self, 200, {'ok': ok, 'param': param, 'value': value})

elif self.path == '/api/settings/firewall-action':
    action = data.get('action', '').strip()  # allow, deny, reset
    port = data.get('port', '')
    proto = data.get('proto', 'tcp').lower()  # tcp or udp
    if action == 'allow':
        if not port:
            return respond(self, 400, {'error': 'port required for allow action'})
        ok, _, _ = run_cmd(f"ufw allow {port}/{proto}")
        respond(self, 200, {'ok': ok, 'action': 'allow', 'port': port, 'proto': proto})
    elif action == 'deny':
        if not port:
            return respond(self, 400, {'error': 'port required for deny action'})
        ok, _, _ = run_cmd(f"ufw deny {port}/{proto}")
        respond(self, 200, {'ok': ok, 'action': 'deny', 'port': port, 'proto': proto})
    elif action == 'enable':
        ok, _, _ = run_cmd("ufw --force enable")
        respond(self, 200, {'ok': ok, 'action': 'enable'})
    elif action == 'disable':
        ok, _, _ = run_cmd("echo y | ufw disable")
        respond(self, 200, {'ok': ok, 'action': 'disable'})
    else:
        respond(self, 400, {'error': 'invalid action'})

elif self.path == '/api/settings/ssl-renew':
    try:
        run_cmd("systemctl stop nginx xxtlonline-sshws")
        time.sleep(2)
        ok, out, err = run_cmd("certbot renew --force-renewal")
        run_cmd("systemctl start nginx xxtlonline-sshws")
        respond(self, 200, {'ok': ok, 'message': 'SSL renewal attempt complete'})
    except Exception as e:
        respond(self, 200, {'ok': False, 'error': str(e)})

elif self.path == '/api/settings/logs':
    service = data.get('service', '').strip()
    lines = int(data.get('lines', 50))
    if not service:
        return respond(self, 400, {'error': 'service required'})
    _, log_out, _ = run_cmd(f"journalctl -u {service} -n {lines} --no-pager")
    respond(self, 200, {'service': service, 'logs': log_out.strip().split('\n') if log_out else []})

elif self.path == '/api/settings/theme':
    theme = data.get('theme', '').strip()
    valid_themes = ['dark-purple', 'neon-pink', 'forest', 'ocean']
    if theme not in valid_themes:
        return respond(self, 400, {'error': f'invalid theme. valid: {",".join(valid_themes)}'})
    # This would require updating CSS in dashboard files
    # For now, just store preference
    with open('/etc/xxtlonline/ui-theme.conf', 'w') as f:
        f.write(theme)
    respond(self, 200, {'ok': True, 'theme': theme})

# ============================================================
# END OF NEW ENDPOINTS
# ============================================================
# 
# USAGE:
# 1. Copy these functions into existing app.py
# 2. Add necessary imports at top
# 3. Restart service: sudo systemctl restart xxtlonline-ssh-api
#
# API Calls from Frontend:
# GET /api/settings/server       - Server config
# GET /api/settings/system       - System info
# GET /api/settings/network      - Network tuning
# GET /api/settings/ssl          - SSL certificate
# GET /api/settings/firewall     - Firewall status
# GET /api/settings/backup       - Backup list
# POST /api/settings/password-change    - Change admin password
# POST /api/settings/domain-change      - Change domain
# POST /api/settings/backup-now         - Create backup
# POST /api/settings/service-action     - Start/stop/restart service
# POST /api/settings/network-tuning     - Adjust network params
# POST /api/settings/firewall-action    - Manage firewall rules
# POST /api/settings/ssl-renew          - Renew SSL cert
# POST /api/settings/logs               - Get service logs
# POST /api/settings/theme              - Change UI theme
