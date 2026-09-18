import ActivityKit
import SwiftUI
import WidgetKit

struct DatebookLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DatebookLiveAttributes.self) { context in
      lockView(context.state)
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.kind == "class" ? "Class" : "Focus")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title).font(.headline).lineLimit(2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary)
          if context.state.end > 0 {
            ProgressView(timerInterval: Date(timeIntervalSince1970: context.state.start / 1000)...Date(timeIntervalSince1970: context.state.end / 1000), countsDown: true)
              .tint(Color(hex: context.state.color))
          }
        }
      } compactLeading: {
        Image(systemName: context.state.kind == "class" ? "graduationcap" : "timer")
      } compactTrailing: {
        if context.state.end > 0 {
          Text(timerText(context.state)).monospacedDigit().font(.caption.weight(.semibold))
        }
      } minimal: {
        Image(systemName: context.state.kind == "class" ? "graduationcap" : "timer")
      }
    }
  }

  @ViewBuilder
  func lockView(_ state: DatebookLiveAttributes.ContentState) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(state.kind == "class" ? (state.running ? "In class" : "Class soon") : (state.running ? "Focus" : "Paused"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(state.title).font(.headline)
      Text(state.subtitle).font(.subheadline).foregroundStyle(.secondary)
      if state.end > 0 {
        ProgressView(timerInterval: Date(timeIntervalSince1970: state.start / 1000)...Date(timeIntervalSince1970: state.end / 1000), countsDown: true)
          .tint(Color(hex: state.color))
      }
    }
  }

  func timerText(_ state: DatebookLiveAttributes.ContentState) -> String {
    let remaining = max(0, state.end / 1000 - Date().timeIntervalSince1970)
    let m = Int(remaining) / 60
    return "\(m)m"
  }
}
