#!/usr/bin/env python3
# Email users whose VPN access expires within EXPIRY_WARN_DAYS.
# Run daily via cron. Does nothing if SMTP_HOST is not configured.

import os
import smtplib
import sys
from email.mime.text import MIMEText

import pymysql
from dotenv import load_dotenv

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(PROJECT_DIR, '.env'))

SMTP_HOST = os.environ.get('SMTP_HOST', '').strip()
SMTP_PORT = int(os.environ.get('SMTP_PORT', 587))
SMTP_USER = os.environ.get('SMTP_USER', '')
SMTP_PASS = os.environ.get('SMTP_PASSWORD', '')
SMTP_FROM = os.environ.get('SMTP_FROM', 'VPN Manager <noreply@localhost>')
WARN_DAYS = int(os.environ.get('EXPIRY_WARN_DAYS', 3))

if not SMTP_HOST:
    print('[SKIP] SMTP_HOST not configured — email notifications disabled.')
    sys.exit(0)

db = pymysql.connect(
    host=os.environ.get('MYSQL_HOST', 'localhost'),
    user=os.environ.get('MYSQL_USER', 'vpnuser'),
    password=os.environ.get('MYSQL_PASSWORD', 'vpnpassword'),
    database=os.environ.get('MYSQL_DB', 'vpn_system'),
    cursorclass=pymysql.cursors.DictCursor,
)

with db.cursor() as cur:
    cur.execute(
        "SELECT id, username, email, expires_at FROM users "
        "WHERE is_active = 1 AND expiry_notified = 0 "
        "  AND expires_at > NOW() "
        "  AND expires_at <= NOW() + INTERVAL %s DAY",
        (WARN_DAYS,),
    )
    users = cur.fetchall()

if not users:
    print('[OK] No users to notify.')
    sys.exit(0)

smtp = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15)
smtp.starttls()
if SMTP_USER:
    smtp.login(SMTP_USER, SMTP_PASS)

sent = 0
for u in users:
    body = (
        f"Hi {u['username']},\n\n"
        f"Your VPN access expires on {u['expires_at']:%d %b %Y %H:%M}.\n"
        f"Please contact the administrator if you need an extension.\n\n"
        f"— VPN Manager"
    )
    msg = MIMEText(body)
    msg['Subject'] = f"VPN access expires {u['expires_at']:%d %b %Y}"
    msg['From']    = SMTP_FROM
    msg['To']      = u['email']

    try:
        smtp.send_message(msg)
        with db.cursor() as cur:
            cur.execute("UPDATE users SET expiry_notified=1 WHERE id=%s", (u['id'],))
        db.commit()
        sent += 1
        print(f"[SENT] {u['username']} <{u['email']}>")
    except Exception as exc:
        print(f"[FAIL] {u['username']} <{u['email']}>: {exc}")

smtp.quit()
db.close()
print(f'[DONE] Notified {sent}/{len(users)} user(s).')
