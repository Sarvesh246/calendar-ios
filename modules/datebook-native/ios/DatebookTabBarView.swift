import ExpoModulesCore
import UIKit

/// A standalone `UITabBar` reports a fixed ~49pt `intrinsicContentSize`/
/// `sizeThatFits` by default — a leftover from the assumption that a
/// `UITabBarController` owns it. Even though Auto Layout still gives it
/// whatever frame `DatebookTabBarView` is laid out at, the bar's own
/// internal item layout consults its intrinsic/fitting size to decide how
/// much vertical room the icon/label stack gets, so an unmodified bar
/// squeezes its content into that ~49pt assumption inside a taller frame.
/// Handing its own current bounds back through both queries makes the
/// *system* item layout use the real height — React's style height (set on
/// `DatebookTabBarView`, which this bar exactly fills) stays the only place
/// that number is decided; nothing here hard-codes a second one.
private final class SizedTabBar: UITabBar {
  override var intrinsicContentSize: CGSize {
    let height = bounds.height > 0 ? bounds.height : super.intrinsicContentSize.height
    return CGSize(width: UIView.noIntrinsicMetric, height: height)
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    var fitted = super.sizeThatFits(size)
    if bounds.height > 0 {
      fitted.height = bounds.height
    }
    return fitted
  }
}

/// Wraps a real system `UITabBar` so the three-item nav tray gets Apple's own
/// interactive Liquid Glass selection behavior (press-and-hold lift, finger
/// tracking between items, accent preview, spring settle, Reduce Motion /
/// Reduce Transparency handling, accessibility) for free on iOS 26+, and a
/// standard translucent `UITabBar` on older iOS. None of that behavior is
/// reimplemented here — this view only feeds the bar its items/tint and
/// relays the user's selection back to JS. React remains the source of truth
/// for routing: this view never navigates on its own.
public class DatebookTabBarView: ExpoView, UITabBarDelegate {
  let onSelect = EventDispatcher()

  private let tabBar = SizedTabBar()
  private var isProgrammaticSelection = false
  private var pendingItems: [[String: String]] = []

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

    configureTypography()
  }

  // A standalone UITabBar's actual rendered row height (not just the frame
  // Auto Layout gives it) tracks its content's needed size — the same
  // mechanism that grows the system bar under larger Dynamic Type sizes —
  // not the `intrinsicContentSize`/`sizeThatFits` overrides above, which
  // only affect what UIKit *thinks* the bar wants when something else asks.
  // So the real lever for a taller floating pill is bigger item content:
  // larger icons and a slightly larger title font, both through the
  // documented `UITabBarAppearance` typography path — never the
  // background/blur/shadow properties on it, which would fight the system
  // Liquid Glass material.
  private func configureTypography() {
    let appearance = UITabBarAppearance()
    let titleFont: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium)]
    let selectedTitleFont: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = titleFont
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedTitleFont
    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }
  }

  private static let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 25, weight: .medium)

  func setItems(_ items: [[String: String]]) {
    pendingItems = items
    tabBar.items = items.enumerated().map { index, item in
      let image = UIImage(systemName: item["symbol"] ?? "circle", withConfiguration: Self.iconConfiguration)
      let tabItem = UITabBarItem(title: item["label"], image: image, tag: index)
      tabItem.accessibilityIdentifier = item["url"]
      return tabItem
    }
    applySelection(currentSelectedIndex, animated: false)
  }

  private var currentSelectedIndex = 0

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
