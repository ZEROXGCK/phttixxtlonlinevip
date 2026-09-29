# XXTLONLINE SSH API Reference

**REST API for managing SSH users, checking system status, and monitoring services**

Base URL: `http://127.0.0.1:6789` (localhost only by default)  
Authentication: Username/password via POST (optional for read-only endpoints)

---

## Quick Start

### Authentication
```bash
curl -X POST http://localhost:6789/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your_password"}'
```

Response (success):
```json
{"ok": true}
```

Response (failure):
```json
{"ok": false, "error": "invalid credentials"}
```

---

## Endpoints

### 1. **GET /api/status**
Check all services and active connections.

**Request:**
```bash
curl http://localhost:6789/api/status
```

**Response:**
```json
{
  "ok": true,
  "connections": 42,
  "total_users": 15,
  "services": {
    "ssh": true,
    "dropbear": true,
    "nginx": true,
    "badvpn": true,
    "sshws": true,
    "xui": true
  }
}
```

**Response Fields:**
- `connections` (int) — Total active TCP connections across all ports
- `total_users` (int) — Number of SSH users created
- `services` (object) — Boolean status for each service

---

### 2. **GET /api/info**
Get server configuration and connection details.

**Request:**
```bash
curl http://localhost:6789/api/info
```

**Response:**
```json
{
  "host": "panel.example.com",
  "xui_port": 2503,
  "dropbear_port": 143,
  "dropbear_port2": 109,
  "udpgw_port": 7300
}
```

**Response Fields:**
- `host` — Domain or server IP
- `xui_port` — Port for 3x-ui reverse proxy
- `dropbear_port` — Primary Dropbear SSH port
- `dropbear_port2` — Secondary Dropbear SSH port
- `udpgw_port` — BadVPN UDP gateway port (localhost only)

---

### 3. **GET /api/users**
List all SSH users with expiry dates.

**Request:**
```bash
curl http://localhost:6789/api/users
```

**Response:**
```json
{
  "users": [
    {
      "user": "alice",
      "active": true,
      "exp": "2025-12-31"
    },
    {
      "user": "bob",
      "active": false,
      "exp": "2024-06-15"
    }
  ]
}
```

**Response Fields:**
- `user` (string) — Username
- `active` (bool) — Whether user's expiry date has passed
- `exp` (string|null) — Expiry date (ISO 8601) or null if no expiry

---

### 4. **POST /api/login**
Authenticate with 3x-ui admin credentials.

**Request:**
```bash
curl -X POST http://localhost:6789/api/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "secretpassword"
  }'
```

**Response (success):**
```json
{"ok": true}
```

**Response (failure):**
```json
{"ok": false, "error": "invalid credentials"}
```

---

### 5. **POST /api/create_ssh**
Create a new SSH user.

**Request:**
```bash
curl -X POST http://localhost:6789/api/create_ssh \
  -H "Content-Type: application/json" \
  -d '{
    "user": "newuser",
    "password": "pass123",
    "days": 30
  }'
```

**Required Fields:**
- `user` (string) — Username (alphanumeric + underscore, 3-20 chars)
- `password` (string) — Password (any characters allowed)
- `days` (int) — Validity period in days (default: 30)

**Response (success):**
```json
{
  "ok": true,
  "user": "newuser",
  "exp": "2025-08-20"
}
```

**Response (failure):**
```json
{
  "error": "user and password required"
}
```

**Status Codes:**
- `200` — User created successfully
- `400` — Missing required fields

---

### 6. **POST /api/delete_ssh**
Delete an SSH user.

**Request:**
```bash
curl -X POST http://localhost:6789/api/delete_ssh \
  -H "Content-Type: application/json" \
  -d '{"user": "olduser"}'
```

**Required Fields:**
- `user` (string) — Username to delete

**Response (success):**
```json
{
  "ok": true,
  "user": "olduser"
}
```

**Response (failure):**
```json
{
  "error": "user required"
}
```

---

### 7. **POST /api/extend_ssh**
Extend SSH user expiry date.

**Request:**
```bash
curl -X POST http://localhost:6789/api/extend_ssh \
  -H "Content-Type: application/json" \
  -d '{
    "user": "alice",
    "days": 60
  }'
```

**Required Fields:**
- `user` (string) — Username
- `days` (int) — Additional days to extend

**Response (success):**
```json
{
  "ok": true,
  "user": "alice",
  "exp": "2026-09-18"
}
```

**Notes:**
- Extension is calculated from current expiry date (or today if no expiry)
- If user has no expiry yet, extends from today

---

### 8. **POST /api/speedtest**
Run network speedtest.

**Request:**
```bash
curl -X POST http://localhost:6789/api/speedtest
```

**Response (success):**
```json
{
  "ok": true,
  "ping": 12.5,
  "download": 450.75,
  "upload": 89.2,
  "server": "Bangkok, Thailand"
}
```

