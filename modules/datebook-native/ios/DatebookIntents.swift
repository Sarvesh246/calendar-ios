import AppIntents
import Foundation

@available(iOS 16.0, *)
struct AddToDatebookIntent: AppIntent {
  static var title: LocalizedStringResource = "Add to Datebook"
  static var description = IntentDescription("Create something in Datebook from what you say.")
  static var openAppWhenRun = true

  @Parameter(title: "What to add")
  var text: String

  func perform() async throws -> some IntentResult {
    if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
      DatebookOpenURL.pending = URL(string: "datebook://open?intent=compose&prefill=\(encoded)")
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct StartFocusIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Focus"
  static var openAppWhenRun = true
  func perform() async throws -> some IntentResult {
    DatebookOpenURL.pending = URL(string: "datebook://open?intent=focus")
    return .result()
  }
}

@available(iOS 16.0, *)
struct OpenTodayIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Today in Datebook"
  static var openAppWhenRun = true
  func perform() async throws -> some IntentResult {
    DatebookOpenURL.pending = URL(string: "datebook://open?intent=today")
    return .result()
  }
}

@available(iOS 16.0, *)
struct DatebookShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: AddToDatebookIntent(), phrases: ["Add to \(.applicationName)"], shortTitle: "Add to Datebook", systemImageName: "plus")
    AppShortcut(intent: StartFocusIntent(), phrases: ["Start Focus in \(.applicationName)"], shortTitle: "Start Focus", systemImageName: "timer")
    AppShortcut(intent: OpenTodayIntent(), phrases: ["Open Today in \(.applicationName)"], shortTitle: "Today", systemImageName: "calendar")
  }
}

enum DatebookOpenURL {
  static var pending: URL?
}
