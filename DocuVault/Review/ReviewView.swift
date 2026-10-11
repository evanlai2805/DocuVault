import SwiftUI
import DocuVaultCore

/// Pages → OCR → **Review** → Save. Type card (green = all checks pass, red = a check failed,
/// graphite = nothing to check), then Main and Secondary field lists. Tap a field to edit.
struct ReviewView: View {
    let onDone: () -> Void
    @Environment(CaptureSession.self) private var capture
    @State private var editing: ExtractedField?
    @State private var editingPinyin = false
    @State private var showChangeType = false
    @State private var goToSave = false

    private var ex: ExtractionResult? { capture.extraction }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                typeCard
                if let ex, !ex.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ex.warnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.warning)
                                Text(w).font(.system(size: 15))
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let ex, !ex.fields.isEmpty {
                    sectionHeader("Main", trailing: "tap to edit")
                    fieldList(ex.mainFields)
                    if !ex.secondaryFields.isEmpty {
                        sectionHeader("Secondary", trailing: "stored separately")
                        fieldList(ex.secondaryFields)
                    }
                } else {
                    HintBanner(badge: "NO FIELDS", title: "Nothing to extract for this type",
                               detail: "The text is still saved and searchable. Change the type if the rules missed it.")
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { goToSave = true }.fontWeight(.semibold)
            }
        }
        .navigationDestination(isPresented: $goToSave) { SaveDocumentView(onDone: onDone) }
        .sheet(item: $editing) { f in
            FieldEditSheet(field: f, hints: hints(for: f)) { newValue in capture.editField(key: f.key, value: newValue) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $editingPinyin) {
            PinyinSheet(chineseName: chineseName ?? "", initial: nil) { capture.applyPinyin($0) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChangeType) {
            ChangeTypeSheet(verdict: capture.verdict, current: capture.chosenType) { capture.changeType($0) }
                .presentationDetents([.large])
        }
        .onAppear { if capture.extraction == nil { capture.classifyAndExtract() } }
    }

    // MARK: - Pieces

    private var chineseName: String? {
        guard let n = ex?.fields.first(where: { $0.key == "name" })?.value, Pinyin.split(n) != nil else { return nil }
        return n
    }

    private var cardStyle: Theme.CardStyle {
        guard let ex else { return .graphite }
        if ex.checksTotal == 0 { return .graphite }
        return ex.allChecksPassed ? .green : .red
    }

    private var typeCard: some View {
        let v = capture.verdict
        let detectedBy = v?.reasons.first?.text ?? "No rule matched"
        return GradientCard(style: cardStyle) {
            CardHeader(title: capture.chosenType.displayName,
                       subtitle: v.map { "\(detectedBy) · \($0.score) pts" } ?? "")
            HStack(alignment: .top, spacing: 10) {
                if let ex, ex.checksTotal > 0 {
                    StatBlock(label: "Checks", value: "\(ex.checksPassed)/\(ex.checksTotal)",
                              footnote: ex.allChecksPassed ? "All passed" : "Fix the red field", small: true)
                } else {
                    StatBlock(label: "Checks", value: "—", footnote: "Nothing to verify", small: true)
                }
                StatBlock(label: "Fields", value: "\((ex?.fields.count ?? 0) - (ex?.missingCount ?? 0))/\(ex?.fields.count ?? 0)",
                          footnote: (ex?.missingCount ?? 0) == 0 ? "Complete" : "\(ex!.missingCount) missing", small: true)
            }
            CardButton(title: "Change type") { showChangeType = true }
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title.uppercased()).tracking(0.5)
            Spacer()
            Text(trailing)
        }
        .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
        .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, -8)
    }

    private func fieldList(_ fields: [ExtractedField]) -> some View {
        VStack(spacing: 0) {
            ForEach(fields) { f in
                Button {
                    if f.key == "namePinyin", chineseName != nil { editingPinyin = true } else { editing = f }
                } label: { FieldRow(field: f) }
                    .buttonStyle(.plain)
                if f.id != fields.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Edit-sheet hints: for a failed checksum, show the expected digit and the visual-zone value when known.
    private func hints(for f: ExtractedField) -> [String] {
        var out: [String] = []
        if f.key == "passportNumber", let (l1, l2) = MRZ.locateLines(in: capture.allTextLines),
           let td3 = try? MRZ.parseTD3(line1: l1, line2: l2), !td3.documentNumberCheckOK {
            out.append("MRZ check digit failed for \(td3.documentNumber). Compare with the printed number on the page.")
        }
        if f.key == "pan", let c = CardCheck.validate(f.value), !c.luhnOK {
            out.append("Luhn fails. One digit is probably misread; compare with the card.")
        }
        if f.key == "nric", let n = NRIC.validate(f.value), !n.checksumOK {
            out.append("Expected check letter \(n.expectedLetter).")
        }
        if f.key == "idNumber", let c = ChinaID.validate(f.value), !c.checksumOK {
            out.append("Expected check character \(c.expectedCheck).")
        }
        if f.key == "namePinyin" {
            out.append("Hanyu Pinyin, upper case. Surname first (WANG WEI) or given name first (WEI WANG) — choose per person.")
        }
        if f.key == "category" { out.append("Categories: " + ExpenseCategories.names.prefix(8).joined(separator: " · ") + " …") }
        return out
    }
}

struct FieldRow: View {
    let field: ExtractedField
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(field.labelEN).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
                if let zh = field.labelZH { Text(zh).font(.system(size: 12)).foregroundStyle(Theme.Colors.ink2) }
            }
            .frame(width: 110, alignment: .leading)
            Text(field.value.isEmpty ? "—" : field.value)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(field.check == .missing ? Theme.Colors.danger : Theme.Colors.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusPill(text: pillText, tone: tone)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    private var pillText: String {
        switch field.check {
        case .mrz: "MRZ ✓"; case .luhn: "Luhn ✓"; case .nric: "NRIC ✓"; case .cnid: "ID ✓"
        case .regex: "regex"; case .ocr: "OCR"; case .user: "edited"; case .missing: "Missing"
        }
    }
    private var tone: StatusPill.Tone {
        switch field.check.confidenceTier {
        case .verified: field.check == .user ? .info : .verified
        case .unverified: .unverified
        case .missing: .missing
        }
    }
}

struct FieldEditSheet: View {
    let field: ExtractedField
    let hints: [String]
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField(field.labelEN, text: $value, axis: .vertical)
                    .font(.system(size: 18, design: .monospaced))
                    .padding(14)
                    .background(Theme.Colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                liveCheck
                ForEach(hints, id: \.self) { Text($0).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2) }
                Spacer()
            }
            .padding(16)
            .navigationTitle(field.labelEN + (field.labelZH.map { " · \($0)" } ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(value.trimmingCharacters(in: .whitespaces)); dismiss() }.fontWeight(.semibold) }
            }
            .onAppear { value = field.value; focused = true }
        }
    }

    /// Recomputes the relevant checksum as the user types.
    @ViewBuilder private var liveCheck: some View {
        switch field.key {
        case "pan":
            if let c = CardCheck.validate(value) { StatusPill(text: c.luhnOK ? "Luhn ✓ · \(c.brand.rawValue)" : "Luhn ✗", tone: c.luhnOK ? .verified : .missing) }
        case "nric":
            if let n = NRIC.validate(value) { StatusPill(text: n.checksumOK ? "Checksum ✓" : "Expected \(n.expectedLetter)", tone: n.checksumOK ? .verified : .missing) }
        case "idNumber":
            if let c = ChinaID.validate(value) { StatusPill(text: c.checksumOK ? "Checksum ✓ · \(c.dateOfBirthISO)" : "Expected \(c.expectedCheck)", tone: c.checksumOK ? .verified : .missing) }
        case "dateOfBirth", "expiry", "issueDate", "date", "effectiveDate", "expiryDate", "validFrom", "validTo":
            if let d = TextRules.firstISODate(in: value) { StatusPill(text: "Date \(d)", tone: .verified) } else if !value.isEmpty { StatusPill(text: "Not a date", tone: .unverified) }
        default: EmptyView()
        }
    }
}

