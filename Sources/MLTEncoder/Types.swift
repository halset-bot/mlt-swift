// Types.swift — Public API types for the MLT encoder.
//
// Geometry input uses SwiftGeo protocol types (Point, LineString, Polygon, etc.)
// so callers work with geographic (WGS-84 lon/lat) coordinates directly.
// The encoder projects them to integer tile-space using WebMercatorTile internally.
//
// MapLibre Tile (MLT) format: https://maplibre.org/maplibre-tile-spec/

import Foundation
import SwiftGeo

// MARK: - Property values

/// Typed scalar value for a feature property.
///
/// Use `.null` for missing / null values in nullable columns.
public enum MLTPropertyValue {
    case boolean(Bool)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case float(Float)
    case double(Double)
    case string(String)
    /// Missing / null value for a nullable column.
    case null
}

// MARK: - Feature

/// A geospatial feature with a SwiftGeo geometry and typed properties.
///
/// Geometry must be one of the types the encoder recognises:
///   - Any type conforming to `Point` (single point)
///   - Any type conforming to `LinearGeometry` (used as LineString)
///   - Any type conforming to `Polygon`
///   - Any type conforming to `MultiGeometry` whose sub-geometries are homogeneous
///     Points, LinearGeometries, or Polygons (MultiPoint / MultiLineString / MultiPolygon)
public struct MLTFeature {
    public let id: UInt64?
    /// Geographic geometry (WGS-84 lon/lat), projected to tile-space at encode time.
    public let geometry: any Geometry
    public let properties: [String: MLTPropertyValue]

    public init(
        id: UInt64? = nil,
        geometry: any Geometry,
        properties: [String: MLTPropertyValue] = [:]
    ) {
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }
}

// MARK: - Layer

/// A named collection of features (equivalent to an MVT layer).
public struct MLTLayer {
    public let name: String
    /// Tile coordinate extent (default 4096).
    public let extent: UInt32
    public let features: [MLTFeature]

    public init(name: String, extent: UInt32 = 4096, features: [MLTFeature]) {
        self.name = name
        self.extent = extent
        self.features = features
    }
}

// MARK: - Internal column type

/// Column scalar type, inferred at encode time from the feature data.
enum ColumnType {
    case boolean(nullable: Bool)
    case int32(nullable: Bool)
    case uint32(nullable: Bool)
    case int64(nullable: Bool)
    case uint64(nullable: Bool)
    case float(nullable: Bool)
    case double_(nullable: Bool)
    case string(nullable: Bool)

    var isNullable: Bool {
        switch self {
        case .boolean(let n), .int32(let n), .uint32(let n),
             .int64(let n), .uint64(let n), .float(let n),
             .double_(let n), .string(let n):
            return n
        }
    }
}

// MARK: - Errors

enum MLTEncoderError: Error {
    case emptyLayer(name: String)
    case typeMismatch(column: String, message: String)
    case unsupportedGeometry(String)
    case emptyGeometry(String)
    case heterogeneousMultiGeometry(String)
}
