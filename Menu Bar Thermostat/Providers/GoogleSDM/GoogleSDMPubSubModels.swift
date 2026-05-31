import Foundation

enum PubSubError: Error {
    case subscriptionNotExists
    case authenticationFailure
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)

    var description: String {
        switch self {
        case .subscriptionNotExists:
            return "Pub/Sub subscription does not exist"
        case .authenticationFailure:
            return "Authentication failure for Pub/Sub"
        case .invalidResponse:
            return "Invalid response from Pub/Sub"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode message: \(error.localizedDescription)"
        }
    }
}

struct PubSubResponse: Decodable {
    let receivedMessages: [PubSubReceivedMessage]?
}

struct PubSubReceivedMessage: Decodable {
    let ackId: String
    let message: PubSubMessage

    enum CodingKeys: String, CodingKey {
        case ackId
        case message
    }
}

struct PubSubMessage: Decodable {
    let messageId: String
    let publishTime: String
    let data: String?
    let attributes: [String: String]?
}

struct PubSubAcknowledgeRequest: Encodable {
    let ackIds: [String]
}

struct EventMessage: Decodable {
    let eventId: String
    let timestamp: String
    let resourceUpdate: ResourceUpdate?

    struct ResourceUpdate: Decodable {
        let name: String
        let traits: [String: JSONAny]?

        enum CodingKeys: String, CodingKey {
            case name
            case traits
        }
    }
}

/// Lightweight wrapper that allows decoding heterogeneous JSON values.
struct JSONAny: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let dictValue = try? container.decode([String: JSONAny].self) {
            value = dictValue.mapValues { $0.value }
        } else if let arrayValue = try? container.decode([JSONAny].self) {
            value = arrayValue.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

extension JSONAny: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let dictValue as [String: Any]:
            let converted = dictValue.mapValues { JSONAny(value: $0) }
            try container.encode(converted)
        case let arrayValue as [Any]:
            let converted = arrayValue.map { JSONAny(value: $0) }
            try container.encode(converted)
        case _ as NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
            throw EncodingError.invalidValue(value, context)
        }
    }

    init(value: Any) {
        self.value = value
    }
}
