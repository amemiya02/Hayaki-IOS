import SwiftUI

/// A problem the learner can read and dismiss while they keep working: an
/// inline row at the top of a screen instead of an alert.
public struct InlineErrorBanner: View {
    private let title: Text
    private let message: String
    private let onDismiss: () -> Void

    public init(title: Text, message: String, onDismiss: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline.weight(.semibold))
                if !message.isEmpty {
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // The system's own localized "Close" label and xmark icon.
            Button(role: .close, action: onDismiss)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-error")
    }
}

public extension View {
    /// Shows an error banner above the content while `error` is set, as a
    /// glass card. Use it on screens whose content is not a list; in a list,
    /// put `InlineErrorBanner` in a row instead.
    func inlineErrorBanner(_ error: Binding<InlineError?>) -> some View {
        modifier(InlineErrorBannerModifier(error: error))
    }

    /// Stands in for content that is still loading: its shape shows as
    /// placeholder bars, it cannot be tapped, and VoiceOver hears a single
    /// "in progress" element.
    func loadingPlaceholder() -> some View {
        redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityRepresentation { ProgressView() }
            .accessibilityIdentifier("loading-placeholder")
    }
}

/// An error for `inlineErrorBanner(_:)`.
public struct InlineError: Identifiable {
    public let id = UUID()
    public let title: Text
    public let message: String

    public init(title: Text, message: String) {
        self.title = title
        self.message = message
    }
}

private struct InlineErrorBannerModifier: ViewModifier {
    @Binding var error: InlineError?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let shown = error {
                    InlineErrorBanner(title: shown.title, message: shown.message) {
                        error = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: error == nil)
    }
}
