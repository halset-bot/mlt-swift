// Varint.swift — Protobuf-style variable-length integer encoding.
//
// Unsigned VarInt:  1–10 bytes, 7 bits of value per byte, MSB set if more follows.
// ZigZag encoding:  maps signed integers to unsigned before varinting.
//   encode: (n << 1) ^ (n >> 63)  for Int64
//   encode: (n << 1) ^ (n >> 31)  for Int32

import Foundation

// MARK: - Unsigned varint

func encodeVarint(_ value: UInt64, into buffer: inout Data) {
    var v = value
    while v > 0x7F {
        buffer.append(UInt8((v & 0x7F) | 0x80))
        v >>= 7
    }
    buffer.append(UInt8(v))
}

@inline(__always)
func encodeVarint(_ value: UInt32, into buffer: inout Data) {
    encodeVarint(UInt64(value), into: &buffer)
}

// MARK: - ZigZag + varint for signed integers

@inline(__always)
func encodeZigZag32(_ value: Int32, into buffer: inout Data) {
    let encoded = UInt32(bitPattern: (value << 1) ^ (value >> 31))
    encodeVarint(UInt64(encoded), into: &buffer)
}

@inline(__always)
func encodeZigZag64(_ value: Int64, into buffer: inout Data) {
    let encoded = UInt64(bitPattern: (value << 1) ^ (value >> 63))
    encodeVarint(encoded, into: &buffer)
}

// MARK: - Helpers returning Data

func varintData(_ value: UInt64) -> Data {
    var d = Data()
    encodeVarint(value, into: &d)
    return d
}

func varintData(_ value: UInt32) -> Data { varintData(UInt64(value)) }
func varintData(_ value: Int) -> Data    { varintData(UInt64(value)) }
