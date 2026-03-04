// StreamMetadata.swift — Encode MLT stream metadata headers.
//
// Every data stream in an MLT tile is preceded by a two-byte header
// followed by two varints (numValues, byteLength).
//
// Byte 0: (PhysicalStreamType << 4) | logicalType
// Byte 1: (LogicalLevelTechnique1 << 5) | (LogicalLevelTechnique2 << 2) | PhysicalLevelTechnique
//
// References:
//   cpp/src/mlt/metadata/stream.cpp  — StreamMetadata::decodeInternal
//   cpp/include/mlt/metadata/stream.hpp — enum values

import Foundation

// MARK: - Enumerations (values match the C++ implementation)

enum PhysicalStreamType: UInt8 {
    case present = 0
    case data    = 1
    case offset  = 2
    case length  = 3
}

enum DictionaryType: UInt8 {    // logical type for DATA streams
    case none   = 0
    case single = 1
    case shared = 2
    case vertex = 3
    case morton = 4
    case fsst   = 5
}

enum LengthType: UInt8 {        // logical type for LENGTH streams
    case varBinary  = 0
    case geometries = 1
    case parts      = 2
    case rings      = 3
    case triangles  = 4
    case symbol     = 5
    case dictionary = 6
}

enum OffsetType: UInt8 {        // logical type for OFFSET streams
    case vertex = 0
    case index  = 1
    case string = 2
    case key    = 3
}

enum LogicalLevelTechnique: UInt8 {
    case none               = 0
    case delta              = 1
    case componentwiseDelta = 2
    case rle                = 3
    case morton             = 4
    case pseudoDecimal      = 5
}

enum PhysicalLevelTechnique: UInt8 {
    case none     = 0
    case fastPfor = 1
    case varint   = 2
    case alp      = 3
}

// MARK: - Header builder

struct StreamMeta {
    let physicalType:      PhysicalStreamType
    let logicalType:       UInt8                 // 4-bit field, type depends on physicalType
    let logicalTechnique1: LogicalLevelTechnique
    let logicalTechnique2: LogicalLevelTechnique
    let physicalTechnique: PhysicalLevelTechnique
}

extension StreamMeta {
    // Convenience factories for the common cases we use in this encoder.

    /// PRESENT stream — Boolean-RLE packed booleans (1 bit per feature).
    static let present = StreamMeta(
        physicalType:      .present,
        logicalType:       0,
        logicalTechnique1: .rle,
        logicalTechnique2: .none,
        physicalTechnique: .none
    )

    /// DATA stream — Byte-RLE (used for GeometryType).
    static let dataByteRLE = StreamMeta(
        physicalType:      .data,
        logicalType:       DictionaryType.none.rawValue,
        logicalTechnique1: .rle,
        logicalTechnique2: .none,
        physicalTechnique: .none
    )

    /// DATA stream — plain VarInt integers (unsigned, no further transformation).
    static let dataVarint = StreamMeta(
        physicalType:      .data,
        logicalType:       DictionaryType.none.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )

    /// DATA stream — vertex buffer (DictionaryType.VERTEX).
    /// Decoder identifies this dict-type specifically and applies ZigZag decoding
    /// (isSigned=true path in decodeIntStream).  Data must be ZigZag-encoded
    /// x,y pairs written as unsigned varints.
    static let dataVertexVarint = StreamMeta(
        physicalType:      .data,
        logicalType:       DictionaryType.vertex.rawValue,  // 3
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )

    /// DATA stream — plain bytes (no integer compression; used for raw UTF-8).
    static let dataPlain = StreamMeta(
        physicalType:      .data,
        logicalType:       DictionaryType.none.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .none
    )

    /// LENGTH stream — VarInt-encoded lengths (string byte-lengths).
    static let lengthVarBinary = StreamMeta(
        physicalType:      .length,
        logicalType:       LengthType.varBinary.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )

    /// LENGTH stream — geometry part-counts (NumParts).
    static let lengthParts = StreamMeta(
        physicalType:      .length,
        logicalType:       LengthType.parts.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )

    /// LENGTH stream — ring-counts (NumRings).
    static let lengthRings = StreamMeta(
        physicalType:      .length,
        logicalType:       LengthType.rings.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )

    /// LENGTH stream — geometry counts (NumGeometries, for Multi types).
    static let lengthGeometries = StreamMeta(
        physicalType:      .length,
        logicalType:       LengthType.geometries.rawValue,
        logicalTechnique1: .none,
        logicalTechnique2: .none,
        physicalTechnique: .varint
    )
}

// MARK: - Serialisation

/// Serialise a stream: [2-byte header][varint numValues][varint byteLength][data bytes]
func encodeStream(_ meta: StreamMeta, numValues: Int, data: Data) -> Data {
    var out = Data()
    // Byte 0: (physicalType << 4) | logicalType
    out.append((meta.physicalType.rawValue << 4) | (meta.logicalType & 0x0F))
    // Byte 1: (lt1 << 5) | (lt2 << 2) | physTech
    out.append(
        (meta.logicalTechnique1.rawValue << 5) |
        (meta.logicalTechnique2.rawValue << 2) |
        meta.physicalTechnique.rawValue
    )
    encodeVarint(UInt32(numValues), into: &out)
    encodeVarint(UInt32(data.count), into: &out)
    out.append(data)
    return out
}
