import io
from datetime import datetime
from functools import wraps

import qrcode
import qrcode.image.pure
from flask import (Blueprint, current_app, flash, make_response,
                   redirect, render_template, request, session, url_for)

from routes.auth import login_required
from services.database import query
from services.geolocation import get_location
from services.wireguard import (add_peer, allocate_ip, generate_client_config,
                                 generate_keypair, generate_preshared_key,
                                 mark_ip_allocated, remove_peer)

user_bp = Blueprint('user', __name__)


def _user_only(f):
    @wraps(f)
    @login_required
    def wrapper(*args, **kwargs):
        if session.get('role') not in ('user', 'admin'):
            flash('Access denied.', 'danger')
            return redirect(url_for('auth.login'))
        return f(*args, **kwargs)
    return wrapper


@user_bp.route('/')
@_user_only
def dashboard():
    uid     = session['user_id']
    user    = query("SELECT * FROM users WHERE id=%s", (uid,), one=True)
    peer    = query("SELECT * FROM vpn_peers WHERE user_id=%s AND is_active=1", (uid,), one=True)
    logs    = query(
        "SELECT * FROM connection_logs WHERE user_id=%s ORDER BY event_time DESC LIMIT 6",
        (uid,),
    )
    now     = datetime.now()
    expired = user['expires_at'] < now
    days_left = max(0, (user['expires_at'] - now).days)

    return render_template(
        'user/dashboard.html',
        user=user, peer=peer, logs=logs,
        now=now, expired=expired, days_left=days_left,
    )


@user_bp.route('/vpn/generate', methods=['POST'])
@_user_only
def generate_vpn():
    uid  = session['user_id']
    user = query("SELECT * FROM users WHERE id=%s", (uid,), one=True)

    if user['expires_at'] < datetime.now():
        flash('Your account has expired. Contact an administrator to extend access.', 'danger')
        return redirect(url_for('user.dashboard'))

    if query("SELECT id FROM vpn_peers WHERE user_id=%s AND is_active=1", (uid,), one=True):
        flash('You already have an active VPN configuration.', 'info')
        return redirect(url_for('user.dashboard'))

    try:
        private_key, public_key = generate_keypair()
        preshared_key           = generate_preshared_key()
    except RuntimeError as exc:
        flash(f'Key generation failed: {exc}', 'danger')
        return redirect(url_for('user.dashboard'))

    ip_row = allocate_ip()
    if not ip_row:
        flash('No VPN IP addresses available. Please contact an administrator.', 'danger')
        return redirect(url_for('user.dashboard'))

    vpn_ip = ip_row['ip_address']

    ok, msg = add_peer(public_key, preshared_key, vpn_ip)
    if not ok:
        flash(f'Could not add VPN peer: {msg}', 'danger')
        return redirect(url_for('user.dashboard'))

    mark_ip_allocated(ip_row['id'], uid)

    cfg = current_app.config
    query(
        "INSERT INTO vpn_peers "
        "  (user_id, private_key, public_key, preshared_key, "
        "   vpn_ip, dns, server_endpoint, server_public_key) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        (uid, private_key, public_key, preshared_key,
         vpn_ip, cfg['WG_DNS'], cfg['WG_SERVER_ENDPOINT'], cfg['WG_SERVER_PUBLIC_KEY']),
        commit=True,
    )

    real_ip  = request.headers.get('X-Forwarded-For', request.remote_addr).split(',')[0].strip()
    loc      = get_location(real_ip)
    query(
        "INSERT INTO connection_logs "
        "  (user_id, vpn_ip, real_ip, country, city, latitude, longitude, event_type) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, 'key_generated')",
        (uid, vpn_ip, real_ip, loc['country'], loc['city'], loc['lat'], loc['lon']),
        commit=True,
    )

    flash('VPN configuration generated! Click "Download Config" to get your .conf file.', 'success')
    return redirect(url_for('user.dashboard'))


@user_bp.route('/vpn/download')
@_user_only
def download_config():
    uid  = session['user_id']
    peer = query("SELECT * FROM vpn_peers WHERE user_id=%s AND is_active=1", (uid,), one=True)

    if not peer:
        flash('No active VPN configuration found. Generate one first.', 'warning')
        return redirect(url_for('user.dashboard'))

    config_content = generate_client_config(
        peer['private_key'], peer['vpn_ip'], peer['preshared_key'],
    )

    query(
        "UPDATE vpn_peers SET config_downloaded=1 WHERE id=%s",
        (peer['id'],), commit=True,
    )

    real_ip = request.headers.get('X-Forwarded-For', request.remote_addr).split(',')[0].strip()
    loc     = get_location(real_ip)
    query(
        "INSERT INTO connection_logs "
        "  (user_id, vpn_ip, real_ip, country, city, latitude, longitude, event_type) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, 'config_download')",
        (uid, peer['vpn_ip'], real_ip, loc['country'], loc['city'], loc['lat'], loc['lon']),
        commit=True,
    )

    username = session['username']
    response = make_response(config_content)
    response.headers['Content-Type']        = 'application/octet-stream'
    response.headers['Content-Disposition'] = f'attachment; filename="{username}-wg.conf"'
    return response


@user_bp.route('/vpn/qrcode')
@_user_only
def config_qrcode():
    uid  = session['user_id']
    peer = query("SELECT * FROM vpn_peers WHERE user_id=%s AND is_active=1", (uid,), one=True)

    if not peer:
        flash('No active VPN configuration found. Generate one first.', 'warning')
        return redirect(url_for('user.dashboard'))

    config_content = generate_client_config(
        peer['private_key'], peer['vpn_ip'], peer['preshared_key'],
    )

    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=8,
        border=2,
        image_factory=qrcode.image.pure.PyPNGImage,
    )
    qr.add_data(config_content)
    qr.make(fit=True)

    buf = io.BytesIO()
    qr.make_image().save(buf)

    response = make_response(buf.getvalue())
    response.headers['Content-Type']  = 'image/png'
    response.headers['Cache-Control'] = 'no-store'
    return response
