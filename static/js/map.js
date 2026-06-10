(function () {
  'use strict';

  const el = document.getElementById('geoMap');
  if (!el) return;

  const map = L.map('geoMap', {
    center: [20, 0],
    zoom: 2,
    minZoom: 1,
    maxZoom: 18,
    zoomControl: true,
    attributionControl: true,
  });

  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> ' +
      '&copy; <a href="https://carto.com/">CARTO</a>',
    subdomains: 'abcd',
    maxZoom: 20,
  }).addTo(map);

  const COLOURS = {
    key_generated:   '#0d6efd',
    config_download: '#0dcaf0',
    connect:         '#198754',
    disconnect:      '#6c757d',
    revoked:         '#dc3545',
    expired:         '#ffc107',
  };

  function makeIcon(eventType) {
    const colour = COLOURS[eventType] || '#adb5bd';
    const svg = `
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="26" viewBox="0 0 20 26">
        <ellipse cx="10" cy="24" rx="5" ry="2" fill="rgba(0,0,0,.4)"/>
        <path d="M10 0C6 0 2 3.5 2 8c0 6 8 18 8 18S18 14 18 8C18 3.5 14 0 10 0z"
              fill="${colour}" stroke="#fff" stroke-width="1.5"/>
        <circle cx="10" cy="8" r="3.5" fill="#fff" fill-opacity=".9"/>
      </svg>`;
    return L.divIcon({
      className: '',
      html: svg,
      iconSize:   [20, 26],
      iconAnchor: [10, 26],
      popupAnchor:[0, -26],
    });
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  const points = (typeof MAP_POINTS !== 'undefined') ? MAP_POINTS : [];

  if (points.length === 0) {
    el.style.cssText = 'display:flex;align-items:center;justify-content:center;';
    el.innerHTML = '<p style="color:#666;font-size:.85rem;">No geolocation data available yet.</p>';
    return;
  }

  // Store connect markers by "lat,lon" so rows can fly to them
  const connectMarkers = {};

  const seen = {};
  points.forEach(function (pt) {
    const key = `${pt.lat.toFixed(2)},${pt.lon.toFixed(2)}`;
    seen[key] = (seen[key] || 0) + 1;
    const jitter = (seen[key] - 1) * 0.003;

    const label  = pt.event_type.replace(/_/g, ' ');
    const colour = COLOURS[pt.event_type] || '#adb5bd';

    const popup = L.popup({ maxWidth: 220, className: 'vpn-popup' }).setContent(`
      <div style="line-height:1.6">
        <div style="font-weight:700;font-size:.9rem;margin-bottom:4px">
          ${escapeHtml(pt.username)}
        </div>
        <div>
          <span style="display:inline-block;width:10px;height:10px;
                       border-radius:50%;background:${colour};margin-right:5px;
                       vertical-align:middle;"></span>
          <em>${label}</em>
        </div>
        <div style="color:#888;margin-top:3px;font-size:.8rem">
          📍 ${escapeHtml(pt.city)}, ${escapeHtml(pt.country)}
        </div>
      </div>`);

    const marker = L.marker([pt.lat + jitter, pt.lon + jitter], { icon: makeIcon(pt.event_type) })
      .bindPopup(popup)
      .addTo(map);

    // Index the first connect marker at each location for row click
    if (pt.event_type === 'connect') {
      const ck = `${pt.lat.toFixed(4)},${pt.lon.toFixed(4)}`;
      if (!connectMarkers[ck]) connectMarkers[ck] = marker;
    }
  });

  try {
    const latLngs = points.map(p => [p.lat, p.lon]);
    map.fitBounds(L.latLngBounds(latLngs).pad(0.15));
  } catch (_) {
    map.setView([20, 0], 2);
  }

  // Legend
  const legend = L.control({ position: 'bottomright' });
  legend.onAdd = function () {
    const div = L.DomUtil.create('div');
    div.style.cssText =
      'background:#1e1e1e;border:1px solid #2a2a2a;border-radius:6px;' +
      'padding:8px 12px;font-size:.75rem;color:#ccc;line-height:1.8;';
    div.innerHTML = Object.entries(COLOURS).map(([k, c]) =>
      `<span style="display:inline-block;width:10px;height:10px;border-radius:50%;` +
      `background:${c};margin-right:5px;vertical-align:middle;"></span>` +
      k.replace(/_/g, ' ') + '<br>'
    ).join('');
    return div;
  };
  legend.addTo(map);

  // Global function — called by table row click handlers
  window.flyToMarker = function (lat, lon) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    map.flyTo([lat, lon], 13, { animate: true, duration: 1.2 });
    const ck = `${parseFloat(lat).toFixed(4)},${parseFloat(lon).toFixed(4)}`;
    if (connectMarkers[ck]) {
      setTimeout(function () { connectMarkers[ck].openPopup(); }, 1300);
    }
  };
})();
