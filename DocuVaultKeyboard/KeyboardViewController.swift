import UIKit
import SwiftUI
import DocuVaultCore

/// Custom keyboard: hosts the SwiftUI keyboard and bridges text insertion.
/// Needs "Allow Full Access" to read the App Group store and the vault key. No network code anywhere in this target.
final class KeyboardViewController: UIInputViewController {

    private var model: KeyboardModel!
    private var host: UIHostingController<KeyboardRootView>!
    private var heightConstraint: NSLayoutConstraint?

    /// A keyboard cannot draw above its own top edge, so search matches grow the keyboard upward
    /// instead of floating over the app the way Telegram's list does (Evan, 13 Oct).
    private func trackHeight() {
        let target = withObservationTracking { KeyboardRootView.preferredHeight(model) } onChange: { [weak self] in
            Task { @MainActor in self?.trackHeight() }
        }
        if heightConstraint?.constant != target { heightConstraint?.constant = target }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model = KeyboardModel(
            hasFullAccess: hasFullAccess,
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            dismiss: { [weak self] in self?.dismissKeyboard() }
        )
        host = UIHostingController(rootView: KeyboardRootView(model: model, showsGlobe: needsInputModeSwitchKey))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.overrideUserInterfaceStyle = .light   // light-only design; dark mode made the keys illegible
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let h = view.heightAnchor.constraint(equalToConstant: KeyboardRootView.height)
        h.priority = .defaultHigh
        h.isActive = true
        heightConstraint = h
        host.didMove(toParent: self)
        model.load()
        trackHeight()
        // Phone locked: drop the key at once, whatever the lock window says. Checked on the device
        // that iOS delivers this to a keyboard extension; the lock window still applies if it does not.
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.lock() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.willAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.didDisappear()   // starts the lock window; the key lives in memory only
    }

    override func textDidChange(_ textInput: UITextInput?) {
        refreshContext()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        refreshContext()
    }

    /// Everything iOS lets a keyboard see about the field: keyboard type, content type, text around the cursor.
    private func refreshContext() {
        let proxy = textDocumentProxy
        model.isSecureField = proxy.isSecureTextEntry ?? false
        let numeric: FillInference.FieldKeyboard = switch proxy.keyboardType {
            case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad: .numeric
            default: .other
        }
        model.fieldContext = FillInference.Context(
            keyboard: numeric,
            contentType: proxy.textContentType?.rawValue,
            before: proxy.documentContextBeforeInput ?? "",
            after: proxy.documentContextAfterInput ?? "",
            region: Locale.current.region?.identifier ?? "SG"
        )
    }
}
