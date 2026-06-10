import os
import subprocess
from flask import current_app
from services.database import query


def _run(cmd: list, input_data: str = None):
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            capture_output=True,
            text=True,
            timeout=15,
        )
        return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
    except FileNotFoundError:
        return False, '', f'Command not found: {cmd[0]}'
    except subprocess.TimeoutExpired:
        return False, '', f'Command timed out: {" ".join(cmd)}'


def generate_keypair():
    ok, priv, err = _run(['wg', 'genkey'])
    if not ok:
        raise RuntimeError(f'wg genkey failed: {err}')
    ok2, pub, err2 = _run(['wg', 'pubkey'], input_data=priv + '\n')
    if not ok2:
        raise RuntimeError(f'wg pubkey failed: {err2}')
    return priv, pub


def generate_preshared_key():
    ok, psk, err = _run(['wg', 'genpsk'])
    if not ok:
        raise RuntimeError(f'wg genpsk failed: {err}')
    return psk


def allocate_ip():
    return query(
        "SELECT id, ip_address FROM ip_pool WHERE is_allocated = 0 ORDER BY id LIMIT 1",
        one=True,
    )


def mark_ip_allocated(pool_id: int, user_id: int):
    query(
        "UPDATE ip_pool SET is_allocated=1, allocated_to=%s, allocated_at=NOW() WHERE id=%s",
        (user_id, pool_id),
        commit=True,
    )


def release_ip(ip_address: str):
    query(
        "UPDATE ip_pool SET is_allocated=0, allocated_to=NULL, allocated_at=NULL "
        "WHERE ip_address=%s",
        (ip_address,),
        commit=True,
    )


def add_peer(public_key: str, preshared_key: str, vpn_ip: str):
    script = os.path.join(current_app.config['SCRIPTS_PATH'], 'add_peer.sh')
    if not os.path.isfile(script):
        return False, f'Script not found: {script}'
    ok, out, err = _run(['bash', script, public_key, preshared_key, vpn_ip])
    return ok, (err or out)


def remove_peer(public_key: str):
    script = os.path.join(current_app.config['SCRIPTS_PATH'], 'remove_peer.sh')
    if not os.path.isfile(script):
        return False, f'Script not found: {script}'
    ok, out, err = _run(['bash', script, public_key])
    return ok, (err or out)


def generate_client_config(private_key: str, vpn_ip: str, preshared_key: str) -> str:
    cfg = current_app.config
    return (
        f"[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"Address = {vpn_ip}/32\n"
        f"DNS = {cfg['WG_DNS']}\n"
        f"\n"
        f"[Peer]\n"
        f"PublicKey = {cfg['WG_SERVER_PUBLIC_KEY']}\n"
        f"PresharedKey = {preshared_key}\n"
        f"Endpoint = {cfg['WG_SERVER_ENDPOINT']}\n"
        f"AllowedIPs = 0.0.0.0/0, ::/0\n"
        f"PersistentKeepalive = 25\n"
    )


def get_peer_stats() -> dict:
    iface = current_app.config['WG_INTERFACE']
    ok, out, _ = _run(['wg', 'show', iface, 'dump'])
    if not ok or not out:
        return {}

    peers = {}
    for line in out.splitlines()[1:]:   # skip server line
        parts = line.split('\t')
        if len(parts) < 7:
            continue
        peers[parts[0]] = {
            'endpoint':       parts[2],
            'last_handshake': int(parts[4]) if parts[4].isdigit() else 0,
            'rx':             int(parts[5]) if parts[5].isdigit() else 0,
            'tx':             int(parts[6]) if parts[6].isdigit() else 0,
        }
    return peers


def is_interface_up() -> bool:
    iface = current_app.config['WG_INTERFACE']
    ok, _, _ = _run(['wg', 'show', iface])
    return ok
