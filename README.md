# Automated VPN Access Management System
### Final Year Project — WireGuard + Flask Web Dashboard

---

## Overview

A full-stack web application that automates WireGuard VPN provisioning.
Users self-register and receive a ready-to-use `.conf` file. Admins manage
access, view live connection logs, and see geolocation data on an interactive map.

---

## System Architecture

```
Browser
  │
  ├─ User Portal  (/user/)   — register, generate key, download .conf
  └─ Admin Panel  (/admin/)  — manage users, view logs, live peer stats
         │
    Flask / Gunicorn  (systemd: vpn-webapp.service)
         │
    ┌────┴────────────────────────┐
    │ MySQL          WireGuard    │
    │ vpn_system     wg0 (Linux)  │
    └─────────────────────────────┘
         │
    Nginx (reverse proxy, port 80/443)
```

---

## Project Structure

```
vpn-project/
├── app.py                   # Flask application factory
├── config.py                # Configuration (reads .env)
├── requirements.txt         # Python dependencies
├── create_admin.py          # One-time admin account setup
├── .env.example             # Environment variable template
├── vpn_system.sql           # Full MySQL schema + IP pool
│
├── routes/
│   ├── auth.py              # Login, register, logout + decorators
│   ├── admin.py             # Admin dashboard & user management
│   └── user.py              # User VPN portal
│
├── services/
│   ├── database.py          # PyMySQL connection + query helper
│   ├── wireguard.py         # Key gen, peer add/remove, live stats
│   └── geolocation.py       # ip-api.com geolocation lookup
│
├── templates/               # Bootstrap 5 light theme
│   ├── base.html            # Shared layout (navbar, flash messages)
│   ├── login.html
│   ├── register.html
│   ├── admin/
│   │   ├── dashboard.html   # Stats cards + recent activity
│   │   ├── users.html       # User table + extend/revoke actions
│   │   ├── create_user.html # Admin-generated user form
│   │   ├── logs.html        # Leaflet.js map + paginated log table
│   │   └── user_detail.html # Per-user deep-dive view
│   └── user/
│       └── dashboard.html   # VPN status, download config, activity
│
├── static/
│   ├── css/style.css        # Custom light theme styles
│   └── js/map.js            # Leaflet map renderer (geolocation)
│
└── scripts/
    ├── full_setup.sh        # ★ Interactive production installer (start here)
    ├── setup_wireguard.sh   # WireGuard-only setup (called by full_setup.sh)
    ├── add_peer.sh          # Called by Flask to add a WG peer
    ├── remove_peer.sh       # Called by Flask to remove a WG peer
    ├── cron_expiry.sh       # Auto-revoke expired users every 5 minutes
    ├── vpn-webapp.service   # systemd unit for Gunicorn (auto-start)
    └── install_service.sh   # Register services only (subset of full_setup.sh)
```

---

## Prerequisites

| Component     | Version     |
|---------------|-------------|
| Ubuntu/Debian | 20.04+      |
| Python        | 3.10+       |
| MySQL         | 8.0+        |
| WireGuard     | any current |
| Nginx         | any current |

---

## Installation (Linux Server)

### Quick Start — One Interactive Script

Upload your project folder to the server, then run:

```bash
# Upload project files to server first (from your local machine)
scp -r vpn-project/ user@yourserver:/root/vpn-project

# SSH into the server, then run the installer
ssh user@yourserver
sudo bash /root/vpn-project/scripts/full_setup.sh
```

The script will prompt you for the required values — the source path is
auto-detected from the script's own location, so you only need to answer:

```
? Domain / IP address:                vpn.example.com
? Deploy path [/opt/vpn-project]:
? MySQL root password:                ••••••••
? VPN app DB password:                ••••••••
? WireGuard endpoint [203.x.x.x:51820]:
```

**What `full_setup.sh` does automatically:**

| Phase | Action |
|-------|--------|
| 1 | Installs Nginx, MySQL, Python3, WireGuard, UFW, Certbot |
| 2 | Creates MySQL database `vpn_system` and user `vpnuser` |
| 3 | Imports database schema (`vpn_system.sql`) |
| 4 | Copies project files to deploy path |
| 5 | Generates `.env` with all settings filled in |
| 6 | Creates Python venv and installs requirements |
| 7 | Generates WireGuard server keypair and writes `wg0.conf` |
| 8 | Writes and enables Nginx vhost for your domain |
| 9 | Configures UFW firewall — opens ports 22, 80, 443, WireGuard |
| 10 | Installs and enables `vpn-webapp.service` (auto-start on reboot) |
| 11 | Installs cron job for auto-expiry of VPN users |

After the script finishes, only one manual step remains:

```bash
# Create the first admin account
sudo -u www-data bash -c 'cd /opt/vpn-project && venv/bin/python create_admin.py'

# (Optional but recommended) Enable HTTPS
sudo certbot --nginx -d yourdomain.com
```

---

