var vpnMap = null;

(function () {
  'use strict';

  var el = document.getElementById('geoMap');
  if (!el) return;

  vpnMap = L.map('geoMap', {
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
  }).addTo(vpnMap);

  var PIN_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="26" viewBox="0 0 20 26">' +
      '<ellipse cx="10" cy="24" rx="5" ry="2" fill="rgba(0,0,0,.4)"/>' +
      '<path d="M10 0C6 0 2 3.5 2 8c0 6 8 18 8 18S18 14 18 8C18 3.5 14 0 10 0z"' +
      '  fill="#198754" stroke="#fff" stroke-width="1.5"/>' +
      '<circle cx="10" cy="8" r="3.5" fill="#fff" fill-opacity=".9"/>' +
    '</svg>';

  var PIN_ICON = L.divIcon({
    className: '',
    html: PIN_SVG,
    iconSize:    [20, 26],
    iconAnchor:  [10, 26],
    popupAnchor: [0, -26],
  });

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  var points = (typeof MAP_POINTS !== 'undefined') ? MAP_POINTS : [];

  if (points.length === 0) {
    el.style.cssText = 'display:flex;align-items:center;justify-content:center;';
    el.innerHTML = '<p style="color:#666;font-size:.85rem;">No connection data available yet.</p>';
    return;
  }

  var seen = {};
  points.forEach(function (pt) {
    var key = pt.lat.toFixed(2) + ',' + pt.lon.toFixed(2);
    seen[key] = (seen[key] || 0) + 1;
    var jitter = (seen[key] - 1) * 0.003;

    var popupHtml =
      '<div style="line-height:1.6">' +
        '<div style="font-weight:700;font-size:.9rem;margin-bottom:4px">' + escapeHtml(pt.username) + '</div>' +
        '<div><span style="display:inline-block;width:10px;height:10px;border-radius:50%;' +
          'background:#198754;margin-right:5px;vertical-align:middle;"></span>' +
          '<em>connected</em></div>' +
        '<div style="color:#888;margin-top:3px;font-size:.8rem">📍 ' +
          escapeHtml(pt.city) + ', ' + escapeHtml(pt.country) + '</div>' +
      '</div>';

    L.marker([pt.lat + jitter, pt.lon + jitter], { icon: PIN_ICON })
      .bindPopup(L.popup({ maxWidth: 220 }).setContent(popupHtml))
      .addTo(vpnMap);
  });

  try {
    var latLngs = points.map(function (p) { return [p.lat, p.lon]; });
    // maxZoom caps single-point fits — full zoom renders almost black on dark tiles
    vpnMap.fitBounds(L.latLngBounds(latLngs).pad(0.2), { maxZoom: 11 });
  } catch (e) {
    vpnMap.setView([20, 0], 2);
  }
})();
