import SwiftUI
import SwiftData
import DocuVaultCore

/// Summary section on the document detail: graphite card with stats + white box with the content.
/// States: none (Summarise button), running (progress), ready, unavailable/failed, and the "ask format" case.
struct SummaryCard: View {
    @Bindable var doc: StoredDocument
    let text: String
    @Environment(\.modelContext) private var context
    @State private var service = SummaryService.shared
    @State private var cloud = CloudService.shared
    @State private var askFormat = false
    @State private var cloudDraft: CloudService.Draft?
    @State private var showAsk = false

    private var summary: DocumentSummary? { service.summary(for: doc) }
    private var state: SummaryService.State { service.state(for: doc) }

    var body: some View {
        VStack(spacing: 16) {
            card
            if state == .askLanguage { languageAsk }
            if let s = summary, state == .idle {
                if s.format == .unsure || askFormat { formatAsk } else { contentBox(s) }
            }
        }
        .sheet(item: $cloudDraft) { d in CloudApprovalSheet(draft: d) }
        .sheet(isPresented: $showAsk) { AskClaudeSheet(doc: doc, text: text) }
    }

    /// Cloud is offered only when a key exists and the gate allows this document (never vault, never ID types).
    private var cloudAllowed: Bool { cloud.canOffer(doc) }

    // MARK: Card

