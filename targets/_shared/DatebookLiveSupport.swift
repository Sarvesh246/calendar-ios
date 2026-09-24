import ActivityKit
import Foundation
import os

enum DatebookLiveMode: String, Codable, Hashable {
  case day
  case upcoming
  case current
  case focus
  case allClear
  case test
}

/// The one ActivityKit schema compiled into both the containing app target and
/// DatebookWidgets. Keeping it under the Apple target's `_shared` directory is
/// what gives both targets the exact same source and prevents schema drift.
struct DatebookLiveAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var mode: DatebookLiveMode
    var title: String
    var subtitle: String?
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var nextTitle: String?
    var nextDate: Date?
    var remainingItemCount: Int
    var completedItemCount: Int
    var totalItemCount: Int
    var accentHex: String
    var hidesPrivateDetails: Bool
    var deepLink: String
    var lastUpdated: Date
    var isRunning: Bool
  }

  var id: String
}

private struct DatebookLiveSnapshot: Codable {
  var enabled: Bool
  var eligible: Bool
  var eligibilityReason: String
  var mode: DatebookLiveMode
  var title: String
  var subtitle: String?
  var location: String?
  var startDate: Double?
  var endDate: Double?
  var nextTitle: String?
  var nextDate: Double?
  var remainingItemCount: Int
  var completedItemCount: Int
  var totalItemCount: Int
  var accentHex: String
  var hidesPrivateDetails: Bool
  var deepLink: String
  var lastUpdated: Double
  var isRunning: Bool

  var state: DatebookLiveAttributes.ContentState {
    DatebookLiveAttributes.ContentState(
      mode: mode,
      title: String(title.prefix(180)),
      subtitle: subtitle.map { String($0.prefix(180)) },
      location: location.map { String($0.prefix(120)) },
      startDate: startDate.map { Date(timeIntervalSince1970: $0 / 1000) },
      endDate: endDate.map { Date(timeIntervalSince1970: $0 / 1000) },
      nextTitle: nextTitle.map { String($0.prefix(120)) },
      nextDate: nextDate.map { Date(timeIntervalSince1970: $0 / 1000) },
      remainingItemCount: max(0, remainingItemCount),
      completedItemCount: max(0, completedItemCount),
      totalItemCount: max(0, totalItemCount),
      accentHex: accentHex,
      hidesPrivateDetails: hidesPrivateDetails,
      deepLink: deepLink,
      lastUpdated: Date(timeIntervalSince1970: lastUpdated / 1000),
      isRunning: isRunning
    )
  }
}

private struct DatebookLiveOperationResult: Codable {
  var success: Bool
  var code: String
  var message: String
  var activityId: String?
  var activityState: String?
  var activeCount: Int?
  var errorType: String?
  var operation: String?

  var dictionary: [String: Any] {
    var value: [String: Any] = [
      "success": success,
      "code": code,
      "message": message,
    ]
    if let activityId { value["activityId"] = activityId }
    if let activityState { value["activityState"] = activityState }
    if let activeCount { value["activeCount"] = activeCount }
    if let errorType { value["errorType"] = errorType }
    if let operation { value["operation"] = operation }
    return value
  }
}

private let datebookLiveAppGroup = "group.com.sarveshjagtap.datebook"
private let datebookLiveSnapshotKey = "datebook.liveActivity.snapshot"
private let datebookLiveLastResultKey = "datebook.liveActivity.lastResult"

/// What a signer actually embedded, read from `embedded.mobileprovision`.
/// The file is a CMS blob wrapping an XML plist, so the plist is cut out by
/// its markers. This is what tells a free-account re-sign that dropped the App
/// Group apart from a healthy one, which `extensionPresent` cannot.
private func provisioningSummary(for bundleURL: URL) -> [String: Any] {
  let profileURL = bundleURL.appendingPathComponent("embedded.mobileprovision")
  guard let data = try? Data(contentsOf: profileURL) else {
    return ["profile": "missing"]
  }
  guard
    let text = String(data: data, encoding: .isoLatin1),
    let start = text.range(of: "<?xml"),
    let end = text.range(of: "</plist>"),
    let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
    let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any]
  else {
    return ["profile": "unreadable"]
  }
  let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
  var summary: [String: Any] = [
    "profile": "present",
    "applicationIdentifier": entitlements["application-identifier"] as? String ?? "none",
    "appGroups": entitlements["com.apple.security.application-groups"] as? [String] ?? [],
    "teamIdentifier": (plist["TeamIdentifier"] as? [String])?.first ?? "none",
  ]
  if let expiry = plist["ExpirationDate"] as? Date {
    summary["expires"] = ISO8601DateFormatter().string(from: expiry)
  }
  return summary
}