struct ChangeTypeSheet: View {
    let verdict: Classifier.Verdict?
    let current: DocumentType
    let onPick: (DocumentType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: DocumentType = .other

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChipRow(items: DocumentType.allCases.map { ($0, $0.displayName) }, selection: $picked).padding(.horizontal, -16)
                    if let v = verdict {
                        Text("WHY \(v.type.displayName.uppercased())").font(.system(size: 14)).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                        VStack(spacing: 0) {
                            ForEach(Array(v.reasons.enumerated()), id: \.offset) { _, r in
                                HStack { Text(r.text).font(.system(size: 15)); Spacer(); StatusPill(text: "+\(r.points)", tone: .verified) }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                Divider().padding(.leading, 16)
                            }
                            ForEach(v.ranked.dropFirst().prefix(4), id: \.0) { t, s in
                                HStack { Text(t.displayName).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2); Spacer(); StatusPill(text: "\(s)", tone: .neutral) }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                            }
                        }
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    HintBanner(badge: "RE-EXTRACT", title: "Fields follow the type",
                               detail: "Picking another type re-runs that type's rules. Your edits are kept where the field key matches.")
                }
                .padding(16)
            }
            .background(Theme.Colors.canvas)
            .navigationTitle("Change type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Use") { onPick(picked); dismiss() }.fontWeight(.semibold).disabled(picked == current) }
            }
            .onAppear { picked = current }
        }
    }
}
