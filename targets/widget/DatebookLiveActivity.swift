import ActivityKit
import SwiftUI
import WidgetKit

func makeDatebookLiveActivityConfiguration() -> some WidgetConfiguration {
  ActivityConfiguration(for: DatebookLiveAttributes.self) { context in
    LiveLockView(state: context.state)
      .padding(14)
      .activityBackgroundTint(liveTint(context.state))
      .activitySystemActionForegroundColor(.white)
  } dynamicIsland: { context in
    DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        LiveMark(state: context.state, size: 22)
          .padding(.leading, 2)
      }
      DynamicIslandExpandedRegion(.trailing) {
        if let interval = liveInterval(context.state) {
          Text(timerInterval: interval, countsDown: true)
            .monospacedDigit()
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: context.state.color))
            .frame(minWidth: 52, alignment: .trailing)
            .padding(.trailing, 2)
        }
      }
      DynamicIslandExpandedRegion(.center) {
        VStack(spacing: 2) {
          Text(liveCaption(context.state))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(context.state.title)
            .font(.headline)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
      }
      DynamicIslandExpandedRegion(.bottom) {
        VStack(alignment: .leading, spacing: 8) {
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
      LiveMark(state: context.state, size: 14)
    } compactTrailing: {
      if let interval = liveInterval(context.state) {
        Text(timerInterval: interval, countsDown: true)
          .monospacedDigit()
          .font(.caption2.weight(.semibold))
          .frame(minWidth: 36, alignment: .trailing)
          .foregroundStyle(Color(hex: context.state.color))
      } else {
        Text(liveCaption(context.state))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color(hex: context.state.color))
      }
    } minimal: {
      LiveMark(state: context.state, size: 12)
    }
    .keylineTint(Color(hex: context.state.color))
  }
}

struct DatebookLiveActivity: Widget {
  var body: some WidgetConfiguration {
    makeDatebookLiveActivityConfiguration()
  }
}

private struct LiveMark: View {
  var state: DatebookLiveAttributes.ContentState
  var size: CGFloat

  var body: some View {
    Image(systemName: islandSymbol(state))
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(Color(hex: state.color))
      .widgetAccentable()
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
    HStack(spacing: 10) {
      LiveMark(state: state, size: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(liveCaption(state))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(state.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if let interval = liveInterval(state) {
        Text(timerInterval: interval, countsDown: true)
          .monospacedDigit()
          .font(.title3.weight(.semibold))
          .foregroundStyle(Color(hex: state.color))
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
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        LiveMark(state: state, size: 16)
        Text(liveCaption(state))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text("Datebook")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      Text(state.title)
        .font(.title3.weight(.semibold))
        .lineLimit(2)
      Text(state.subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      if let interval = liveInterval(state) {
        ProgressView(timerInterval: interval, countsDown: true)
          .tint(Color(hex: state.color))
      }
    }
  }
}

private func islandSymbol(_ state: DatebookLiveAttributes.ContentState) -> String {
  state.kind == "class" ? "graduationcap.fill" : "timer"
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
  guard end > Date().addingTimeInterval(-1) else { return nil }
  if end > start { return start...end }
  let now = Date()
  if end > now { return now...end }
  return nil
}

private func liveTint(_ state: DatebookLiveAttributes.ContentState) -> Color {
  let brand = Color(hex: state.color)
  if #available(iOS 26.0, *) {
    return brand.opacity(0.28)
  }
  return Color.black.opacity(0.72)
}
