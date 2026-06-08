from functools import wraps
from datetime import datetime, timedelta

from flask import (Blueprint, flash, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

from config import Config
from services.database import query

auth_bp = Blueprint('auth', __name__)


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if 'user_id' not in session:
            flash('Please log in first.', 'warning')
            return redirect(url_for('auth.login'))
        return f(*args, **kwargs)
    return wrapper


def admin_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if session.get('role') != 'admin':
            flash('Admin access required.', 'danger')
            return redirect(url_for('auth.login'))
        return f(*args, **kwargs)
    return wrapper


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if 'user_id' in session:
        return _redirect_by_role()

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        role     = request.form.get('role', 'user')

        if role == 'admin':
            row = query("SELECT * FROM admins WHERE username=%s", (username,), one=True)
            if row and check_password_hash(row['password_hash'], password):
                _set_session(row['id'], row['username'], 'admin')
                query("UPDATE admins SET last_login=NOW() WHERE id=%s", (row['id'],), commit=True)
                flash(f"Welcome back, {row['username']}!", 'success')
                return redirect(url_for('admin.dashboard'))
        else:
            row = query(
                "SELECT * FROM users WHERE username=%s AND is_active=1",
                (username,), one=True,
            )
            if row and check_password_hash(row['password_hash'], password):
                if row['expires_at'] < datetime.now():
                    flash('Your account has expired. Contact an administrator.', 'danger')
                    return render_template('login.html')
                _set_session(row['id'], row['username'], 'user')
                flash(f"Welcome, {row['username']}!", 'success')
                return redirect(url_for('user.dashboard'))

        flash('Invalid credentials. Please try again.', 'danger')

    return render_template('login.html')


@auth_bp.route('/register', methods=['GET', 'POST'])
def register():
    if 'user_id' in session:
        return _redirect_by_role()

    if request.method == 'POST':
        username  = request.form.get('username', '').strip()
        email     = request.form.get('email', '').strip()
        password  = request.form.get('password', '')
        full_name = request.form.get('full_name', '').strip()

        if not all([username, email, password]):
            flash('Username, email and password are required.', 'danger')
            return render_template('register.html')

        if len(password) < 8:
            flash('Password must be at least 8 characters.', 'danger')
            return render_template('register.html')

        if query("SELECT id FROM users WHERE username=%s OR email=%s",
                 (username, email), one=True):
            flash('Username or email is already registered.', 'danger')
            return render_template('register.html')

        expires_at = datetime.now() + timedelta(days=Config.DEFAULT_EXPIRY_DAYS)
        query(
            "INSERT INTO users (username, email, password_hash, full_name, expires_at) "
            "VALUES (%s, %s, %s, %s, %s)",
            (username, email, generate_password_hash(password), full_name, expires_at),
            commit=True,
        )
        flash('Account created! You can now sign in.', 'success')
        return redirect(url_for('auth.login'))

    return render_template('register.html')


@auth_bp.route('/logout')
def logout():
    session.clear()
    flash('You have been signed out.', 'info')
    return redirect(url_for('auth.login'))


def _set_session(uid, username, role):
    session.clear()
    session['user_id']  = uid
    session['username'] = username
    session['role']     = role


def _redirect_by_role():
    if session.get('role') == 'admin':
        return redirect(url_for('admin.dashboard'))
    return redirect(url_for('user.dashboard'))
