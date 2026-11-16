import Foundation
import SwiftUI

/// Every line of voice in one place. The voice stays the same and only the tone moves:
/// plain is neutral and brief, playful is warm and lightly witty, never loud.
/// Pass `settings.playfulCopy` (or `model.playful`) as the flag.
enum Copy {
    struct Line {
        let title: String
        let detail: String
    }

    private static func pick(_ playful: Bool, _ plain: Line, _ warm: Line) -> Line { playful ? warm : plain }

    // MARK: Empty states

    static func emptyDock(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "This dock is empty.", detail: "Start with one of these, or drag apps and folders here from Finder."),
             Line(title: "Nothing docked yet.", detail: "Drop in an app or two to get it started."))
    }

    static func noDocks(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "No docks yet", detail: "A dock holds the apps, folders and widgets you want close at hand, on any edge of any screen."),
             Line(title: "No docks in the harbor.", detail: "Build one for the apps, folders and widgets you reach for most."))
    }

    static func createDock(_ playful: Bool) -> String { playful ? "Build a Dock" : "Create Dock" }

    static func emptyShelf(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Nothing on the shelf", detail: "Drop files on the shelf icon or here to keep a copy."),
             Line(title: "The shelf is bare.", detail: "Drop a file here and Harbor keeps a copy for you."))
    }

    static func pinnedFiles(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Nothing on the shelf", detail: "Drop files or folders here to keep them close without moving them."),
             Line(title: "Nothing pinned yet.", detail: "Drop files or folders here. They stay right where they are."))
    }

    static func emptyTrash(_ playful: Bool) -> String { playful ? "All tidy in here." : "The Trash is empty" }

    static func noBackups(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "No backups yet", detail: "One appears after your first change tomorrow."),
             Line(title: "No backups yet.", detail: "Harbor saves one after your first change tomorrow."))
    }

    static func noResults(_ query: String, _ playful: Bool) -> Line {
        pick(playful,
             Line(title: "No results", detail: "Nothing matches \"\(query)\"."),
             Line(title: "Nothing by that name.", detail: "Try another word for \"\(query)\"."))
    }

    // MARK: Onboarding

    static func welcomeTitle(_ playful: Bool) -> String { playful ? "Welcome aboard" : "Welcome to Harbor" }

    static func replaceDock(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Replace my Dock", detail: "Same apps and folders; the macOS Dock hides"),
             Line(title: "Move my Dock in", detail: "Same apps and folders; the macOS Dock steps aside"))
    }

    static func emptyChoice(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Empty dock", detail: "Start from scratch"),
             Line(title: "Fresh start", detail: "An empty dock, ready for anything"))
    }

    static func notNow(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Not now", detail: "Open the Manager"),
             Line(title: "Maybe later", detail: "Take me to the Manager"))
    }

    // MARK: Banners and confirmations

    static func saveFailed(_ error: String, _ playful: Bool) -> String {
        playful ? "That didn't save: \(error). Harbor will keep trying."
                : "Changes couldn't be saved: \(error). Harbor will keep trying."
    }

    static func restoreConfirm(_ playful: Bool) -> Line {
        pick(playful,
             Line(title: "Replace your current docks?", detail: "Your current setup is saved first, so you can undo this from the same list."),
             Line(title: "Swap in this backup?", detail: "Your current setup is saved first, so you can always come back."))
    }

    static func deleteIcon(_ playful: Bool) -> String { playful ? "Delete this icon for good?" : "Delete this icon?" }

    // MARK: Library and timer

    static func libraryTitle(_ playful: Bool) -> String { playful ? "Pick a widget" : "Widgets" }

    static func timerDone(_ playful: Bool) -> String { playful ? "Time's up." : "Finished" }
}

/// Search with nothing found, in the current voice.
struct NoResultsView: View {
    @Environment(AppModel.self) private var model
    let query: String

    var body: some View {
        let line = Copy.noResults(query, model.playful)
        ContentUnavailableView(line.title, systemImage: "magnifyingglass", description: Text(line.detail))
    }
}
