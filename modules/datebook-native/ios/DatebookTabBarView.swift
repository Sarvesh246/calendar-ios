import ExpoModulesCore
import UIKit

/// Embeds a real `UITabBarController` rather than a bare `UITabBar`. Four
/// separate techniques against a bare, unmanaged `UITabBar` (forcing its
/// frame via constraints, an intrinsic-size override, bigger icon/label
/// content, and a wrapping second glass view) each either failed to grow
/// its own rendered background or introduced illegal glass-in-glass
/// nesting artifacts. Apple's own apps (e.g. News) ship exactly this
/// floating-tray-plus-separate-button layout with a taller, better-
/// proportioned bar than any of those attempts reproduced — real evidence
/// that treatment is tied to `UITabBarController`'s own composition of its
/// bar, not something a standalone `UITabBar` can be coaxed into.
///
/// The controller's "content" is never actually shown — each tab holds an
/// empty, transparent view controller, since the WebView (driven by React)
/// remains the real content and routing source of truth. This view is
/// deliberately taller than the visible dock so the controller has the
/// room its own layout expects above the bar; `hitTest` restricts real
/// touch handling to the bar's own frame so that extra transparent space
/// passes taps through to the WebView underneath instead of blocking them.
public class DatebookTabBarView: ExpoView, UITabBarControllerDelegate {
  let onSelect = EventDispatcher()

  private let tabBarController = UITabBarController()
  private var isProgrammaticSelection = false
  private var currentSelectedIndex = 0
  private var didAttemptContainment = false

  /// Liquid Glass over dark or busy content can read as almost clear. A thin
  /// blur material sits under the bar's glass so it frosts what scrolls
  /// beneath it. Raise `frostAlpha` for more frost, lower it for less.
  private let frostView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
  private let frostAlpha: CGFloat = 0.92

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    clipsToBounds = false
    tabBarController.delegate = self
    tabBarController.view.backgroundColor = .clear
    tabBarController.tabBar.clipsToBounds = false
    frostView.isUserInteractionEnabled = false
    frostView.clipsToBounds = true
    frostView.alpha = frostAlpha
    tabBarController.tabBar.insertSubview(frostView, at: 0)
    tabBarController.view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(tabBarController.view)

    NSLayoutConstraint.activate([
      tabBarController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      tabBarController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      tabBarController.view.topAnchor.constraint(equalTo: topAnchor),
      tabBarController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    // Proper view-controller containment (best effort): walk the responder
    // chain for the nearest real UIViewController hosting this native view
    // so `tabBarController` gets correct lifecycle/appearance callbacks and
    // safe-area propagation, rather than just floating its `.view` as a
    // plain subview. Only needs to happen once, and only once this view is
    // actually installed in a window.
    guard window != nil, !didAttemptContainment, tabBarController.parent == nil else { return }
    didAttemptContainment = true
    var responder: UIResponder? = self
    while let current = responder {
      if let hostVC = current as? UIViewController {
        hostVC.addChild(tabBarController)
        tabBarController.didMove(toParent: hostVC)
        return
      }
      responder = current.next
    }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    // Track the visible pill, not the safe-area padding below it, and keep it
    // a capsule so the blur never pokes out past the glass edge.
    let bar = tabBarController.tabBar
    let bottomInset = bar.safeAreaInsets.bottom
    let rect = CGRect(
      x: 0,
      y: 0,
      width: bar.bounds.width,
      height: max(0, bar.bounds.height - bottomInset)
    )
    frostView.frame = rect
    frostView.layer.cornerRadius = min(rect.width, rect.height) / 2
    if #available(iOS 13.0, *) { frostView.layer.cornerCurve = .continuous }
  }

  // Only the tab bar's own frame (plus a small touch-slop margin) is
  // interactive; the rest of this taller view passes touches through to
  // whatever's beneath it (the WebView).
  public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let barFrame = tabBarController.tabBar.frame.insetBy(dx: -8, dy: -8)
    guard barFrame.contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }

  func setItems(_ items: [[String: String]]) {
    let controllers: [UIViewController] = items.enumerated().map { index, item in
      let vc = UIViewController()
      vc.view.backgroundColor = .clear
      let tabItem = UITabBarItem(
        title: item["label"],
        image: UIImage(systemName: item["symbol"] ?? "circle"),
        tag: index
      )
      tabItem.accessibilityIdentifier = item["url"]
      vc.tabBarItem = tabItem
      return vc
    }
    tabBarController.viewControllers = controllers
    applySelection(currentSelectedIndex)
  }

  func setSelectedIndex(_ index: Int) {
    currentSelectedIndex = index
    applySelection(index)
  }

  private func applySelection(_ index: Int) {
    guard let controllers = tabBarController.viewControllers, index >= 0, index < controllers.count else {
      // A route with no matching tab (Settings/Schedule) — a
      // UITabBarController has no "no selection" state the way a bare
      // UITabBar's `selectedItem = nil` does, so the last real tab just
      // stays lit rather than forcing an invalid index.
      return
    }
    isProgrammaticSelection = true
    tabBarController.selectedIndex = index
    isProgrammaticSelection = false
  }

  func setTint(_ hex: String?) {
    tabBarController.tabBar.tintColor = UIColor(datebookHex: hex) ?? .systemBlue
  }

  func setUnselectedTint(_ hex: String?) {
    tabBarController.tabBar.unselectedItemTintColor = UIColor(datebookHex: hex) ?? .secondaryLabel
  }

  func setDisabled(_ disabled: Bool) {
    tabBarController.tabBar.isUserInteractionEnabled = !disabled
    // Dim, don't fake a different material, while chrome is suppressed
    // (a sheet/drawer/focus overlay is up).
    tabBarController.tabBar.alpha = disabled ? 0.4 : 1
  }

  /// Datebook's own resolved in-app theme, not the phone's Dark Mode
  /// setting — this view otherwise inherits `userInterfaceStyle` from the
  /// window, which tracks the device, not the app's selected appearance.
  /// Applied on `self` so it cascades to the tab bar's Liquid Glass
  /// material and dynamic colors (`.secondaryLabel` for unselected items)
  /// without touching any other native chrome or system UI. Re-applying
  /// this never resets `selectedIndex` or recreates the controller.
  func setInterfaceStyle(_ style: String?) {
    switch style {
    case "light":
      overrideUserInterfaceStyle = .light
    case "dark":
      overrideUserInterfaceStyle = .dark
    default:
      overrideUserInterfaceStyle = .unspecified
    }
  }

  // MARK: UITabBarControllerDelegate

  public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    // Programmatic selection (`applySelection`, driven by React's route
    // sync) does not invoke this delegate method — only a real user
    // tap/drag-release does. This guard is a second line of defense in
    // case that ever changes, so a programmatic sync can never round-trip
    // into a second navigate intent.
    guard !isProgrammaticSelection else { return }
    guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else { return }
    currentSelectedIndex = index
    onSelect(["index": index])
  }
}

extension UIColor {
  convenience init?(datebookHex hex: String?) {
    guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    value = value.replacingOccurrences(of: "#", with: "")
    guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1
    )
  }
}
