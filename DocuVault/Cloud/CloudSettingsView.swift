import SwiftUI
import SwiftData
import DocuVaultCore

/// Settings → Claude: key, model, log options, and the send log (checkpoint 10).
struct CloudSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredCloudSend.sentAt, order: .reverse) private var log: [StoredCloudSend]
    @State private var cloud = CloudService.shared
    @State private var keyDraft = ""
    @State private var editingKey = false

    private var sent: [StoredCloudSend] { log.filter { $0.status == .ok } }
    private var last30: [StoredCloudSend] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return sent.filter { $0.sentAt >= cutoff }
    }

    var body: some View {
        CardPage {
            GradientCard(style: .clay) {
                CardHeader(title: "Claude", subtitle: cloud.hasKey ? "Opt-in · One send at a time" : "Off · No API key")
                HStack(alignment: .top, spacing: 10) {
                    StatBlock(label: "Sends", value: "\(sent.count)", footnote: sent.isEmpty ? "None yet" : "All approved by you")
                    StatBlock(label: "Spent", value: CloudCost.formatUSD(last30.reduce(0) { $0 + $1.estimatedUSD }), footnote: "Estimate · 30 d", small: true)
                }
            }

            CardSection(title: "API key", note: cloud.hasKey ? nil : "Kept in this phone's Keychain only. Get one at console.anthropic.com.") {
                if editingKey || !cloud.hasKey {
                    SecureField("API key", text: $keyDraft)
                        .font(.system(size: 17, design: .monospaced)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    HStack {
                        Button("Save key") { cloud.setKey(keyDraft); keyDraft = ""; editingKey = false }
                            .fontWeight(.semibold)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).count < 20)
                        Spacer()
                        if cloud.hasKey { Button("Cancel") { keyDraft = ""; editingKey = false } }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    Button { editingKey = true } label: { CardRow(title: "Key", value: cloud.maskedKey, chevron: true) }.buttonStyle(.plain)
                    ConfirmRow(title: "Remove key", subtitle: "Turns every Claude option off",
                               question: "Claude options disappear until you add a key again.", action: "Remove key") { cloud.deleteKey() }
                }
            }

            CardSection(title: "Model") {
                ForEach(CloudCost.models) { m in
                    Button { cloud.modelID = m.id } label: {
                        HStack {
                            CardRow(title: m.displayName, subtitle: "$\(Int(m.inputPerM)) in · $\(Int(m.outputPerM)) out per million tokens")
                            if cloud.modelID == m.id {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.Colors.accent).padding(.trailing, 16)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            CardSection(title: "Log", note: "The log records what left the phone. With the text kept, you can read the exact redacted send.") {
                CardToggle(title: "Keep sent text", isOn: Binding(get: { cloud.keepSentText }, set: { cloud.keepSentText = $0 }))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep the log for").font(.system(size: 17, weight: .semibold))
                    ChoiceChips(options: [(30, "30 days"), (90, "90 days"), (365, "1 year")],
                                selection: Binding(get: { cloud.logRetentionDays }, set: { cloud.logRetentionDays = $0 }))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            CardSection(title: "Sends · \(log.count)") {
                if log.isEmpty {
                    CardRow(title: "No sends yet")
                } else {
                    ForEach(log) { row in
                        NavigationLink { CloudSendDetailView(row: row) } label: { logRow(row) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { context.delete(row); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    ConfirmRow(title: "Clear log", question: "Every row of the send log is deleted.", action: "Clear log") {
                        log.forEach(context.delete); try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logRow(_ r: StoredCloudSend) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(r.documentTitle).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                StatusPill(text: r.status.rawValue.capitalized, tone: r.status == .ok ? .verified : r.status == .failed ? .missing : .neutral)
            }
            Text(detailLine(r)).font(.system(size: 13)).foregroundStyle(Theme.Colors.ink2).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Older rows stored lower-case purposes and summaries; capitalise every segment for display.
    private func detailLine(_ r: StoredCloudSend) -> String {
        DisplayText.capitalisedSegments(rawDetailLine(r))
    }

    private func rawDetailLine(_ r: StoredCloudSend) -> String {
        let when = r.sentAt.formatted(.relative(presentation: .named))
        switch r.status {
        case .ok: return "\(when) · \(r.purpose) · \(r.characters) chars · \(r.redactionSummary) · \(r.inputTokens + r.outputTokens) tok · \(CloudCost.formatUSD(r.estimatedUSD))"
        case .failed: return "\(when) · \(r.purpose) · \(r.error ?? "failed")"
        case .cancelled: return "\(when) · \(r.purpose) · you cancelled on the sheet · nothing sent"
        }
    }
}

/// One log row in full, including the exact redacted text when it was kept.
struct CloudSendDetailView: View {
    let row: StoredCloudSend
    var body: some View {
        CardPage {
            CardSection {
                kv("When", row.sentAt.dvDisplay(time: true))
                kv("Document", row.documentTitle)
                kv("Purpose", DisplayText.capitalisedSegments(row.purpose))
                kv("Model", row.model)
                kv("Status", row.status.rawValue.capitalized)
                if let e = row.error { kv("Error", e) }
            }
            CardSection(title: "What left the phone") {
                kv("Characters", "\(row.characters)")
                kv("Redacted", row.redactionSummary)
                kv("Tokens", "\(row.inputTokens) in · \(row.outputTokens) out")
                kv("Estimated cost", CloudCost.formatUSD(row.estimatedUSD))
            }
            if let t = row.sentText {
                CardSection(title: "Exact text sent") {
                    Text(t).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if row.status == .ok {
                Text("The sent text was not kept. Turn on Keep sent text in Claude settings to keep it next time.")
                    .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func kv(_ k: String, _ v: String) -> some View {
        CardRow(title: k, value: v)
    }
}
