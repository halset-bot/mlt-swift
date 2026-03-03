// MLTEncoderTests.swift — Test runner using SwiftGeo geometry types.
// Uses a plain executable instead of XCTest (CommandLineTools has no XCTest).
@testable import MLTEncoder
import SwiftGeo
import Foundation

// MARK: - Minimal test harness

var passed = 0
var failed = 0

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

// MARK: - Summary

print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
