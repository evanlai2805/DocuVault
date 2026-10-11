import SwiftUI

/// Design tokens from docs/design-system.md. Light theme only.
enum Theme {
    enum Colors {
        static let canvas = Color(.systemGroupedBackground)
        static let surface = Color.white
        static let ink = Color.primary
        static let ink2 = Color(.secondaryLabel)
        static let hairline = Color(.separator)
        static let accent = Color(red: 0x2F/255, green: 0x6B/255, blue: 0xFF/255)
        static let graphite = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
        static let lavenderBG = Color(red: 0xF4/255, green: 0xEE/255, blue: 0xFC/255)
        static let lavenderBorder = Color(red: 0xDC/255, green: 0xCF/255, blue: 0xF3/255)
        static let lavenderText = Color(red: 0x6E/255, green: 0x2F/255, blue: 0xC4/255)
        static let verified = Color(red: 0x1B/255, green: 0x7F/255, blue: 0x4C/255)
        static let warning = Color(red: 0xB5/255, green: 0x73/255, blue: 0x1B/255)
        static let danger = Color(red: 0x8E/255, green: 0x1F/255, blue: 0x1F/255)
        static let cloud = Color(red: 0xC9/255, green: 0x61/255, blue: 0x2B/255)
    }

    /// Gradient cards keyed by state, not by document type.
    enum CardStyle {
        case navy, red, green, graphite
        /// Cloud: anything that leaves the phone wears this colour (Phase 7).
        case clay
        var gradient: LinearGradient {
            let (a, b): (Color, Color) = switch self {
            case .navy: (Color(red: 0x1B/255, green: 0x0F/255, blue: 0x55/255), Color(red: 0x16/255, green: 0x3C/255, blue: 0x8C/255))
            case .red: (Color(red: 0x5B/255, green: 0x0E/255, blue: 0x0E/255), Color(red: 0x8E/255, green: 0x1F/255, blue: 0x1F/255))
            case .green: (Color(red: 0x0C/255, green: 0x4A/255, blue: 0x2E/255), Color(red: 0x1B/255, green: 0x7F/255, blue: 0x4C/255))
            case .graphite: (Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255), Color(red: 0x3A/255, green: 0x3A/255, blue: 0x3C/255))
            case .clay: (Color(red: 0x5A/255, green: 0x2A/255, blue: 0x12/255), Color(red: 0xC9/255, green: 0x61/255, blue: 0x2B/255))
            }
            return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    enum Radius {
        static let card: CGFloat = 28
        static let insetButton: CGFloat = 16
        static let chip: CGFloat = 22
        static let field: CGFloat = 20
    }
}

// MARK: - Type styles

extension Font {
    /// UPPERCASE condensed tracked label used on cards.
    static func cardLabel(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium).width(.condensed) }
    static let cardTitle: Font = .system(size: 20, weight: .semibold).width(.condensed)
    static let statValue: Font = .system(size: 40, weight: .bold)
    static let statValueSmall: Font = .system(size: 28, weight: .bold)
    static let rowTitle: Font = .system(size: 19, weight: .semibold)
    static let rowSubtitle: Font = .system(size: 16, weight: .regular)
    static let chip: Font = .system(size: 17, weight: .medium)
}

// MARK: - Components

/// Full-width gradient card with white content. Pass any content; use `StatBlock` and `CardButton` inside.
struct GradientCard<Content: View>: View {
    let style: Theme.CardStyle
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.gradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct CardHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.cardTitle).tracking(0.5)
            if let subtitle {
                Text(subtitle.uppercased()).font(.cardLabel(12)).tracking(1).opacity(0.7)
            }
        }
        .padding(.bottom, 16)
    }
}

struct StatBlock: View {
    let label: String
    let value: String
    var footnote: String? = nil
    var small = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.cardLabel()).tracking(1).opacity(0.7)
            Text(value).font(small ? .statValueSmall : .statValue).monospacedDigit().tracking(-1).lineLimit(1).minimumScaleFactor(0.6)
            if let footnote { Text(footnote).font(.system(size: 15)).opacity(0.75) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The translucent row at the bottom of a card: "All documents ›".
struct CardButton: View {
    let title: String
    var systemImage: String = "chevron.right"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.insetButton, style: .continuous))
        }
        .buttonStyle(.pressScale)
        .padding(.top, 16)
    }
}

/// Lavender hint banner (Flighty's PRO banner shape).
struct HintBanner: View {
    let badge: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(badge).font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.Colors.lavenderBorder).clipShape(RoundedRectangle(cornerRadius: 7))
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            Text(detail).font(.system(size: 16))
        }
        .foregroundStyle(Theme.Colors.lavenderText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.lavenderBG)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.Colors.lavenderBorder))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Flighty chip row: selected has a hairline border; unselected is grey text only.
struct ChipRow<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items, id: \.0) { item in
                    let on = item.0 == selection
                    Button { selection = item.0 } label: {
                        Text(item.1).font(.chip)
                            .padding(.horizontal, 18).frame(height: 44)
                            .foregroundStyle(on ? Theme.Colors.ink : Theme.Colors.ink2)
                            .background(on ? Theme.Colors.surface : .clear)
                            .overlay(Capsule().stroke(on ? Theme.Colors.hairline : .clear))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(on ? 0.05 : 0), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Big icon row used on the import sheet and lists: 44pt icon tile, 19pt title, 16pt grey subtitle.
struct IconRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = Theme.Colors.graphite
    var light = false
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(light ? Theme.Colors.ink : .white)
                .frame(width: 44, height: 44)
                .background(light ? Theme.Colors.canvas : tint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rowTitle).foregroundStyle(Theme.Colors.ink)
                if let subtitle { Text(subtitle).font(.rowSubtitle).foregroundStyle(Theme.Colors.ink2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct CircleGlassButton: View {
    let systemImage: String
    var fill: Color = .white.opacity(0.9)
    var foreground: Color = Theme.Colors.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 48, height: 48)
                .background(fill)
                .overlay(Circle().stroke(Theme.Colors.hairline))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
        .buttonStyle(.pressScale)
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
}

/// Green / amber / red / blue pill for check states.
struct StatusPill: View {
    enum Tone { case verified, unverified, missing, info, neutral }
    let text: String
    let tone: Tone
    var color: Color {
        switch tone {
        case .verified: Theme.Colors.verified
        case .unverified: Theme.Colors.warning
        case .missing: Theme.Colors.danger
        case .info: Theme.Colors.accent
        case .neutral: Theme.Colors.ink2
        }
    }
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14)).foregroundStyle(color)
            .clipShape(Capsule())
    }
}
