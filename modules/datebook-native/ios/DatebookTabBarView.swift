import ExpoModulesCore
import UIKit

/// A single, plain `UITabBar` — no outer `UIVisualEffectView`/`UIGlassEffect`
/// wrapper. An earlier version added one purely to grow the tray's visible
/// height, but it produced a second, wrongly-shaped glass shape behind the
/// real bar on a physical device, and that persisted even after clipping
/// the wrapper's bounds — confirmed by the same artifact appearing around
/// the separate "+" button too, which that wrapper never touched. Rather
/// than keep adjusting properties on a component confirmed to be the
/// problem, it's removed outright: with exactly one glass-backed view in
/// this hierarchy, a second visible glass shape isn't possible by
/// construction. The known tradeoff is that `tabBar`'s own background
/// material renders at its native, content-hugging height rather than
/// whatever taller frame this view is laid out at — a separate, already
/// surfaced limitation, not something this file is trying to solve again.
public class DatebookTabBarView: ExpoView, UITabBarDelegate {
  let onSelect = EventDispatcher()

  private let tabBar = UITabBar()
  private var isProgrammaticSelection = false
  private var currentSelectedIndex = 0

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    tabBar.delegate = self
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    // Let the system material show real content behind it — never force the
    // bar opaque, and never clip the pressed selection bubble as it lifts
    // outside the bar's resting bounds.
    tabBar.isTranslucent = true
    tabBar.clipsToBounds = false
    clipsToBounds = false
    addSubview(tabBar)

    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func setItems(_ items: [[String: String]]) {
    tabBar.items = items.enumerated().map { index, item in
      let tabItem = UITabBarItem(
        title: item["label"],
        image: UIImage(systemName: item["symbol"] ?? "circle"),
        tag: index
      )
      tabItem.accessibilityIdentifier = item["url"]
      return tabItem
    }
    applySelection(currentSelectedIndex, animated: false)
  }

  func setSelectedIndex(_ index: Int) {
    currentSelectedIndex = index
    applySelection(index, animated: true)
  }

  private func applySelection(_ index: Int, animated: Bool) {
    guard let items = tabBar.items, index >= 0, index < items.count else {
      // A route with no matching tab (Settings/Schedule) — leave the tray
      // without a system selection rather than forcing a wrong tab lit.
      isProgrammaticSelection = true
      tabBar.selectedItem = nil
      isProgrammaticSelection = false
      return
    }
    isProgrammaticSelection = true
    tabBar.selectedItem = items[index]
    isProgrammaticSelection = false
  }

  func setTint(_ hex: String?) {
    tabBar.tintColor = UIColor(datebookHex: hex) ?? .systemBlue
  }

  func setUnselectedTint(_ hex: String?) {
    tabBar.unselectedItemTintColor = UIColor(datebookHex: hex) ?? .secondaryLabel
  }

  func setDisabled(_ disabled: Bool) {
    tabBar.isUserInteractionEnabled = !disabled
    // Dim, don't fake a different material, while chrome is suppressed
    // (a sheet/drawer/focus overlay is up).
    tabBar.alpha = disabled ? 0.4 : 1
  }

  /// Datebook's own resolved in-app theme, not the phone's Dark Mode
  /// setting — a `UITabBar` otherwise inherits `userInterfaceStyle` from the
  /// window, which tracks the device, not the app's selected appearance.
  /// Overriding it here (rather than window-wide) scopes the effect to this
  /// control and its Liquid Glass material/dynamic colors (`.secondaryLabel`
  /// for unselected items, the glass tint) without touching any other native
  /// chrome or system UI. Re-applying this never resets `selectedItem` or
  /// recreates the bar.
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

  // MARK: UITabBarDelegate

  public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    // `selectedItem =` (used by setSelectedIndex, driven by React's route
    // sync) does not itself invoke this delegate method on iOS — only a real
    // user tap/drag-release does. This guard is a second line of defense in
    // case that ever changes, so a programmatic sync can never round-trip
    // into a second navigate intent.
    guard !isProgrammaticSelection else { return }
    currentSelectedIndex = item.tag
    onSelect(["index": item.tag])
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
