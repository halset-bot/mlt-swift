// OrcEncoding.swift — ORC-compatible Byte-RLE and Boolean-RLE encoders.
//
// Byte-RLE (used for GeometryType stream):
//   Runs of identical bytes:    header = runLength - 3  (0..127, i.e. 3..130 bytes)
//                               followed by the single repeated byte.
//   Literals (distinct bytes):  header = -literalCount  (-1..-128)
//                               followed by literalCount bytes.
//
// Boolean-RLE (used for PRESENT streams):
//   Pack 8 booleans per byte (LSB = first boolean).
//   Then apply Byte-RLE on those bytes.

import Foundation

// MARK: - Byte-RLE

/// Encode an array of bytes using ORC Byte-RLE.
func encodeByteRLE(_ values: [UInt8]) -> Data {
    guard !values.isEmpty else { return Data() }

    var output = Data()
    var i = 0
    let n = values.count

    while i < n {
        // Try to detect a run starting at i
        var runLen = 1
        while runLen < 130 && i + runLen < n && values[i + runLen] == values[i] {
            runLen += 1
        }

        if runLen >= 3 {
            // Emit a run
            output.append(UInt8(runLen - 3))   // header: 0..127
            output.append(values[i])
            i += runLen
        } else {
            // Collect literals until we'd break into a run of >=3
            var litStart = i
            var litCount = 0
            while litCount < 128 && i < n {
                // Look ahead: is there a run of >=3 starting here?
                var ahead = 1
                while i + ahead < n
                      && ahead < 3
                      && values[i + ahead] == values[i] {
                    ahead += 1
                }
                if ahead >= 3 && litCount > 0 {
                    break  // flush literals, then handle the run on next pass
                }
                litCount += 1
                i += 1
            }
            // Header: -litCount (interpreted as signed byte)
            output.append(UInt8(bitPattern: Int8(-litCount)))
            output.append(contentsOf: values[litStart ..< litStart + litCount])
        }
    }

    return output
}

// MARK: - Boolean-RLE

/// Pack an array of Booleans (8 per byte, LSB first) then Byte-RLE encode.
func encodeBooleanRLE(_ values: [Bool]) -> Data {
    guard !values.isEmpty else { return Data() }

    // Pack into bytes
    let byteCount = (values.count + 7) / 8
    var bytes = [UInt8](repeating: 0, count: byteCount)
    for (index, flag) in values.enumerated() {
        if flag {
            bytes[index / 8] |= (1 << (index % 8))
        }
    }
    return encodeByteRLE(bytes)
}
