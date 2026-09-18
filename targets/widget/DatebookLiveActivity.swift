import ActivityKit
import SwiftUI
import WidgetKit

func makeDatebookLiveActivityConfiguration() -> some WidgetConfiguration {
  ActivityConfiguration(for: DatebookLiveAttributes.self) { context in
    LiveLockView(state: context.state)
      .padding(16)
      .activityBackgroundTint(liveTint(context.state))
      .activitySystemActionForegroundColor(.white)
  } dynamicIsland: { context in
    DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        Image(systemName: islandSymbol(context.state))
          .foregroundStyle(Color(hex: context.state.color))
          .padding(.leading, 4)
      }
      DynamicIslandExpandedRegion(.trailing) {
        if let interval = liveInterval(context.state) {
          Text(timerInterval: interval, countsDown: true)
            .monospacedDigit()
            .font(.caption.weight(.semibold))
            .frame(width: 56, alignment: .trailing)
            .padding(.trailing, 4)
        }
      }
      DynamicIslandExpandedRegion(.center) {
        Text(context.state.title)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      DynamicIslandExpandedRegion(.bottom) {
        VStack(alignment: .leading, spacing: 6) {
          Text(liveCaption(context.state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(context.state.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
          if let interval = liveInterval(context.state) {
            ProgressView(timerInterval: interval, countsDown: true)
              .tint(Color(hex: context.state.color))
          }
        }
      }
    } compactLeading: {
      Image(systemName: islandSymbol(context.state))
        .foregroundStyle(Color(hex: context.state.color))
    } compactTrailing: {
      if let interval = liveInterval(context.state) {
        Text(timerInterval: interval, countsDown: true)
          .monospacedDigit()
          .font(.caption2.weight(.semibold))
          .frame(minWidth: 36, alignment: .trailing)
          .foregroundStyle(Color(hex: context.state.color))
      }
    } minimal: {
      Image(systemName: islandSymbol(context.state))
        .foregroundStyle(Color(hex: context.state.color))
    }
  }
}

struct DatebookLiveActivity: Widget {
  var body: some WidgetConfiguration {
    makeDatebookLiveActivityConfiguration()
  }
}

@available(iOS 18.0, *)
struct DatebookLiveActivityModern: Widget {
  var body: some WidgetConfiguration {
    makeDatebookLiveActivityConfiguration()
      .supplementalActivityFamilies([.small])
  }
}

private struct LiveLockView: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    if #available(iOS 18.0, *) {
      LiveLockViewWithFamily(state: state)
    } else {
      LiveLockFullView(state: state)
    }
  }
}

@available(iOS 18.0, *)
private struct LiveLockViewWithFamily: View {
  var state: DatebookLiveAttributes.ContentState
  @Environment(\.activityFamily) private var family

  var body: some View {
    if family == .small {
      LiveLockCompactView(state: state)
    } else {
      LiveLockFullView(state: state)
    }
  }
}

private struct LiveLockCompactView: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: islandSymbol(state))
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color(hex: state.color))
      VStack(alignment: .leading, spacing: 2) {
        Text(liveCaption(state))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(state.title)
          .font(.headline)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if let interval = liveInterval(state) {
        Text(timerInterval: interval, countsDown: true)
          .monospacedDigit()
          .font(.title3.weight(.semibold))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .frame(minWidth: 52, alignment: .trailing)
      }
    }
  }
}

private struct LiveLockFullView: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(liveCaption(state))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Image(systemName: islandSymbol(state))
          .foregroundStyle(Color(hex: state.color))
      }
      Text(state.title).font(.headline)
      Text(state.subtitle).font(.subheadline).foregroundStyle(.secondary)
      if let interval = liveInterval(state) {
        ProgressView(timerInterval: interval, countsDown: true)
          .tint(Color(hex: state.color))
      }
    }
  }
}

private func islandSymbol(_ state: DatebookLiveAttributes.ContentState) -> String {
  state.kind == "class" ? "graduationcap" : "timer"
}

private func liveCaption(_ state: DatebookLiveAttributes.ContentState) -> String {
  if state.kind == "class" {
    return state.running ? "In class" : "Class soon"
  }
  return state.running ? "Focus" : "Paused"
}

private func liveInterval(_ state: DatebookLiveAttributes.ContentState) -> ClosedRange<Date>? {
  guard state.end > 0 else { return nil }
  let start = Date(timeIntervalSince1970: state.start / 1000)
  let end = Date(timeIntervalSince1970: state.end / 1000)
  if end > start { return start...end }
  return start...start.addingTimeInterval(1)
}

private func liveTint(_ state: DatebookLiveAttributes.ContentState) -> Color {
  let brand = Color(hex: state.color)
  if #available(iOS 26.0, *) {
    return brand.opacity(0.22)
  }
  return Color.black.opacity(0.72)
}
