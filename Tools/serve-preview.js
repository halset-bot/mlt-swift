#!/usr/bin/env node
// serve-preview.js — Dev server for the MLT visual preview.
//
// MapLibre GL JS reads the MLT tile directly via a vector source with
// encoding "mlt" — no client-side decoding or GeoJSON conversion.
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

// Demo tile coordinates — must match the Swift encoder call.
const TILE_Z = 6, TILE_X = 33, TILE_Y = 19;

// ── HTML page ─────────────────────────────────────────────────────────────────
const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>MLTEncoder Preview</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link  rel="stylesheet" href="https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.css" />
  <script src="https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.js"></script>
  <style>
    html, body, #map { margin: 0; padding: 0; height: 100%; width: 100%; }
    #legend {
      position: absolute; top: 10px; right: 10px;
      background: rgba(255,255,255,.92); border-radius: 8px;
      padding: 12px 16px; font: 13px/1.6 system-ui, sans-serif;
      box-shadow: 0 2px 8px rgba(0,0,0,.25); min-width: 190px;
    }
    #legend h3 { margin: 0 0 8px; font-size: 14px; }
    .row { display: flex; align-items: center; gap: 8px; margin: 4px 0; }
    .sw           { width: 24px; height: 14px; border-radius: 3px; flex-shrink: 0; }
    .sw.line      { height: 4px; }
    .sw.pt        { width: 14px; height: 14px; border-radius: 50%; }
  </style>
</head>
<body>
<div id="map"></div>

<div id="legend">
  <h3>MLTEncoder Preview</h3>
  <div class="row"><div class="sw" style="background:rgba(70,130,180,.25);border:2px solid #4682b4"></div><span>Areas (polygon)</span></div>
  <div class="row"><div class="sw line" style="background:#e05c00"></div><span>Routes (line)</span></div>
  <div class="row"><div class="sw pt" style="background:#2ecc71;border:2px solid #27ae60"></div><span>Cities (point)</span></div>
  <p style="margin:8px 0 0;font-size:11px;color:#666">
    Tile z=${TILE_Z} x=${TILE_X} y=${TILE_Y}<br>encoding: mlt
  </p>
</div>

<script>
const map = new maplibregl.Map({
  container: 'map',
  style: {
    version: 8,
    glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
    sources: {
      osm: {
        type: 'raster',
        tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
        tileSize: 256,
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxzoom: 19,
      },
      demo: {
        type: 'vector',
        encoding: 'mlt',
        tiles: [\`\${location.origin}/tiles/{z}/{x}/{y}.mlt\`],
        minzoom: ${TILE_Z},
        maxzoom: ${TILE_Z},
      },
    },
    layers: [
      // Base map
      { id: 'osm', type: 'raster', source: 'osm',
        paint: { 'raster-opacity': 0.6 } },

      // Polygon fill — areas layer
      { id: 'areas-fill', type: 'fill', source: 'demo', 'source-layer': 'areas',
        paint: { 'fill-color': '#4682b4', 'fill-opacity': 0.15 } },
      { id: 'areas-outline', type: 'line', source: 'demo', 'source-layer': 'areas',
        paint: { 'line-color': '#4682b4', 'line-width': 2, 'line-dasharray': [4, 3] } },

      // Line — routes layer
      { id: 'routes-line', type: 'line', source: 'demo', 'source-layer': 'routes',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#e05c00', 'line-width': 3 } },
      { id: 'routes-label', type: 'symbol', source: 'demo', 'source-layer': 'routes',
        layout: { 'symbol-placement': 'line', 'text-field': ['get', 'name'],
                  'text-size': 12, 'text-offset': [0, -0.8] },
        paint: { 'text-color': '#e05c00', 'text-halo-color': '#fff', 'text-halo-width': 1.5 } },

      // Points — cities layer
      { id: 'cities-circle', type: 'circle', source: 'demo', 'source-layer': 'cities',
        paint: { 'circle-radius': 7, 'circle-color': '#2ecc71',
                 'circle-stroke-color': '#27ae60', 'circle-stroke-width': 2 } },
      { id: 'cities-label', type: 'symbol', source: 'demo', 'source-layer': 'cities',
        layout: { 'text-field': ['get', 'name'], 'text-size': 13,
                  'text-offset': [0, -1.5], 'text-anchor': 'bottom' },
        paint: { 'text-color': '#1a5c2a', 'text-halo-color': '#fff', 'text-halo-width': 1.5 } },
    ],
  },
  center: [8.8, 61.4],
  zoom: 6.5,
});

// Click popup
map.on('click', ['cities-circle', 'routes-line', 'areas-fill'], e => {
  const props = e.features[0].properties;
  const html  = Object.entries(props).map(([k, v]) => \`<b>\${k}</b>: \${v}\`).join('<br>');
  new maplibregl.Popup().setLngLat(e.lngLat).setHTML(html || '(no properties)').addTo(map);
});
['cities-circle', 'routes-line', 'areas-fill'].forEach(id => {
  map.on('mouseenter', id, () => { map.getCanvas().style.cursor = 'pointer'; });
  map.on('mouseleave', id, () => { map.getCanvas().style.cursor = ''; });
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

    // Tile requests: /tiles/{z}/{x}/{y}.mlt
    const tileMatch = url.match(/^\/tiles\/(\d+)\/(\d+)\/(\d+)\.mlt$/);
    if (tileMatch) {
        const [, z, x, y] = tileMatch.map(Number);
        if (z === TILE_Z && x === TILE_X && y === TILE_Y) {
            if (!fs.existsSync(MLT_PATH)) {
                res.writeHead(404, { 'Content-Type': 'text/plain' });
                return res.end('visual-demo.mlt not found — run: swift run MLTEncoderTests');
            }
            const data = fs.readFileSync(MLT_PATH);
            res.writeHead(200, {
                'Content-Type':                'application/octet-stream',
                'Access-Control-Allow-Origin': '*',
                'Content-Length':              data.length,
            });
            return res.end(data);
        }
        // Any other tile → empty 204 (MapLibre will skip it)
        res.writeHead(204);
        return res.end();
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
});

server.listen(PORT, () => {
    console.log(`MLT preview server → http://localhost:${PORT}`);
    console.log(`  Tile: /tiles/{z}/{x}/{y}.mlt  (serves ${TILE_Z}/${TILE_X}/${TILE_Y})`);
    console.log(`  Re-run swift run MLTEncoderTests and refresh to pick up new tiles.`);
});