    private var card: some View {
        GradientCard(style: .graphite) {
            CardHeader(title: "Summary", subtitle: subtitle)
            switch state {
            case .running(let done, let total):
                HStack(alignment: .top, spacing: 10) {
                    StatBlock(label: "Progress", value: total > 1 ? "\(done)/\(total)" : "…", footnote: total > 1 ? "Chunks" : "One pass", small: true)
                    StatBlock(label: "Model", value: "Apple", footnote: "On-device", small: true)
                }
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0).tint(.white).padding(.top, 12)
            case .askLanguage:
                Text("This document mixes Chinese and English. Pick the summary language below.").font(.system(size: 15)).opacity(0.9)
            case .failed(let msg):
                Text(msg).font(.system(size: 15)).opacity(0.9)
                if msg.contains("Apple Intelligence") {
                    CardButton(title: "Open Settings", systemImage: "arrow.up.right") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                CardButton(title: "Try again", systemImage: "arrow.clockwise") { run() }
                if cloudAllowed { CardButton(title: "Use Claude instead · You approve the send", systemImage: "cloud") { runCloud() } }
            case .idle:
                if let s = summary {
                    HStack(alignment: .top, spacing: 10) {
                        StatBlock(label: "Format", value: formatLabel(s), footnote: s.length == .short ? "Short" : "Long", small: true)
                        StatBlock(label: "Model", value: s.model == "claude" ? "Claude" : s.model.hasPrefix("mlx") ? "Qwen" : "Apple",
                                  footnote: String(format: "%.1f s · %@", s.seconds, modelFootnote(s)), small: true)
                    }
                    if s.partial { Text("Partial: only the first \(SummarySpec.maxChunks) chunks were read.").font(.system(size: 13)).opacity(0.8).padding(.top, 8) }
                    if s.model == "claude" {
                        Text("Sent \(s.sentCharacters ?? 0) characters to Claude · \(s.redacted ?? 0) placeholders restored on this phone\((s.unresolved ?? 0) > 0 ? " · \(s.unresolved!) unresolved" : "") · Logged")
                            .font(.system(size: 13)).opacity(0.8).padding(.top, 8)
                    }
                    regenerateMenu(s)
                } else {
                    Text("On-device. The document's language. Nothing is uploaded.").font(.system(size: 15)).opacity(0.85)
                    CardButton(title: "Summarise", systemImage: "sparkles") { run() }
                    if cloudAllowed {
                        Menu {
                            Button { runCloud() } label: { Label("Summarise with Claude…", systemImage: "cloud") }
                            Button { showAsk = true } label: { Label("Ask Claude about this…", systemImage: "questionmark.bubble") }
                        } label: {
                            HStack {
                                Text("Claude · You approve each send").font(.system(size: 18, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.insetButton, style: .continuous))
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func modelFootnote(_ s: DocumentSummary) -> String {
        if s.model == "claude" { return "Cloud · \(s.redacted ?? 0) restored" }
        if s.model.contains("failed") { return "Qwen failed" }
        return s.chunks > 1 ? "\(s.chunks) chunks" : "No upload"
    }

    private var subtitle: String {
        if let s = summary { return "\(s.model == "claude" ? "Claude" : "On-device") · \(s.language == "zh-Hans" ? "中文" : "English\(s.language == "en" ? " · STE" : "")") · \(doc.pages.count) page\(doc.pages.count == 1 ? "" : "s")" }
        let lang = SummarySpec.language(for: text) == "zh-Hans" ? "中文" : "English"
        return "\(lang) · \(doc.pages.count) page\(doc.pages.count == 1 ? "" : "s")"
    }

    private func formatLabel(_ s: DocumentSummary) -> String {
        switch s.format {
        case .bullets: s.language == "zh-Hans" ? "要点" : "Bullets"
        case .paragraph: s.language == "zh-Hans" ? "段落" : "Paragraph"
        case .both: "Both"
        case .unsure: "?"
        }
    }

    private func regenerateMenu(_ s: DocumentSummary) -> some View {
        Menu {
            Button { run(length: s.length == .short ? .long : .short, format: s.format) } label: { Label(s.length == .short ? "Longer" : "Shorter", systemImage: "text.alignleft") }
            Button { run(length: s.length, format: s.format == .bullets ? .paragraph : .bullets) } label: { Label(s.format == .bullets ? "Paragraph" : "Bullets", systemImage: "list.bullet") }
            Button { run(length: s.length, format: s.format, language: s.language == "en" ? "zh-Hans" : "en") } label: { Label(s.language == "en" ? "中文" : "English", systemImage: "character.book.closed") }
            Divider()
            Button { askFormat = true } label: { Label("Choose format…", systemImage: "slider.horizontal.3") }
            if cloudAllowed {
                Divider()
                Button { runCloud(length: s.length, format: s.format, language: s.language) } label: { Label("Summarise with Claude…", systemImage: "cloud") }
                Button { showAsk = true } label: { Label("Ask Claude about this…", systemImage: "questionmark.bubble") }
            }
            Button(role: .destructive) { service.clear(doc, context: context) } label: { Label("Remove summary", systemImage: "trash") }
        } label: {
            HStack {
                Text("Regenerate · \(s.length == .short ? "Longer" : "Shorter") · \(s.format == .bullets ? "Paragraph" : "Bullets")").font(.system(size: 18, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.insetButton, style: .continuous))
        }
        .padding(.top, 16)
    }

    // MARK: Content

    private func contentBox(_ s: DocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.headline).font(.system(size: 18, weight: .bold))
            switch s.format {
            case .paragraph:
                Text(s.body.joined(separator: " ")).font(.system(size: 16)).lineSpacing(3)
            case .both:
                if let first = s.body.first { Text(first).font(.system(size: 16)).lineSpacing(3) }
                bullets(Array(s.body.dropFirst()))
            default:
                bullets(s.body)
            }
            if !s.keyFacts.isEmpty {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(s.keyFacts.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .top, spacing: 8) {
                            Text(f.label).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).frame(width: 110, alignment: .leading)
                            Text(f.value).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                        }
                    }
                }
            }
            if !s.actions.isEmpty {
                Divider().padding(.vertical, 4)
                Text(s.language == "zh-Hans" ? "待办" : "ACTIONS").font(.system(size: 13)).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                ForEach(Array(s.actions.enumerated()), id: \.offset) { _, a in
                    HStack(alignment: .top, spacing: 8) { Image(systemName: "square").foregroundStyle(Theme.Colors.ink2); Text(a).font(.system(size: 15)) }
                }
            }
            HStack {
                Spacer()
                Button { UIPasteboard.general.string = s.markdown } label: { Label("Copy summary", systemImage: "doc.on.doc").font(.system(size: 14, weight: .medium)) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .textSelection(.enabled)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 8) { Text("•").font(.system(size: 16, weight: .bold)); Text(b).font(.system(size: 16)).lineSpacing(2) }
            }
        }
    }

    /// Mixed-language document: which language should the summary use?
    private var languageAsk: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary language · 摘要语言").font(.system(size: 18, weight: .bold))
            HStack(spacing: 6) {
                Button { run(language: "en") } label: { Text("English").font(.chip).padding(.horizontal, 18).frame(height: 40).background(Theme.Colors.canvas).clipShape(Capsule()) }
                Button { run(language: "zh-Hans") } label: { Text("中文").font(.chip).padding(.horizontal, 18).frame(height: 40).background(Theme.Colors.canvas).clipShape(Capsule()) }
            }
            .buttonStyle(.plain)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The model (or you) is unsure: pick once; remembered for this document type.
    private var formatAsk: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How should this read?").font(.system(size: 18, weight: .bold))
            Text("The document mixes narrative and tables. Pick the format that serves you. Remembered for \(doc.type.displayName).")
                .font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
            HStack(spacing: 6) {
                ForEach([DocumentSummary.Format.bullets, .paragraph, .both], id: \.self) { f in
                    Button {
                        service.setPreferredFormat(f, for: doc.type)
                        askFormat = false
                        run(format: f)
                    } label: {
                        Text(f == .bullets ? "Bullets" : f == .paragraph ? "Paragraph" : "Both").font(.chip)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Theme.Colors.canvas).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func run(length: DocumentSummary.Length = .short, format: DocumentSummary.Format? = nil, language: String? = nil) {
        Task { await service.summarise(doc, text: text, format: format, length: length, language: language, context: context) }
    }

    /// Opens the approval sheet. Nothing is sent until "Send once".
    private func runCloud(length: DocumentSummary.Length = .short, format: DocumentSummary.Format? = nil, language: String? = nil) {
        let lang = language ?? SummarySpec.language(for: text)
        let fmt = format ?? service.preferredFormat(for: doc.type) ?? SummarySpec.defaultFormat(for: doc.type)
        cloudDraft = cloud.draft(doc, text: text, purpose: .summarise(format: fmt, length: length, language: lang))
    }
}
