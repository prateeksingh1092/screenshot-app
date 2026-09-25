import Foundation
import SwiftUI
import FrisketCore

@MainActor final class ThumbnailSettings: ObservableObject {
    @Published var never: Bool
    @Published var seconds: Int
    @Published private(set) var applying = false
    private let defaults: UserDefaults
    private var commands: CaptureLifecycleCoordinator?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = ThumbnailAutoDismissPreference.load(
            never: defaults.bool(forKey: PreferenceKey.thumbnailAutoDismissNever.rawValue),
            seconds: defaults.object(forKey: PreferenceKey.thumbnailAutoDismissSeconds.rawValue))
        never = stored.never
        seconds = stored.seconds
    }

    var preference: ThumbnailAutoDismissPreference {
        ThumbnailAutoDismissPreference(never: never, seconds: seconds)
    }

    var policy: ThumbnailStackPolicy {
        ThumbnailStackPolicy(autoDismiss: preference.autoDismiss)
    }

    func connect(_ commands: CaptureLifecycleCoordinator) {
        self.commands = commands
        Task { await commands.setThumbnailPolicy(policy) }
    }

    func apply() {
        guard !applying else { return }
        applying = true
        let selected = preference
        never = selected.never
        seconds = selected.seconds
        defaults.set(selected.never, forKey: PreferenceKey.thumbnailAutoDismissNever.rawValue)
        defaults.set(selected.seconds, forKey: PreferenceKey.thumbnailAutoDismissSeconds.rawValue)
        Task {
            await commands?.setThumbnailPolicy(ThumbnailStackPolicy(autoDismiss: selected.autoDismiss))
            applying = false
        }
    }
}

struct ThumbnailSettingsSection: View {
    @ObservedObject var settings: ThumbnailSettings

    var body: some View {
        Section("Thumbnails") {
            Toggle("Never auto-dismiss", isOn: $settings.never)
                .accessibilityLabel("Never auto-dismiss thumbnails")
            TextField("Auto-dismiss after (seconds)", value: $settings.seconds, format: .number)
                .disabled(settings.never)
                .accessibilityLabel("Thumbnail auto-dismiss delay in seconds")
            Button("Apply Thumbnail Settings", action: settings.apply).disabled(settings.applying)
            Text("Zero seconds dismisses immediately. Never keeps cards until you act or the stack overflows.")
        }
    }
}
