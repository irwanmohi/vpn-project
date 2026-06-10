import secrets
from datetime import datetime, timedelta
from functools import wraps

from flask import (Blueprint, flash, jsonify, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import generate_password_hash

from config import Config
from routes.auth import admin_required, login_required
from services.database import query
from services.geolocation import get_location
from services.wireguard import (add_peer, allocate_ip, generate_keypair,
                                 generate_preshared_key, get_peer_stats,
                                 is_interface_up, mark_ip_allocated,
                                 release_ip, remove_peer)

admin_bp = Blueprint('admin', __name__)


def _admin(f):
    @wraps(f)
    @login_required
    @admin_required
    def wrapper(*args, **kwargs):
        return f(*args, **kwargs)
    return wrapper


@admin_bp.route('/')
@_admin
def dashboard():
    stats = {
        'total_users':   query("SELECT COUNT(*) AS c FROM users",                                          one=True)['c'],
        'active_users':  query("SELECT COUNT(*) AS c FROM users WHERE is_active=1 AND expires_at>NOW()",   one=True)['c'],
        'expired_users': query("SELECT COUNT(*) AS c FROM users WHERE expires_at<=NOW() OR is_active=0",   one=True)['c'],
        'active_peers':  query("SELECT COUNT(*) AS c FROM vpn_peers WHERE is_active=1",                    one=True)['c'],
        'logs_today':    query("SELECT COUNT(*) AS c FROM connection_logs WHERE DATE(event_time)=CURDATE()", one=True)['c'],
        'wg_up':         is_interface_up(),
    }
    recent_logs = query(
        "SELECT cl.*, u.username FROM connection_logs cl "
        "JOIN users u ON cl.user_id=u.id "
        "ORDER BY cl.event_time DESC LIMIT 12"
    )

    # Connections per day, last 14 days (missing days filled with 0)
    rows = query(
        "SELECT DATE(event_time) AS d, COUNT(*) AS c "
        "FROM connection_logs "
        "WHERE event_type='connect' AND event_time > NOW() - INTERVAL 14 DAY "
        "GROUP BY DATE(event_time)"
    )
    counts = {r['d'].strftime('%Y-%m-%d'): r['c'] for r in rows}
    today  = datetime.now().date()
    chart_labels = []
    chart_values = []
    for i in range(13, -1, -1):
        day = today - timedelta(days=i)
        chart_labels.append(day.strftime('%d %b'))
        chart_values.append(counts.get(day.strftime('%Y-%m-%d'), 0))

    return render_template(
        'admin/dashboard.html',
        stats=stats, recent_logs=recent_logs,
        chart_labels=chart_labels, chart_values=chart_values,
    )


@admin_bp.route('/users')
@_admin
def users():
    rows = query(
        "SELECT u.*, "
        "       vp.vpn_ip, vp.is_active AS vpn_active, vp.id AS peer_id, "
        "       vp.config_downloaded, vp.public_key, vp.total_rx, vp.total_tx "
        "FROM users u "
        "LEFT JOIN vpn_peers vp ON u.id=vp.user_id AND vp.is_active=1 "
        "ORDER BY u.created_at DESC"
    )

    # Live handshake data — peer is online if handshake < 3 min ago
    stats = get_peer_stats()
    now_ts = datetime.now().timestamp()
    for r in rows:
        peer_stat   = stats.get(r['public_key']) if r['public_key'] else None
        r['online'] = bool(
            peer_stat
            and peer_stat['last_handshake'] > 0
            and (now_ts - peer_stat['last_handshake']) < 180
        )

    return render_template('admin/users.html', users=rows, now=datetime.now())


@admin_bp.route('/users/create', methods=['GET', 'POST'])
@_admin
def create_user():
    if request.method == 'POST':
        username  = request.form.get('username', '').strip()
        email     = request.form.get('email', '').strip()
        password  = request.form.get('password', '')
        full_name = request.form.get('full_name', '').strip()
        days      = int(request.form.get('expiry_days', Config.DEFAULT_EXPIRY_DAYS))

        if not all([username, email, password]):
            flash('Username, email and password are required.', 'danger')
            return render_template('admin/create_user.html', default_days=Config.DEFAULT_EXPIRY_DAYS)

        if query("SELECT id FROM users WHERE username=%s OR email=%s",
                 (username, email), one=True):
            flash('Username or email already exists.', 'danger')
            return render_template('admin/create_user.html', default_days=Config.DEFAULT_EXPIRY_DAYS)

        expires_at = datetime.now() + timedelta(days=days)
        query(
            "INSERT INTO users (username, email, password_hash, full_name, expires_at, created_by) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (username, email, generate_password_hash(password),
             full_name, expires_at, session['user_id']),
            commit=True,
        )
        flash(f'User "{username}" created with {days}-day access.', 'success')
        return redirect(url_for('admin.users'))

    return render_template('admin/create_user.html', default_days=Config.DEFAULT_EXPIRY_DAYS)


@admin_bp.route('/users/<int:user_id>/extend', methods=['POST'])
@_admin
def extend_user(user_id):
    days = int(request.form.get('days', 7))
    user = query("SELECT * FROM users WHERE id=%s", (user_id,), one=True)
    if not user:
        flash('User not found.', 'danger')
        return redirect(url_for('admin.users'))

    base       = max(datetime.now(), user['expires_at'])
    new_expiry = base + timedelta(days=days)
    query(
        "UPDATE users SET expires_at=%s, is_active=1, expiry_notified=0 WHERE id=%s",
        (new_expiry, user_id), commit=True,
    )
    flash(f'Extended {user["username"]}\'s access by {days} day(s) → expires {new_expiry.strftime("%Y-%m-%d")}.', 'success')
    return redirect(url_for('admin.users'))


