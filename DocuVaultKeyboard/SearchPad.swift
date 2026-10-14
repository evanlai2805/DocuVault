import SwiftUI
import UIKit
import AudioToolbox

/// The search pad's letters, laid out like Apple's English keyboard and handled the way Apple's is
/// (keyboard rebuild, 13 Oct). One view owns every touch, so there are no dead zones: a touch in a gap
/// goes to the nearest key. The key's letter rises in a callout the instant the finger lands, with a
/// click and a light tap; the letter types on lift. Each finger is tracked on its own, and a second
/// finger landing commits the first, so fast typing never drops letters.
struct SearchPad: UIViewRepresentable {
    var showsGlobe: Bool
    var openEnabled: Bool
    var onLetter: (String) -> Void
    var onDelete: () -> Void
    var onSpace: () -> Void
    var onBack: () -> Void
    var onOpen: () -> Void
    var onGlobe: () -> Void

    func makeUIView(context: Context) -> SearchPadView { SearchPadView() }

    func updateUIView(_ v: SearchPadView, context: Context) {
        v.actions = self
        if v.showsGlobe != showsGlobe { v.showsGlobe = showsGlobe }
        if v.openEnabled != openEnabled { v.openEnabled = openEnabled }
    }
}

final class SearchPadView: UIView {
    typealias System = KeyboardRootView.System

    enum Key: Hashable {
        case letter(String), shift, delete, globe, back, space, open
        var isLetter: Bool { if case .letter = self { return true }; return false }
    }

    var actions: SearchPad?
    var showsGlobe = false { didSet { setNeedsLayout() } }
    var openEnabled = false { didSet { styleKeys() } }

    private static let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private var shifted = false { didSet { styleKeys() } }
    private var caps: [Key: KeyCap] = [:]
    private var frames: [Key: CGRect] = [:]
    /// Each finger's key. nil once the key was committed early by the next finger (rollover).
    private var touches: [ObjectIdentifier: Key?] = [:]
    private let callout = Callout()
    private var repeater: Task<Void, Never>?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        clipsToBounds = false           // the top row's callout rises over the strip above
        backgroundColor = .clear
        for row in Self.rows { for l in row { add(.letter(l)) } }
        for k: Key in [.shift, .delete, .globe, .back, .space, .open] { add(k) }
        addSubview(callout)
        callout.isHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.styleKeys() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func add(_ k: Key) {
        let cap = KeyCap()
        caps[k] = cap
        addSubview(cap)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, gap = System.keyGap, h = System.keyHeight
        let letter = (w - 9 * gap) / 10
        func y(_ row: Int) -> CGFloat { CGFloat(row) * (h + System.rowGap) }
        var f: [Key: CGRect] = [:]
        for (i, l) in Self.rows[0].enumerated() {
            f[.letter(l)] = CGRect(x: CGFloat(i) * (letter + gap), y: y(0), width: letter, height: h)
        }
        let inset2 = (w - 9 * letter - 8 * gap) / 2
        for (i, l) in Self.rows[1].enumerated() {
            f[.letter(l)] = CGRect(x: inset2 + CGFloat(i) * (letter + gap), y: y(1), width: letter, height: h)
        }
        let inset3 = (w - 7 * letter - 6 * gap) / 2
        for (i, l) in Self.rows[2].enumerated() {
            f[.letter(l)] = CGRect(x: inset3 + CGFloat(i) * (letter + gap), y: y(2), width: letter, height: h)
        }
        f[.shift] = CGRect(x: 0, y: y(2), width: System.modifierWidth, height: h)
        f[.delete] = CGRect(x: w - System.modifierWidth, y: y(2), width: System.modifierWidth, height: h)
        // Bottom row: [globe] Back · space · Open. Without the globe, Back spans both modifier slots.
        var x: CGFloat = 0
        if showsGlobe {
            f[.globe] = CGRect(x: 0, y: y(3), width: System.modifierWidth, height: h)
            x = System.modifierWidth + gap
        }
        let backWidth = showsGlobe ? System.modifierWidth : 2 * System.modifierWidth + gap
        f[.back] = CGRect(x: x, y: y(3), width: backWidth, height: h)
        let openX = w - System.returnWidth
        f[.open] = CGRect(x: openX, y: y(3), width: System.returnWidth, height: h)
        let spaceX = x + backWidth + gap
        f[.space] = CGRect(x: spaceX, y: y(3), width: openX - gap - spaceX, height: h)
        frames = f
        for (k, cap) in caps {
            cap.isHidden = f[k] == nil
            if let r = f[k] { cap.frame = r }
        }
        styleKeys()
    }

