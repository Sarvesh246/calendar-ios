#if DEBUG
import ActivityKit
import SwiftUI
import WidgetKit

private let previewAttributes = DatebookLiveAttributes(id: "datebook:preview")
private let previewNow = Date()

private func previewState(
  mode: DatebookLiveMode,
  title: String,
  subtitle: String,
  start: Date? = nil,
  end: Date? = nil,
  location: String? = nil,
  running: Bool = false
) -> DatebookLiveAttributes.ContentState {
  DatebookLiveAttributes.ContentState(
    mode: mode,
    title: title,
    subtitle: subtitle,
    location: location,
    startDate: start,
    endDate: end,
    nextTitle: mode == .current ? "Study group" : nil,
    nextDate: mode == .current ? previewNow.addingTimeInterval(90 * 60) : nil,
    remainingItemCount: 3,
    completedItemCount: 2,
    totalItemCount: 5,
    accentHex: "#5B6EE1",
    hidesPrivateDetails: false,
    deepLink: "datebook://today",
    lastUpdated: previewNow,
    isRunning: running
  )
}

#Preview("Day overview", as: .content, using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .day,
    title: "Finish the research outline",
    subtitle: "Your day",
    start: previewNow.addingTimeInterval(2 * 60 * 60)
  )
}

#Preview("Upcoming event", as: .content, using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .upcoming,
    title: "MATH 150",
    subtitle: "Up next",
    start: previewNow.addingTimeInterval(38 * 60),
    end: previewNow.addingTimeInterval(88 * 60),
    location: "Blocker 102"
  )
}

#Preview("Current event", as: .content, using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .current,
    title: "Advanced Topics in Mathematical Modeling",
    subtitle: "Happening now",
    start: previewNow.addingTimeInterval(-20 * 60),
    end: previewNow.addingTimeInterval(30 * 60),
    location: "Blocker 102",
    running: true
  )
}

#Preview("Focus session", as: .content, using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .focus,
    title: "Draft literature review",
    subtitle: "Focus in progress",
    start: previewNow.addingTimeInterval(-5 * 60),
    end: previewNow.addingTimeInterval(20 * 60),
    running: true
  )
}

#Preview("All clear", as: .content, using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(mode: .allClear, title: "Nothing else scheduled today", subtitle: "All clear")
}

#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .upcoming,
    title: "MATH 150",
    subtitle: "Up next",
    start: previewNow.addingTimeInterval(38 * 60),
    end: previewNow.addingTimeInterval(88 * 60)
  )
}

#Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .focus,
    title: "Draft literature review",
    subtitle: "Focus in progress",
    start: previewNow.addingTimeInterval(-5 * 60),
    end: previewNow.addingTimeInterval(20 * 60),
    running: true
  )
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
  DatebookLiveActivity()
} contentStates: {
  previewState(
    mode: .current,
    title: "Advanced Topics in Mathematical Modeling",
    subtitle: "Happening now",
    start: previewNow.addingTimeInterval(-20 * 60),
    end: previewNow.addingTimeInterval(30 * 60),
    location: "Blocker 102",
    running: true
  )
}
#endif
