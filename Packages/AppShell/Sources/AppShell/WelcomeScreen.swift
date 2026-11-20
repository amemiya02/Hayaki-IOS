import HayakiAppearance
import PackagesFeature
import SwiftUI
import SyncFeature

/// The first screen of a fresh collection: the app icon, a large title, a
/// short value line, and the two ways in, Import or Sync. Quieter links below
/// offer a text file, shared decks, or an empty start.
struct WelcomeScreen: View {
    let sync: SyncModel
    let onContinue: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 112.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    VStack(spacing: 12) {
                        ImportPackageButton()
                            .buttonStyle(.glassProminent)
                        NavigationLink {
                            syncScreen
                        } label: {
                            Label {
                                Text("Set Up Sync", bundle: .module)
                            } icon: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    .labelStyle(WideButtonLabelStyle())
                    .controlSize(.extraLarge)
                    VStack(spacing: 16) {
                        TextImportButton()
                        SharedDecksLink()
                        Button(action: onContinue) {
                            Text("Start Empty", bundle: .module)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { HayakiBackground(.grouped).ignoresSafeArea() }
            #if os(iOS)
            // The large title is part of the content.
            .toolbarVisibility(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image("WelcomeIcon", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(.rect(cornerRadius: iconSize * 0.225, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("Welcome to Hayaki", bundle: .module)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Flashcards with spaced repetition. Import your decks or sync your collection to begin.", bundle: .module)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var syncScreen: some View {
        SyncScreen(model: sync)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onContinue) {
                        Text("Done", bundle: .module)
                    }
                    .disabled(sync.isBusy)
                }
            }
    }
}

/// An icon and title centred across the full width of a large button.
private struct WideButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
        .frame(maxWidth: .infinity)
    }
}
