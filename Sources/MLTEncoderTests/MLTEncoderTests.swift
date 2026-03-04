// MLTEncoderTests.swift — Test runner using SwiftGeo geometry types.
// Uses a plain executable instead of XCTest (CommandLineTools has no XCTest).
@testable import MLTEncoder
import SwiftGeo
import Foundation

// MARK: - Minimal test harness

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("  ✅ \(name)")
        passed += 1
    } catch {
        print("  ❌ \(name): \(error)")
        failed += 1
    }
}

func expect(_ cond: Bool, _ msg: String = "expectation failed", file: String = #file, line: Int = #line) throws {
    if !cond { throw TestError.failed("\(msg) (\(file):\(line))") }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    if a != b { throw TestError.failed("\(a) != \(b) (\(file):\(line))") }
}
func expectThrows(_ body: () throws -> Void, file: String = #file, line: Int = #line) throws {
    do {
        try body()
        throw TestError.failed("Expected throw but none occurred (\(file):\(line))")
    } catch TestError.failed(let m) { throw TestError.failed(m) }
    catch { /* good */ }
}
enum TestError: Error { case failed(String) }

// MARK: - Helpers

let geo = DefaultGeometryCreator()

/// Oslo city centre, WGS-84.
let oslo      = geo.createCoordinate2D(x: 10.7522, y: 59.9139)
/// Bergen city centre, WGS-84.
let bergen    = geo.createCoordinate2D(x: 5.3221,  y: 60.3913)
/// Trondheim city centre.
let trondheim = geo.createCoordinate2D(x: 10.3951, y: 63.4305)

/// A small square near Oslo, suitable for polygon/ring tests.
let squareRing = geo.createLinearRing(coords: [
    geo.createCoordinate2D(x: 10.70, y: 59.90),
    geo.createCoordinate2D(x: 10.70, y: 59.95),
    geo.createCoordinate2D(x: 10.80, y: 59.95),
    geo.createCoordinate2D(x: 10.80, y: 59.90),
    geo.createCoordinate2D(x: 10.70, y: 59.90),
])

// Tile z=6 x=33 y=19 covers Norway at a coarse zoom.
let tileZ = 6, tileX = 33, tileY = 19

let encoder = MLTEncoder()

// MARK: - Varint tests (encoding primitives, unchanged)

print("\n=== MLTEncoder Tests ===\n")

test("varint single byte") {
    var d = Data(); encodeVarint(UInt32(127), into: &d)
    try expectEqual(d, Data([0x7F]))
}
test("varint two bytes") {
    var d = Data(); encodeVarint(UInt32(128), into: &d)
    try expectEqual(d, Data([0x80, 0x01]))
}
test("varint 300") {
    var d = Data(); encodeVarint(UInt32(300), into: &d)
    try expectEqual(d, Data([0xAC, 0x02]))
}
test("zigzag +1") {
    var d = Data(); encodeZigZag32(1, into: &d)
    try expectEqual(d, Data([0x02]))
}
test("zigzag -1") {
    var d = Data(); encodeZigZag32(-1, into: &d)
    try expectEqual(d, Data([0x01]))
}
test("zigzag 0") {
    var d = Data(); encodeZigZag32(0, into: &d)
    try expectEqual(d, Data([0x00]))
}

// MARK: - ORC encoding

test("byte-RLE run of 3") {
    try expectEqual(encodeByteRLE([0xAB, 0xAB, 0xAB]), Data([0x00, 0xAB]))
}
test("byte-RLE 2 literals") {
    try expectEqual(encodeByteRLE([0x01, 0x02]), Data([0xFE, 0x01, 0x02]))
}
test("byte-RLE run of 10") {
    try expectEqual(encodeByteRLE(Array(repeating: UInt8(0x55), count: 10)), Data([0x07, 0x55]))
}
test("boolean-RLE 8×true") {
    try expectEqual(encodeBooleanRLE(Array(repeating: true, count: 8)), Data([0xFF, 0xFF]))
}
test("boolean-RLE empty") {
    try expectEqual(encodeBooleanRLE([]), Data())
}

// MARK: - Stream metadata headers