### Manual Installation (Step by Step)

Use this method if you prefer to control each step individually.

#### Step 1 — Set up WireGuard

```bash
sudo bash scripts/setup_wireguard.sh
```

This script installs WireGuard, generates the server keypair, writes
`/etc/wireguard/wg0.conf`, enables IP forwarding, and configures sudoers
for the web app user. Copy the printed **public key** — you will need it in `.env`.

#### Step 2 — Create the MySQL database and user

```sql
CREATE DATABASE vpn_system CHARACTER SET utf8mb4;
CREATE USER 'vpnuser'@'localhost' IDENTIFIED BY 'vpnpassword';
GRANT ALL PRIVILEGES ON vpn_system.* TO 'vpnuser'@'localhost';
FLUSH PRIVILEGES;
```

#### Step 3 — Import the schema

```bash
mysql -u vpnuser -p vpn_system < vpn_system.sql
```

#### Step 4 — Configure the environment

```bash
cp .env.example .env
nano .env          # fill in SECRET_KEY, WG_SERVER_PUBLIC_KEY, WG_SERVER_ENDPOINT
```

#### Step 5 — Install Python dependencies

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Step 6 — Create the first admin account

```bash
python create_admin.py
```

#### Step 7 — Fix script permissions

```bash
dos2unix scripts/*.sh          # only needed if transferred from Windows
chmod +x scripts/*.sh
```

#### Step 8 — Open firewall ports

```bash
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 51820/udp  # WireGuard VPN
sudo ufw --force enable
sudo ufw status
```

#### Step 9 — Configure Nginx

Create `/etc/nginx/sites-available/vpn-manager`:

```nginx
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }

    location /static/ {
        alias /opt/vpn-project/static/;
        expires 7d;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/vpn-manager /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

#### Step 10 — Register all services for auto-start

```bash
sudo bash scripts/install_service.sh
```

#### Step 11 — Set up the cron job (auto-expire users)

```bash
crontab -e
# Add:
*/5 * * * * /opt/vpn-project/scripts/cron_expiry.sh >> /var/log/vpn_expiry.log 2>&1
```

#### Step 12 — (Optional) Add HTTPS with Let's Encrypt

```bash
sudo certbot --nginx -d yourdomain.com
```

Certbot auto-renews the certificate and reconfigures Nginx for HTTPS.

---

## Production Auto-Start (systemd)

This table shows which services start automatically after a server reboot
and how each one is configured:

| Service | Auto-start | Configured by |
|---|---|---|
| **MySQL** (`mysql.service`) | ✅ Yes | `install_service.sh` — `systemctl enable mysql` |
| **WireGuard** (`wg-quick@wg0`) | ✅ Yes | `setup_wireguard.sh` + `install_service.sh` |
| **Flask/Gunicorn** (`vpn-webapp.service`) | ✅ Yes | `install_service.sh` — installs systemd unit |
| **Nginx** | ✅ Yes | Manual step above — `systemctl enable nginx` |
| **Cron expiry** (`cron_expiry.sh`) | ✅ Yes | Runs via system cron daemon (always active) |

### Boot order guaranteed

The `vpn-webapp.service` unit declares:

```ini
After=network.target mysql.service
Wants=mysql.service
```

This ensures Flask only starts **after** the network is up and MySQL is ready,
preventing connection errors on boot.

### Useful service management commands

```bash
# Check status of all key services
sudo systemctl status vpn-webapp
sudo systemctl status wg-quick@wg0
sudo systemctl status mysql
sudo systemctl status nginx

# Restart Flask app (e.g. after updating code)
sudo systemctl restart vpn-webapp

# Reload Flask without dropping connections (zero-downtime)
sudo systemctl reload vpn-webapp

# View Flask logs live
sudo journalctl -u vpn-webapp -f

# View application log files
sudo tail -f /var/log/vpn-webapp/access.log
sudo tail -f /var/log/vpn-webapp/error.log

# Manually verify WireGuard peers are loaded
sudo wg show wg0
```

### Verify everything survived a reboot

```bash
sudo reboot

# After reconnecting:
sudo systemctl is-active vpn-webapp    # should print: active
sudo systemctl is-active wg-quick@wg0  # should print: active
sudo systemctl is-active mysql          # should print: active
sudo systemctl is-active nginx          # should print: active
```

---

## Default Access

| Role  | URL                          | Notes                                 |
|-------|------------------------------|---------------------------------------|
| Admin | `http://yourserver/login`    | Created via `python create_admin.py`  |
| User  | `http://yourserver/register` | Self-registration, 7-day default      |

---

## Key Features

### User Portal
- Self-register with email + password
- 7-day default access period
- One-click WireGuard config generation
- Download named `.conf` file
- View own activity log and connection history

