import HarborCore
import SwiftUI

struct StyleSection: View { let dock: Dock; var body: some View { Text("Style") } }
struct PositionSection: View { let dock: Dock; var body: some View { Text("Position") } }
struct ScreensSection: View { let dock: Dock; var body: some View { Text("Screens") } }
struct BehaviorSection: View { let dock: Dock; var body: some View { Text("Behavior") } }
struct ItemOptionsSheet: View { let ref: ItemRef; var body: some View { Text("Options") } }
struct WidgetLibrary: View { let dock: Dock; var body: some View { Text("Library") } }
struct RestoreSheet: View { var body: some View { Text("Restore") } }
struct SettingsView: View { var body: some View { Text("Settings") } }
struct OnboardingView: View { var body: some View { Text("Welcome") } }
