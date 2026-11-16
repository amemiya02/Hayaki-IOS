import CollectionStore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Settings row that leads to the reminder screen, showing the reminder's
/// time or that it is off.
public struct ReminderSettingsRow: View {
    private let store: CollectionStore

    @AppStorage(ReminderPreferences.Key.isOn) private var isOn = false
    @AppStorage(ReminderPreferences.Key.hour) private var hour = ReminderPreferences().hour
    @AppStorage(ReminderPreferences.Key.minute) private var minute = ReminderPreferences().minute

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationLink {
            ReminderScreen(store: store)
        } label: {
            LabeledContent {
                if isOn, let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) {
                    Text(time, format: .dateTime.hour().minute())
                } else {
                    Text("Off", bundle: .module, comment: "Shown next to Daily Reminder in Settings when the reminder is off.")
                }
            } label: {
                Label {
                    Text("Daily Reminder", bundle: .module, comment: "Name of the daily study reminder, as a Settings row and the reminder screen's title.")
                } icon: {
                    Image(systemName: "bell")
                }
            }
        }
    }
}

/// Turning the daily reminder on and off and choosing its time.
public struct ReminderScreen: View {
    @State private var model: ReminderModel
    @Environment(\.scenePhase) private var scenePhase

    public init(store: CollectionStore) {
        _model = State(initialValue: ReminderModel(store: store))
    }

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.isOn },
                    set: { on in Task { await model.setOn(on) } }
                )) {
                    Text("Daily Reminder", bundle: .module)
                }
                if model.isOn {
                    DatePicker(
                        selection: Binding(
                            get: { model.time },
                            set: { time in Task { await model.setTime(time) } }
                        ),
                        displayedComponents: .hourAndMinute
                    ) {
                        Text("Time", bundle: .module, comment: "Label of the reminder's time of day.")
                    }
                }
            } footer: {
                Text(
                    "Once a day, Hayaki reminds you how many cards are due. On a day with nothing to study, there is no reminder.",
                    bundle: .module,
                    comment: "Explanation below the daily reminder switch."
                )
            }

            if model.notificationsRefused {
                NotificationsRefusedSection()
            }

            if model.isOn, let next = model.nextReminder {
                Section {
                    LabeledContent {
                        Text(next.delivery, format: .dateTime.weekday(.wide).hour().minute())
                    } label: {
                        Text("When", bundle: .module, comment: "Label of the date and time of the next reminder.")
                    }
                    Text(next.body)
                } header: {
                    Text("Next Reminder", bundle: .module, comment: "Header of the section showing when the next reminder comes and what it says.")
                } footer: {
                    Text(
                        "The count is updated whenever your collection changes. Reviews done on another device are counted after you sync.",
                        bundle: .module,
                        comment: "Explanation below the next reminder of how its due count stays current."
                    )
                }
            }
        }
        .navigationTitle(Text("Daily Reminder", bundle: .module))
        .task { await model.run() }
        .onChange(of: scenePhase) { _, phase in
            // The learner may have allowed notifications in the Settings app.
            if phase == .active {
                Task { await model.refreshPermission() }
            }
        }
    }
}

/// Explains that notifications are refused and how to allow them.
private struct NotificationsRefusedSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Label {
                Text(
                    "Hayaki is not allowed to send notifications, so the reminder cannot appear. To get it, allow notifications for Hayaki in the Settings app, then turn the reminder on.",
                    bundle: .module,
                    comment: "Shown when the learner refused notifications, explaining how to allow them later."
                )
            } icon: {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.red)
            }
            #if canImport(UIKit)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("Open Settings", bundle: .module, comment: "Button that opens Hayaki's notification settings in the Settings app.")
            }
            #endif
        }
    }
}
