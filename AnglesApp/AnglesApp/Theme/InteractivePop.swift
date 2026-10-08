import SwiftUI
import UIKit

/// Swipe back for a pushed page that hides the navigation bar and draws its own chevron.
///
/// UIKit turns its edge swipe off when the back button is hidden, and the edge strip is
/// only a few points wide. This turns the system gesture back on for the page that asks
/// for it, and on iOS 26 and later also opens the system's content-swipe gesture over the
/// left part of the screen (`backSwipeFraction`, 40%). Both are UIKit's own interactive pop,
/// so the previous page slides in under the finger. Older systems keep the edge strip.
///
/// Nothing is global: the gestures are handed back untouched when the page goes away, and
/// every reference to the navigation controller is weak.
extension View {
    func wideBackSwipe(fraction: CGFloat = 0.4) -> some View {
        background(BackSwipeInstaller(fraction: fraction).frame(width: 0, height: 0))
    }
}

private struct BackSwipeInstaller: UIViewControllerRepresentable {
    let fraction: CGFloat

    func makeUIViewController(context: Context) -> BackSwipeController {
        BackSwipeController(fraction: fraction)
    }

    func updateUIViewController(_ controller: BackSwipeController, context: Context) {}
}

final class BackSwipeController: UIViewController {
    private let fraction: CGFloat
    private var installed: [Installed] = []

    init(fraction: CGFloat) {
        self.fraction = fraction
        super.init(nibName: nil, bundle: nil)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        install()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        uninstall()
    }

    deinit {
        // Only the delegate pointers are touched, which is safe from any thread.
        for item in installed {
            item.restore()
        }
    }

    private func install() {
        guard installed.isEmpty, let navigationController else {
            return
        }
        if let edge = navigationController.interactivePopGestureRecognizer {
            installed.append(Installed(edge, navigationController, fraction: nil))
        }
        if #available(iOS 26.0, *), let content = navigationController.interactiveContentPopGestureRecognizer {
            installed.append(Installed(content, navigationController, fraction: fraction))
        }
    }

    private func uninstall() {
        for item in installed {
            item.restore()
        }
        installed.removeAll()
    }
}

/// One recognizer with our gate in front of it, and the way back.
private final class Installed {
    private weak var recognizer: UIGestureRecognizer?
    private weak var original: UIGestureRecognizerDelegate?
    private let gate: BackSwipeGate

    init(_ recognizer: UIGestureRecognizer, _ navigationController: UINavigationController, fraction: CGFloat?) {
        self.recognizer = recognizer
        self.original = recognizer.delegate
        self.gate = BackSwipeGate(navigationController: navigationController, fraction: fraction, original: recognizer.delegate)
        recognizer.delegate = gate
    }

    func restore() {
        guard let recognizer, recognizer.delegate === gate else {
            return
        }
        recognizer.delegate = original
    }
}

private final class BackSwipeGate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private weak var original: UIGestureRecognizerDelegate?
    private let fraction: CGFloat?

    init(navigationController: UINavigationController, fraction: CGFloat?, original: UIGestureRecognizerDelegate?) {
        self.navigationController = navigationController
        self.fraction = fraction
        self.original = original
    }

    /// Only with a page to go back to.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }

    /// The wide gesture only takes touches that land in the left part of the screen.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let fraction, let view = navigationController?.view else {
            return true
        }
        return touch.location(in: view).x <= view.bounds.width * fraction
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        original?.gestureRecognizer?(gestureRecognizer, shouldRecognizeSimultaneouslyWith: other) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        original?.gestureRecognizer?(gestureRecognizer, shouldRequireFailureOf: other) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        original?.gestureRecognizer?(gestureRecognizer, shouldBeRequiredToFailBy: other) ?? false
    }
}
