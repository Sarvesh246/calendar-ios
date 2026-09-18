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
        let existing = Activity<DatebookLiveAttributes>.activities.first { $0.attributes.id == attrs.id }
        if let existing {
          await existing.update(ActivityContent(state: state, staleDate: nil))
        } else {
          _ = try? Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
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
  }
}
