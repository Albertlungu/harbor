import Foundation

/// A parsed JSON-RPC 2.0 message. Notifications have no id and get no reply.
public struct JSONRPCRequest: Sendable {
    public var id: JSONValue?
    public var method: String
    public var params: [String: JSONValue]

    public var isNotification: Bool { id == nil }
}

public enum JSONRPCError {
    public static let parse = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

public enum JSONRPC {
    public enum ParseResult: Sendable {
        case request(JSONRPCRequest)
        case failure(id: JSONValue?, code: Int, message: String)
    }

    public static func parse(_ line: String) -> ParseResult {
        guard let data = line.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .failure(id: nil, code: JSONRPCError.parse, message: "Parse error")
        }
        guard case .object(let object) = value, object["jsonrpc"]?.stringValue == "2.0",
              let method = object["method"]?.stringValue else {
            var id: JSONValue?
            if case .object(let o) = value { id = o["id"] }
            return .failure(id: id, code: JSONRPCError.invalidRequest, message: "Invalid request")
        }
        var params: [String: JSONValue] = [:]
        if case .object(let p)? = object["params"] { params = p }
        var id = object["id"]
        if case .null? = id { id = nil }
        return .request(JSONRPCRequest(id: id, method: method, params: params))
    }

    public static func result(id: JSONValue?, _ result: JSONValue) -> String {
        encode(["jsonrpc": .string("2.0"), "id": id ?? .null, "result": result])
    }

    public static func error(id: JSONValue?, code: Int, message: String) -> String {
        encode(["jsonrpc": .string("2.0"), "id": id ?? .null,
                "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }

    /// Compact single-line JSON, as the stdio transport requires.
    public static func encode(_ object: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(JSONValue.object(object))) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
