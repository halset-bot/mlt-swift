// PropertyEncoder.swift — Encode property columns for a FeatureTable.
//
// One column per distinct property key across all features in the layer.
// The encoder infers the column type from the first non-null value found.
// Mixed scalar types within a column produce an error.

import Foundation

// MARK: - Column type inference

/// Infer the ColumnType from the values of one property key across all features.
func inferColumnType(key: String, features: [MLTFeature]) throws -> ColumnType {
    var hasNull = false
    var inferred: ColumnType? = nil

    for f in features {
        guard let val = f.properties[key] else {
            hasNull = true
            continue
        }
        switch val {
        case .null:
            hasNull = true
        case .boolean:
            if let existing = inferred, case .boolean = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .boolean(nullable: false)
            }
        case .int32:
            if let existing = inferred, case .int32 = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .int32(nullable: false)
            }
        case .uint32:
            if let existing = inferred, case .uint32 = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .uint32(nullable: false)
            }
        case .int64:
            if let existing = inferred, case .int64 = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .int64(nullable: false)
            }
        case .uint64:
            if let existing = inferred, case .uint64 = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .uint64(nullable: false)
            }
        case .float:
            if let existing = inferred, case .float = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .float(nullable: false)
            }
        case .double:
            if let existing = inferred, case .double_ = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .double_(nullable: false)
            }
        case .string:
            if let existing = inferred, case .string = existing {} else if inferred != nil {
                throw MLTEncoderError.typeMismatch(column: key, message: "Mixed types")
            } else {
                inferred = .string(nullable: false)
            }
        }
    }

    // If all values were null, default to string nullable
    guard let base = inferred else {
        return .string(nullable: true)
    }

    if hasNull {
        // Make nullable
        switch base {
        case .boolean:  return .boolean(nullable: true)
        case .int32:    return .int32(nullable: true)
        case .uint32:   return .uint32(nullable: true)
        case .int64:    return .int64(nullable: true)
        case .uint64:   return .uint64(nullable: true)
        case .float:    return .float(nullable: true)
        case .double_:  return .double_(nullable: true)
        case .string:   return .string(nullable: true)
        }
    }
    return base
}

// MARK: - Column type code (matches type_map::Tag0x01)

func typeCode(for columnType: ColumnType) -> UInt32 {
    switch columnType {
    case .boolean(let n):  return n ? 11 : 10
    case .int32(let n):    return n ? 17 : 16
    case .uint32(let n):   return n ? 19 : 18
    case .int64(let n):    return n ? 21 : 20
    case .uint64(let n):   return n ? 23 : 22
    case .float(let n):    return n ? 25 : 24
    case .double_(let n):  return n ? 27 : 26
    case .string(let n):   return n ? 29 : 28
    }
}

// MARK: - PRESENT stream helper

private func encodePresentStream(key: String, features: [MLTFeature]) -> Data {
    let presence = features.map { f -> Bool in
        guard let val = f.properties[key] else { return false }
        if case .null = val { return false }
        return true
    }
    let rleData = encodeBooleanRLE(presence)
    return encodeStream(.present, numValues: features.count, data: rleData)
}

// MARK: - Per-type column encoder

/// Returns the column data bytes (streams only, no metadata header).
func encodePropertyColumn(
    key: String,
    columnType: ColumnType,
    features: [MLTFeature]
) -> Data {
    var out = Data()
    let nullable = columnType.isNullable

    switch columnType {

    // ---- BOOLEAN ----
    case .boolean:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var bits: [Bool] = []
        for f in features {
            switch f.properties[key] {
            case .boolean(let b): bits.append(b)
            default:              bits.append(false)
            }
        }
        let rleData = encodeBooleanRLE(bits)
        out.append(encodeStream(.dataByteRLE, numValues: features.count, data: rleData))

    // ---- INT32 ----
    case .int32:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .int32(let v) = f.properties[key] {
                encodeZigZag32(v, into: &payload); count += 1
            }
        }
        out.append(encodeStream(.dataVarint, numValues: count, data: payload))

    // ---- UINT32 ----
    case .uint32:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .uint32(let v) = f.properties[key] {
                encodeVarint(v, into: &payload); count += 1
            }
        }
        out.append(encodeStream(.dataVarint, numValues: count, data: payload))

    // ---- INT64 ----
    case .int64:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .int64(let v) = f.properties[key] {
                encodeZigZag64(v, into: &payload); count += 1
            }
        }
        out.append(encodeStream(.dataVarint, numValues: count, data: payload))

    // ---- UINT64 ----
    case .uint64:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .uint64(let v) = f.properties[key] {
                encodeVarint(v, into: &payload); count += 1
            }
        }
        out.append(encodeStream(.dataVarint, numValues: count, data: payload))

    // ---- FLOAT ----
    case .float:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .float(let v) = f.properties[key] {
                var bits = v.bitPattern  // UInt32 IEEE 754
                withUnsafeBytes(of: &bits) { payload.append(contentsOf: $0) }
                count += 1
            }
        }
        out.append(encodeStream(.dataPlain, numValues: count, data: payload))

    // ---- DOUBLE ----
    case .double_:
        if nullable { out.append(encodePresentStream(key: key, features: features)) }
        var payload = Data()
        var count = 0
        for f in features {
            if case .double(let v) = f.properties[key] {
                var bits = v.bitPattern  // UInt64 IEEE 754
                withUnsafeBytes(of: &bits) { payload.append(contentsOf: $0) }
                count += 1
            }
        }
        out.append(encodeStream(.dataPlain, numValues: count, data: payload))

    // ---- STRING ----
    case .string:
        // String columns carry a numStreams varint (2 or 3).
        let streamCount: UInt32 = nullable ? 3 : 2
        encodeVarint(streamCount, into: &out)

        if nullable { out.append(encodePresentStream(key: key, features: features)) }

        var lengths = Data()
        var rawBytes = Data()
        var lengthCount = 0
        for f in features {
            if case .string(let s) = f.properties[key] {
                let utf8 = Data(s.utf8)
                encodeVarint(UInt32(utf8.count), into: &lengths)
                rawBytes.append(utf8)
                lengthCount += 1
            }
        }
        out.append(encodeStream(.lengthVarBinary, numValues: lengthCount, data: lengths))
        out.append(encodeStream(.dataPlain, numValues: rawBytes.count, data: rawBytes))
    }

    return out
}
