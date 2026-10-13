import SwiftUI

// The building blocks every settings-style screen uses (checkpoint 17), so no screen falls back to the
// stock iOS form: white 20pt cards on the grey canvas, an upper-case label above, rows of a 17pt title
// and a 14pt grey line, an icon tile only when the row opens something.

/// A scrolling page on the grey canvas. Scroll views take the tab bar's content margin from RootView.
struct CardPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(16)
        }
        .background(Theme.Colors.canvas)
    }
}

/// An upper-case grey label, a white card of rows with hairlines between them, and at most one short
/// line under it where a choice has a consequence.
struct CardSection<Content: View>: View {
    var title: String? = nil
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased()).font(.system(size: 14)).tracking(0.5)
                    .foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Divider().padding(.leading, 16) }
                        row
                    }
                }
            }
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let note {
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
            }
        }
    }
}

/// One line per item: title, optional grey line, optional icon tile, trailing value or chevron.
struct CardRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.Colors.ink
    var value: String? = nil
    var chevron = false
    var destructive = false

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint == Theme.Colors.ink ? Theme.Colors.canvas : tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.Colors.danger : Theme.Colors.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
                }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.system(size: 16)).foregroundStyle(Theme.Colors.ink2).multilineTextAlignment(.trailing) }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A row with a switch on the right.
struct CardToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.ink)
                if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2) }
            }
        }
        .tint(Theme.Colors.verified)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// The vault item's input: a blue label above a large value.
struct CardField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var keyboard: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.Colors.accent)
            TextField(placeholder, text: $text, axis: axis)
                .font(.system(size: 17, weight: .medium))
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Chips that wrap, for a short set of choices (the app's chip rule: selected white pill + hairline).
struct ChoiceChips<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button { selection = value } label: {
                    Text(label).font(.system(size: 15, weight: on ? .semibold : .regular))
                        .padding(.horizontal, 14).frame(height: 36)
                        .foregroundStyle(on ? Theme.Colors.ink : Theme.Colors.ink2)
                        .background(on ? Theme.Colors.surface : .clear)
                        .overlay(Capsule().stroke(on ? Theme.Colors.hairline : .clear))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A destructive row that asks in a drop-down opened from the row itself: the same Liquid Glass menu
/// and spring as "Opens on" (Evan, 13 Oct). A confirmation dialog was pinned to the page and appeared
/// at the top of the screen, far from the row that was tapped.
struct ConfirmRow: View {
    let title: String
    var subtitle: String? = nil
    let question: String
    let action: String
    let perform: () -> Void

    var body: some View {
        Menu {
            Section(question) {
                Button(action, role: .destructive, action: perform)
            }
        } label: {
            CardRow(title: title, subtitle: subtitle, destructive: true)
        }
        .buttonStyle(.plain)
    }
}
