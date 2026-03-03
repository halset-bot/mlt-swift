# MLTEncoder

A Swift encoder for the [MapLibre Tile (MLT)](https://maplibre.org/maplibre-tile-spec/) vector tile format.

Uses [swift-geo](https://github.com/ElectronicChartCentre/swift-geo) geometry types so you work with real geographic coordinates (WGS-84 lon/lat) — the encoder handles WebMercator projection to tile-space automatically.

## Features

- All geometry types: Point, LineString, Polygon, MultiPoint, MultiLineString, MultiPolygon
- All scalar property types: `bool`, `int32`, `uint32`, `int64`, `uint64`, `float`, `double`, `string` — nullable variants inferred automatically
- Optional feature IDs
- Multiple layers per tile
- WebMercator projection built-in (uses `SwiftGeo.WebMercator`)
- Encodings: ORC Byte-RLE, Boolean-RLE, ZigZag+VarInt

## Requirements

- macOS 14+ / iOS 17+
- Swift 5.9+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/MLTEncoder", from: "1.0.0"),
],
targets: [
    .target(dependencies: [
        .product(name: "MLTEncoder", package: "MLTEncoder"),
    ]),
]
```

## Usage

```swift
import MLTEncoder
import SwiftGeo

let geo = DefaultGeometryCreator()

// Create features using SwiftGeo geometry types (WGS-84 lon/lat)
let oslo   = geo.createPoint(coord: geo.createCoordinate2D(x: 10.7522, y: 59.9139))
let bergen = geo.createPoint(coord: geo.createCoordinate2D(x: 5.3221,  y: 60.3913))

let layer = MLTLayer(
    name: "cities",
    extent: 4096,        // tile grid size (default)
    features: [
        MLTFeature(id: 1, geometry: oslo,   properties: ["name": .string("Oslo")]),
        MLTFeature(id: 2, geometry: bergen, properties: ["name": .string("Bergen")]),
    ]
)

let encoder = MLTEncoder()

// Encode for tile z=10, x=532, y=302
let data: Data = try encoder.encode(
    layers: [layer],
    tileZ: 10, tileX: 532, tileY: 302
)
```

## Geometry types

All geometry inputs come from `SwiftGeo.GeometryCreator`:

```swift
let creator = DefaultGeometryCreator()

// Point
let pt = creator.createPoint(coord: creator.createCoordinate2D(x: lon, y: lat))

// LineString
let line = creator.createLineString(coords: [c1, c2, c3])

// Polygon (shell + optional holes, each a LinearRing)
let ring = creator.createLinearRing(coords: [c1, c2, c3, c4, c1])
let poly = creator.createPolygon(shell: ring, holes: [])

// MultiPoint
let mp = DefaultMultiPoint(coordinates: [c1, c2, c3])

// MultiLineString / MultiPolygon — use DefaultMultiGeometry
let multi = DefaultMultiGeometry(geometries: [line1, line2])
```

## Property values

```swift
let properties: [String: MLTPropertyValue] = [
    "name":       .string("Oslo"),
    "population": .int32(700_000),
    "area_km2":   .double(480.76),
    "capital":    .boolean(true),
    "optional":   .null,           // nullable column
]
```

Type inference rules:
- First non-null value determines the column type
- Any feature missing the key or providing `.null` makes the column nullable
- Mixed types (e.g. `.int32` and `.string` in the same column) throw `MLTEncoderError.typeMismatch`

## License

Apache 2.0