    /// The key a touch belongs to: the one under it, else the nearest, so gaps between keys never swallow a tap.
    private func key(at p: CGPoint) -> Key? {
        var best: (Key, CGFloat)?
        for (k, r) in frames {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            let d = dx * dx + dy * dy
            if best == nil || d < best!.1 { best = (k, d) }
        }
        return best?.0
    }

    // MARK: Style

    private func styleKeys() {
        let held = Set(touches.values.compactMap { $0 })
        for (k, cap) in caps {
            let down = held.contains(k)
            switch k {
            case .letter(let l):
                cap.set(text: shifted ? l.uppercased() : l, font: .systemFont(ofSize: System.font), color: KeyColors.ink,
                        fill: KeyColors.key)
            case .shift:
                cap.set(symbol: shifted ? "shift.fill" : "shift", color: KeyColors.ink,
                        fill: shifted || down ? KeyColors.key : KeyColors.modifier)
            case .delete:
                cap.set(symbol: down ? "delete.left.fill" : "delete.left", color: KeyColors.ink,
                        fill: down ? KeyColors.key : KeyColors.modifier)
            case .globe:
                cap.set(symbol: "globe", color: KeyColors.ink, fill: down ? KeyColors.key : KeyColors.modifier)
            case .back:
                cap.set(text: "Back", font: .systemFont(ofSize: 16), color: KeyColors.ink,
                        fill: down ? KeyColors.key : KeyColors.modifier)
            case .space:
                cap.set(text: "space", font: .systemFont(ofSize: 16), color: KeyColors.ink,
                        fill: down ? KeyColors.modifier : KeyColors.key)
            case .open:
                if openEnabled {
                    // Flat gunmetal like Done, no sheen (checkpoint 20 Q8).
                    cap.set(text: "Open", font: .systemFont(ofSize: 16, weight: .semibold), color: .white, fill: UIColor(hex: 0x3A424C))
                    cap.alpha = down ? 0.75 : 1
                } else {
                    cap.set(text: "Open", font: .systemFont(ofSize: 16, weight: .semibold), color: KeyColors.ink3,
                            fill: KeyColors.modifier)
                    cap.alpha = 1
                }
            }
        }
    }

    // MARK: Touches

