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
    @State private var confirmDeleteKey = false
    @State private var confirmClearLog = false

    private var sent: [StoredCloudSend] { log.filter { $0.status == .ok } }
    private var last30: [StoredCloudSend] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return sent.filter { $0.sentAt >= cutoff }
    }

    var body: some View {
        List {
            Section {
                GradientCard(style: .clay) {
                    CardHeader(title: "Cloud", subtitle: cloud.hasKey ? "Opt-in · Per send · Your API key" : "Off · No API key")
                    HStack(alignment: .top, spacing: 10) {
                        StatBlock(label: "Sends", value: "\(sent.count)", footnote: sent.isEmpty ? "None yet" : "All approved by you")
                        StatBlock(label: "Spent", value: CloudCost.formatUSD(last30.reduce(0) { $0 + $1.estimatedUSD }), footnote: "Estimate · 30 d", small: true)
                    }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section {
                if editingKey || !cloud.hasKey {
                    SecureField("sk-ant-…", text: $keyDraft).font(.system(.body, design: .monospaced)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button("Save key") { cloud.setKey(keyDraft); keyDraft = ""; editingKey = false }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).count < 20)
                        if cloud.hasKey { Spacer(); Button("Cancel") { keyDraft = ""; editingKey = false } }
                    }
                } else {
                    HStack { Text("API key"); Spacer(); Text(cloud.maskedKey).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.Colors.ink2) }
                    Button("Change key") { editingKey = true }
                    Button(role: .destructive) { confirmDeleteKey = true } label: { Text("Remove key · Turns Claude off") }
                }
            } header: { Text("API key") } footer: {
                Text("Stored in this phone's Keychain, this device only. Get a key at console.anthropic.com. Removing it removes every Claude option in the app.")
            }

            Section("Model") {
                Picker("Model", selection: Binding(get: { cloud.modelID }, set: { cloud.modelID = $0 })) {
                    ForEach(CloudCost.models) { m in
                        Text("\(m.displayName) · $\(Int(m.inputPerM))/$\(Int(m.outputPerM)) per M tokens").tag(m.id)
                    }
                }
                .pickerStyle(.inline).labelsHidden()
            }

            Section {
                Toggle("Keep sent text in log", isOn: Binding(get: { cloud.keepSentText }, set: { cloud.keepSentText = $0 }))
                Picker("Log retention", selection: Binding(get: { cloud.logRetentionDays }, set: { cloud.logRetentionDays = $0 })) {
                    Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
                }
            } header: { Text("Log") } footer: {
                Text("The log keeps what left the phone: when, which document, how many characters, what was redacted, tokens and estimated cost. With \u{201C}Keep sent text\u{201D} on, the exact redacted text is kept too, so you can audit a send.")
            }

            Section {
                if log.isEmpty {
                    Text("No sends yet.").foregroundStyle(Theme.Colors.ink2)
                } else {
                    ForEach(log) { row in
                        NavigationLink { CloudSendDetailView(row: row) } label: { logRow(row) }
                    }
                    .onDelete { idx in idx.map { log[$0] }.forEach(context.delete); try? context.save() }
                    Button(role: .destructive) { confirmClearLog = true } label: { Text("Clear log") }
                }
            } header: { HStack { Text("Send log"); Spacer(); Text("\(log.count)") } }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove the API key? Claude options disappear until you add one again.", isPresented: $confirmDeleteKey, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { cloud.deleteKey() }
        }
        .confirmationDialog("Clear the whole send log?", isPresented: $confirmClearLog, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) { log.forEach(context.delete); try? context.save() }
        }
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
        .padding(.vertical, 2)
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
        List {
            Section {
                kv("When", row.sentAt.dvDisplay(time: true))
                kv("Document", row.documentTitle)
                kv("Purpose", DisplayText.capitalisedSegments(row.purpose))
                kv("Model", row.model)
                kv("Status", row.status.rawValue.capitalized)
                if let e = row.error { kv("Error", e) }
            }
            Section("What left the phone") {
                kv("Characters", "\(row.characters)")
                kv("Redacted", row.redactionSummary)
                kv("Tokens", "\(row.inputTokens) in · \(row.outputTokens) out")
                kv("Est. cost", CloudCost.formatUSD(row.estimatedUSD))
            }
            if let t = row.sentText {
                Section("Exact text sent") {
                    Text(t).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                }
            } else if row.status == .ok {
                Section { Text("Sent text was not kept (Settings → Claude → Keep sent text).").foregroundStyle(Theme.Colors.ink2) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k); Spacer(); Text(v).foregroundStyle(Theme.Colors.ink2).multilineTextAlignment(.trailing) }
    }
}
