import Foundation
import HarborCore

setvbuf(stdout, nil, _IOLBF, 0)

func write(_ line: String) {
    print(line)
    fflush(stdout)
}

func handle(_ request: JSONRPCRequest) -> String? {
    switch request.method {
    case "initialize":
        let version = request.params["protocolVersion"]?.stringValue ?? "2024-11-05"
        return JSONRPC.result(id: request.id, .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("harbor"), "version": .string("0.1.0")]),
        ]))
    case "ping":
        return JSONRPC.result(id: request.id, .object([:]))
    case "tools/list":
        return JSONRPC.result(id: request.id, .object(["tools": .array(Tools.list)]))
    case "tools/call":
        guard let name = request.params["name"]?.stringValue else {
            return JSONRPC.error(id: request.id, code: JSONRPCError.invalidParams, message: "Missing tool name")
        }
        var args: [String: JSONValue] = [:]
        if case .object(let a)? = request.params["arguments"] { args = a }
        let outcome = Tools.call(name, args)
        return JSONRPC.result(id: request.id, .object([
            "content": .array([.object(["type": .string("text"), "text": .string(outcome.text)])]),
            "isError": .bool(outcome.isError),
        ]))
    default:
        // Notifications such as notifications/initialized need no reply.
        if request.isNotification { return nil }
        return JSONRPC.error(id: request.id, code: JSONRPCError.methodNotFound, message: "Method not found: \(request.method)")
    }
}

while let line = readLine(strippingNewline: true) {
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    switch JSONRPC.parse(line) {
    case .request(let request):
        if let response = handle(request) { write(response) }
    case .failure(let id, let code, let message):
        write(JSONRPC.error(id: id, code: code, message: message))
    }
}
