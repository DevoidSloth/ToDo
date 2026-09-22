import Combine
import SwiftUI

/// Closing the window on a single-window utility should mean "I'm done", so the
/// app exits rather than lingering with no window. Everything is already on
/// disk by then — the store writes after every change.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TodoListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TodoStore()
    @StateObject private var focus = FocusCoordinator()

    var body: some Scene {
        WindowGroup("Todo List") {
            ContentView()
                .environmentObject(store)
                .environmentObject(focus)
        }
        .defaultSize(width: 480, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            // A single-window utility has no use for "New Window".
            CommandGroup(replacing: .newItem) {}

            // Each shortcut switches to the right view and drops the cursor in
            // that field, so a task can be filed without touching the mouse.
            CommandMenu("Add Task") {
                ForEach(Array(Bucket.allCases.enumerated()), id: \.element) { index, bucket in
                    Button("New \(bucket.singular)") { focus.target = .bucket(bucket) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                          modifiers: .command)
                }
                Divider()
                Button("New Long-Term Task") { focus.target = .longTerm }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
