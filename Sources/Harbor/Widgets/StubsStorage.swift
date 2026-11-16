// Placeholder until the storage widgets land. Delete when implementing.
import HarborCore
import SwiftUI
struct FolderStackWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct AppStackWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct ShelfWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct FileShelfWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct TrashWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct StorageWidgetMenu: View { let item: DockItem; let dock: Dock; var body: some View { EmptyView() } }
struct StorageWidgetSettings: View { let item: DockItem; let dockID: UUID; var body: some View { EmptyView() } }
@MainActor enum StorageWidgetDrop { static func handle(_ providers: [NSItemProvider], item: DockItem, dock: Dock, model: AppModel) -> Bool { false } }
