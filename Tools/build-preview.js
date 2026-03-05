#!/usr/bin/env node
// build-preview.js — Reads Tools/visual-demo.mlt and generates
// Tools/preview.html: a self-contained MapLibre GL JS map page showing the
// encoded geometry types (polygon-fill, line, points with labels).
//
// Usage (from repo root):
//   swift run MLTEncoderTests        # writes Tools/visual-demo.mlt
//   node Tools/build-preview.js      # writes Tools/preview.html
//   open Tools/preview.html

'use strict';

const path = require('path');
const fs   = require('fs');

const { decodeTile, GEOMETRY_TYPE } = require(path.join(__dirname, 'mlt-bundle.cjs'));

// ── Tile metadata ──────────────────────────────────────────────────────────────
// Must match the Swift encoder call in the visual demo test.
const TILE_Z  = 6;
const TILE_X  = 33;
const TILE_Y  = 19;
const EXTENT  = 4096;

// ── Coordinate conversion: tile-space pixel → WGS-84 [lon, lat] ───────────────
function pixelToLonLat(px, py) {
    const n     = Math.pow(2, TILE_Z);
    const normX = (TILE_X + px / EXTENT) / n;
    const normY = (TILE_Y + py / EXTENT) / n;
    const lon   = normX * 360 - 180;
    const lat   = Math.atan(Math.sinh(Math.PI * (1 - 2 * normY))) * 180 / Math.PI;
    return [
        Math.round(lon * 1e6) / 1e6,
        Math.round(lat * 1e6) / 1e6,
    ];
}

function ringToLonLat(ring) {
    return ring.map(pt => pixelToLonLat(pt.x, pt.y));
}

// ── Decode MLT → GeoJSON FeatureCollections keyed by layer name ────────────────
const mltPath = path.join(__dirname, 'visual-demo.mlt');
if (!fs.existsSync(mltPath)) {
    console.error(`ERROR: ${mltPath} not found.\nRun: swift run MLTEncoderTests`);
    process.exit(1);
}

const bytes        = new Uint8Array(fs.readFileSync(mltPath));
const featureTables = decodeTile(bytes);

const layers = {};   // { layerName: GeoJSON FeatureCollection }

for (const table of featureTables) {
    const name     = table.name ?? 'unknown';
    const features = [];

    for (const feat of table) {
        const geom = feat.geometry;
        if (!geom) continue;

        const typeName = GEOMETRY_TYPE[geom.type] ?? `UNKNOWN_${geom.type}`;
        const coords   = geom.coordinates;   // array of rings (each: array of {x,y} Points)
        let geojsonGeom;

        switch (typeName) {
            case 'POINT':
                // coords = [[{x,y}]]  — one ring, one vertex
                geojsonGeom = { type: 'Point', coordinates: pixelToLonLat(coords[0][0].x, coords[0][0].y) };
                break;

            case 'LINESTRING':
                // coords = [[{x,y}, ...]]
                geojsonGeom = { type: 'LineString', coordinates: ringToLonLat(coords[0]) };
                break;

            case 'POLYGON':
                // coords = [outerRing, ...holes]
                geojsonGeom = { type: 'Polygon', coordinates: coords.map(ringToLonLat) };
                break;

            case 'MULTIPOINT':
                // coords = [[[{x,y}]], ...]  — one ring per point
                geojsonGeom = { type: 'MultiPoint', coordinates: coords.map(r => pixelToLonLat(r[0].x, r[0].y)) };
                break;

            case 'MULTILINESTRING':
                geojsonGeom = { type: 'MultiLineString', coordinates: coords.map(ringToLonLat) };
                break;

            case 'MULTIPOLYGON':
                // coords = [polygon, ...]  where polygon = [ring, ...]
                // The MLT decoder flattens multi-polygon as a flat list of rings;
                // treat each ring as a separate single-ring polygon for now.
                geojsonGeom = { type: 'MultiPolygon', coordinates: coords.map(r => [ringToLonLat(r)]) };
                break;

            default:
                console.warn(`Skipping unsupported geometry type: ${typeName}`);
                continue;
        }

        features.push({
            type:       'Feature',
            id:         feat.id ?? undefined,
            geometry:   geojsonGeom,
            properties: feat.properties ?? {},
        });
    }

    layers[name] = { type: 'FeatureCollection', features };
}

console.log(`Decoded layers: ${Object.keys(layers).join(', ')}`);

// ── Generate HTML ──────────────────────────────────────────────────────────────
const geojsonBlock = JSON.stringify(layers, null, 2);

