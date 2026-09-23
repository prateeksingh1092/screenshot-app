import Foundation
import SwiftUI
import FrisketCore

@MainActor final class HistorySettings: ObservableObject {
    @Published var retentionDays: Int
    @Published var maximumMegabytes: Int
    @Published private(set) var usage: HistoryUsage?
    @Published private(set) var unavailable = false
    @Published private(set) var applying = false
    private let defaults: UserDefaults
    private var commands: CaptureCommandLayer?
    var onQuotaEviction: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        retentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 30
        maximumMegabytes = defaults.object(forKey: "historyMaximumMegabytes") as? Int ?? 1000
    }

    var limits: HistoryLimits {
        HistoryLimits(retentionDays: retentionDays, maximumBytes: Int64(min(1_000_000, max(1, maximumMegabytes))) * 1_000_000)
    }

    func connect(_ commands: CaptureCommandLayer) {
        self.commands = commands
        Task {
            _ = await commands.maintainHistory()
            await refresh()
        }
    }

    func apply() {
        guard !applying, let commands else { return }
        applying = true
        let selected = limits
        retentionDays = selected.retentionDays
        maximumMegabytes = Int(selected.maximumBytes / 1_000_000)
        defaults.set(retentionDays, forKey: "historyRetentionDays")
        defaults.set(maximumMegabytes, forKey: "historyMaximumMegabytes")
        Task {
            _ = await commands.maintainHistory(limits: selected)
            await refresh()
            applying = false
        }
    }

    func refresh() async {
        guard let commands else { return }
        switch await commands.historyStatus(consumeNotice: true) {
        case .success(let status):
            usage = status
            unavailable = false
            if status.quotaNoticePending { onQuotaEviction?() }
        case .failure:
            unavailable = true
        }
    }
}

struct HistorySettingsSection: View {
    @ObservedObject var settings: HistorySettings
    var body: some View {
        Section("History") {
            TextField("Keep captures for (days)", value: $settings.retentionDays, format: .number)
                .accessibilityLabel("History retention in days")
            TextField("Size limit (MB)", value: $settings.maximumMegabytes, format: .number)
                .accessibilityLabel("History size limit in megabytes")
            Button("Apply History Limits", action: settings.apply).disabled(settings.applying)
            Text("1,000 MB = 1 GB. Oldest captures are removed first. Saved exports are kept.")
            if settings.unavailable {
                Text("History usage is unavailable. Captures can still be copied or saved.").foregroundStyle(.red)
            } else if let usage = settings.usage {
                Text("History uses \(ByteCountFormatter.string(fromByteCount: usage.usageBytes, countStyle: .decimal)) of \(ByteCountFormatter.string(fromByteCount: usage.limits.maximumBytes, countStyle: .decimal)).")
                if let date = usage.lastQuotaEviction {
                    Text("Older captures were removed to meet the size limit on \(date.formatted(date: .abbreviated, time: .shortened)).")
                }
                if usage.usageBytes > usage.limits.maximumBytes {
                    Text("History is above its size limit. The latest capture and History database are protected.")
                }
                if usage.ageEvictionDeferred {
                    Text("Age cleanup is paused because the clock changed unexpectedly.")
                }
            }
        }
    }
}