### Admin Dashboard
- Live WireGuard interface status indicator
- Stats: total / active / expired users, active peers, daily logs
- Create users with custom expiry duration
- Extend access (1 / 3 / 7 / 14 / 30 days)
- Revoke access (removes WireGuard peer immediately)
- Paginated connection logs with event and username filters
- Leaflet.js map of connection geolocations
- JSON API endpoint: `/admin/api/peer-stats`

### WireGuard Automation
- Automatic keypair + PSK generation per user
- IP allocation from pool (`10.8.0.2 – 10.8.0.254`)
- Peers added/removed live via `wg set` without restarting WireGuard
- Config persisted with `wg-quick save` (survives reboot)

### Security
- Passwords hashed with PBKDF2-SHA256 (Werkzeug)
- SQL injection prevented with parameterised queries
- Role-based session authentication (admin / user)
- Expired session auto-redirect to login
- Preshared keys per peer for additional encryption layer

---

## Environment Variables Reference

| Variable               | Default              | Description                      |
|------------------------|----------------------|----------------------------------|
| `SECRET_KEY`           | random (change this) | Flask session signing key        |
| `MYSQL_HOST`           | `localhost`          | MySQL host                       |
| `MYSQL_USER`           | `vpnuser`            | MySQL username                   |
| `MYSQL_PASSWORD`       | `vpnpassword`        | MySQL password                   |
| `MYSQL_DB`             | `vpn_system`         | Database name                    |
| `WG_INTERFACE`         | `wg0`                | WireGuard interface name         |
| `WG_SERVER_PUBLIC_KEY` | *(required)*         | Server WireGuard public key      |
| `WG_SERVER_ENDPOINT`   | `0.0.0.0:51820`      | `<IP>:<port>` clients connect to |
| `WG_DNS`               | `1.1.1.1, 1.0.0.1`  | DNS pushed to clients            |
| `DEFAULT_EXPIRY_DAYS`  | `7`                  | Default user access duration     |

---

## Database Schema

| Table             | Purpose                                    |
|-------------------|--------------------------------------------|
| `admins`          | Admin accounts (username, email, password) |
| `users`           | VPN subscriber accounts with expiry        |
| `vpn_peers`       | WireGuard peer config per user             |
| `connection_logs` | All VPN events with geolocation data       |
| `ip_pool`         | 10.8.0.2–254 IP allocation pool            |

---

## API Endpoints

| Method | Path                       | Auth  | Description              |
|--------|----------------------------|-------|--------------------------|
| GET    | `/`                        | —     | Redirect to login        |
| GET    | `/login`                   | —     | Login page               |
| POST   | `/login`                   | —     | Authenticate             |
| GET    | `/register`                | —     | Registration page        |
| POST   | `/register`                | —     | Create user account      |
| GET    | `/logout`                  | any   | Clear session            |
| GET    | `/user/`                   | user  | VPN dashboard            |
| POST   | `/user/vpn/generate`       | user  | Generate WG config       |
| GET    | `/user/vpn/download`       | user  | Download `.conf` file    |
| GET    | `/admin/`                  | admin | Admin dashboard          |
| GET    | `/admin/users`             | admin | User list                |
| GET    | `/admin/users/create`      | admin | Create user form         |
| POST   | `/admin/users/create`      | admin | Create user              |
| POST   | `/admin/users/<id>/extend` | admin | Extend user expiry       |
| POST   | `/admin/users/<id>/revoke` | admin | Revoke user access       |
| GET    | `/admin/logs`              | admin | Connection logs          |
| GET    | `/admin/api/peer-stats`    | admin | Live WG stats (JSON)     |

---

## Troubleshooting

**Flask app does not start after reboot:**
```bash
sudo journalctl -u vpn-webapp -n 50 --no-pager
```
Check that `/opt/vpn-project/.env` exists and `WorkingDirectory` in
`/etc/systemd/system/vpn-webapp.service` points to the correct path.
After any change to the service file, run `sudo systemctl daemon-reload`.

**WireGuard peers disappear after reboot:**
Ensure `wg-quick save wg0` completed successfully after the last peer change.
Check that `systemctl is-enabled wg-quick@wg0` returns `enabled`.

**WireGuard commands fail (permission denied):**
Verify the sudoers file at `/etc/sudoers.d/vpn-webapp` grants `www-data`
passwordless access to `wg`, `wg-quick`, `add_peer.sh`, and `remove_peer.sh`.
Re-run `sudo bash scripts/setup_wireguard.sh` to regenerate it.

**`wg genkey` not found on Windows:**
The application is designed to run on Linux. For local development on Windows,
the Flask app starts normally but VPN key generation will fail with a clear
error message — this is expected behaviour.

**Geolocation shows Unknown:**
The free `ip-api.com` API is rate-limited to ~45 requests/minute.
Private and localhost IP addresses always show as "Local Network" by design.

**MySQL connection refused on boot:**
The `vpn-webapp.service` unit already declares `After=mysql.service`.
If MySQL is slow to start, increase `RestartSec` in the service file or
add `TimeoutStartSec=60` under `[Service]`.