@available(iOS 16.2, *)
actor DatebookLiveManager {
  static let shared = DatebookLiveManager()
  private let logger = Logger(subsystem: "com.sarveshjagtap.datebook", category: "LiveActivity")

  private var defaults: UserDefaults {
    UserDefaults(suiteName: datebookLiveAppGroup) ?? .standard
  }

  private func matchingActivities() -> [Activity<DatebookLiveAttributes>] {
    Activity<DatebookLiveAttributes>.activities.filter { $0.attributes.id.hasPrefix("datebook:") }
  }

  private func stateName(_ state: ActivityState) -> String {
    switch state {
    case .active: return "active"
    case .stale: return "stale"
    case .ended: return "ended"
    case .dismissed: return "dismissed"
    @unknown default: return "unknown"
    }
  }

  private func extensionPresent() -> Bool {
    guard let plugIns = Bundle.main.builtInPlugInsURL else { return false }
    let expected = plugIns.appendingPathComponent("DatebookWidgets.appex", isDirectory: true)
    return FileManager.default.fileExists(atPath: expected.path)
  }

  private func loadSnapshot(_ json: String?) throws -> DatebookLiveSnapshot? {
    let raw: String?
    if let json {
      defaults.set(json, forKey: datebookLiveSnapshotKey)
      raw = json
    } else {
      raw = defaults.string(forKey: datebookLiveSnapshotKey)
    }
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    return try JSONDecoder().decode(DatebookLiveSnapshot.self, from: data)
  }

  private func remember(_ result: DatebookLiveOperationResult) -> [String: Any] {
    if let data = try? JSONEncoder().encode(result) {
      defaults.set(data, forKey: datebookLiveLastResultKey)
    }
    return result.dictionary
  }

  private func lastResult() -> DatebookLiveOperationResult? {
    guard let data = defaults.data(forKey: datebookLiveLastResultKey) else { return nil }
    return try? JSONDecoder().decode(DatebookLiveOperationResult.self, from: data)
  }

  private func failure(_ code: String, operation: String, error: Error) -> [String: Any] {
    let type = String(reflecting: Swift.type(of: error))
    let message = String(error.localizedDescription.prefix(300))
    logger.error("\(operation, privacy: .public) failed [\(type, privacy: .public)]: \(message, privacy: .private)")
    return remember(DatebookLiveOperationResult(
      success: false,
      code: code,
      message: "\(operation) failed: \(message)",
      errorType: type,
      operation: operation
    ))
  }

  private func content(for state: DatebookLiveAttributes.ContentState) -> ActivityContent<DatebookLiveAttributes.ContentState> {
    let boundary: Date
    switch state.mode {
    case .focus, .current, .test:
      boundary = state.endDate ?? Date().addingTimeInterval(30 * 60)
    case .upcoming:
      boundary = state.startDate ?? Date().addingTimeInterval(60 * 60)
    case .day, .allClear:
      boundary = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
    }
    let stale = max(boundary.addingTimeInterval(5 * 60), Date().addingTimeInterval(15 * 60))
    let relevance: Double
    switch state.mode {
    case .focus: relevance = 100
    case .current: relevance = 90
    case .test: relevance = 85
    case .upcoming: relevance = 70
    case .day: relevance = 45
    case .allClear: relevance = 30
    }
    return ActivityContent(state: state, staleDate: stale, relevanceScore: relevance)
  }

  func reconcile(_ json: String?) async -> [String: Any] {
    let snapshot: DatebookLiveSnapshot
    do {
      guard let decoded = try loadSnapshot(json) else {
        return remember(DatebookLiveOperationResult(
          success: false,
          code: "notEligible",
          message: "Waiting for Datebook to publish its first schedule snapshot.",
          activeCount: matchingActivities().count,
          operation: "reconcile"
        ))
      }
      snapshot = decoded
    } catch {
      return failure("unknownError", operation: "reconcile", error: error)
    }

    if !snapshot.enabled || !snapshot.eligible {
      _ = await stopAll(reason: snapshot.eligibilityReason)
      return remember(DatebookLiveOperationResult(
        success: true,
        code: "notEligible",
        message: snapshot.eligibilityReason,
        activeCount: 0,
        operation: "reconcile"
      ))
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return remember(DatebookLiveOperationResult(
        success: false,
        code: "activitiesDisabled",
        message: "Live Activities are disabled for Datebook in iOS Settings.",
        activeCount: matchingActivities().count,
        operation: "reconcile"
      ))
    }
    guard extensionPresent() else {
      return remember(DatebookLiveOperationResult(
        success: false,
        code: "extensionMissing",
        message: "DatebookWidgets.appex is missing from the installed app bundle.",
        activeCount: matchingActivities().count,
        operation: "reconcile"
      ))
    }

    let state = snapshot.state
    let nextContent = content(for: state)
    let activities = matchingActivities()
    let primary = activities.first { $0.attributes.id == "datebook:primary" }
    for duplicate in activities where duplicate.id != primary?.id {
      await duplicate.end(nil, dismissalPolicy: .immediate)
      logger.notice("Ended duplicate Datebook Live Activity")
    }
    if let primary {
      await primary.update(nextContent)
      let observedState = stateName(primary.activityState)
      guard observedState == "active" || observedState == "stale" else {
        return remember(DatebookLiveOperationResult(
          success: false,
          code: "updateFailed",
          message: "ActivityKit moved the activity to \(observedState) during update.",
          activityId: primary.id,
          activityState: observedState,
          activeCount: matchingActivities().count,
          operation: "update"
        ))
      }
      logger.notice("Updated Datebook Live Activity mode \(state.mode.rawValue, privacy: .public)")
      return remember(DatebookLiveOperationResult(
        success: true,
        code: "updated",
        message: "Live Activity updated to \(state.mode.rawValue) mode.",
        activityId: primary.id,
        activityState: stateName(primary.activityState),
        activeCount: 1,
        operation: "update"
      ))
    }

    do {
      let activity = try Activity.request(
        attributes: DatebookLiveAttributes(id: "datebook:primary"),
        content: nextContent,
        pushType: nil
      )
      guard matchingActivities().contains(where: { $0.id == activity.id }) else {
        return remember(DatebookLiveOperationResult(
          success: false,
          code: "requestFailed",
          message: "ActivityKit returned an activity, but it is absent from the active list.",
          activityId: activity.id,
          operation: "start"
        ))
      }
      logger.notice("Started Datebook Live Activity mode \(state.mode.rawValue, privacy: .public)")
      return remember(DatebookLiveOperationResult(
        success: true,
        code: "started",
        message: "Live Activity started in \(state.mode.rawValue) mode.",
        activityId: activity.id,
        activityState: stateName(activity.activityState),
        activeCount: 1,
        operation: "start"
      ))
    } catch {
      return failure("requestFailed", operation: "start", error: error)
    }
  }

  func startTest() async -> [String: Any] {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return remember(DatebookLiveOperationResult(
        success: false,
        code: "activitiesDisabled",
        message: "Live Activities are disabled for Datebook in iOS Settings.",
        activeCount: matchingActivities().count,
        operation: "testStart"
      ))
    }
    guard extensionPresent() else {
      return remember(DatebookLiveOperationResult(
        success: false,
        code: "extensionMissing",
        message: "DatebookWidgets.appex is missing from the installed app bundle.",
        activeCount: matchingActivities().count,
        operation: "testStart"
      ))
    }
    let now = Date()
    let state = DatebookLiveAttributes.ContentState(
      mode: .test,
      title: "Datebook Live Activity",
      subtitle: "Testing Lock Screen presentation",
      location: nil,
      startDate: now,
      endDate: now.addingTimeInterval(15 * 60),
      nextTitle: nil,
      nextDate: nil,
      remainingItemCount: 0,
      completedItemCount: 0,
      totalItemCount: 0,
      accentHex: "#0A84FF",
      hidesPrivateDetails: true,
      deepLink: "datebook://today",
      lastUpdated: now,
      isRunning: true
    )
    let nextContent = content(for: state)
    let activities = matchingActivities()
    if let existing = activities.first {
      for duplicate in activities.dropFirst() {
        await duplicate.end(nil, dismissalPolicy: .immediate)
      }
      await existing.update(nextContent)
      return remember(DatebookLiveOperationResult(
        success: true,
        code: "alreadyRunning",
        message: "The existing Datebook Live Activity now shows deterministic test content.",
        activityId: existing.id,
        activityState: stateName(existing.activityState),
        activeCount: 1,
        operation: "testStart"
      ))
    }
    do {
      let activity = try Activity.request(
        attributes: DatebookLiveAttributes(id: "datebook:primary"),
        content: nextContent,
        pushType: nil
      )
      guard matchingActivities().contains(where: { $0.id == activity.id }) else {
        return remember(DatebookLiveOperationResult(
          success: false,
          code: "requestFailed",
          message: "The test activity was requested but did not appear in ActivityKit's active list.",
          activityId: activity.id,
          operation: "testStart"
        ))
      }
      return remember(DatebookLiveOperationResult(
        success: true,
        code: "started",
        message: "Test Live Activity started and confirmed in ActivityKit.",
        activityId: activity.id,
        activityState: stateName(activity.activityState),
        activeCount: 1,
        operation: "testStart"
      ))
    } catch {
      return failure("requestFailed", operation: "testStart", error: error)
    }
  }

  func stopAll(reason: String = "Stopped by the user.") async -> [String: Any] {
    let activities = matchingActivities()
    for activity in activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    let remaining = matchingActivities().count
    if remaining > 0 {
      return remember(DatebookLiveOperationResult(
        success: false,
        code: "endFailed",
        message: "ActivityKit still reports \(remaining) Datebook activity after stopping.",
        activeCount: remaining,
        operation: "end"
      ))
    }
    return remember(DatebookLiveOperationResult(
      success: true,
      code: "ended",
      message: activities.isEmpty ? "No Datebook Live Activity was running." : reason,
      activeCount: 0,
      operation: "end"
    ))
  }

  func status() -> [String: Any] {
    let activities = matchingActivities()
    let storedSnapshot = try? loadSnapshot(nil)
    let last = lastResult()
    let baseSuccess = last?.success ?? true
    let baseCode = activities.isEmpty
      ? (baseSuccess ? "ready" : (last?.code ?? "unknownError"))
      : "alreadyRunning"
    let baseMessage = activities.isEmpty
      ? (baseSuccess
          ? "ActivityKit is ready. No Datebook activity is currently visible."
          : (last?.message ?? "The last Live Activity operation failed."))
      : "Datebook has \(activities.count) active Live Activity."
    var result: [String: Any] = [
      "success": activities.isEmpty ? baseSuccess : true,
      "code": baseCode,
      "message": baseMessage,
      "supported": true,
      "activitiesEnabled": ActivityAuthorizationInfo().areActivitiesEnabled,
      "activeCount": activities.count,
      "activityIds": activities.map(\.id),
      "activityStates": activities.map { stateName($0.activityState) },
      "extensionPresent": extensionPresent(),
      "scheduleEligible": storedSnapshot?.eligible ?? false,
      "eligibilityReason": storedSnapshot?.eligibilityReason ?? "Waiting for the first schedule snapshot.",
    ]
    result["appGroupContainerAvailable"] =
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: datebookLiveAppGroup) != nil
    var signing: [String: Any] = ["app": provisioningSummary(for: Bundle.main.bundleURL)]
    if let plugIns = Bundle.main.builtInPlugInsURL {
      let appex = plugIns.appendingPathComponent("DatebookWidgets.appex", isDirectory: true)
      var widget = provisioningSummary(for: appex)
      widget["bundleIdentifier"] = Bundle(url: appex)?.bundleIdentifier ?? "unknown"
      signing["widgetExtension"] = widget
    }
    signing["appBundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
    result["signing"] = signing
    if let first = activities.first {
      result["activityId"] = first.id
      result["activityState"] = stateName(first.activityState)
    }
    if !ActivityAuthorizationInfo().areActivitiesEnabled {
      result["success"] = false
      result["code"] = "activitiesDisabled"
      result["message"] = "Live Activities are disabled for Datebook in iOS Settings."
    } else if !extensionPresent() {
      result["success"] = false
      result["code"] = "extensionMissing"
      result["message"] = "DatebookWidgets.appex is missing from the installed app bundle."
    }
    if let last {
      result["lastOperationCode"] = last.code
      result["lastOperationMessage"] = last.message
      result["lastErrorCode"] = last.success ? NSNull() : last.code
      result["lastErrorMessage"] = last.success ? NSNull() : last.message
      if let errorType = last.errorType { result["errorType"] = errorType }
      if let operation = last.operation { result["operation"] = operation }
    }
    return result
  }
}
