import Foundation
import Testing
@testable import Serialization

// MARK: - Error mapping tests

@Suite("Error mapping: bad bytes → SerializationError only")
struct ErrorMappingTests {
    private let badData = Data([0xFF, 0xFE, 0xFD, 0x00, 0x11])

    @Test("CBOR malformed data → SerializationError.malformedData")
    func cborMalformedData() {
        #expect(throws: SerializationError.self) {
            _ = try CBORCodec().decode(Vector3.self, from: badData)
        }
    }

    @Test("JSON malformed data → SerializationError.malformedData")
    func jsonMalformedData() {
        #expect(throws: SerializationError.self) {
            _ = try JSONCodec().decode(Vector3.self, from: badData)
        }
    }

    @Test("MessagePack malformed data → SerializationError.malformedData")
    func msgpackMalformedData() {
        #expect(throws: SerializationError.self) {
            _ = try MessagePackCodec().decode(Vector3.self, from: badData)
        }
    }

    @Test("JSON type mismatch → SerializationError.schemaMismatch")
    func jsonTypeMismatch() throws {
        // Encode a string, try to decode as Vector3
        let stringData = try JSONCodec().encode("not-a-vector3")
        #expect(throws: SerializationError.self) {
            _ = try JSONCodec().decode(Vector3.self, from: stringData)
        }
    }

    @Test("CBOR type mismatch → SerializationError.schemaMismatch")
    func cborTypeMismatch() throws {
        let stringData = try CBORCodec().encode("not-a-vector3")
        #expect(throws: SerializationError.self) {
            _ = try CBORCodec().decode(Vector3.self, from: stringData)
        }
    }

    @Test("No raw SwiftCBOR/Foundation errors escape the public API")
    func noRawLibraryErrorsEscape() {
        for codec: any Codec in [CBORCodec(), JSONCodec(), MessagePackCodec()] {
            do {
                _ = try codec.decode(Vector3.self, from: badData)
                Issue.record("Expected an error from \(codec.contentType)")
            } catch let error as SerializationError {
                // Good — only SerializationError is allowed
                _ = error
            } catch {
                Issue.record("Raw library error escaped from \(codec.contentType): \(error)")
            }
        }
    }
}

// MARK: - contentType values

@Suite("contentType identifiers")
struct ContentTypeTests {
    @Test("JSON contentType is application/json")
    func jsonContentType() {
        #expect(JSONCodec().contentType == "application/json")
    }

    @Test("CBOR contentType is application/cbor")
    func cborContentType() {
        #expect(CBORCodec().contentType == "application/cbor")
    }

    @Test("MessagePack contentType is application/msgpack")
    func msgpackContentType() {
        #expect(MessagePackCodec().contentType == "application/msgpack")
    }
}

// MARK: - Cross-codec fidelity

@Suite("Cross-codec: JSON → CBOR → MessagePack same data")
struct CrossCodecTests {
    @Test("Same struct encodes to decodeable bytes across all three codecs independently")
    func independentCodecEquality() throws {
        let original = Twist(
            linear: Vector3(x: 1.0, y: 2.0, z: 3.0),
            angular: Vector3(x: 0.0, y: 0.0, z: 0.785)
        )
        let viaJSON = try JSONCodec().decode(Twist.self, from: JSONCodec().encode(original))
        let viaCBOR = try CBORCodec().decode(Twist.self, from: CBORCodec().encode(original))
        let viaMSG = try MessagePackCodec().decode(Twist.self, from: MessagePackCodec().encode(original))
        #expect(viaJSON == original)
        #expect(viaCBOR == original)
        #expect(viaMSG == original)
    }
}

// Note: CBOR tagged-value (tag 1) timestamp fixture tests will be added in M3 Transport
// when we parse actual foxglove_bridge binary frames. The tag-1 parsing requires
// raw CBOR handling outside the Codable layer.
