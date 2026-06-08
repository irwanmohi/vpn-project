#!/usr/bin/env python3
"""
Run once to create the first admin account.
Usage:  python create_admin.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from getpass import getpass
from werkzeug.security import generate_password_hash
import pymysql
from dotenv import load_dotenv

load_dotenv()


def main():
    print("=" * 50)
    print("  VPN System — Create Admin Account")
    print("=" * 50)

    username = input("\nAdmin username : ").strip()
    email    = input("Admin email    : ").strip()
    password = getpass("Admin password : ")
    confirm  = getpass("Confirm password: ")

    if not username or not email or not password:
        print("\n[ERROR] All fields are required.")
        sys.exit(1)

    if password != confirm:
        print("\n[ERROR] Passwords do not match.")
        sys.exit(1)

    if len(password) < 8:
        print("\n[ERROR] Password must be at least 8 characters.")
        sys.exit(1)

    pw_hash = generate_password_hash(password)

    conn = pymysql.connect(
        host=os.environ.get('MYSQL_HOST',     'localhost'),
        user=os.environ.get('MYSQL_USER',     'vpnuser'),
        password=os.environ.get('MYSQL_PASSWORD', 'vpnpassword'),
        database=os.environ.get('MYSQL_DB',   'vpn_system'),
        port=int(os.environ.get('MYSQL_PORT', 3306)),
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM admins WHERE username=%s OR email=%s",
                (username, email)
            )
            if cur.fetchone():
                print(f"\n[ERROR] An admin with username '{username}' or email '{email}' already exists.")
                sys.exit(1)
            cur.execute(
                "INSERT INTO admins (username, email, password_hash) VALUES (%s, %s, %s)",
                (username, email, pw_hash)
            )
        conn.commit()
        print(f"\n[OK] Admin account '{username}' created successfully.")
        print("     You can now log in at http://localhost:5000/login\n")
    finally:
        conn.close()


if __name__ == '__main__':
    main()