**Response (error):**
```json
{
  "ok": false,
  "error": "speedtest unavailable"
}
```

**Notes:**
- Speeds in Mbps
- Requires `speedtest-cli` installed on server
- Takes 30-60 seconds to complete

---

## Error Handling

### Common HTTP Status Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | OK — Request successful | User created, status retrieved |
| 400 | Bad Request — Missing/invalid fields | Missing `user` parameter |
| 401 | Unauthorized — Wrong credentials | Invalid login |
| 404 | Not Found — Endpoint doesn't exist | `/api/invalid` |
| 500 | Internal Server Error — Server error | Database failure |

### Error Response Format
```json
{
  "ok": false,
  "error": "error description"
}
```

---

## Usage Examples

### Create Multiple Users from CSV
```bash
#!/bin/bash
while IFS=',' read user pass days; do
  curl -X POST http://localhost:6789/api/create_ssh \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"$user\",\"password\":\"$pass\",\"days\":$days}"
  sleep 1
done < users.csv
```

CSV format:
```
alice,pass123,30
bob,securepass456,60
charlie,anotherpass789,90
```

### Bulk Delete Inactive Users
```bash
#!/bin/bash
CUTOFF_DATE=$(date -d "30 days ago" +%Y-%m-%d)
curl http://localhost:6789/api/users | jq -r '.users[] | select(.exp < "'$CUTOFF_DATE'") | .user' | while read user; do
  curl -X POST http://localhost:6789/api/delete_ssh \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"$user\"}"
done
```

### Monitor API in Real-time
```bash
#!/bin/bash
while true; do
  clear
  echo "=== XXTLONLINE Status ==="
  curl -s http://localhost:6789/api/status | jq '.connections, .total_users, .services'
  sleep 5
done
```

### Sync User Expirations to External DB
```python
#!/usr/bin/env python3
import requests, json, sqlite3
api_url = "http://localhost:6789/api/users"
resp = requests.get(api_url).json()
conn = sqlite3.connect('users.db')
for user in resp['users']:
    conn.execute("INSERT OR REPLACE INTO users (name, expiry, active) VALUES (?, ?, ?)",
                 (user['user'], user['exp'], user['active']))
conn.commit()
```

---

## Security Considerations

### Access Control
- **Default:** API listens on `127.0.0.1:6789` (localhost only)
- **NOT exposed to WAN** — Connect only from server itself or via SSH tunnel
- **Authentication:** Simple username/password (HTTP, no HTTPS on localhost)

### Enabling Remote Access (NOT RECOMMENDED for production)
If you need remote API access, use SSH tunnel:
```bash
# From remote client:
ssh -L 6789:127.0.0.1:6789 root@panel.example.com
# Then access API on localhost:6789
```

### Best Practices
1. Never expose API on WAN without TLS + strong auth
2. Use firewall rules to restrict API access
3. Rotate admin password regularly
4. Log all API calls via monitoring
5. Rate-limit API requests to prevent abuse

---

## Response Codes Reference

```
GET /api/status         → 200 OK
GET /api/info           → 200 OK
GET /api/users          → 200 OK
POST /api/login         → 200 OK (if valid), 401 Unauthorized (if invalid)
POST /api/create_ssh    → 200 OK, 400 Bad Request
POST /api/delete_ssh    → 200 OK, 400 Bad Request
POST /api/extend_ssh    → 200 OK, 400 Bad Request
POST /api/speedtest     → 200 OK (with result or error flag)
```

---

## Testing the API

### Using curl (command line)
```bash
# Check status
curl http://localhost:6789/api/status | jq

# Create user
curl -X POST http://localhost:6789/api/create_ssh \
  -H "Content-Type: application/json" \
  -d '{"user":"test","password":"test123","days":30}' | jq
```

### Using Python (requests library)
```python
import requests

api = "http://localhost:6789"
resp = requests.get(f"{api}/api/status")
print(resp.json())

resp = requests.post(f"{api}/api/create_ssh", json={
    "user": "testuser",
    "password": "testpass",
    "days": 30
})
print(resp.json())
```

### Using JavaScript (fetch)
```javascript
fetch('http://localhost:6789/api/status')
  .then(r => r.json())
  .then(data => console.log(data))

fetch('http://localhost:6789/api/create_ssh', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({user: 'testuser', password: 'testpass', days: 30})
})
  .then(r => r.json())
  .then(data => console.log(data))
```

---

## Changelog

### v1.0 (2026-07-21)
- Initial release
- Core endpoints: status, info, users, create_ssh, delete_ssh, extend_ssh
- Speedtest integration
- CORS headers for cross-origin requests

---

## Support & Issues

For API bugs or feature requests:
1. Check logs: `sudo journalctl -u xxtlonline-ssh-api -n 50`
2. Verify API is running: `sudo systemctl status xxtlonline-ssh-api`
3. Test connectivity: `curl http://localhost:6789/api/status`
