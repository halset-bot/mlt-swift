#!/usr/bin/env node
// validate-mlt.js — Decodes an MLT tile using @maplibre/mlt and prints a JSON
// summary suitable for assertion in tests.
//
// Usage:
//   node validate-mlt.js <path-to-tile.mlt>
//
// Exits 0 and prints JSON on success:
//   { "ok": true, "layers": [ { "name": "...", "numFeatures": N, "geometryTypes": [...] } ] }
//
// Exits 1 and prints JSON on failure:
//   { "ok": false, "error": "..." }
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

try {
    const bytes = new Uint8Array(fs.readFileSync(mltPath));
    const featureTables = decodeTile(bytes);

    const layers = featureTables.map(table => {
        // Collect unique geometry type names from the first few features.
        const typeSet = new Set();
        let count = 0;
        for (const feature of table) {
            if (feature.geometry != null) {
                const typeName = GEOMETRY_TYPE[feature.geometry.type] ?? `UNKNOWN(${feature.geometry.type})`;
                typeSet.add(typeName);
            }
            count++;
        }
        return {
            name: table.name,
            numFeatures: count,
            geometryTypes: [...typeSet].sort(),
        };
    });

    console.log(JSON.stringify({ ok: true, layers }));
} catch (e) {
    console.error(JSON.stringify({ ok: false, error: e.message }));
    process.exit(1);
}
