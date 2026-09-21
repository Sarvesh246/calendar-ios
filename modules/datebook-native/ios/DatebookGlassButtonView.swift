import ExpoModulesCore
import UIKit

/// The separate circular "+" control, kept deliberately outside the tab
/// tray. On iOS 26+ this is a real `UIButton` configured with
/// `UIButton.Configuration.glass()` (or `.prominentGlass()` once a tint
/// color is supplied — a deliberate, requested design choice, not reached
/// for out of convenience), so press, stretch, bounce, refraction and
/// release are all system behavior — nothing here animates a transform,
/// opacity or highlight on top of it. Older iOS falls back to a plain
/// system button on a translucent circular background, with the same tint
/// washed into that background so the two paths read consistently.
public class DatebookGlassButtonView: ExpoView {
  let onPress = EventDispatcher()

  private let button = UIButton(type: .system)
  private var fallbackBackground: UIVisualEffectView?
  private var tintHex: String?
  private var foregroundHex: String?

  private static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    clipsToBounds = false
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "Add"
    button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

    if #available(iOS 26.0, *) {
      applyGlassConfiguration()
    } else {
      let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      backdrop.translatesAutoresizingMaskIntoConstraints = false
      backdrop.isUserInteractionEnabled = false
      backdrop.clipsToBounds = true
      addSubview(backdrop)
      fallbackBackground = backdrop
      applyFallbackAppearance()
      NSLayoutConstraint.activate([
        backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
        backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        backdrop.topAnchor.constraint(equalTo: topAnchor),
        backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor),
      // Apple HIG minimum interactive target, independent of the visual size
      // the caller lays this view out at.
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
  }

  @available(iOS 26.0, *)
  private func applyGlassConfiguration() {
    let tint = UIColor(datebookHex: tintHex)
    var configuration = tint != nil ? UIButton.Configuration.prominentGlass() : UIButton.Configuration.glass()
    configuration.image = UIImage(systemName: "plus", withConfiguration: Self.symbolConfiguration)
    configuration.baseForegroundColor = UIColor(datebookHex: foregroundHex) ?? .label
    if let tint {
      configuration.baseBackgroundColor = tint
    }
    configuration.cornerStyle = .capsule
    button.configuration = configuration
  }

  private func applyFallbackAppearance() {
    button.setImage(UIImage(systemName: "plus", withConfiguration: Self.symbolConfiguration), for: .normal)
    button.tintColor = UIColor(datebookHex: foregroundHex) ?? .label
    // No second glass effect pre-26 — just wash the existing blur with a
    // light layer of the accent color so the fallback still reads as
    // "tinted" rather than a flat system gray.
    if let tint = UIColor(datebookHex: tintHex) {
      fallbackBackground?.contentView.backgroundColor = tint.withAlphaComponent(0.22)
    } else {
      fallbackBackground?.contentView.backgroundColor = .clear
    }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    fallbackBackground?.layer.cornerRadius = bounds.height / 2
  }

  func setDisabled(_ disabled: Bool) {
    button.isEnabled = !disabled
    alpha = disabled ? 0.4 : 1
  }

  func setLabel(_ label: String?) {
    button.accessibilityLabel = label?.isEmpty == false ? label : "Add"
  }

  /// A constant accent tint on the glass itself — requested explicitly, so
  /// this is exactly the "design requires a tinted glass background" case
  /// that justifies `.prominentGlass()` over plain `.glass()` on iOS 26+.
  func setTint(_ hex: String?) {
    tintHex = hex
    refreshAppearance()
  }

  /// The icon/label color to read against that tint — Datebook's own
  /// `accentInk` (computed for contrast on the accent color), not a fixed
  /// `.label`, since a colored background needs its own contrasting ink.
  func setForeground(_ hex: String?) {
    foregroundHex = hex
    refreshAppearance()
  }

  private func refreshAppearance() {
    if #available(iOS 26.0, *) {
      applyGlassConfiguration()
    } else {
      applyFallbackAppearance()
    }
  }

  /// Same reasoning as `DatebookTabBarView.setInterfaceStyle`: Datebook's
  /// resolved in-app theme, not the phone's Dark Mode setting, must drive
  /// this button's glass material and dynamic colors.
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

  @objc private func handleTap() {
    onPress([:])
  }
}
