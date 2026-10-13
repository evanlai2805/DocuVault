import SwiftUI
import DocuVaultCore

/// Query-style widget: each character is a chip. Tap the gap after a character to set where the surname ends.
/// Toggle the order. The preview updates live. Saves pinyin, surname and given name together.
struct PinyinSheet: View {
    let chineseName: String
    let initial: Pinyin.NameSplit?
    let onSave: (Pinyin.NameSplit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var split: Pinyin.NameSplit?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let s = split {
                    Text("Which characters are the surname?").font(.system(size: 17, weight: .semibold))
                    chips(s)
                    Text("Order on forms").font(.system(size: 17, weight: .semibold))
                    Picker("Order", selection: Binding(get: { s.surnameFirst }, set: { split?.surnameFirst = $0 })) {
                        Text("Surname first · \(s.surname) \(s.givenName)").tag(true)
                        Text("Given first · \(s.givenName) \(s.surname)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    preview(s)
                } else {
                    Text("No Chinese characters found in \"\(chineseName)\".").foregroundStyle(Theme.Colors.ink2)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.Colors.canvas)
            .navigationTitle("Pinyin · 拼音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let s = split { onSave(s) }; dismiss() }.fontWeight(.semibold).disabled(split == nil)
                }
            }
            .onAppear { split = initial ?? Pinyin.split(chineseName) }
        }
    }

    private func chips(_ s: Pinyin.NameSplit) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(s.characters.enumerated()), id: \.offset) { i, ch in
                let isSurname = i < s.surnameCount
                VStack(spacing: 4) {
                    Text(String(ch)).font(.system(size: 28, weight: .semibold))
                    Text(s.syllables[i]).font(.system(size: 13, weight: .medium)).foregroundStyle(isSurname ? .white : Theme.Colors.ink2)
                }
                .frame(width: 64, height: 76)
                .background(isSurname ? Theme.Colors.accentFill : Theme.Colors.surface)
                .foregroundStyle(isSurname ? .white : Theme.Colors.ink)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.Colors.hairline))
                // Divider handle: tapping the gap after character i sets surnameCount = i+1 (max count-1 so a given name remains).
                if i < s.characters.count - 1 {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { split?.surnameCount = i + 1 }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: s.surnameCount == i + 1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                                .font(.system(size: 10))
                            Rectangle().fill(s.surnameCount == i + 1 ? Theme.Colors.accent : Theme.Colors.hairline).frame(width: 2, height: 56)
                        }
                        .frame(width: 22)
                        .foregroundStyle(s.surnameCount == i + 1 ? Theme.Colors.accent : Theme.Colors.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    private func preview(_ s: Pinyin.NameSplit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW").font(.system(size: 13)).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
            Text(s.formatted).font(.system(size: 26, weight: .bold, design: .monospaced))
            Text("Surname \(s.surname) · Given \(s.givenName)").font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
