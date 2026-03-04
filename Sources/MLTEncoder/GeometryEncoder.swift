// GeometryEncoder.swift — Encode the geometry column of a FeatureTable.
//
// Accepts features whose geometries are SwiftGeo protocol types
// (Point, LinearGeometry, Polygon, MultiGeometry) and projects
// them to tile-space Int32 coordinates via a TileProjector.
//
// Column layout (preceded by a varint numStreams):
//   GeometryType stream  (Byte-RLE — one byte per feature)
//   [NumGeometries]      (VarInt — for Multi* types)
//   [NumParts]           (VarInt — for LineString / Polygon)
//   [NumRings]           (VarInt — for Polygon interior rings)
//   VertexBuffer         (ZigZag+VarInt — interleaved x,y per vertex)

import Foundation
import SwiftGeo

// MARK: - Geometry type byte values (match MLT spec)

private enum GeomTypeByte: UInt8 {
    case point           = 0
    case lineString      = 1
    case polygon         = 2
    case multiPoint      = 3
    case multiLineString = 4
    case multiPolygon    = 5
}

// MARK: - Helpers

private func tileVerts(from coords: [any Coordinate], using p: TileProjector) -> [(Int32, Int32)] {
    coords.map { p.project($0) }
}

// MARK: - Main encoder

/// Returns the fully encoded geometry column bytes (numStreams varint + all stream data).
func encodeGeometryColumn(_ features: [MLTFeature], projector: TileProjector) throws -> Data {

    var geomTypeBytesRaw: [UInt8] = []
    var numGeometries:   [UInt32] = []
    var numParts:        [UInt32] = []
    var numRings:        [UInt32] = []
    var verticesX:       [Int32]  = []
    var verticesY:       [Int32]  = []

    var hasMulti = false
    var hasParts = false
    var hasRings = false

    for f in features {
        let geom = f.geometry

        // ---- Point ----
        if let point = geom as? (any Point) {
            geomTypeBytesRaw.append(GeomTypeByte.point.rawValue)
            let v = projector.project(point.coordinate)
            verticesX.append(v.x); verticesY.append(v.y)

        // ---- Polygon ----
        } else if let poly = geom as? (any Polygon) {
            try appendPolygon(poly, geomTypeBytesRaw: &geomTypeBytesRaw,
                              numParts: &numParts, numRings: &numRings,
                              verticesX: &verticesX, verticesY: &verticesY,
                              projector: projector)
            hasParts = true; hasRings = true

        // ---- LineString (any LinearGeometry that isn't a sub-ring) ----
        } else if let linear = geom as? (any LinearGeometry) {
            guard !linear.coordinates.isEmpty else {
                throw MLTEncoderError.emptyGeometry("lineString")
            }
            geomTypeBytesRaw.append(GeomTypeByte.lineString.rawValue)
            numParts.append(UInt32(linear.coordinates.count))
            for c in linear.coordinates {
                let v = projector.project(c); verticesX.append(v.x); verticesY.append(v.y)
            }
            hasParts = true

        // ---- MultiGeometry (MultiPoint / MultiLineString / MultiPolygon) ----
        } else if let multi = geom as? (any MultiGeometry) {
            let subGeoms = multi.geometries()
            guard !subGeoms.isEmpty else {
                throw MLTEncoderError.emptyGeometry("multiGeometry")
            }
            try appendMulti(subGeoms,
                            geomTypeBytesRaw: &geomTypeBytesRaw,
                            numGeometries: &numGeometries,
                            numParts: &numParts,
                            numRings: &numRings,
                            verticesX: &verticesX,
                            verticesY: &verticesY,
                            hasMulti: &hasMulti,
                            hasParts: &hasParts,
                            hasRings: &hasRings,
                            projector: projector)

        } else {
            throw MLTEncoderError.unsupportedGeometry(
                "Unsupported geometry type: \(type(of: geom))"
            )
        }
    }

    // Stream count
    var streamCount = 2  // GeometryType + VertexBuffer always present
    if hasMulti { streamCount += 1 }
    if hasParts { streamCount += 1 }
    if hasRings { streamCount += 1 }

    // Geometry type stream: one plain unsigned varint per feature (values 0–5).
    // We intentionally avoid Byte-RLE here because the JS decoder only reads the
    // required RLE metadata (runs/numRleValues) when physicalLevelTechnique ≠ NONE.
    var geomTypeData = Data()
    for t in geomTypeBytesRaw { encodeVarint(UInt32(t), into: &geomTypeData) }

    var numGeomData = Data()
    for v in numGeometries { encodeVarint(v, into: &numGeomData) }

    var numPartsData = Data()
    for v in numParts { encodeVarint(v, into: &numPartsData) }

    var numRingsData = Data()
    for v in numRings { encodeVarint(v, into: &numRingsData) }

    // Vertex buffer: ZigZag-encoded x,y pairs written as unsigned varints.
    // Use DictionaryType.VERTEX so the decoder routes to the ZigZag-decode path.
    var vertexData = Data()
    for i in 0 ..< verticesX.count {
        encodeZigZag32(verticesX[i], into: &vertexData)
        encodeZigZag32(verticesY[i], into: &vertexData)
    }

    // Assemble
    var out = Data()
    encodeVarint(UInt32(streamCount), into: &out)
    out.append(encodeStream(.dataVarint, numValues: features.count, data: geomTypeData))
    if hasMulti {
        out.append(encodeStream(.lengthGeometries, numValues: numGeometries.count, data: numGeomData))
    }
    if hasParts {
        out.append(encodeStream(.lengthParts, numValues: numParts.count, data: numPartsData))
    }
    if hasRings {
        out.append(encodeStream(.lengthRings, numValues: numRings.count, data: numRingsData))
    }
    out.append(encodeStream(.dataVertexVarint, numValues: verticesX.count * 2, data: vertexData))
    return out
}

