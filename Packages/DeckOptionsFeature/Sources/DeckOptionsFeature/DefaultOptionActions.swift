import AnkiProto
import SwiftUI

extension View {
    @MainActor
    func restorePresetDefault<Value>(
        _ model: DeckOptionsModel,
        _ field: WritableKeyPath<Anki_DeckConfig_DeckConfig.Config, Value>
    ) -> some View {
        offerOptionDefault {
            model.selectedConfig[keyPath: field] = model.settings.defaults.config[keyPath: field]
        }
    }

    @MainActor
    func offerOptionDefault(_ restore: @escaping () -> Void) -> some View {
        contextMenu {
            Button(action: restore) {
                Text("Restore Default", bundle: .module)
            }
        }
    }
}