    override func touchesBegan(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            // Rollover: a new finger commits the letter still held by another, as Apple's keyboard does.
            for (id, k) in touches { if let k, k.isLetter { commit(k); touches[id] = .some(nil) } }
            guard let k = key(at: t.location(in: self)) else { continue }
            if k == .open, !openEnabled { continue }
            touches[ObjectIdentifier(t)] = k
            press(k)
        }
        styleKeys()
    }

    override func touchesMoved(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            // A letter follows the finger, as on Apple's keyboard; other keys stay put.
            guard let entry = touches[ObjectIdentifier(t)], let k = entry, k.isLetter,
                  let now = key(at: t.location(in: self)), now.isLetter, now != k else { continue }
            touches[ObjectIdentifier(t)] = now
            showCallout(now)
        }
        styleKeys()
    }

    override func touchesEnded(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            if let entry = touches.removeValue(forKey: ObjectIdentifier(t)), let k = entry { commit(k) }
        }
        settle()
    }

    override func touchesCancelled(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set { touches.removeValue(forKey: ObjectIdentifier(t)) }
        settle()
    }

    private func settle() {
        if !touches.values.contains(where: { $0 == .delete }) { stopRepeat() }
        if !touches.values.contains(where: { $0?.isLetter == true }) { callout.isHidden = true }
        styleKeys()
    }

    /// Touch down: feedback at once. Letters show their callout; delete deletes and starts repeating;
    /// shift toggles. Everything else waits for the lift.
    private func press(_ k: Key) {
        haptic.impactOccurred(intensity: 0.7)
        haptic.prepare()
        switch k {
        case .letter:
            AudioServicesPlaySystemSound(1104)
            showCallout(k)
        case .delete:
            AudioServicesPlaySystemSound(1155)
            actions?.onDelete()
            startRepeat()
        case .shift:
            AudioServicesPlaySystemSound(1156)
            shifted.toggle()
        default:
            AudioServicesPlaySystemSound(1156)
        }
    }

    private func commit(_ k: Key) {
        switch k {
        case .letter(let l):
            actions?.onLetter(shifted ? l.uppercased() : l)
            if shifted { shifted = false }
        case .space: actions?.onSpace()
        case .back: actions?.onBack()
        case .open: if openEnabled { actions?.onOpen() }
        case .globe: actions?.onGlobe()
        case .shift, .delete: break
        }
    }

    private func showCallout(_ k: Key) {
        guard case .letter(let l) = k, let r = frames[k] else { return }
        callout.show(letter: shifted ? l.uppercased() : l, key: r, in: bounds)
        bringSubviewToFront(callout)
    }

    /// Like UIKit's delete: one on touch, then repeats after 0.4 s, faster after about 1.5 s.
    private func startRepeat() {
        stopRepeat()
        repeater = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            var interval = 90, fired = 0
            while !Task.isCancelled, let self {
                self.actions?.onDelete()
                AudioServicesPlaySystemSound(1155)
                fired += 1
                if fired == 15 { interval = 45 }
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func stopRepeat() {
        repeater?.cancel()
        repeater = nil
    }
}

/// The search pad's colours, light and dark, measured from Apple's own keyboard (see `Palette`).
enum KeyColors {
    static var key: UIColor { UIColor(Palette.key) }
    static var modifier: UIColor { UIColor(Palette.keyModifier) }
    static var ink: UIColor { UIColor(Palette.ink) }
    static var ink3: UIColor { UIColor(Palette.ink3) }
    static var shadow: UIColor { UIColor(Palette.keyShadow) }
}

/// One key: rounded face, Apple's one-point bottom shadow, a letter or a symbol.
final class KeyCap: UIView {
    private let label = UILabel()
    private let icon = UIImageView()
    private let sheenLayer = CAGradientLayer()
    private let shadowLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = KeyboardRootView.System.radius
        layer.cornerCurve = .continuous
        shadowLayer.cornerRadius = KeyboardRootView.System.radius
        shadowLayer.cornerCurve = .continuous
        layer.addSublayer(shadowLayer)
        sheenLayer.cornerRadius = KeyboardRootView.System.radius
        sheenLayer.cornerCurve = .continuous
        sheenLayer.startPoint = CGPoint(x: 0, y: 0)
        sheenLayer.endPoint = CGPoint(x: 1, y: 1)
        sheenLayer.colors = [0x22282F, 0x5C6672, 0x22282F].map { UIColor(hex: $0).cgColor }
        sheenLayer.borderWidth = 0.5
        sheenLayer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        layer.addSublayer(sheenLayer)
        label.textAlignment = .center
        icon.contentMode = .center
        addSubview(label)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var face: UIColor?

    func set(text: String? = nil, symbol: String? = nil, font: UIFont = .systemFont(ofSize: 16), color: UIColor,
             fill: UIColor?, sheen: Bool = false) {
        label.isHidden = text == nil
        icon.isHidden = symbol == nil
        if let text, label.text != text { label.text = text }
        label.font = font
        label.textColor = color
        if let symbol {
            icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
            icon.tintColor = color
        }
        face = fill
        sheenLayer.isHidden = !sheen
        applyColors()
    }

    private func applyColors() {
        let tc = traitCollection
        backgroundColor = .clear
        shadowLayer.backgroundColor = KeyColors.shadow.resolvedColor(with: tc).cgColor
        // The face sits one point above the shadow, so only the bottom edge shows.
        layer.backgroundColor = nil
        faceLayer.backgroundColor = (face ?? .clear).resolvedColor(with: tc).cgColor
    }

    private lazy var faceLayer: CALayer = {
        let l = CALayer()
        l.cornerRadius = KeyboardRootView.System.radius
        l.cornerCurve = .continuous
        layer.insertSublayer(l, above: shadowLayer)
        return l
    }()

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds.offsetBy(dx: 0, dy: 1)
        faceLayer.frame = bounds
        sheenLayer.frame = bounds
        shadowLayer.isHidden = !sheenLayer.isHidden
        CATransaction.commit()
        label.frame = bounds.offsetBy(dx: 0, dy: -1)
        icon.frame = bounds
    }
}

