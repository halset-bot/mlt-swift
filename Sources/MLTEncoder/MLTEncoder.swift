// MLTEncoder.swift — Top-level encoder orchestrating the binary MLT tile format.
//
// Geometry coordinates are projected from WGS-84 lon/lat to integer tile-space
// using SwiftGeo's WebMercatorTile projection.
//
// Tile layout:
//   For each layer:
//     [varint: layerDataLength]
//     [varint: layerTag = 1]         -- "basic MVT-equivalent"
//     [FeatureTableMetadata]         -- name, extent, column descriptors
//     [Column data...]               -- geometry + property streams

import Foundation
import SwiftGeo

/// Encodes one or more MLT layers into a binary MLT tile.
public struct MLTEncoder {

    public init() {}

    /// Encode layers into a binary MLT tile.
    ///
    /// - Parameters:
    ///   - layers: Layers to encode.
    ///   - tileZ: Zoom level used for WebMercatorTile projection.
    ///   - tileX: Tile column.
    ///   - tileY: Tile row.
    public func encode(
        layers: [MLTLayer],
        tileZ: Int,
        tileX: Int,
        tileY: Int
    ) throws -> Data {
        var tile = Data()
        for layer in layers {
            let layerData = try encodeLayer(layer, tileZ: tileZ, tileX: tileX, tileY: tileY)
            encodeVarint(UInt32(layerData.count), into: &tile)
            tile.append(layerData)
        }
        return tile
    }

    // MARK: - Layer

    private func encodeLayer(
        _ layer: MLTLayer,
        tileZ: Int, tileX: Int, tileY: Int
    ) throws -> Data {
        guard !layer.features.isEmpty else {
            throw MLTEncoderError.emptyLayer(name: layer.name)
        }

        let features = layer.features
        let projector = TileProjector(
            tileZ: tileZ, tileX: tileX, tileY: tileY,
            extent: layer.extent
        )

        // Collect and sort property column keys for determinism
        var allKeys = Set<String>()
        for f in features { allKeys.formUnion(f.properties.keys) }
        let sortedKeys = allKeys.sorted()

        var columnTypes: [(key: String, type: ColumnType)] = []
        for key in sortedKeys {
            let ct = try inferColumnType(key: key, features: features)
            columnTypes.append((key, ct))
        }

        // ---- FeatureTableMetadata ----
        var metadata = Data()
        metadata.append(encodeMltString(layer.name))
        encodeVarint(layer.extent, into: &metadata)

        let hasID = features.contains { $0.id != nil }
        var columnCount = 1 + columnTypes.count  // geometry always present
        if hasID { columnCount += 1 }
        encodeVarint(UInt32(columnCount), into: &metadata)

        if hasID {
            // typeCode 0 = uint32 ID, non-nullable
            encodeVarint(UInt32(0), into: &metadata)
        }
        // Geometry column: typeCode 4, non-nullable, no name (typeCode < 10)
        encodeVarint(UInt32(4), into: &metadata)
        // Property columns
        for (key, ct) in columnTypes {
            encodeVarint(typeCode(for: ct), into: &metadata)
            metadata.append(encodeMltString(key))
        }

        // ---- Column data ----
        var columnData = Data()

        if hasID {
            var payload = Data()
            for f in features { encodeVarint(f.id ?? 0, into: &payload) }
            columnData.append(encodeStream(.dataVarint, numValues: features.count, data: payload))
        }

        columnData.append(try encodeGeometryColumn(features, projector: projector))

        for (key, ct) in columnTypes {
            columnData.append(encodePropertyColumn(key: key, columnType: ct, features: features))
        }

        // ---- Assemble: layerTag(1) + metadata + columnData ----
        var out = Data()
        encodeVarint(UInt32(1), into: &out)
        out.append(metadata)
        out.append(columnData)
        return out
    }

    // MARK: - Helpers

    private func encodeMltString(_ s: String) -> Data {
        let utf8 = Data(s.utf8)
        var d = Data()
        encodeVarint(UInt32(utf8.count), into: &d)
        d.append(utf8)
        return d
    }
}
