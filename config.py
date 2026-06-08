import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()


class Config:
    # Flask
    SECRET_KEY = os.environ.get('SECRET_KEY', os.urandom(32).hex())
    SESSION_PERMANENT          = False
    PERMANENT_SESSION_LIFETIME = timedelta(hours=4)

    # MySQL
    MYSQL_HOST     = os.environ.get('MYSQL_HOST',     'localhost')
    MYSQL_USER     = os.environ.get('MYSQL_USER',     'vpnuser')
    MYSQL_PASSWORD = os.environ.get('MYSQL_PASSWORD', 'vpnpassword')
    MYSQL_DB       = os.environ.get('MYSQL_DB',       'vpn_system')
    MYSQL_PORT     = int(os.environ.get('MYSQL_PORT', 3306))

    # WireGuard
    WG_INTERFACE        = os.environ.get('WG_INTERFACE',        'wg0')
    WG_SERVER_PUBLIC_KEY = os.environ.get('WG_SERVER_PUBLIC_KEY', 'REPLACE_WITH_SERVER_PUBLIC_KEY')
    WG_SERVER_ENDPOINT   = os.environ.get('WG_SERVER_ENDPOINT',   '0.0.0.0:51820')
    WG_DNS               = os.environ.get('WG_DNS',               '1.1.1.1, 1.0.0.1')
    WG_CONFIG_PATH       = os.environ.get('WG_CONFIG_PATH',       '/etc/wireguard/wg0.conf')

    # Paths
    BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
    SCRIPTS_PATH = os.path.join(BASE_DIR, 'scripts')

    # Defaults
    DEFAULT_EXPIRY_DAYS = int(os.environ.get('DEFAULT_EXPIRY_DAYS', 7))
    GEOLOCATION_API     = 'http://ip-api.com/json/'
