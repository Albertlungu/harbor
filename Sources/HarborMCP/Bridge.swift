import Foundation
import HarborCore

/// Sends a command to the running app and waits for the matching reply.
enum Bridge {
    enum Result {
        case reply(AssistantReply)
        case timedOut
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AssistantReply?
        func set(_ reply: AssistantReply) { lock.lock(); value = reply; lock.unlock() }
        func get() -> AssistantReply? { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func send(_ command: AssistantCommand, timeout: TimeInterval) -> Result {
        let center = DistributedNotificationCenter.default()
        let box = Box()
        let id = command.id
        // Observe before posting so a fast reply cannot be missed.
        let token = center.addObserver(forName: Notification.Name(AssistantChannel.replyName), object: nil, queue: nil) { note in
            guard let json = note.userInfo?[AssistantChannel.payloadKey] as? String,
                  let reply = AssistantReply.decode(json), reply.id == id else { return }
            box.set(reply)
        }
        defer { center.removeObserver(token) }

        center.postNotificationName(Notification.Name(AssistantChannel.commandName), object: nil,
                                    userInfo: [AssistantChannel.payloadKey: command.encoded()],
                                    deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        // Distributed notifications are delivered through the run loop.
        while Date() < deadline {
            if let reply = box.get() { return .reply(reply) }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return box.get().map(Result.reply) ?? .timedOut
    }
}
