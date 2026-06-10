import os

import requests

_PRIVATE = (
    '10.', '127.', '::1',
    '172.16.', '172.17.', '172.18.', '172.19.',
    '172.20.', '172.21.', '172.22.', '172.23.',
    '172.24.', '172.25.', '172.26.', '172.27.',
    '172.28.', '172.29.', '172.30.', '172.31.',
    '192.168.', 'fc', 'fd',
)

_UNKNOWN = {'country': 'Unknown', 'city': 'Unknown', 'lat': 0.0, 'lon': 0.0}

# Local MaxMind GeoLite2 database (kept updated by geoipupdate).
# Falls back to ip-api.com when the file or geoip2 lib is unavailable.
GEOIP_DB = os.environ.get('GEOIP_DB', '/var/lib/GeoIP/GeoLite2-City.mmdb')

_reader = None


def _is_private(ip: str) -> bool:
    return not ip or any(ip.startswith(p) for p in _PRIVATE)


def _get_reader():
    global _reader
    if _reader is None and os.path.isfile(GEOIP_DB):
        try:
            import geoip2.database
            _reader = geoip2.database.Reader(GEOIP_DB)
        except Exception:
            _reader = False
    return _reader or None


def _lookup_geolite(ip_address: str):
    reader = _get_reader()
    if not reader:
        return None
    try:
        r = reader.city(ip_address)
        city = r.city.name or r.subdivisions.most_specific.name
        # Incomplete record (country only) — fall through to ip-api
        if not city or not r.country.name:
            return None
        return {
            'country': r.country.name,
            'city':    city,
            'lat':     float(r.location.latitude or 0.0),
            'lon':     float(r.location.longitude or 0.0),
        }
    except Exception:
        return None


def _lookup_ipapi(ip_address: str):
    try:
        resp = requests.get(
            f'http://ip-api.com/json/{ip_address}?fields=status,country,city,lat,lon',
            timeout=4,
        )
        data = resp.json()
        if data.get('status') == 'success':
            return {
                'country': data.get('country', 'Unknown'),
                'city':    data.get('city',    'Unknown'),
                'lat':     float(data.get('lat', 0.0)),
                'lon':     float(data.get('lon', 0.0)),
            }
    except Exception:
        pass
    return None


def get_location(ip_address: str) -> dict:
    if _is_private(ip_address):
        return {'country': 'Local', 'city': 'Private Network', 'lat': 0.0, 'lon': 0.0}
    return _lookup_geolite(ip_address) or _lookup_ipapi(ip_address) or _UNKNOWN
