import Foundation
import SwiftUI
import FrisketCore

@MainActor final class HistorySettings: ObservableObject {
    @Published var retentionDays: Int
    @Published var maximumMegabytes: Int
    @Published private(set) var usage: HistoryUsage?
    @Published private(set) var unavailable = false
    @Published private(set) var failure: HistoryFailure?
    @Published private(set) var applying = false
    private let defaults: UserDefaults
    private var history: HistoryStore?
    var onQuotaEviction: (() -> Void)?
    var onRevealHistory: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        retentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 30
        maximumMegabytes = defaults.object(forKey: "historyMaximumMegabytes") as? Int ?? 1000
    }

    var limits: HistoryLimits {
        HistoryLimits(retentionDays: retentionDays, maximumBytes: Int64(min(1_000_000, max(1, maximumMegabytes))) * 1_000_000)
    }

    func connect(_ history: HistoryStore) {
        self.history = history
        Task {
            _ = await history.maintain(limits: nil)
            await refresh()
        }
    }

    func apply() {
        guard !applying, let history else { return }
        applying = true
        let selected = limits
        retentionDays = selected.retentionDays
        maximumMegabytes = Int(selected.maximumBytes / 1_000_000)
        defaults.set(retentionDays, forKey: "historyRetentionDays")
        defaults.set(maximumMegabytes, forKey: "historyMaximumMegabytes")
        Task {
            _ = await history.maintain(limits: selected)
            await refresh()
            applying = false
        }
    }

    func refresh() async {
        guard let history else { return }
        failure = await history.availability()
        unavailable = failure != nil
        if unavailable {
            usage = nil
            return
        }
        switch await history.status(consumeNotice: true) {
        case .success(let status):
            usage = status
            if status.quotaNoticePending { onQuotaEviction?() }
        case .failure(let statusFailure):
            failure = statusFailure
            unavailable = true
            usage = nil
        }
    }

    func retry() {
        guard !applying, let history else { return }
        applying = true
        Task {
            _ = await history.recover()
            await refresh()
            applying = false
        }
    }

    var notice: String { HistoryFailureNotice.text(failure) }
}

enum HistoryFailureNotice {
    static func text(_ failure: HistoryFailure?) -> String {
        switch failure {
        case .unknownMigrations:
            return "History can't open this library because it was written by a newer version. Captures can still be copied or saved."
        case .recoveryRequired:
            return "History needs attention before it can save new items. Captures can still be copied or saved."
        case .rootLocked:
            return "History is in use by another Frisket instance. Captures can still be copied or saved."
        default:
            return "History is unavailable. Captures can still be copied or saved."
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
                Text(settings.notice).foregroundStyle(.red)
                Button("Try Again", action: settings.retry).disabled(settings.applying)
                    .accessibilityLabel("Try opening History again")
                Button("Show History Folder") { settings.onRevealHistory?() }
                    .accessibilityLabel("Show History folder")
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
