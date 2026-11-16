import Darwin
import HarborCore
import SwiftUI

/// Local and public address state, shared by every IP widget and the right-click menu.
@MainActor
@Observable
final class IPAddressModel {
    static let shared = IPAddressModel()

    enum PublicState: Equatable { case idle, loading, offline, address(String) }

    private(set) var local: String?
    private(set) var publicState: PublicState = .idle

    @ObservationIgnored private var modes: [UUID: String] = [:]
    @ObservationIgnored private var loop: SystemLoop?
    @ObservationIgnored private var lastPublicFetch: Date?
    @ObservationIgnored private var fetching = false

    private static let localInterval: TimeInterval = 30
    private static let publicInterval: TimeInterval = 300

    private init() {
        loop = SystemLoop { [weak self] in await self?.tick() }
    }

    private var wantsPublic: Bool { modes.values.contains { $0 != "local" } }

    func register(_ id: UUID, mode: String) {
        let hadPublic = wantsPublic
        modes[id] = mode
        loop?.register(id, interval: Self.localInterval)
        if wantsPublic && !hadPublic { Task { await fetchPublic() } }
    }

    func unregister(_ id: UUID) {
        modes[id] = nil
        loop?.unregister(id)
    }

    func refresh() async {
        local = Self.readLocal()
        if wantsPublic { await fetchPublic() }
    }

    /// Fetches on demand for the menu, which may run with no widget on screen.
    func currentPublic() async -> String? {
        if case .address(let value) = publicState { return value }
        await fetchPublic()
        if case .address(let value) = publicState { return value }
        return nil
    }

    func currentLocal() -> String? {
        local ?? Self.readLocal()
    }

    private func tick() async {
        local = Self.readLocal()
        if wantsPublic, lastPublicFetch.map({ Date().timeIntervalSince($0) >= Self.publicInterval }) ?? true {
            await fetchPublic()
        }
    }

    private func fetchPublic() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        if case .address = publicState {} else { publicState = .loading }
        var request = URLRequest(url: URL(string: "https://api.ipify.org")!, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            // Guards against captive-portal pages answering in place of the service.
            if !text.isEmpty, text.count <= 45, !text.contains(where: { $0.isWhitespace || $0 == "<" }) {
                publicState = .address(text)
                lastPublicFetch = Date()
            } else {
                publicState = .offline
            }
        } catch {
            publicState = .offline
        }
    }

    private static func readLocal() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found: [SystemLogic.InterfaceAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let up = Int32(entry.ifa_flags) & IFF_UP != 0 && Int32(entry.ifa_flags) & IFF_RUNNING != 0
            found.append(.init(name: String(cString: entry.ifa_name), address: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), isUp: up))
        }
        return SystemLogic.rankIPv4(found).first?.address
    }
}

struct IPWidget: View {
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @Environment(AppModel.self) private var model
    @State private var token = UUID()
    private let ip = IPAddressModel.shared

    private var mode: String { widget.string("mode", "public") }

    var body: some View {
        let both = mode == "both"
        VStack(spacing: size.height * 0.04) {
            if mode != "local" { line(label: "Public", symbol: "globe", text: publicText, address: publicAddress, compact: both) }
            if mode != "public" { line(label: "Local", symbol: "network", text: localText, address: ip.local, compact: both) }
        }
        .padding(.horizontal, Tokens.Space.xs)
        .frame(width: size.width, height: size.height)
        .onAppear { ip.register(token, mode: mode) }
        .onDisappear { ip.unregister(token) }
        .onChange(of: mode) { ip.register(token, mode: mode) }
    }

    private func line(label: String, symbol: String, text: String, address: String?, compact: Bool) -> some View {
        let unit = compact ? size.height * 0.5 : size.height
        return VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.xxs) {
                Image(systemName: symbol)
                Text(label)
            }
            .font(.system(size: max(7, unit * 0.2), weight: .medium, design: .rounded))
            .foregroundStyle(Tokens.textMuted)
            Text(text)
                .font(.system(size: max(8, unit * 0.3), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(address == nil ? Tokens.textMuted : Tokens.text)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .contentShape(Rectangle())
        .onTapGesture { copy(address) }
        .help(address.map { "Click to copy \($0)" } ?? text)
        .accessibilityElement(children: .combine)
    }

    private var publicAddress: String? {
        if case .address(let value) = ip.publicState { return value }
        return nil
    }

    private var publicText: String {
        switch ip.publicState {
        case .address(let value): value
        case .offline: "Offline"
        case .idle, .loading: "Loading"
        }
    }

    private var localText: String { ip.local ?? "No network" }

    private func copy(_ address: String?) {
        guard let address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        model.flashHint("Copied")
    }
}
