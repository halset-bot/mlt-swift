#!/usr/bin/env node
// validate-mlt.js — Decodes an MLT tile using @maplibre/mlt and prints a JSON
// summary suitable for assertion in tests.
//
// Usage:
//   node validate-mlt.js <path-to-tile.mlt>
//
// Output on success:
//   {
//     "ok": true,
//     "layers": [{
//       "name": "...",
//       "numFeatures": N,
//       "geometryTypes": ["POINT", ...],   -- unique types, sorted
//       "features": [{
//         "id": N | null,
//         "geometryType": "POINT",
//         "coordinates": [                 -- rings/parts array
//           [[x, y], [x, y], ...]          -- vertices as [x, y] integers
//         ]
//       }, ...]
//     }]
//   }
//
// Coordinates are tile-space integers (same CRS as the encoder input, i.e.
// WebMercator pixel coords within the tile, range [0, extent)).
//
// Exits 1 and prints { "ok": false, "error": "..." } on failure.
//
// Regenerate mlt-bundle.cjs (when @maplibre/mlt is updated):
//   npm install @maplibre/mlt
//   npx esbuild node_modules/@maplibre/mlt/dist/index.js \
//     --bundle --platform=node --format=cjs --outfile=mlt-bundle.cjs

'use strict';

const path = require('path');
const fs   = require('fs');

const { decodeTile, GEOMETRY_TYPE } = require(path.join(__dirname, 'mlt-bundle.cjs'));

const mltPath = process.argv[2];
if (!mltPath) {
    console.error(JSON.stringify({ ok: false, error: 'Usage: validate-mlt.js <path-to-mlt>' }));
    process.exit(1);
}

/**
 * Convert a coordinates array from the decoder ({x,y} objects per vertex)
 * to plain [[x, y], ...] integer arrays, one sub-array per ring/part.
 *
 * The decoder returns geometry.coordinates as an array of "rings" where each
 * ring is an array of @mapbox/point-geometry Point objects with .x / .y fields.
 */
function coordsToArrays(coordinates) {
    if (!coordinates) return [];
    return coordinates.map(ring => ring.map(pt => [Math.round(pt.x), Math.round(pt.y)]));
}

try {
    const bytes = new Uint8Array(fs.readFileSync(mltPath));
    const featureTables = decodeTile(bytes);

    const layers = featureTables.map(table => {
        const typeSet  = new Set();
        const features = [];

        for (const feature of table) {
            const typeName = feature.geometry != null
                ? (GEOMETRY_TYPE[feature.geometry.type] ?? `UNKNOWN(${feature.geometry.type})`)
                : 'NONE';
            typeSet.add(typeName);
            features.push({
                id:           feature.id ?? null,
                geometryType: typeName,
                coordinates:  coordsToArrays(feature.geometry?.coordinates),
            });
        }

        return {
            name:          table.name,
            numFeatures:   features.length,
            geometryTypes: [...typeSet].sort(),
            features,
        };
    });

    console.log(JSON.stringify({ ok: true, layers }));
} catch (e) {
    console.error(JSON.stringify({ ok: false, error: e.message }));
    process.exit(1);
}
