import ExpoModulesCore
import UIKit

/// A native model menu for the assistant. UIKit owns menu presentation,
/// selection state, accessibility and the iOS 26 glass interaction.
public class DatebookModelPickerView: ExpoView {
  let onSelect = EventDispatcher()

  private let button = UIButton(type: .system)
  private var options: [[String: String]] = []
  private var selectedId = "auto"

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = false
    button.translatesAutoresizingMaskIntoConstraints = false
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "Assistant model"
    addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
    rebuild()
  }

  func setOptions(_ next: [[String: String]]) {
    options = next.filter { $0["id"]?.isEmpty == false && $0["label"]?.isEmpty == false }
    rebuild()
  }

  func setSelectedId(_ next: String?) {
    selectedId = next?.isEmpty == false ? next! : "auto"
    rebuild()
  }

  func setInterfaceStyle(_ style: String?) {
    overrideUserInterfaceStyle = style == "light" ? .light : style == "dark" ? .dark : .unspecified
  }

  private func rebuild() {
    let rows = [["id": "auto", "label": "Auto"]] + options
    let selected = rows.first(where: { $0["id"] == selectedId }) ?? rows[0]
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = .glass()
    } else {
      configuration = .bordered()
      configuration.background.backgroundColor = .secondarySystemBackground
    }
    configuration.title = selected["label"] ?? "Auto"
    configuration.image = UIImage(systemName: "chevron.down")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 7
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .label
    button.configuration = configuration
    button.menu = UIMenu(children: rows.map { row in
      let id = row["id"] ?? "auto"
      return UIAction(
        title: row["label"] ?? id,
        state: id == selectedId ? .on : .off
      ) { [weak self] _ in
        self?.selectedId = id
        self?.onSelect(["id": id])
        self?.rebuild()
      }
    })
  }
}
