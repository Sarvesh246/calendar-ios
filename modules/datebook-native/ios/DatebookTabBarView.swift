import ExpoModulesCore
import UIKit

/// Structure: a taller outer glass capsule supplies the tray's real height
/// and padding; a fully transparent `UITabBar` sits inside it and supplies
/// everything native — items, selection state, touch handling, tint,
/// accessibility. This exists because a bare `UITabBar`'s own background
/// material renders at a fixed, content-hugging height that does not
/// stretch to fill a larger frame and does not grow with bigger icons or
/// labels either (both tried and confirmed not to work against a real
/// device). `UITabBarController` doesn't change that either — it composes
/// the same `UITabBar` class, so it wouldn't make the bar's own material
/// taller. The outer capsule is a genuine `UIVisualEffectView`, which does
/// stretch to whatever bounds it's given, so it can be the taller surface
/// while the transparent bar keeps every bit of native tab behavior on top
/// of it.
public class DatebookTabBarView: ExpoView, UITabBarDelegate {
  let onSelect = EventDispatcher()

  private let trayGlass: UIVisualEffectView = {
    if #available(iOS 26.0, *) {
      return UIVisualEffectView(effect: UIGlassEffect())
    }
    return UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  }()

  private let tabBar = UITabBar()
  private var isProgrammaticSelection = false
  private var currentSelectedIndex = 0

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    clipsToBounds = false
    trayGlass.translatesAutoresizingMaskIntoConstraints = false
    addSubview(trayGlass)
    NSLayoutConstraint.activate([
      trayGlass.leadingAnchor.constraint(equalTo: leadingAnchor),
      trayGlass.trailingAnchor.constraint(equalTo: trailingAnchor),
      trayGlass.topAnchor.constraint(equalTo: topAnchor),
      trayGlass.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    if #available(iOS 26.0, *) {
      // The new corner API rounds without a hard clip mask, so the
      // interactive selection glass can still visually bulge past the
      // capsule's resting edge while pressed/dragged instead of being cut
      // off. Manual `cornerRadius` + `clipsToBounds` (the pre-26 fallback
      // below) can't do that — clipping is exactly what it is.
      trayGlass.cornerConfiguration = .capsule()
      trayGlass.clipsToBounds = false
    } else {
      trayGlass.clipsToBounds = true
    }

    configureTransparentTabBarBackground()
    tabBar.delegate = self
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.isTranslucent = true
    tabBar.clipsToBounds = false
    trayGlass.contentView.addSubview(tabBar)

    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: trayGlass.contentView.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: trayGlass.contentView.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: trayGlass.contentView.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: trayGlass.contentView.bottomAnchor),
    ])
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    if #unavailable(iOS 26.0) {
      // No `cornerConfiguration` pre-26 — round the fallback blur by hand,
      // which does require clipping (see the `clipsToBounds = true` above).
      trayGlass.layer.cornerRadius = trayGlass.bounds.height / 2
    }
  }

  /// Strips only the bar's own base material/shadow so it doesn't draw a
  /// second, shorter glass capsule on top of `trayGlass` — items, their
  /// selected state, and the system tint are untouched. `configureWith
  /// TransparentBackground()` is the documented starting point for "no
  /// background" (as opposed to leaving `UITabBarAppearance()` at its
  /// opaque-by-default baseline); explicitly zeroing `backgroundEffect`
  /// removes the blur it still applies by default even when transparent.
  private func configureTransparentTabBarBackground() {
    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundColor = .clear
    appearance.backgroundEffect = nil
    appearance.shadowColor = .clear
    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }
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
    trayGlass.alpha = disabled ? 0.4 : 1
  }

  /// Datebook's own resolved in-app theme, not the phone's Dark Mode
  /// setting — this view otherwise inherits `userInterfaceStyle` from the
  /// window, which tracks the device, not the app's selected appearance.
  /// Applied on `self` so it cascades to both `trayGlass`'s material and
  /// `tabBar`'s dynamic colors (`.secondaryLabel` for unselected items)
  /// without touching any other native chrome or system UI. Re-applying
  /// this never resets `selectedItem` or recreates any view.
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
