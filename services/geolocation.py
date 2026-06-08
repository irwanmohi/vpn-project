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


def _is_private(ip: str) -> bool:
    return not ip or any(ip.startswith(p) for p in _PRIVATE)


def get_location(ip_address: str) -> dict:
    if _is_private(ip_address):
        return {'country': 'Local', 'city': 'Private Network', 'lat': 0.0, 'lon': 0.0}
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
    return _UNKNOWN
