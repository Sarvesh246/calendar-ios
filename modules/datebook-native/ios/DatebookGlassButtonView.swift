import ExpoModulesCore
import UIKit

/// The separate circular "+" control, kept deliberately outside the tab
/// tray. On iOS 26+ this is a real `UIButton` configured with
/// `UIButton.Configuration.glass()`, so press, stretch, bounce, refraction
/// and release are all system behavior — nothing here animates a transform,
/// opacity or highlight on top of it. Older iOS falls back to a plain
/// system button on a translucent circular background.
public class DatebookGlassButtonView: ExpoView {
  let onPress = EventDispatcher()

  private let button = UIButton(type: .system)
  private var fallbackBackground: UIView?

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    clipsToBounds = false
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "Add"
    button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

    let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
    let image = UIImage(systemName: "plus", withConfiguration: symbolConfig)

    if #available(iOS 26.0, *) {
      var configuration = UIButton.Configuration.glass()
      configuration.image = image
      configuration.baseForegroundColor = .label
      configuration.cornerStyle = .capsule
      button.configuration = configuration
    } else {
      let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      backdrop.translatesAutoresizingMaskIntoConstraints = false
      backdrop.isUserInteractionEnabled = false
      backdrop.clipsToBounds = true
      addSubview(backdrop)
      fallbackBackground = backdrop
      button.setImage(image, for: .normal)
      button.tintColor = .label
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

  /// Same reasoning as `DatebookTabBarView.setInterfaceStyle`: Datebook's
  /// resolved in-app theme, not the phone's Dark Mode setting, must drive
  /// this button's glass material and `.label` foreground.
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