const html = `<!DOCTYPE html>
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
      position: absolute;
      top: 10px; right: 10px;
      background: rgba(255,255,255,0.92);
      border-radius: 8px;
      padding: 12px 16px;
      font: 13px/1.6 system-ui, sans-serif;
      box-shadow: 0 2px 8px rgba(0,0,0,.25);
      min-width: 180px;
    }
    #legend h3 { margin: 0 0 8px; font-size: 14px; }
    .legend-row { display: flex; align-items: center; gap: 8px; margin: 4px 0; }
    .swatch      { width: 24px; height: 14px; border-radius: 3px; flex-shrink: 0; }
    .swatch.line { height: 4px; border-radius: 2px; }
    .swatch.pt   { width: 14px; height: 14px; border-radius: 50%; }
  </style>
</head>
<body>
<div id="map"></div>

<div id="legend">
  <h3>MLTEncoder Preview</h3>
  <div class="legend-row">
    <div class="swatch" style="background:rgba(70,130,180,.25);border:2px solid #4682b4;"></div>
    <span>Areas (polygon-fill)</span>
  </div>
  <div class="legend-row">
    <div class="swatch line" style="background:#e05c00;"></div>
    <span>Routes (line)</span>
  </div>
  <div class="legend-row">
    <div class="swatch pt" style="background:#2ecc71;border:2px solid #27ae60;"></div>
    <span>Cities (point)</span>
  </div>
  <p style="margin:8px 0 0;font-size:11px;color:#666;">
    Tile z=${TILE_Z} x=${TILE_X} y=${TILE_Y}<br>
    Generated by MLTEncoder
  </p>
</div>

<script>
// ── Embedded GeoJSON (generated by build-preview.js) ────────────────────────
const LAYERS = ${geojsonBlock};

// ── Map setup ─────────────────────────────────────────────────────────────────
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
    },
    layers: [
      { id: 'osm', type: 'raster', source: 'osm', paint: { 'raster-opacity': 0.6 } },
    ],
  },
  center: [8.8, 61.4],
  zoom: 6.5,
});

map.on('load', () => {

  // ── Add each decoded layer as a GeoJSON source ──────────────────────────────
  for (const [name, fc] of Object.entries(LAYERS)) {
    map.addSource(name, { type: 'geojson', data: fc });
  }

  // ── Polygon fill (areas layer) ──────────────────────────────────────────────
  if (LAYERS.areas) {
    map.addLayer({
      id:     'areas-fill',
      type:   'fill',
      source: 'areas',
      paint: {
        'fill-color':   '#4682b4',
        'fill-opacity': 0.15,
      },
    });
    map.addLayer({
      id:     'areas-outline',
      type:   'line',
      source: 'areas',
      paint: {
        'line-color': '#4682b4',
        'line-width': 2,
        'line-dasharray': [4, 3],
      },
    });
  }

  // ── Line (routes layer) ────────────────────────────────────────────────────
  if (LAYERS.routes) {
    map.addLayer({
      id:     'routes-line',
      type:   'line',
      source: 'routes',
      layout: {
        'line-cap':  'round',
        'line-join': 'round',
      },
      paint: {
        'line-color': '#e05c00',
        'line-width': 3,
      },
    });
    map.addLayer({
      id:     'routes-label',
      type:   'symbol',
      source: 'routes',
      layout: {
        'symbol-placement': 'line',
        'text-field':       ['get', 'name'],
        'text-size':        12,
        'text-offset':      [0, -0.8],
      },
      paint: {
        'text-color':       '#e05c00',
        'text-halo-color':  '#fff',
        'text-halo-width':  1.5,
      },
    });
  }

  // ── Points / circles (cities layer) ────────────────────────────────────────
  if (LAYERS.cities) {
    map.addLayer({
      id:     'cities-circle',
      type:   'circle',
      source: 'cities',
      paint: {
        'circle-radius':       7,
        'circle-color':        '#2ecc71',
        'circle-stroke-color': '#27ae60',
        'circle-stroke-width': 2,
      },
    });
    map.addLayer({
      id:     'cities-label',
      type:   'symbol',
      source: 'cities',
      layout: {
        'text-field':  ['get', 'name'],
        'text-size':   13,
        'text-offset': [0, -1.5],
        'text-anchor': 'bottom',
      },
      paint: {
        'text-color':      '#1a5c2a',
        'text-halo-color': '#fff',
        'text-halo-width': 1.5,
      },
    });
  }

  // ── Popup on click ────────────────────────────────────────────────────────
  const clickLayers = ['cities-circle', 'routes-line', 'areas-fill'].filter(id => map.getLayer(id));
  map.on('click', clickLayers, e => {
    const f    = e.features[0];
    const props = f.properties;
    const html  = Object.entries(props)
      .map(([k, v]) => \`<b>\${k}</b>: \${v}\`)
      .join('<br>');
    new maplibregl.Popup()
      .setLngLat(e.lngLat)
      .setHTML(html || '(no properties)')
      .addTo(map);
  });

  clickLayers.forEach(id => {
    map.on('mouseenter', id, () => { map.getCanvas().style.cursor = 'pointer'; });
    map.on('mouseleave', id, () => { map.getCanvas().style.cursor = ''; });
  });
});
</script>
</body>
</html>
`;

const outPath = path.join(__dirname, 'preview.html');
fs.writeFileSync(outPath, html);
console.log(`Written → ${outPath}`);
console.log('Open with: open Tools/preview.html');
