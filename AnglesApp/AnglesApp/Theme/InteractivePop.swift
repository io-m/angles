import UIKit

/// Keeps the system edge swipe-back alive on pages that hide the navigation bar and its back
/// button (the author page draws its own chevron). UIKit turns the gesture off whenever the
/// back button is hidden; this gives it back, and only when there is a page to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