@admin_bp.route('/users/<int:user_id>/reset-password', methods=['POST'])
@_admin
def reset_password(user_id):
    user = query("SELECT * FROM users WHERE id=%s", (user_id,), one=True)
    if not user:
        flash('User not found.', 'danger')
        return redirect(url_for('admin.users'))

    alphabet     = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
    new_password = ''.join(secrets.choice(alphabet) for _ in range(12))

    query(
        "UPDATE users SET password_hash=%s WHERE id=%s",
        (generate_password_hash(new_password), user_id), commit=True,
    )
    query("DELETE FROM failed_logins WHERE username=%s", (user['username'],), commit=True)

    flash(
        f'Password for "{user["username"]}" has been reset to:  {new_password}  '
        f'— copy it now, it will not be shown again.',
        'warning',
    )
    return redirect(url_for('admin.users'))


@admin_bp.route('/users/<int:user_id>/revoke', methods=['POST'])
@_admin
def revoke_user(user_id):
    user = query("SELECT * FROM users WHERE id=%s", (user_id,), one=True)
    if not user:
        flash('User not found.', 'danger')
        return redirect(url_for('admin.users'))

    peer = query(
        "SELECT * FROM vpn_peers WHERE user_id=%s AND is_active=1",
        (user_id,), one=True,
    )
    if peer:
        remove_peer(peer['public_key'])
        query("UPDATE vpn_peers SET is_active=0 WHERE id=%s", (peer['id'],), commit=True)
        release_ip(peer['vpn_ip'])
        query(
            "INSERT INTO connection_logs (user_id, vpn_ip, event_type, notes) "
            "VALUES (%s, %s, 'revoked', 'Revoked by admin')",
            (user_id, peer['vpn_ip']), commit=True,
        )

    query("UPDATE users SET is_active=0 WHERE id=%s", (user_id,), commit=True)
    flash(f'User "{user["username"]}" has been revoked.', 'warning')
    return redirect(url_for('admin.users'))


@admin_bp.route('/users/<int:user_id>/detail')
@_admin
def user_detail(user_id):
    user = query("SELECT * FROM users WHERE id=%s", (user_id,), one=True)
    if not user:
        flash('User not found.', 'danger')
        return redirect(url_for('admin.users'))
    peer = query("SELECT * FROM vpn_peers WHERE user_id=%s AND is_active=1", (user_id,), one=True)
    logs = query(
        "SELECT * FROM connection_logs WHERE user_id=%s ORDER BY event_time DESC LIMIT 30",
        (user_id,),
    )
    return render_template('admin/user_detail.html', user=user, peer=peer, logs=logs, now=datetime.now())


@admin_bp.route('/logs')
@_admin
def logs():
    page     = max(1, int(request.args.get('page', 1)))
    per_page = 20
    offset   = (page - 1) * per_page

    event_filter = request.args.get('event', '').strip()
    user_filter  = request.args.get('user',  '').strip()

    conditions = ['1=1']
    params: list = []
    if event_filter:
        conditions.append('cl.event_type=%s')
        params.append(event_filter)
    if user_filter:
        conditions.append('u.username LIKE %s')
        params.append(f'%{user_filter}%')

    where = ' AND '.join(conditions)

    total = query(
        f"SELECT COUNT(*) AS c FROM connection_logs cl "
        f"JOIN users u ON cl.user_id=u.id WHERE {where}",
        tuple(params), one=True,
    )['c']

    log_rows = query(
        f"SELECT cl.*, u.username FROM connection_logs cl "
        f"JOIN users u ON cl.user_id=u.id "
        f"WHERE {where} ORDER BY cl.event_time DESC LIMIT %s OFFSET %s",
        tuple(params) + (per_page, offset),
    )

    # Map points — only rows with valid coordinates
    raw_points = query(
        "SELECT cl.latitude, cl.longitude, cl.country, cl.city, u.username "
        "FROM connection_logs cl "
        "JOIN users u ON cl.user_id=u.id "
        "WHERE cl.event_type = 'connect' "
        "  AND cl.latitude != 0 AND cl.longitude != 0 "
        "ORDER BY cl.event_time DESC LIMIT 300"
    )
    map_points = [
        {
            'lat':      float(r['latitude']),
            'lon':      float(r['longitude']),
            'country':  r['country'],
            'city':     r['city'],
            'username': r['username'],
        }
        for r in raw_points
    ]

    return render_template(
        'admin/logs.html',
        logs=log_rows,
        map_points=map_points,
        page=page,
        total_pages=max(1, (total + per_page - 1) // per_page),
        event_filter=event_filter,
        user_filter=user_filter,
        total=total,
    )


@admin_bp.route('/peer-stats')
@_admin
def peer_stats_page():
    return render_template('admin/peer_stats.html')


@admin_bp.route('/api/peer-stats')
@_admin
def api_peer_stats():
    peer_stats   = get_peer_stats()
    active_peers = query(
        "SELECT vp.public_key, vp.vpn_ip, u.username "
        "FROM vpn_peers vp JOIN users u ON vp.user_id=u.id WHERE vp.is_active=1"
    )
    result = []
    for p in active_peers:
        s = peer_stats.get(p['public_key'], {})
        result.append({
            'username':       p['username'],
            'vpn_ip':         p['vpn_ip'],
            'last_handshake': s.get('last_handshake', 0),
            'rx':             s.get('rx', 0),
            'tx':             s.get('tx', 0),
        })
    return jsonify(result)
