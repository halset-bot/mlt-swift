#!/usr/bin/env node
// serve-preview.js — Dev server for the MLT visual preview.
//
// The browser fetches the raw MLT binary tile, decodes it client-side using a
// browser-wrapped build of mlt-bundle.cjs, and renders the layers in MapLibre
// GL JS — no pre-baked GeoJSON, no build step required.
//
// Usage (from repo root):
//   swift run MLTEncoderTests        # writes Tools/visual-demo.mlt
//   node Tools/serve-preview.js      # default port 3000
//   node Tools/serve-preview.js 8080 # custom port
//   open http://localhost:3000

'use strict';

const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT     = parseInt(process.argv[2] ?? '3000', 10);
const TOOLS    = __dirname;
const MLT_PATH = path.join(TOOLS, 'visual-demo.mlt');
const CJS_PATH = path.join(TOOLS, 'mlt-bundle.cjs');

// ── Tile metadata (must match the Swift encoder call) ─────────────────────────
const TILE_Z = 6, TILE_X = 33, TILE_Y = 19, EXTENT = 4096;

// ── Browser wrapper for mlt-bundle.cjs ───────────────────────────────────────
// The CJS bundle has no external requires and sets module.exports at line 28.
// We wrap it in an IIFE that provides a fake `module` object, then expose the
// result as window.MLT so the HTML page can call MLT.decodeTile() / MLT.GEOMETRY_TYPE.
const cjsSource = fs.readFileSync(CJS_PATH, 'utf8');
const BROWSER_BUNDLE = `
(function () {
  const module = { exports: {} };
${cjsSource}
  window.MLT = module.exports;
})();
`;

// ── HTML page ─────────────────────────────────────────────────────────────────
const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>MLTEncoder Preview (live tile)</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link  rel="stylesheet" href="https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.css" />
  <script src="https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.js"></script>
  <!-- Client-side MLT decoder (mlt-bundle.cjs wrapped for browser) -->
  <script src="/mlt-decode.js"></script>
  <style>
    html, body, #map { margin: 0; padding: 0; height: 100%; width: 100%; }
    #info {
      position: absolute; top: 10px; right: 10px;
      background: rgba(255,255,255,.92); border-radius: 8px;
      padding: 12px 16px; font: 13px/1.6 system-ui, sans-serif;
      box-shadow: 0 2px 8px rgba(0,0,0,.25); min-width: 200px;
    }
    #info h3 { margin: 0 0 8px; font-size: 14px; }
    .row { display: flex; align-items: center; gap: 8px; margin: 4px 0; }
    .sw  { width: 24px; height: 14px; border-radius: 3px; flex-shrink: 0; }
    .sw.line { height: 4px; }  .sw.pt { width: 14px; height: 14px; border-radius: 50%; }
    #status { margin-top: 8px; font-size: 11px; color: #666; }
  </style>
</head>
<body>
<div id="map"></div>

<div id="info">
  <h3>MLTEncoder Preview</h3>
  <div class="row"><div class="sw" style="background:rgba(70,130,180,.25);border:2px solid #4682b4"></div><span>Areas (polygon)</span></div>
  <div class="row"><div class="sw line" style="background:#e05c00"></div><span>Routes (line)</span></div>
  <div class="row"><div class="sw pt"   style="background:#2ecc71;border:2px solid #27ae60"></div><span>Cities (point)</span></div>
  <p id="status">Fetching tile…</p>
</div>

<script>
// ── Tile metadata ─────────────────────────────────────────────────────────────
const TILE_Z = ${TILE_Z}, TILE_X = ${TILE_X}, TILE_Y = ${TILE_Y}, EXTENT = ${EXTENT};

// ── Coordinate conversion: tile-space pixel → WGS-84 [lon, lat] ──────────────
function pixelToLonLat(px, py) {
  const n     = Math.pow(2, TILE_Z);
  const normX = (TILE_X + px / EXTENT) / n;
  const normY = (TILE_Y + py / EXTENT) / n;
  const lon   = normX * 360 - 180;
  const lat   = Math.atan(Math.sinh(Math.PI * (1 - 2 * normY))) * 180 / Math.PI;
  return [Math.round(lon * 1e6) / 1e6, Math.round(lat * 1e6) / 1e6];
}

function ringToLonLat(ring) { return ring.map(pt => pixelToLonLat(pt.x, pt.y)); }

