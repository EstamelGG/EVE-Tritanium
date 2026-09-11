import SwiftUI

struct RateLimitMonitorView: View {
    @ObservedObject private var monitor = ESIRateLimitMonitor.shared
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if monitor.isEmpty {
                Section {
                    Text(NSLocalizedString("RateLimit_Monitor_Empty", comment: ""))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(monitor.snapshots) { group in
                    Section {
                        if let balance = group.balance {
                            balanceRow(balance)
                        }
                        ForEach(group.endpoints) { endpoint in
                            Text(endpoint.pathTemplate)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(group.group)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("RateLimit_Monitor_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(monitor.isEmpty)
            }
        }
        .alert(
            NSLocalizedString("RateLimit_Monitor_Clear_Title", comment: ""),
            isPresented: $showClearConfirm
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("RateLimit_Monitor_Clear", comment: ""), role: .destructive) {
                monitor.clear()
            }
        } message: {
            Text(NSLocalizedString("RateLimit_Monitor_Clear_Message", comment: ""))
        }
    }

    private func balanceRow(_ balance: RateLimitBalance) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let usedFraction = 1 - balance.fraction
            let tint = barColor(usedFraction)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(balance.consumed)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text("/ \(balance.quota.maxTokens)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(
                        String(
                            format: NSLocalizedString("RateLimit_Monitor_Window", comment: ""),
                            balance.quota.windowLabel
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ProgressView(value: usedFraction)
                    .tint(tint)

                HStack {
                    Text(String(format: "%.0f%%", usedFraction * 100))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Spacer()
                    Text(relativeTime(from: balance.observedAt, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func barColor(_ usedFraction: Double) -> Color {
        if usedFraction >= 0.95 { return .red }
        if usedFraction >= 0.8 { return .orange }
        return .green
    }

    private func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 {
            return NSLocalizedString("RateLimit_Monitor_JustNow", comment: "")
        }
        if seconds < 60 {
            return String(
                format: NSLocalizedString("RateLimit_Monitor_SecondsAgo", comment: ""),
                seconds
            )
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return String(
                format: NSLocalizedString("RateLimit_Monitor_MinutesAgo", comment: ""),
                minutes
            )
        }
        return String(
            format: NSLocalizedString("RateLimit_Monitor_HoursAgo", comment: ""),
            minutes / 60
        )
    }
}