/// Apple's key callout: the letter, enlarged, in a balloon that grows up out of the key.
final class Callout: UIView {
    private let shape = CAShapeLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.shadowOffset = CGSize(width: 0, height: 1)
        shape.shadowRadius = 3
        shape.shadowOpacity = 0.3
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(letter: String, key k: CGRect, in bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = bounds
        let extra: CGFloat = 11, topH: CGFloat = 52, neck: CGFloat = 12, r: CGFloat = 10
        let w = k.width + 2 * extra
        let left = min(max(k.midX - w / 2, bounds.minX - 2), bounds.maxX + 2 - w)
        let top = CGRect(x: left, y: k.minY - topH + 2, width: w, height: topH)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: top.minX, y: top.minY + r))
        p.addArc(withCenter: CGPoint(x: top.minX + r, y: top.minY + r), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        p.addLine(to: CGPoint(x: top.maxX - r, y: top.minY))
        p.addArc(withCenter: CGPoint(x: top.maxX - r, y: top.minY + r), radius: r, startAngle: 1.5 * .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: top.maxX, y: top.maxY - 4))
        p.addCurve(to: CGPoint(x: k.maxX, y: top.maxY + neck),
                   controlPoint1: CGPoint(x: top.maxX, y: top.maxY + neck * 0.4),
                   controlPoint2: CGPoint(x: k.maxX, y: top.maxY + neck * 0.5))
        let kr = KeyboardRootView.System.radius
        p.addLine(to: CGPoint(x: k.maxX, y: k.maxY - kr))
        p.addArc(withCenter: CGPoint(x: k.maxX - kr, y: k.maxY - kr), radius: kr, startAngle: 0, endAngle: 0.5 * .pi, clockwise: true)
        p.addLine(to: CGPoint(x: k.minX + kr, y: k.maxY))
        p.addArc(withCenter: CGPoint(x: k.minX + kr, y: k.maxY - kr), radius: kr, startAngle: 0.5 * .pi, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: k.minX, y: top.maxY + neck))
        p.addCurve(to: CGPoint(x: top.minX, y: top.maxY - 4),
                   controlPoint1: CGPoint(x: k.minX, y: top.maxY + neck * 0.5),
                   controlPoint2: CGPoint(x: top.minX, y: top.maxY + neck * 0.4))
        p.close()
        shape.path = p.cgPath
        shape.fillColor = KeyColors.key.resolvedColor(with: traitCollection).cgColor
        shape.shadowColor = UIColor.black.cgColor
        label.text = letter
        label.textColor = KeyColors.ink.resolvedColor(with: traitCollection)
        label.frame = top.insetBy(dx: 0, dy: 4).offsetBy(dx: 0, dy: -2)
        isHidden = false
        CATransaction.commit()
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