// ── Decode MLT bytes → GeoJSON FeatureCollections per layer ──────────────────
function mltToGeoJSON(buffer) {
  const bytes  = new Uint8Array(buffer);
  const tables = MLT.decodeTile(bytes);
  const result = {};

  for (const table of tables) {
    const name     = table.name ?? 'unknown';
    const features = [];

    for (const feat of table) {
      const geom = feat.geometry;
      if (!geom) continue;

      const type   = MLT.GEOMETRY_TYPE[geom.type] ?? \`UNKNOWN_\${geom.type}\`;
      const coords = geom.coordinates;  // array of rings, each ring: array of {x,y} Points
      let g;

      switch (type) {
        case 'POINT':
          g = { type: 'Point', coordinates: pixelToLonLat(coords[0][0].x, coords[0][0].y) };
          break;
        case 'LINESTRING':
          g = { type: 'LineString', coordinates: ringToLonLat(coords[0]) };
          break;
        case 'POLYGON':
          g = { type: 'Polygon', coordinates: coords.map(ringToLonLat) };
          break;
        case 'MULTIPOINT':
          g = { type: 'MultiPoint', coordinates: coords.map(r => pixelToLonLat(r[0].x, r[0].y)) };
          break;
        case 'MULTILINESTRING':
          g = { type: 'MultiLineString', coordinates: coords.map(ringToLonLat) };
          break;
        case 'MULTIPOLYGON':
          g = { type: 'MultiPolygon', coordinates: coords.map(r => [ringToLonLat(r)]) };
          break;
        default:
          console.warn('Unsupported geometry:', type); continue;
      }

      features.push({ type: 'Feature', id: feat.id ?? undefined, geometry: g, properties: feat.properties ?? {} });
    }

    result[name] = { type: 'FeatureCollection', features };
  }

  return result;
}

// ── Map ───────────────────────────────────────────────────────────────────────
const map = new maplibregl.Map({
  container: 'map',
  style: {
    version: 8,
    glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
    sources: {
      osm: { type: 'raster', tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
             tileSize: 256, attribution: '© OpenStreetMap contributors', maxzoom: 19 },
    },
    layers: [{ id: 'osm', type: 'raster', source: 'osm', paint: { 'raster-opacity': 0.6 } }],
  },
  center: [8.8, 61.4],
  zoom: 6.5,
});

map.on('load', async () => {
  const status = document.getElementById('status');

  try {
    // ── 1. Fetch raw MLT bytes from the server ──────────────────────────────
    status.textContent = 'Fetching tile…';
    const resp = await fetch('/tiles/visual-demo.mlt');
    if (!resp.ok) throw new Error(\`HTTP \${resp.status}\`);
    const buffer = await resp.arrayBuffer();
    status.textContent = \`Tile: \${buffer.byteLength} bytes\`;

    // ── 2. Decode MLT client-side ─────────────────────────────────────────
    const layers = mltToGeoJSON(buffer);
    const names  = Object.keys(layers);
    status.textContent = \`Decoded: \${names.join(', ')} (\${buffer.byteLength}B)\`;

    // ── 3. Add each layer as a GeoJSON source ─────────────────────────────
    for (const [name, fc] of Object.entries(layers)) {
      map.addSource(name, { type: 'geojson', data: fc });
    }

    // ── 4. Style layers ────────────────────────────────────────────────────
    if (layers.areas) {
      map.addLayer({ id: 'areas-fill', type: 'fill', source: 'areas',
        paint: { 'fill-color': '#4682b4', 'fill-opacity': 0.15 } });
      map.addLayer({ id: 'areas-outline', type: 'line', source: 'areas',
        paint: { 'line-color': '#4682b4', 'line-width': 2, 'line-dasharray': [4, 3] } });
    }

    if (layers.routes) {
      map.addLayer({ id: 'routes-line', type: 'line', source: 'routes',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#e05c00', 'line-width': 3 } });
      map.addLayer({ id: 'routes-label', type: 'symbol', source: 'routes',
        layout: { 'symbol-placement': 'line', 'text-field': ['get', 'name'],
                  'text-size': 12, 'text-offset': [0, -0.8] },
        paint: { 'text-color': '#e05c00', 'text-halo-color': '#fff', 'text-halo-width': 1.5 } });
    }

    if (layers.cities) {
      map.addLayer({ id: 'cities-circle', type: 'circle', source: 'cities',
        paint: { 'circle-radius': 7, 'circle-color': '#2ecc71',
                 'circle-stroke-color': '#27ae60', 'circle-stroke-width': 2 } });
      map.addLayer({ id: 'cities-label', type: 'symbol', source: 'cities',
        layout: { 'text-field': ['get', 'name'], 'text-size': 13,
                  'text-offset': [0, -1.5], 'text-anchor': 'bottom' },
        paint: { 'text-color': '#1a5c2a', 'text-halo-color': '#fff', 'text-halo-width': 1.5 } });
    }

    // ── 5. Click popup ─────────────────────────────────────────────────────
    const clickLayers = ['cities-circle','routes-line','areas-fill'].filter(id => map.getLayer(id));
    map.on('click', clickLayers, e => {
      const props = e.features[0].properties;
      const html  = Object.entries(props).map(([k,v]) => \`<b>\${k}</b>: \${v}\`).join('<br>');
      new maplibregl.Popup().setLngLat(e.lngLat).setHTML(html || '(no properties)').addTo(map);
    });
    clickLayers.forEach(id => {
      map.on('mouseenter', id, () => { map.getCanvas().style.cursor = 'pointer'; });
      map.on('mouseleave', id, () => { map.getCanvas().style.cursor = ''; });
    });

  } catch (err) {
    status.textContent = \`Error: \${err.message}\`;
    console.error(err);
  }
});
</script>
</body>
</html>`;

// ── HTTP server ───────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];

    if (url === '/' || url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        return res.end(HTML);
    }

    if (url === '/mlt-decode.js') {
        res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8' });
        return res.end(BROWSER_BUNDLE);
    }

    if (url === '/tiles/visual-demo.mlt') {
        if (!fs.existsSync(MLT_PATH)) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            return res.end('visual-demo.mlt not found — run: swift run MLTEncoderTests');
        }
        const data = fs.readFileSync(MLT_PATH);
        res.writeHead(200, {
            'Content-Type':                'application/octet-stream',
            'Content-Disposition':         'inline; filename="visual-demo.mlt"',
            'Access-Control-Allow-Origin': '*',
            'Content-Length':              data.length,
        });
        return res.end(data);
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
});

server.listen(PORT, () => {
    console.log(`MLT preview server running at http://localhost:${PORT}`);
    console.log(`  Serving tile: ${MLT_PATH}`);
    console.log(`  Endpoints:`);
    console.log(`    GET /                     → preview page`);
    console.log(`    GET /mlt-decode.js        → browser MLT decoder`);
    console.log(`    GET /tiles/visual-demo.mlt → raw MLT bytes`);
    console.log(`\nTip: re-run swift run MLTEncoderTests and refresh the browser to see updated tiles.`);
});
