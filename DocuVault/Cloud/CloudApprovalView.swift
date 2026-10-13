import SwiftUI
import SwiftData
import DocuVaultCore

/// The per-send approval sheet (checkpoint 10). Shows exactly what will leave the phone, after redaction,
/// with per-category toggles and per-item exclusions. "Send once" is the only way to the network.
/// There is deliberately no "always allow".
struct CloudApprovalSheet: View {
    let draft: CloudService.Draft
    var onOutcome: (CloudService.Outcome) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var service = CloudService.shared
    @State private var options = Redactor.Options()
    @State private var excluded: Set<Int> = []
    @State private var sending = false
    @State private var error: String?
    @State private var answer: String?
    @State private var cancelledLogged = false

    private var activeSpans: [Redactor.Span] {
        draft.spans.enumerated().filter { !excluded.contains($0.offset) || $0.element.category.isLocked }.map(\.element)
    }
    private var result: Redactor.Result { Redactor.apply(draft.text, spans: activeSpans, options: options) }
    private var estimate: (tokens: Int, usd: Double) {
        let req = CloudService.request(purpose: draft.purpose, redactedText: result.text, model: service.modelID)
        let t = CloudCost.estimatedTokens(for: req.system + req.user)
        return (t, CloudCost.estimateUSD(inputTokens: t, outputTokens: 400, model: service.modelID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let answer { answerBox(answer) } else {
                        headerCard
                        toggles
                        if !draft.spans.isEmpty { foundItems }
                        preview
                        if let error { Text(error).font(.footnote).foregroundStyle(Theme.Colors.danger).frame(maxWidth: .infinity, alignment: .leading) }
                        sendButtons
                    }
                }
                .padding(16)
            }
            .background(Theme.Colors.canvas)
            .navigationTitle(answer == nil ? "Send to Claude" : "Claude's answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(answer == nil ? "Cancel" : "Done") { cancelAndClose() }.disabled(sending)
                }
            }
            .interactiveDismissDisabled(sending)
            .onDisappear { if answer == nil && !cancelledLogged && !sending { logCancel() } }
        }
    }

    // MARK: Pieces

    private var headerCard: some View {
        let r = result
        let est = estimate
        return GradientCard(style: .clay) {
            CardHeader(title: "One send", subtitle: "\(draft.doc.title) · \(draft.purpose.logLabel) · \(CloudCost.model(service.modelID).displayName)")
            HStack(alignment: .top, spacing: 10) {
                StatBlock(label: "Leaves phone", value: compact(r.text.count), footnote: "Characters")
                StatBlock(label: "Redacted", value: "\(r.count)", footnote: CloudService.describe(r.counts))
            }
            HStack(alignment: .top, spacing: 10) {
                StatBlock(label: "Est. cost", value: CloudCost.formatUSD(est.usd), footnote: "≈ \(compact(est.tokens)) tokens", small: true)
                StatBlock(label: "Stays here", value: "Images", footnote: "Fields · Notes · Vault", small: true)
            }
            .padding(.top, 14)
        }
    }

    private var toggles: some View {
        VStack(spacing: 0) {
            sectionLabel("Redact before sending", trailing: "Restored on reply")
            VStack(spacing: 0) {
                lockedRow(.identifier)
                Divider().padding(.leading, 16)
                lockedRow(.contact)
                Divider().padding(.leading, 16)
                toggleRow(.name, isOn: $options.names)
                Divider().padding(.leading, 16)
                toggleRow(.amount, isOn: $options.amounts)
                Divider().padding(.leading, 16)
                toggleRow(.date, isOn: $options.dates)
            }
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func count(_ c: Redactor.Category) -> Int { draft.spans.filter { $0.category == c }.count }

    private func lockedRow(_ c: Redactor.Category) -> some View {
        HStack {
            Text(c.displayName).font(.system(size: 17))
            countPill(c)
            Spacer()
            Image(systemName: "lock.fill").foregroundStyle(Theme.Colors.warning)
            Toggle("", isOn: .constant(true)).labelsHidden().disabled(true).tint(Theme.Colors.warning)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func toggleRow(_ c: Redactor.Category, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(c.displayName).font(.system(size: 17))
            countPill(c)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func countPill(_ c: Redactor.Category) -> some View {
        let n = count(c)
        return Text(n == 0 ? "None" : "\(n) found").font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color(.systemGray5)).clipShape(Capsule())
            .foregroundStyle(Theme.Colors.ink2)
    }

    /// Distinct items found, grouped; tap one in an unlocked category to keep it in clear.
    private var foundItems: some View {
        VStack(spacing: 0) {
            sectionLabel("Found", trailing: "Tap to keep in clear")
            VStack(alignment: .leading, spacing: 10) {
                ForEach([Redactor.Category.name, .amount, .date, .identifier, .contact], id: \.self) { c in
                    let items = distinct(c)
                    if !items.isEmpty, options.includes(c) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(c.placeholderWord).font(.cardLabel(11)).tracking(1).foregroundStyle(Theme.Colors.ink2).frame(width: 64, alignment: .leading).padding(.top, 10)
                            FlowLayout(spacing: 6) {
                                ForEach(items) { item in
                                    let off = isExcluded(item.index)
                                    Button {
                                        guard !c.isLocked else { return }
                                        toggleExclusion(key: item.key, category: c)
                                    } label: {
                                        Text(item.text).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                            .strikethrough(off)
                                            .padding(.horizontal, 10).frame(height: 30)
                                            .background(off ? Color.clear : chipColor(c).opacity(0.15))
                                            .overlay(Capsule().stroke(off ? Theme.Colors.hairline : .clear))
                                            .foregroundStyle(off ? Theme.Colors.ink2 : chipColor(c))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(c.isLocked)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private struct FoundItem: Identifiable { let index: Int; let key: String; let text: String; var id: Int { index } }
    private func distinct(_ c: Redactor.Category) -> [FoundItem] {
        var seen: Set<String> = []
        var out: [FoundItem] = []
        for (i, s) in draft.spans.enumerated() where s.category == c {
            if seen.insert(s.key).inserted { out.append(FoundItem(index: i, key: s.key, text: c.isLocked ? maskedLocked(s.original) : s.original)) }
        }
        return out
    }
    private func maskedLocked(_ s: String) -> String { s.count <= 4 ? "••••" : String(repeating: "•", count: max(2, s.count - 4)) + String(s.suffix(4)) }
    private func isExcluded(_ i: Int) -> Bool { excluded.contains(i) }
    private func toggleExclusion(key: String, category: Redactor.Category) {
        let idx = draft.spans.enumerated().filter { $0.element.category == category && $0.element.key == key }.map(\.offset)
        if idx.allSatisfy(excluded.contains) { idx.forEach { excluded.remove($0) } } else { idx.forEach { excluded.insert($0) } }
    }
    private func chipColor(_ c: Redactor.Category) -> Color {
        switch c {
        case .name: Theme.Colors.cloud
        case .amount: Theme.Colors.accent
        case .identifier, .contact: Theme.Colors.danger
        case .date: Theme.Colors.verified
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            sectionLabel("Preview · Exactly this text", trailing: "")
            ScrollView {
                Text(highlighted(result.text))
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: 360)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// Placeholders get a tinted background so the eye finds them.
    private func highlighted(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        guard let re = try? NSRegularExpression(pattern: #"\[(ID|CONTACT|NAME|AMOUNT|DATE) \d+(?: [A-Z]{3})?\]"#) else { return a }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: text), let ar = Range(r, in: a) else { continue }
            let word = ns.substring(with: m.range(at: 1))
            let c: Redactor.Category = switch word { case "NAME": .name; case "AMOUNT": .amount; case "DATE": .date; case "CONTACT": .contact; default: .identifier }
            a[ar].backgroundColor = chipColor(c).opacity(0.18)
            a[ar].foregroundColor = chipColor(c)
            a[ar].font = .system(size: 13, weight: .bold, design: .monospaced)
        }
        return a
    }

    private var sendButtons: some View {
        VStack(spacing: 4) {
            Button { Task { await send() } } label: {
                HStack(spacing: 8) {
                    if sending { ProgressView().tint(.white) }
                    Text(sending ? "Sending…" : "Send once").font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Theme.Colors.ink).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressScale)
            .disabled(sending)
            Button("Cancel") { cancelAndClose() }.disabled(sending).padding(.vertical, 10)
            Text("Only this redacted text, your question and the instructions leave the phone. Nothing is remembered as a default. Logged in Settings → Claude.")
                .font(.footnote).foregroundStyle(Theme.Colors.ink2).multilineTextAlignment(.center)
        }
    }

    private func answerBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .ask(let q, _) = draft.purpose {
                Text(q).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
            }
            Text(text).font(.system(size: 16)).lineSpacing(3).textSelection(.enabled)
            HStack {
                Button { draft.doc.notes += (draft.doc.notes.isEmpty ? "" : "\n\n") + "Q: " + questionText + "\nA (Claude): " + text; try? context.save() } label: {
                    Label("Add to notes", systemImage: "note.text.badge.plus").font(.system(size: 14, weight: .medium))
                }
                Spacer()
                Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 14, weight: .medium)) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private var questionText: String { if case .ask(let q, _) = draft.purpose { return q }; return "" }

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title.uppercased()).font(.cardLabel(13)).tracking(0.5)
            Spacer()
            Text(trailing).font(.system(size: 13))
        }
        .foregroundStyle(Theme.Colors.ink2)
        .padding(.horizontal, 4).padding(.bottom, 6)
    }

    private func compact(_ n: Int) -> String {
        n >= 10_000 ? String(format: "%.0fk", Double(n) / 1000) : n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    // MARK: Actions

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        do {
            let outcome = try await service.send(draft, options: options, excluded: excluded, context: context)
            cancelledLogged = true   // a row was written; don't add a cancel row on dismiss
            switch outcome {
            case .summary: onOutcome(outcome); dismiss()
            case .answer(let a): answer = a; onOutcome(outcome)
            }
        } catch {
            cancelledLogged = true
            self.error = error.localizedDescription
        }
    }

    private func logCancel() {
        cancelledLogged = true
        service.logCancelled(draft, context: context)
    }

    private func cancelAndClose() {
        if answer == nil && !cancelledLogged { logCancel() }
        dismiss()
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// "Ask Claude about this…": one free-text question, then the same approval sheet.
struct AskClaudeSheet: View {
    let doc: StoredDocument
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var draft: CloudService.Draft?
    @State private var service = CloudService.shared
    @FocusState private var focused: Bool

    private var language: String { SummarySpec.language(for: text) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GradientCard(style: .clay) {
                    CardHeader(title: "Ask Claude", subtitle: "\(doc.title) · One question · You approve the send")
                    Text("The whole document goes with your question, redacted the same way as a summary. Answers stay on this phone.")
                        .font(.system(size: 15)).opacity(0.9)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField(language == "zh-Hans" ? "例如：违约金条款是什么？" : "e.g. What are the termination triggers?", text: $question, axis: .vertical)
                        .font(.system(size: 17)).lineLimit(2...6).focused($focused)
                }
                .padding(16).background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let past = service.answers[doc.id], !past.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EARLIER · THIS SESSION").font(.cardLabel(12)).tracking(1).foregroundStyle(Theme.Colors.ink2)
                        ForEach(Array(past.enumerated()), id: \.offset) { _, qa in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(qa.question).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
                                Text(qa.answer).font(.system(size: 15)).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.Colors.canvas)
            .navigationTitle("Ask Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review send") {
                        draft = service.draft(doc, text: text, purpose: .ask(question: question.trimmingCharacters(in: .whitespacesAndNewlines), language: language))
                    }
                    .fontWeight(.semibold)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $draft) { d in CloudApprovalSheet(draft: d) }
            .onAppear { focused = true }
        }
    }
}
