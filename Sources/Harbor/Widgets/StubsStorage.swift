// Placeholder until the storage widgets land. Delete when implementing.
import HarborCore
import SwiftUI
struct StorageWidgetMenu: View { let item: DockItem; let dock: Dock; var body: some View { EmptyView() } }
struct StorageWidgetSettings: View { let item: DockItem; let dockID: UUID; var body: some View { EmptyView() } }
@MainActor enum StorageWidgetDrop { static func handle(_ providers: [NSItemProvider], item: DockItem, dock: Dock, model: AppModel) -> Bool { false } }
