import SwiftUI

public extension View {
    /// Shows sync progress in a glass strip above the tab bar, or at the
    /// foot of the sidebar on iPad, whenever a sync runs: manual, automatic
    /// or one started in the background while the app is active.
    func syncProgressAccessory(_ model: SyncModel) -> some View {
        modifier(SyncAccessoryModifier(model: model))
    }
}

private struct SyncAccessoryModifier: ViewModifier {
    let model: SyncModel
    @State private var accessory: SyncAccessory?
    /// Set when Retry here may ask about a metered connection, which only the
    /// Sync screen can confirm.
    @State private var retrying = false
    @State private var showsSync = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var inSidebar: Bool { sizeClass == .regular }
    #else
    private let inSidebar = true
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct SyncState: Equatable {
        let status: SyncModel.Status
        let media: MediaSyncStatus
    }

    func body(content: Content) -> some View {
        content
            .bottomAccessory(isEnabled: accessory != nil && !inSidebar) { strip }
            .tabViewSidebarBottomBar {
                if accessory != nil, inSidebar {
                    strip
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
            .onChange(of: SyncState(status: model.status, media: model.mediaStatus), initial: true) { _, state in
                let next = SyncAccessory.next(after: accessory, status: state.status, mediaStatus: state.media)
                guard next != accessory else { return }
                announce(next)
                withAnimation(reduceMotion ? nil : .smooth) { accessory = next }
            }
            .task(id: accessory == .succeeded) {
                guard accessory == .succeeded else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, accessory == .succeeded else { return }
                withAnimation(reduceMotion ? nil : .smooth) { accessory = nil }
            }
            .onChange(of: model.needsMeteredConfirmation) { _, needed in
                if needed, retrying { showsSync = true }
            }
            .sheet(isPresented: $showsSync, onDismiss: model.dismissMeteredConfirmation) {
                NavigationStack {
                    SyncScreen(model: model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    showsSync = false
                                } label: {
                                    Text("Done", bundle: .module)
                                }
                            }
                        }
                }
            }
    }

    @ViewBuilder
    private var strip: some View {
        if let accessory {
            SyncAccessoryStrip(
                accessory: accessory,
                cancel: model.cancel,
                retry: { retry(accessory) },
                dismiss: { withAnimation(reduceMotion ? nil : .smooth) { self.accessory = nil } }
            )
        }
    }

    private func retry(_ accessory: SyncAccessory) {
        guard case .failed(_, let action) = accessory else { return }
        retrying = true
        Task {
            defer { retrying = false }
            switch action {
            case .collection: await model.sync()
            case .media: await model.retryMediaSync()
            }
        }
    }

    private func announce(_ accessory: SyncAccessory?) {
        switch accessory {
        case .succeeded:
            AccessibilityNotification.Announcement(String(localized: "Synced", bundle: .module)).post()
        case .failed(let failure, _):
            AccessibilityNotification.Announcement(failure.message).post()
        case .running, nil:
            break
        }
    }
}

private extension View {
    /// The tab view's bottom accessory, which the system draws as glass above
    /// the tab bar. iOS 26.0 cannot hide it, so it starts at 26.1.
    @ViewBuilder
    func bottomAccessory<Accessory: View>(isEnabled: Bool, @ViewBuilder content: () -> Accessory) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// One line of sync status with its control: circular progress and Cancel
/// while running, a checkmark after success, the reason and Retry after a failure.
struct SyncAccessoryStrip: View {
    let accessory: SyncAccessory
    let cancel: () -> Void
    let retry: () -> Void
    let dismiss: () -> Void
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 24, height: 24)
            Text(verbatim: line)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(isFailure ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sync Progress", bundle: .module))
        .accessibilityIdentifier("sync-accessory")
    }

    private var isFailure: Bool {
        if case .failed = accessory { true } else { false }
    }

    private var line: String {
        switch accessory {
        case .running(let progress): progress.line
        case .succeeded: String(localized: "Synced", bundle: .module)
        case .failed(let failure, _): failure.message
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch accessory {
        case .running(let progress):
            Group {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.circular)
            .controlSize(.small)
            .accessibilityHidden(true)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: bounce)
                .onAppear { if !reduceMotion { bounce.toggle() } }
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch accessory {
        case .running:
            Button(action: cancel) {
                Label {
                    Text("Cancel Sync", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("sync-accessory-cancel")
        case .succeeded:
            EmptyView()
        case .failed:
            Button(action: retry) {
                Text("Retry", bundle: .module)
            }
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
            .accessibilityIdentifier("sync-accessory-retry")
            Button(action: dismiss) {
                Label {
                    Text("Dismiss", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("sync-accessory-dismiss")
        }
    }
}
