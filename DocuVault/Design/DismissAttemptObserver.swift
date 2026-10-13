import SwiftUI
import UIKit

/// Tells a sheet when someone swipes it down while `interactiveDismissDisabled` holds it open, so it
/// can ask instead of ignoring the swipe (checkpoint 17: "Discard 3 pages?"). SwiftUI keeps its own
/// delegate on the presentation controller to update the sheet's binding, so every other call is
/// passed through to it unchanged.
struct DismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(onAttempt: onAttempt) }
    func updateUIViewController(_ vc: Controller, context: Context) { vc.onAttempt = onAttempt }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        private weak var original: UIAdaptivePresentationControllerDelegate?

        init(onAttempt: @escaping () -> Void) {
            self.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // `presentationController` walks up to the nearest presented ancestor: the sheet.
            guard let pc = presentationController, pc.delegate !== self else { return }
            original = pc.delegate
            pc.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ pc: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(pc)
            onAttempt()
        }
        func presentationControllerShouldDismiss(_ pc: UIPresentationController) -> Bool {
            original?.presentationControllerShouldDismiss?(pc) ?? true
        }
        func presentationControllerWillDismiss(_ pc: UIPresentationController) {
            original?.presentationControllerWillDismiss?(pc)
        }
        func presentationControllerDidDismiss(_ pc: UIPresentationController) {
            original?.presentationControllerDidDismiss?(pc)
        }
    }
}
