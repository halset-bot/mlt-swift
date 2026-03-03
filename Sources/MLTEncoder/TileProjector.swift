// TileProjector.swift — Projects WGS-84 lon/lat coordinates to MLT tile-space (Int32).
//
// Uses SwiftGeo's WebMercator (EPSG:3857 XYZ tiling).
// With pixelRatio = extent/256, forward() returns pixel coords in [0, extent),
// which are then rounded to Int32 for the MLT vertex buffer.

import Foundation
import SwiftGeo

/// Wraps SwiftGeo's WebMercator projection and scales output to MLT tile coordinates.
struct TileProjector {
    private let projection: WebMercator

    /// - Parameters:
    ///   - tileZ: Zoom level.
    ///   - tileX: Tile column.
    ///   - tileY: Tile row (TMS / XYZ convention).
    ///   - extent: Tile extent in integer units (typically 4096).
    init(tileZ: Int, tileX: Int, tileY: Int, extent: UInt32) {
        // pixelRatio maps the WebMercator pixel-space to [0, extent).
        // WebMercator produces pixels in a (256 * pixelRatio) square,
        // so pixelRatio = extent / 256 gives us [0, extent) directly.
        let pixelRatio = max(1, Int(extent) / 256)
        self.projection = WebMercator(x: tileX, y: tileY, z: tileZ, pixelRatio: pixelRatio)
    }

    /// Project a WGS-84 coordinate (x=lon, y=lat) to tile-space integers.
    func project(_ coord: any Coordinate) -> (x: Int32, y: Int32) {
        let p = projection.forward(coordinate: coord)
        return (x: Int32(p.x.rounded()), y: Int32(p.y.rounded()))
    }
}
