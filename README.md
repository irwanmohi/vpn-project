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
├── vpn_system.sql           # Full MySQL schema + IP pool (fresh installs)
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
│   │   ├── dashboard.html   # Stats cards + connections chart + recent activity
│   │   ├── users.html       # User table (desktop) + card layout (mobile)
│   │   ├── create_user.html # Admin-generated user form
│   │   ├── logs.html        # Live connection map + paginated log table
│   │   ├── peer_stats.html  # Live peer stats with real-time speed
│   │   └── user_detail.html # Per-user deep-dive view
│   └── user/
│       └── dashboard.html   # VPN status, QR code, download config, traffic
│
├── static/
│   ├── favicon.svg          # Browser tab icon
│   ├── css/style.css        # Custom light theme styles
│   └── js/map.js            # Leaflet map renderer (geolocation)
│
└── scripts/
    ├── full_setup.sh        # ★ Interactive production installer (start here)
    ├── setup_wireguard.sh   # WireGuard-only setup (called by full_setup.sh)
    ├── setup_https.sh       # Let's Encrypt HTTPS (run after full_setup.sh)
    ├── add_peer.sh          # Called by Flask to add a WG peer
    ├── remove_peer.sh       # Called by Flask to remove a WG peer
    ├── cron_expiry.sh       # Auto-revoke expired users every 5 minutes
    ├── cron_monitor.sh      # Connect/disconnect detection + traffic (every minute)
    ├── notify_expiry.py     # Expiry warning emails (daily)
    ├── backup_db.sh         # Daily MySQL backup, keeps 7 days
    ├── migrate_v2.sql       # Migration for installs older than v2
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
| 11 | Installs 4 cron jobs — expiry, monitor, email alerts, DB backup |

After the script finishes, only one manual step remains:

```bash
# Create the first admin account
cd /opt/vpn-project && sudo venv/bin/python create_admin.py

# (Optional but recommended) Enable HTTPS with Let's Encrypt
sudo bash scripts/setup_https.sh yourdomain.com admin@example.com
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

#### Step 11 — Set up the cron jobs

Create `/etc/cron.d/vpn-manager`:

```bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root bash /opt/vpn-project/scripts/cron_expiry.sh >> /var/log/vpn_expiry.log 2>&1
* * * * * root bash /opt/vpn-project/scripts/cron_monitor.sh >> /var/log/vpn_monitor.log 2>&1
0 8 * * * root /opt/vpn-project/venv/bin/python /opt/vpn-project/scripts/notify_expiry.py >> /var/log/vpn_notify.log 2>&1
0 3 * * * root bash /opt/vpn-project/scripts/backup_db.sh >> /var/log/vpn_backup.log 2>&1
```

| Job | Schedule | Purpose |
|-----|----------|---------|
| `cron_expiry.sh` | every 5 min | Auto-revoke expired users |
| `cron_monitor.sh` | every minute | Detect connect/disconnect events + traffic counters |
| `notify_expiry.py` | daily 08:00 | Email users 3 days before expiry (needs SMTP in `.env`) |
| `backup_db.sh` | daily 03:00 | MySQL backup to `/var/backups/vpn-manager`, keeps 7 days |

#### Step 12 — (Optional) Add HTTPS with Let's Encrypt

```bash
sudo bash scripts/setup_https.sh yourdomain.com admin@example.com
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
- Download named `.conf` file or scan QR code with the mobile app
- Personal traffic counters (downloaded / uploaded)
- View own activity log and connection history
- Fully responsive — works on phones

### Admin Dashboard
- Live WireGuard interface status indicator
- Stats: total / active / expired users, active peers, daily logs
- Connections-per-day chart (last 14 days, Chart.js)
- Live Online/Offline badge per user (from WireGuard handshake)
- Per-user traffic usage (download / upload)
- Create users with custom expiry duration
- Extend access (1 / 3 / 7 / 14 / 30 days)
- Reset user passwords (random generated, shown once)
- Revoke access (removes WireGuard peer immediately)
- Paginated connection logs with event and username filters
- Live connection map — shows only currently-connected users
- Live peer stats page with real-time transfer speed
- Mobile card layout on small screens

### WireGuard Automation
- Automatic keypair + PSK generation per user
- IP allocation from pool (`10.8.0.2 – 10.8.0.254`)
- Peers added/removed live via `wg set` without restarting WireGuard
- Config persisted with `wg-quick save` (survives reboot)

### Security
- Passwords hashed with PBKDF2-SHA256 (Werkzeug)
- SQL injection prevented with parameterised queries
- Role-based session authentication (admin / user)
- Login rate limiting — 5 failed attempts locks the account for 15 minutes
- HTTPS via Let's Encrypt (`setup_https.sh`)
- MySQL credentials never exposed on the command line (defaults file)
- Expired session auto-redirect to login
- Preshared keys per peer for additional encryption layer
- Daily database backups with restricted permissions (7-day retention)

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
| `SMTP_HOST`            | *(empty = disabled)* | SMTP server for expiry emails    |
| `SMTP_PORT`            | `587`                | SMTP port (STARTTLS)             |
| `SMTP_USER`            | —                    | SMTP login username              |
| `SMTP_PASSWORD`        | —                    | SMTP login password              |
| `SMTP_FROM`            | `VPN Manager <...>`  | From address on emails           |
| `EXPIRY_WARN_DAYS`     | `3`                  | Days before expiry to email user |

---

## Database Schema

| Table             | Purpose                                    |
|-------------------|--------------------------------------------|
| `admins`          | Admin accounts (username, email, password) |
| `users`           | VPN subscriber accounts with expiry        |
| `vpn_peers`       | WireGuard peer config per user             |
| `connection_logs` | All VPN events with geolocation data       |
| `ip_pool`         | 10.8.0.2–254 IP allocation pool            |
| `failed_logins`   | Login attempts for rate limiting           |

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
| GET    | `/user/vpn/qrcode`         | user  | Config as QR code (PNG)  |
| GET    | `/admin/`                  | admin | Admin dashboard + chart  |
| GET    | `/admin/users`             | admin | User list                |
| GET    | `/admin/users/create`      | admin | Create user form         |
| POST   | `/admin/users/create`      | admin | Create user              |
| POST   | `/admin/users/<id>/extend` | admin | Extend user expiry       |
| POST   | `/admin/users/<id>/reset-password` | admin | Reset user password |
| POST   | `/admin/users/<id>/revoke` | admin | Revoke user access       |
| GET    | `/admin/logs`              | admin | Logs + live connection map |
| GET    | `/admin/peer-stats`        | admin | Live peer stats page     |
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
The web app service runs as root (see `scripts/vpn-webapp.service`) so it can
manage WireGuard peers directly. If you changed the service user, WireGuard
calls will fail — restore `User=root` and run `sudo systemctl daemon-reload`.

**Cron jobs show "Permission denied" in logs:**
Ensure the cron entries invoke scripts via `bash` (e.g.
`root bash /opt/vpn-project/scripts/cron_monitor.sh`) — execute permission
can be lost when files are transferred from Windows.

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
