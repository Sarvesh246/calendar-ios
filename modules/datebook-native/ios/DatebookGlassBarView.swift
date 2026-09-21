import ExpoModulesCore
import UIKit

/// The top-right cluster (Ask / Search / Filters / Schedule / Settings) as
/// one shared glass pill hosting several *independent* actions — not a
/// `UITabBar`/`UIToolbar`, since these aren't mutually-exclusive tab
/// selections and a toolbar reads as real navigation chrome, which this
/// deliberately isn't. Same reasoning as `DatebookGlassButtonView`: on
/// iOS 26+ every button gets a real `UIButton.Configuration.glass()`, so
/// press, refraction and release are system behavior — nothing here fakes
/// it with an RN `Animated` scale or a plain tinted `View`. Older iOS shares
/// one translucent backdrop behind plain system buttons, same fallback
/// shape as the other native controls in this module.
public class DatebookGlassBarView: ExpoView {
  let onPress = EventDispatcher()

  private final class Slot {
    let button: UIButton
    let badge: UIView
    let widthConstraint: NSLayoutConstraint
    var active = false
    var accent = false

    init(button: UIButton, badge: UIView, widthConstraint: NSLayoutConstraint) {
      self.button = button
      self.badge = badge
      self.widthConstraint = widthConstraint
    }
  }

  private let stack = UIStackView()
  private var slots: [String: Slot] = [:]
  private var order: [String] = []
  private var fallbackBackdrop: UIVisualEffectView?
  private var tintHex: String?

  private static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
  private static let itemSize: CGFloat = 42

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = false

    if #available(iOS 26.0, *) {
      // Every button below carries its own real glass configuration; no
      // extra backdrop is needed on this path (matches DatebookGlassButtonView).
    } else {
      let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      backdrop.translatesAutoresizingMaskIntoConstraints = false
      backdrop.isUserInteractionEnabled = false
      backdrop.clipsToBounds = true
      addSubview(backdrop)
      fallbackBackdrop = backdrop
      NSLayoutConstraint.activate([
        backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
        backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        backdrop.topAnchor.constraint(equalTo: topAnchor),
        backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    stack.axis = .horizontal
    stack.alignment = .center
    stack.distribution = .fill
    stack.spacing = 1
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
    ])
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    fallbackBackdrop?.layer.cornerRadius = bounds.height / 2
    layer.cornerRadius = bounds.height / 2
    for (_, slot) in slots {
      slot.badge.layer.cornerRadius = slot.badge.bounds.height / 2
    }
  }

  func setItems(_ items: [[String: String]]) {
    let incomingIds = items.compactMap { $0["id"] }
    if incomingIds != order {
      rebuild(items: items)
    } else {
      for item in items { updateState(item) }
    }
  }

  func setTint(_ hex: String?) {
    tintHex = hex
    for id in order { refreshAppearance(id) }
  }

  func setDisabled(_ disabled: Bool) {
    isUserInteractionEnabled = !disabled
    alpha = disabled ? 0.4 : 1
  }

  /// Datebook's own resolved in-app theme, not the phone's Dark Mode
  /// setting — same reasoning as the tab bar and "+" button.
  func setInterfaceStyle(_ style: String?) {
    switch style {
    case "light":
      overrideUserInterfaceStyle = .light
    case "dark":
      overrideUserInterfaceStyle = .dark
    default:
      overrideUserInterfaceStyle = .unspecified
    }
    for id in order { refreshAppearance(id) }
  }

  private func rebuild(items: [[String: String]]) {
    for view in stack.arrangedSubviews {
      stack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    slots.removeAll()
    order.removeAll()

    for item in items {
      guard let id = item["id"] else { continue }

      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.accessibilityIdentifier = id
      button.accessibilityLabel = item["label"]
      button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)

      let badge = UIView()
      badge.translatesAutoresizingMaskIntoConstraints = false
      badge.isUserInteractionEnabled = false
      badge.isHidden = true

      let container = UIView()
      container.translatesAutoresizingMaskIntoConstraints = false
      container.clipsToBounds = true
      container.addSubview(button)
      container.addSubview(badge)

      let widthConstraint = container.widthAnchor.constraint(equalToConstant: Self.itemSize)
      NSLayoutConstraint.activate([
        widthConstraint,
        container.heightAnchor.constraint(equalToConstant: Self.itemSize),
        button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        button.topAnchor.constraint(equalTo: container.topAnchor),
        button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        badge.widthAnchor.constraint(equalToConstant: 6),
        badge.heightAnchor.constraint(equalToConstant: 6),
        badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
        badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
      ])

      stack.addArrangedSubview(container)
      slots[id] = Slot(button: button, badge: badge, widthConstraint: widthConstraint)
      order.append(id)
      updateState(item)
    }
  }

  private func updateState(_ item: [String: String]) {
    guard let id = item["id"], let slot = slots[id] else { return }
    slot.button.setImage(
      UIImage(systemName: item["symbol"] ?? "circle", withConfiguration: Self.symbolConfiguration),
      for: .normal
    )
    slot.active = item["active"] == "1"
    slot.accent = item["accent"] == "1"
    slot.badge.isHidden = item["badge"] != "1"
    applyGlass(slot)

    let visible = item["visible"] != "0"
    let targetWidth: CGFloat = visible ? Self.itemSize : 0
    slot.button.isUserInteractionEnabled = visible
    guard slot.widthConstraint.constant != targetWidth else { return }
    slot.widthConstraint.constant = targetWidth
    UIView.animate(
      withDuration: 0.32,
      delay: 0,
      usingSpringWithDamping: 0.86,
      initialSpringVelocity: 0,
      options: [.curveEaseInOut, .allowUserInteraction],
      animations: {
        slot.button.alpha = visible ? 1 : 0
        self.layoutIfNeeded()
      }
    )
  }

  private func refreshAppearance(_ id: String) {
    guard let slot = slots[id] else { return }
    applyGlass(slot)
  }

  private func applyGlass(_ slot: Slot) {
    let highlighted = slot.active || slot.accent
    let neutral = chromeNeutralColor()
    let tint = UIColor(datebookHex: tintHex) ?? .systemBlue

    if #available(iOS 26.0, *) {
      var configuration = UIButton.Configuration.glass()
      configuration.cornerStyle = .capsule
      configuration.baseForegroundColor = highlighted ? tint : neutral
      slot.button.configuration = configuration
    } else {
      slot.button.tintColor = highlighted ? tint : neutral
    }

    slot.badge.backgroundColor = tint
  }

  /// Fixed chrome neutrals, independent of the app theme's own ink tones —
  /// same values as `chromeNeutral()` in `NativeChrome.tsx`. Glass glyphs
  /// need a color that stays legible over whatever content is scrolling
  /// underneath, not a theme tone tuned for a flat card surface.
  private func chromeNeutralColor() -> UIColor {
    traitCollection.userInterfaceStyle == .dark
      ? UIColor(white: 0.96, alpha: 0.86)
      : UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.68)
  }

  @objc private func handleTap(_ sender: UIButton) {
    guard let id = sender.accessibilityIdentifier else { return }
    onPress(["id": id])
  }
}
