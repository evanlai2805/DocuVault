import UIKit
import SwiftUI
import DocuVaultCore

/// Custom keyboard: hosts the SwiftUI keyboard and bridges text insertion.
/// Needs "Allow Full Access" to read the App Group store and the vault key. No network code anywhere in this target.
final class KeyboardViewController: UIInputViewController {

    private var model: KeyboardModel!
    private var host: UIHostingController<KeyboardRootView>!

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
        host.didMove(toParent: self)
        model.load()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.lock()   // key never outlives the keyboard
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
        model.isSecureField = proxy.isSecureTextEntry
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
