import CollectionStore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Keeps the daily reminder's pending notifications current for as long
    /// as this view is shown, and calls `openDeckList` when the learner opens
    /// a reminder. The app shell applies it once, around its sections.
    ///
    /// The reminders are computed again after the collection changes, and
    /// whenever the app comes to the foreground or moves to the background;
    /// see `ReminderSchedule` for why.
    public func keepingDailyReminderCurrent(
        store: CollectionStore,
        openDeckList: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(DailyReminderKeeper(store: store, openDeckList: openDeckList))
    }
}

private struct DailyReminderKeeper: ViewModifier {
    let store: CollectionStore
    let openDeckList: @MainActor () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var opener = ReminderOpener.shared

    func body(content: Content) -> some View {
        content
            .task {
                await schedule.keepCurrent()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task { await schedule.update() }
                case .background:
                    updateBeforeSuspension()
                default:
                    break
                }
            }
            .onChange(of: opener.deckListRequested, initial: true) { _, requested in
                guard requested else { return }
                opener.deckListRequested = false
                openDeckList()
            }
    }

    private var schedule: ReminderSchedule {
        ReminderSchedule(store: store, centre: SystemNotificationCentre())
    }

    /// Asks iOS for a little time before the app is suspended, so a change
    /// made just before leaving the app still reaches the reminders.
    private func updateBeforeSuspension() {
        #if canImport(UIKit)
        let application = UIApplication.shared
        let backgroundTask = application.beginBackgroundTask(withName: "Update the daily reminder")
        Task {
            await schedule.update()
            application.endBackgroundTask(backgroundTask)
        }
        #else
        Task { await schedule.update() }
        #endif
    }
}
