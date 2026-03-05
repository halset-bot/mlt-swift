// TileProjector.swift — Projects WGS-84 lon/lat coordinates to MLT tile-space (Int32).
//
// Uses SwiftGeo's WebMercatorTile (EPSG:3857 XYZ tiling).
// With pixelRatio = extent/256, forward() returns pixel coords in [0, extent),
// which are then rounded to Int32 for the MLT vertex buffer.

import Foundation
import SwiftGeo

/// Wraps SwiftGeo's WebMercatorTile projection and scales output to MLT tile coordinates.
struct TileProjector {
    private let projection: WebMercatorTile
    private let extent: Int

    /// - Parameters:
    ///   - tileZ: Zoom level.
    ///   - tileX: Tile column.
    ///   - tileY: Tile row (TMS / XYZ convention).
    ///   - extent: Tile extent in integer units (typically 4096).
    init(tileZ: Int, tileX: Int, tileY: Int, extent: UInt32) {
        // pixelRatio maps the WebMercatorTile pixel-space to [0, extent).
        // WebMercatorTile produces pixels in a (256 * pixelRatio) square,
        // so pixelRatio = extent / 256 gives us [0, extent) directly.
        let pixelRatio = max(1, Int(extent) / 256)
        self.projection = WebMercatorTile(x: tileX, y: tileY, z: tileZ, pixelRatio: pixelRatio)
        self.extent = Int(extent)
    }

    /// Project a WGS-84 coordinate (x=lon, y=lat) to tile-space integers.
    func project(_ coord: any Coordinate) -> (x: Int32, y: Int32) {
        let p = projection.forward(coordinate: coord)
        // WebMercatorTile.forward() returns y=0 at the south (bottom) edge of
        // the tile, increasing to y≈extent at the north (top) edge.
        // MLT/MVT tile space uses the opposite convention: y=0 at the north,
        // increasing southward.  Flip to match.
        let flippedY = Double(extent - 1) - p.y
        return (x: Int32(p.x.rounded()), y: Int32(flippedY.rounded()))
    }
}
