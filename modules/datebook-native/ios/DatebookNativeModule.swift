import AppIntents
import CoreSpotlight
import ExpoModulesCore
import Foundation
import ObjectiveC.runtime
import WidgetKit

let appGroupId = "group.com.sarveshjagtap.datebook"
let snapshotKey = "datebook.snapshot"
let inboxKey = "datebook.inbox"
let liveRequestNotification = Notification.Name("DatebookLiveActivity.Request")

func appGroupDefaults() -> UserDefaults {
  UserDefaults(suiteName: appGroupId) ?? .standard
}

private func callLiveBridge(operation: String, snapshot: String? = nil) async -> [String: Any] {
  guard let bridge = NSClassFromString("DatebookLiveBridge") else {
    return [
      "success": false,
      "code": "unknownError",
      "message": "The app-target Live Activity bridge is missing.",
      "operation": operation,
    ]
  }
  let installSelector = NSSelectorFromString("install")
  guard let method = class_getClassMethod(bridge, installSelector) else {
    return [
      "success": false,
      "code": "unknownError",
      "message": "The app-target Live Activity bridge cannot be initialized.",
      "operation": operation,
    ]
  }
  typealias InstallFunction = @convention(c) (AnyClass, Selector) -> Void
  let install = unsafeBitCast(method_getImplementation(method), to: InstallFunction.self)
  install(bridge, installSelector)
  return await withCheckedContinuation { continuation in
    let completion: ([String: Any]) -> Void = { result in
      continuation.resume(returning: result)
    }
    var userInfo: [String: Any] = ["operation": operation, "completion": completion]
    if let snapshot { userInfo["snapshot"] = snapshot }
    NotificationCenter.default.post(name: liveRequestNotification, object: nil, userInfo: userInfo)
  }
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

    AsyncFunction("getLiveActivityStatus") { () async -> [String: Any] in
      await callLiveBridge(operation: "status")
    }

    AsyncFunction("startTestLiveActivity") { () async -> [String: Any] in
      await callLiveBridge(operation: "testStart")
    }

    AsyncFunction("stopAllLiveActivities") { () async -> [String: Any] in
      await callLiveBridge(operation: "stopAll")
    }

    AsyncFunction("reconcileLiveActivities") { (snapshot: String?) async -> [String: Any] in
      await callLiveBridge(operation: "reconcile", snapshot: snapshot)
    }

    AsyncFunction("updateLive") { (snapshot: String) async -> [String: Any] in
      await callLiveBridge(operation: "reconcile", snapshot: snapshot)
    }

    AsyncFunction("startLive") { (kind: String, id: String, title: String, subtitle: String, start: Double, end: Double, color: String, running: Bool) async -> [String: Any] in
      let mode = kind == "focus" ? "focus" : (running ? "current" : "upcoming")
      let snapshot: [String: Any] = [
        "enabled": true,
        "eligible": true,
        "eligibilityReason": "Legacy Datebook snapshot is eligible.",
        "mode": mode,
        "title": title,
        "subtitle": subtitle,
        "startDate": start,
        "endDate": end,
        "remainingItemCount": 0,
        "completedItemCount": 0,
        "totalItemCount": 0,
        "accentHex": color,
        "hidesPrivateDetails": false,
        "deepLink": "datebook://open?intent=item&item=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)",
        "lastUpdated": Date().timeIntervalSince1970 * 1000,
        "isRunning": running,
      ]
      do {
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
          return ["success": false, "code": "unknownError", "message": "Could not encode legacy Live Activity state."]
        }
        return await callLiveBridge(operation: "reconcile", snapshot: json)
      } catch {
        return [
          "success": false,
          "code": "unknownError",
          "message": "Could not encode legacy Live Activity state: \(error.localizedDescription)",
          "errorType": String(reflecting: Swift.type(of: error)),
        ]
      }
    }

    // Kept as a structured compatibility endpoint for older web deployments.
    AsyncFunction("endLive") { (_: String) async -> [String: Any] in
      await callLiveBridge(operation: "stopAll")
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
      Prop("interfaceStyle") { (view: DatebookTabBarView, style: String?) in
        view.setInterfaceStyle(style)
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
      Prop("interfaceStyle") { (view: DatebookGlassButtonView, style: String?) in
        view.setInterfaceStyle(style)
      }
      Prop("tintColor") { (view: DatebookGlassButtonView, hex: String?) in
        view.setTint(hex)
      }
      Prop("foregroundColor") { (view: DatebookGlassButtonView, hex: String?) in
        view.setForeground(hex)
      }
      Events("onPress")
    }
  }
}
