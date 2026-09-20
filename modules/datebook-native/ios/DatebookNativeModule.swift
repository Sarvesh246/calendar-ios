import ActivityKit
import AppIntents
import CoreSpotlight
import ExpoModulesCore
import Foundation
import WidgetKit

let appGroupId = "group.com.sarveshjagtap.datebook"
let snapshotKey = "datebook.snapshot"
let inboxKey = "datebook.inbox"

func appGroupDefaults() -> UserDefaults {
  UserDefaults(suiteName: appGroupId) ?? .standard
}

public class DatebookNativeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("DatebookNative")

    AsyncFunction("writeSnapshot") { (json: String) in
      appGroupDefaults().set(json, forKey: snapshotKey)
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
    }

    AsyncFunction("indexSpotlight") { (json: String) in
      guard let data = json.data(using: .utf8),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
      let ids = rows.compactMap { $0["id"] as? String }
      CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { _ in
        let items: [CSSearchableItem] = rows.compactMap { row in
          guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
          let attrs = CSSearchableItemAttributeSet(contentType: .content)
          attrs.title = title
          attrs.contentDescription = row["subtitle"] as? String
          attrs.keywords = row["keywords"] as? [String]
          return CSSearchableItem(uniqueIdentifier: "datebook.item.\(id)", domainIdentifier: "com.sarveshjagtap.datebook", attributeSet: attrs)
        }
        CSSearchableIndex.default().indexSearchableItems(items, completionHandler: nil)
      }
    }

    AsyncFunction("startLive") { (kind: String, id: String, title: String, subtitle: String, start: Double, end: Double, color: String, running: Bool) in
      if #available(iOS 16.2, *) {
        let attrs = DatebookLiveAttributes(id: "\(kind):\(id)")
        let state = DatebookLiveAttributes.ContentState(
          kind: kind, title: title, subtitle: subtitle, start: start, end: end, color: color, running: running
        )
        let stale = end > 0 ? Date(timeIntervalSince1970: end / 1000) : Date().addingTimeInterval(8 * 60 * 60)
        let content = ActivityContent(state: state, staleDate: stale, relevanceScore: running ? 100 : 40)
        for activity in Activity<DatebookLiveAttributes>.activities
          where activity.attributes.id.hasPrefix("\(kind):") && activity.attributes.id != attrs.id {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let existing = Activity<DatebookLiveAttributes>.activities.first(where: { $0.attributes.id == attrs.id }) {
          await existing.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
          do {
            _ = try Activity.request(attributes: attrs, content: content, pushType: nil)
          } catch {
            NSLog("Datebook Live Activity request failed: \(error)")
          }
        } else {
          NSLog("Datebook Live Activity skipped: system disabled for this app")
        }
      }
    }

    AsyncFunction("endLive") { (kind: String) in
      if #available(iOS 16.2, *) {
        for activity in Activity<DatebookLiveAttributes>.activities where activity.attributes.id.hasPrefix("\(kind):") {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      }
    }

    Function("readInbox") { () -> String? in
      appGroupDefaults().string(forKey: inboxKey)
    }

    Function("clearInbox") {
      appGroupDefaults().removeObject(forKey: inboxKey)
    }

    // Real UITabBar-backed nav tray. React supplies the items/selection/tint;
    // this view owns nothing about routing, only relays the user's tap.
    View(DatebookTabBarView.self) {
      Prop("items") { (view: DatebookTabBarView, items: [[String: String]]) in
        view.setItems(items)
      }
      Prop("selectedIndex") { (view: DatebookTabBarView, index: Int) in
        view.setSelectedIndex(index)
      }
      Prop("tintColor") { (view: DatebookTabBarView, hex: String?) in
        view.setTint(hex)
      }
      Prop("unselectedTintColor") { (view: DatebookTabBarView, hex: String?) in
        view.setUnselectedTint(hex)
      }
      Prop("disabled") { (view: DatebookTabBarView, disabled: Bool) in
        view.setDisabled(disabled)
      }
      Events("onSelect")
    }

    // The separate circular "+" glass control.
    View(DatebookGlassButtonView.self) {
      Prop("disabled") { (view: DatebookGlassButtonView, disabled: Bool) in
        view.setDisabled(disabled)
      }
      Prop("accessibilityLabel") { (view: DatebookGlassButtonView, label: String?) in
        view.setLabel(label)
      }
      Events("onPress")
    }
  }
}