test("stream dataVarint header") {
    let s = encodeStream(.dataVarint, numValues: 5, data: Data([1, 2, 3]))
    try expectEqual(s[0], UInt8(0x10)); try expectEqual(s[1], UInt8(0x02))
    try expectEqual(s[2], UInt8(0x05)); try expectEqual(s[3], UInt8(0x03))
}
test("stream present header") {
    let s = encodeStream(.present, numValues: 1, data: Data([0xFF]))
    try expectEqual(s[0], UInt8(0x00)); try expectEqual(s[1], UInt8(0x60))
}

// MARK: - Full encode tests

test("encode point layer (SwiftGeo Point)") {
    let layer = MLTLayer(name: "cities", features: [
        MLTFeature(id: 1, geometry: geo.createPoint(coord: oslo),
                   properties: ["name": .string("Oslo"), "pop": .int32(700_000)]),
        MLTFeature(id: 2, geometry: geo.createPoint(coord: bergen),
                   properties: ["name": .string("Bergen"), "pop": .int32(280_000)]),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
    try expect(data.count > 10)
}

test("encode linestring layer (SwiftGeo LineString)") {
    let line = geo.createLineString(coords: [oslo, bergen, trondheim])
    let layer = MLTLayer(name: "routes", features: [
        MLTFeature(geometry: line, properties: ["class": .string("ferry")])
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode polygon layer (SwiftGeo Polygon)") {
    let poly = geo.createPolygon(shell: squareRing, holes: [])
    let layer = MLTLayer(name: "areas", features: [
        MLTFeature(geometry: poly, properties: ["type": .string("nature")])
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode polygon with hole") {
    let outerRing = geo.createLinearRing(coords: [
        geo.createCoordinate2D(x: 10.60, y: 59.85),
        geo.createCoordinate2D(x: 10.60, y: 60.00),
        geo.createCoordinate2D(x: 10.90, y: 60.00),
        geo.createCoordinate2D(x: 10.90, y: 59.85),
        geo.createCoordinate2D(x: 10.60, y: 59.85),
    ])
    let innerRing = geo.createLinearRing(coords: [
        geo.createCoordinate2D(x: 10.70, y: 59.90),
        geo.createCoordinate2D(x: 10.70, y: 59.95),
        geo.createCoordinate2D(x: 10.80, y: 59.95),
        geo.createCoordinate2D(x: 10.80, y: 59.90),
        geo.createCoordinate2D(x: 10.70, y: 59.90),
    ])
    let poly = geo.createPolygon(shell: outerRing, holes: [innerRing])
    let layer = MLTLayer(name: "holed", features: [
        MLTFeature(geometry: poly)
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode multipoint (DefaultMultiPoint)") {
    let mp = DefaultMultiPoint(coordinates: [oslo, bergen, trondheim])
    let layer = MLTLayer(name: "multipt", features: [
        MLTFeature(geometry: mp)
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode multilinestring (DefaultMultiGeometry)") {
    let l1 = geo.createLineString(coords: [oslo, bergen])
    let l2 = geo.createLineString(coords: [bergen, trondheim])
    let multi = DefaultMultiGeometry(geometries: [l1, l2])
    let layer = MLTLayer(name: "multiline", features: [
        MLTFeature(geometry: multi)
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode multipolygon (DefaultMultiGeometry)") {
    let sq1 = geo.createPolygon(shell: squareRing, holes: [])
    let sq2Ring = geo.createLinearRing(coords: [
        geo.createCoordinate2D(x: 5.30, y: 60.35),
        geo.createCoordinate2D(x: 5.30, y: 60.45),
        geo.createCoordinate2D(x: 5.40, y: 60.45),
        geo.createCoordinate2D(x: 5.40, y: 60.35),
        geo.createCoordinate2D(x: 5.30, y: 60.35),
    ])
    let sq2 = geo.createPolygon(shell: sq2Ring, holes: [])
    let multi = DefaultMultiGeometry(geometries: [sq1, sq2])
    let layer = MLTLayer(name: "multipoly", features: [
        MLTFeature(geometry: multi)
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode multiple layers") {
    let layers = [
        MLTLayer(name: "cities", features: [
            MLTFeature(geometry: geo.createPoint(coord: oslo),
                       properties: ["name": .string("Oslo")])
        ]),
        MLTLayer(name: "routes", features: [
            MLTFeature(geometry: geo.createLineString(coords: [oslo, bergen]),
                       properties: ["class": .string("ferry")])
        ]),
    ]
    let data = try encoder.encode(layers: layers, tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode nullable string property") {
    let layer = MLTLayer(name: "pois", features: [
        MLTFeature(geometry: geo.createPoint(coord: oslo),
                   properties: ["label": .string("Oslo"), "desc": .null]),
        MLTFeature(geometry: geo.createPoint(coord: bergen),
                   properties: ["label": .string("Bergen"), "desc": .string("Port city")]),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("encode all scalar property types") {
    let layer = MLTLayer(name: "scalars", features: [
        MLTFeature(id: 99, geometry: geo.createPoint(coord: oslo), properties: [
            "bool":  .boolean(true),
            "i32":   .int32(-42),
            "u32":   .uint32(9999),
            "i64":   .int64(-9_000_000_000),
            "u64":   .uint64(18_000_000_000),
            "f":     .float(3.14),
            "d":     .double(2.71828),
            "s":     .string("Loke 🐍"),
        ])
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    try expect(!data.isEmpty)
}

test("type mismatch throws") {
    let layer = MLTLayer(name: "bad", features: [
        MLTFeature(geometry: geo.createPoint(coord: oslo), properties: ["x": .int32(1)]),
        MLTFeature(geometry: geo.createPoint(coord: bergen), properties: ["x": .string("oops")]),
    ])
    try expectThrows { try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY) }
}

test("empty layer throws") {
    let layer = MLTLayer(name: "empty", features: [])
    try expectThrows { try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY) }
}

test("different zoom levels produce different output") {
    let layer = MLTLayer(name: "cities", features: [
        MLTFeature(geometry: geo.createPoint(coord: oslo))
    ])
    let d6  = try encoder.encode(layers: [layer], tileZ: 6,  tileX: 33, tileY: 19)
    let d10 = try encoder.encode(layers: [layer], tileZ: 10, tileX: 532, tileY: 302)
    try expect(d6 != d10, "Different zoom tiles should encode differently")
}

// MARK: - JS decoder cross-validation
//
// These tests encode a tile and then decode it with the official @maplibre/mlt
// JavaScript decoder (Tools/validate-mlt.js + Tools/mlt-bundle.cjs).
// A parse error here means the binary output is not spec-compliant.

/// One feature as returned by the JS validator.
/// `coordinates` mirrors the decoder output: [ring/part][vertex][x, y]
struct MLTValidationFeature: Decodable {
    let id: Int?
    let geometryType: String
    let coordinates: [[[Int]]]   // [ring][vertex][0=x | 1=y]
}
struct MLTValidationLayer: Decodable {
    let name: String
    let numFeatures: Int
    let geometryTypes: [String]
    let features: [MLTValidationFeature]
}
struct MLTValidationResult: Decodable {
    let ok: Bool
    let layers: [MLTValidationLayer]?
    let error: String?
}

// MARK: - Projection helper

/// Project a single WGS-84 coordinate to integer tile-space using the global
/// tile settings (tileZ/X/Y, extent=4096).  Matches the encoder's projection exactly.
func projectToTile(_ coord: any Coordinate) -> (x: Int, y: Int) {
    let p = TileProjector(tileZ: tileZ, tileX: tileX, tileY: tileY, extent: 4096)
    let v = p.project(coord)
    return (x: Int(v.x), y: Int(v.y))
}

/// Assert that a single decoded vertex `[[x,y]]` matches an expected tile coordinate.
func expectVertex(_ ring: [[Int]], _ expected: (x: Int, y: Int),
                  label: String = "", file: String = #file, line: Int = #line) throws {
    guard ring.count == 1, ring[0].count == 2 else {
        throw TestError.failed("expected single vertex [[x,y]], got \(ring) \(label) (\(file):\(line))")
    }
    try expectEqual(ring[0][0], expected.x, file: file, line: line)
    try expectEqual(ring[0][1], expected.y, file: file, line: line)
}

/// Encodes `data` to a temp .mlt file, runs the Node.js validator, returns layer summaries.
func validateWithJSDecoder(_ data: Data, sourceFile: String = #filePath) throws -> [MLTValidationLayer] {
    // Locate Tools/ relative to this source file:
    //   <root>/Sources/MLTEncoderTests/MLTEncoderTests.swift → up ×3 → <root>
    let toolsURL = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()   // drop MLTEncoderTests/
        .deletingLastPathComponent()   // drop Sources/
        .deletingLastPathComponent()   // drop project root (we're now at <root>)
        .appendingPathComponent("Tools/validate-mlt.js")

    // Write tile bytes to a temp file.
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mlt-validate-\(UInt32.random(in: 0..<UInt32.max)).mlt")
    try data.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    // Run: node Tools/validate-mlt.js <tmpfile>
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/local/bin/node")
    proc.arguments    = [toolsURL.path, tmpURL.path]
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError  = errPipe
    try proc.run()
    proc.waitUntilExit()

    let outStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    if proc.terminationStatus != 0 {
        throw TestError.failed(
            "JS validator exited \(proc.terminationStatus): \(errStr.isEmpty ? outStr : errStr)")
    }
    guard let jsonData = outStr.data(using: .utf8) else {
        throw TestError.failed("JS validator produced no output")
    }
    let result = try JSONDecoder().decode(MLTValidationResult.self, from: jsonData)
    if !result.ok {
        throw TestError.failed("JS decoder error: \(result.error ?? "unknown")")
    }
    return result.layers ?? []
}

test("JS decode: point layer round-trip") {
    let layer = MLTLayer(name: "cities", features: [
        MLTFeature(id: 1, geometry: geo.createPoint(coord: oslo),
                   properties: ["name": .string("Oslo"),      "pop": .int32(700_000)]),
        MLTFeature(id: 2, geometry: geo.createPoint(coord: bergen),
                   properties: ["name": .string("Bergen"),    "pop": .int32(280_000)]),
        MLTFeature(id: 3, geometry: geo.createPoint(coord: trondheim),
                   properties: ["name": .string("Trondheim"), "pop": .int32(200_000)]),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    try expectEqual(layers.count, 1)
    try expectEqual(layers[0].name, "cities")
    try expectEqual(layers[0].numFeatures, 3)
    try expect(layers[0].geometryTypes.contains("POINT"), "expected POINT geometry")
}

test("JS decode: linestring layer round-trip") {
    let layer = MLTLayer(name: "routes", features: [
        MLTFeature(geometry: geo.createLineString(coords: [oslo, bergen]),
                   properties: ["class": .string("ferry")]),
        MLTFeature(geometry: geo.createLineString(coords: [oslo, trondheim]),
                   properties: ["class": .string("road")]),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    try expectEqual(layers.count, 1)
    try expectEqual(layers[0].name, "routes")
    try expectEqual(layers[0].numFeatures, 2)
    try expect(layers[0].geometryTypes.contains("LINESTRING"), "expected LINESTRING geometry")
}

test("JS decode: polygon layer round-trip") {
    let poly = geo.createPolygon(shell: squareRing, holes: [])
    let layer = MLTLayer(name: "areas", features: [
        MLTFeature(geometry: poly, properties: ["type": .string("nature")]),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    try expectEqual(layers.count, 1)
    try expectEqual(layers[0].name, "areas")
    try expectEqual(layers[0].numFeatures, 1)
    try expect(layers[0].geometryTypes.contains("POLYGON"), "expected POLYGON geometry")
}

test("JS decode: multiple layers round-trip") {
    let tileLayers = [
        MLTLayer(name: "cities", features: [
            MLTFeature(id: 1, geometry: geo.createPoint(coord: oslo),
                       properties: ["name": .string("Oslo")]),
            MLTFeature(id: 2, geometry: geo.createPoint(coord: bergen),
                       properties: ["name": .string("Bergen")]),
        ]),
        MLTLayer(name: "routes", features: [
            MLTFeature(geometry: geo.createLineString(coords: [oslo, bergen]),
                       properties: ["class": .string("ferry")]),
        ]),
    ]
    let data = try encoder.encode(layers: tileLayers, tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    try expectEqual(layers.count, 2)
    let names = Set(layers.map(\.name))
    try expect(names.contains("cities") && names.contains("routes"),
               "expected layers 'cities' and 'routes', got \(names)")
    let cities = layers.first(where: { $0.name == "cities" })!
    try expectEqual(cities.numFeatures, 2)
    let routes = layers.first(where: { $0.name == "routes" })!
    try expectEqual(routes.numFeatures, 1)
}

// MARK: - JS coordinate validation

test("JS decode: point coordinates") {
    let layer = MLTLayer(name: "cities", features: [
        MLTFeature(id: 1, geometry: geo.createPoint(coord: oslo)),
        MLTFeature(id: 2, geometry: geo.createPoint(coord: bergen)),
        MLTFeature(id: 3, geometry: geo.createPoint(coord: trondheim)),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    let features = layers[0].features
    try expectEqual(features.count, 3)

    // Each point's coordinates are [[[x, y]]] — one ring containing one vertex.
    let coords = [(oslo, "Oslo"), (bergen, "Bergen"), (trondheim, "Trondheim")]
    for (i, (wgs84, name)) in coords.enumerated() {
        let expected = projectToTile(wgs84)
        let ring = features[i].coordinates      // [ring][vertex][x/y]
        try expect(ring.count == 1, "\(name): expected 1 ring, got \(ring.count)")
        try expectVertex(ring[0], expected, label: name)
    }
}

test("JS decode: linestring coordinates") {
    // Two-vertex line Oslo→Bergen
    let coords = [oslo, bergen]
    let layer = MLTLayer(name: "routes", features: [
        MLTFeature(geometry: geo.createLineString(coords: coords)),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    let ring = layers[0].features[0].coordinates[0]   // [vertex][x/y]
    try expectEqual(ring.count, coords.count)
    for (i, wgs84) in coords.enumerated() {
        let exp = projectToTile(wgs84)
        try expect(ring[i][0] == exp.x && ring[i][1] == exp.y,
                   "vertex \(i): expected (\(exp.x),\(exp.y)) got (\(ring[i][0]),\(ring[i][1]))")
    }
}

test("JS decode: polygon coordinates") {
    // 4 unique corners.  The encoder strips the closing vertex (MLT convention);
    // the decoder adds it back.  So we encode 4, decode 5 (4 + closing repeat).
    let corners = [
        geo.createCoordinate2D(x: 10.70, y: 59.90),
        geo.createCoordinate2D(x: 10.70, y: 59.95),
        geo.createCoordinate2D(x: 10.80, y: 59.95),
        geo.createCoordinate2D(x: 10.80, y: 59.90),
    ]
    let ringCoords = corners + [corners[0]]          // add closing vertex for SwiftGeo
    let ring = geo.createLinearRing(coords: ringCoords)
    let layer = MLTLayer(name: "areas", features: [
        MLTFeature(geometry: geo.createPolygon(shell: ring, holes: [])),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    let outerRing = layers[0].features[0].coordinates[0]   // [vertex][x/y]

    // Decoder emits 4 stored vertices + 1 re-added closing vertex = 5
    try expectEqual(outerRing.count, corners.count + 1)
    // Check the 4 unique corners
    for (i, wgs84) in corners.enumerated() {
        let exp = projectToTile(wgs84)
        try expect(outerRing[i][0] == exp.x && outerRing[i][1] == exp.y,
                   "corner \(i): expected (\(exp.x),\(exp.y)) got (\(outerRing[i][0]),\(outerRing[i][1]))")
    }
    // Closing vertex must equal first
    try expect(outerRing[4] == outerRing[0], "closing vertex \(outerRing[4]) != first \(outerRing[0])")
}

test("JS decode: multipoint coordinates") {
    let points = [oslo, bergen, trondheim]
    let mp = DefaultMultiPoint(coordinates: points)
    let layer = MLTLayer(name: "multipt", features: [
        MLTFeature(geometry: mp),
    ])
    let data = try encoder.encode(layers: [layer], tileZ: tileZ, tileX: tileX, tileY: tileY)
    let layers = try validateWithJSDecoder(data)
    // MultiPoint: coordinates = [[[x,y]], [[x,y]], ...] — one ring per point
    let coords = layers[0].features[0].coordinates
    try expectEqual(coords.count, points.count)
    for (i, wgs84) in points.enumerated() {
        let exp = projectToTile(wgs84)
        try expectVertex(coords[i], exp, label: "point \(i)")
    }
}

// MARK: - Summary

print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