// MARK: - Sub-routines

private func appendPolygon(
    _ poly: any Polygon,
    geomTypeBytesRaw: inout [UInt8],
    numParts: inout [UInt32],
    numRings: inout [UInt32],
    verticesX: inout [Int32],
    verticesY: inout [Int32],
    projector: TileProjector
) throws {
    guard !poly.shell.coordinates.isEmpty else {
        throw MLTEncoderError.emptyGeometry("polygon shell")
    }
    geomTypeBytesRaw.append(GeomTypeByte.polygon.rawValue)
    let allRings: [any LinearGeometry] = [poly.shell] + poly.holes
    numParts.append(UInt32(allRings.count))
    for ring in allRings {
        numRings.append(UInt32(ring.coordinates.count))
        for c in ring.coordinates {
            let v = projector.project(c); verticesX.append(v.x); verticesY.append(v.y)
        }
    }
}

private func appendMulti(
    _ subGeoms: [any Geometry],
    geomTypeBytesRaw: inout [UInt8],
    numGeometries: inout [UInt32],
    numParts: inout [UInt32],
    numRings: inout [UInt32],
    verticesX: inout [Int32],
    verticesY: inout [Int32],
    hasMulti: inout Bool,
    hasParts: inout Bool,
    hasRings: inout Bool,
    projector: TileProjector
) throws {
    let first = subGeoms[0]

    if first is (any Point) {
        // MultiPoint
        geomTypeBytesRaw.append(GeomTypeByte.multiPoint.rawValue)
        numGeometries.append(UInt32(subGeoms.count))
        for sg in subGeoms {
            guard let pt = sg as? (any Point) else {
                throw MLTEncoderError.heterogeneousMultiGeometry("MultiPoint contained non-Point")
            }
            let v = projector.project(pt.coordinate)
            verticesX.append(v.x); verticesY.append(v.y)
        }
        hasMulti = true

    } else if first is (any Polygon) {
        // MultiPolygon
        geomTypeBytesRaw.append(GeomTypeByte.multiPolygon.rawValue)
        numGeometries.append(UInt32(subGeoms.count))
        for sg in subGeoms {
            guard let poly = sg as? (any Polygon) else {
                throw MLTEncoderError.heterogeneousMultiGeometry("MultiPolygon contained non-Polygon")
            }
            let allRings: [any LinearGeometry] = [poly.shell] + poly.holes
            numParts.append(UInt32(allRings.count))
            for ring in allRings {
                numRings.append(UInt32(ring.coordinates.count))
                for c in ring.coordinates {
                    let v = projector.project(c); verticesX.append(v.x); verticesY.append(v.y)
                }
            }
        }
        hasMulti = true; hasParts = true; hasRings = true

    } else if first is (any LinearGeometry) {
        // MultiLineString
        geomTypeBytesRaw.append(GeomTypeByte.multiLineString.rawValue)
        numGeometries.append(UInt32(subGeoms.count))
        for sg in subGeoms {
            guard let line = sg as? (any LinearGeometry) else {
                throw MLTEncoderError.heterogeneousMultiGeometry("MultiLineString contained non-LinearGeometry")
            }
            numParts.append(UInt32(line.coordinates.count))
            for c in line.coordinates {
                let v = projector.project(c); verticesX.append(v.x); verticesY.append(v.y)
            }
        }
        hasMulti = true; hasParts = true

    } else {
        throw MLTEncoderError.unsupportedGeometry(
            "Unsupported MultiGeometry sub-type: \(type(of: first))"
        )
    }
}
