import ActivityKit
import SwiftUI
import WidgetKit

struct DatebookLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DatebookLiveAttributes.self) { context in
      LiveLockView(state: context.state)
        .padding(14)
        .widgetURL(URL(string: context.state.deepLink))
        .activityBackgroundTint(liveBackground(context.state))
        .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            LiveMark(state: context.state, size: 18)
            Text(liveCaption(context.state))
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .padding(.leading, 2)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title)
            .font(.headline)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.center)
            .layoutPriority(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          LiveCountdown(state: context.state, compact: true)
            .frame(minWidth: 48, alignment: .trailing)
            .padding(.trailing, 2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          ExpandedBottom(state: context.state)
        }
      } compactLeading: {
        LiveMark(state: context.state, size: 13)
      } compactTrailing: {
        LiveCountdown(state: context.state, compact: true)
          .frame(maxWidth: 48)
      } minimal: {
        LiveMark(state: context.state, size: 11)
      }
      .widgetURL(URL(string: context.state.deepLink))
      .keylineTint(Color(hex: context.state.accentHex))
    }
  }
}

private struct LiveMark: View {
  var state: DatebookLiveAttributes.ContentState
  var size: CGFloat
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced

  var body: some View {
    Image(systemName: islandSymbol(state))
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(Color(hex: state.accentHex).opacity(isLuminanceReduced ? 0.72 : 1))
      .widgetAccentable()
      .accessibilityHidden(true)
  }
}

private struct LiveCountdown: View {
  var state: DatebookLiveAttributes.ContentState
  var compact = false

  var body: some View {
    Group {
      if let interval = countdownInterval(state) {
        Text(timerInterval: interval, countsDown: true)
          .monospacedDigit()
      } else if state.mode == .allClear {
        Image(systemName: "checkmark")
      } else if let date = state.startDate {
        Text(date, style: .time)
      } else {
        Text("Today")
      }
    }
    .font(compact ? .caption2.weight(.bold) : .title2.weight(.semibold))
    .foregroundStyle(compact ? Color(hex: state.accentHex) : .primary)
    .minimumScaleFactor(0.65)
    .lineLimit(1)
  }
}

private struct LiveLockView: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    if #available(iOS 18.0, *) {
      LiveLockFamilyView(state: state)
    } else {
      LiveLockFullView(state: state)
    }
  }
}

@available(iOS 18.0, *)
private struct LiveLockFamilyView: View {
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
      VStack(alignment: .leading, spacing: 2) {
        Text(liveCaption(state).uppercased())
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
        Text(state.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 8)
      LiveCountdown(state: state)
        .frame(maxWidth: 88, alignment: .trailing)
    }
  }
}

private struct LiveLockFullView: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        LiveMark(state: state, size: 15)
        Text(liveCaption(state).uppercased())
          .font(.caption2.weight(.bold))
          .tracking(0.45)
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text("Datebook")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
      }

      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(state.title)
            .font(.title3.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .layoutPriority(1)
          SecondaryLine(state: state)
        }
        Spacer(minLength: 4)
        LiveCountdown(state: state)
          .frame(maxWidth: 112, alignment: .trailing)
      }

      if let interval = progressInterval(state) {
        ProgressView(timerInterval: interval, countsDown: true)
          .tint(Color(hex: state.accentHex))
          .accessibilityLabel(state.mode == .focus ? "Focus progress" : "Event progress")
      } else if state.totalItemCount > 0 {
        ProgressView(
          value: Double(state.completedItemCount),
          total: Double(max(1, state.totalItemCount))
        )
        .tint(Color(hex: state.accentHex))
        .accessibilityLabel("Day progress")
      }

      FooterLine(state: state)
    }
  }
}

private struct SecondaryLine: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 5) {
        if let start = state.startDate {
          Text(start, style: .time)
        }
        if let end = state.endDate, state.mode == .current {
          Text("–")
          Text(end, style: .time)
        }
        if let location = state.location, !location.isEmpty {
          Text("·")
          Text(location).lineLimit(1)
        }
      }
      Text(state.subtitle ?? fallbackSubtitle(state))
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }
}

private struct FooterLine: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    HStack(spacing: 5) {
      if let nextTitle = state.nextTitle, let nextDate = state.nextDate {
        Image(systemName: "arrow.right")
          .font(.caption2.weight(.bold))
        Text(nextTitle).lineLimit(1)
        Text("·")
        Text(nextDate, style: .time).lineLimit(1)
      } else if state.mode == .allClear {
        Image(systemName: "checkmark.circle.fill")
        Text("You’re clear for the rest of today")
      } else {
        let count = state.remainingItemCount
        Image(systemName: "list.bullet")
        Text(count == 1 ? "1 item remaining" : "\(count) items remaining")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

private struct ExpandedBottom: View {
  var state: DatebookLiveAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let interval = progressInterval(state) {
        ProgressView(timerInterval: interval, countsDown: true)
          .tint(Color(hex: state.accentHex))
      }
      HStack(spacing: 6) {
        if let location = state.location, !location.isEmpty {
          Image(systemName: "location.fill")
          Text(location).lineLimit(1)
        } else if let nextTitle = state.nextTitle {
          Image(systemName: "arrow.right")
          Text(nextTitle).lineLimit(1)
        } else {
          Image(systemName: state.mode == .allClear ? "checkmark.circle" : "list.bullet")
          Text(state.mode == .allClear ? "Nothing else scheduled" : "\(state.remainingItemCount) remaining")
        }
        Spacer(minLength: 0)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private func islandSymbol(_ state: DatebookLiveAttributes.ContentState) -> String {
  switch state.mode {
  case .focus: return "timer"
  case .current: return "calendar.badge.clock"
  case .upcoming: return "clock.fill"
  case .allClear: return "checkmark.circle.fill"
  case .test: return "waveform.path.ecg"
  case .day: return "calendar"
  }
}

private func liveCaption(_ state: DatebookLiveAttributes.ContentState) -> String {
  switch state.mode {
  case .focus: return state.isRunning ? "Focus" : "Focus paused"
  case .current: return "Happening now"
  case .upcoming: return "Up next"
  case .allClear: return "All clear"
  case .test: return "Live Activity test"
  case .day: return "Your day"
  }
}

private func fallbackSubtitle(_ state: DatebookLiveAttributes.ContentState) -> String {
  switch state.mode {
  case .focus: return state.isRunning ? "Focus in progress" : "Paused"
  case .current: return "Time remaining"
  case .upcoming: return "Starts soon"
  case .allClear: return "Nothing else scheduled today"
  case .test: return "Testing Lock Screen presentation"
  case .day: return "Today at a glance"
  }
}

private func countdownInterval(_ state: DatebookLiveAttributes.ContentState) -> ClosedRange<Date>? {
  let now = Date()
  if state.mode == .upcoming, let start = state.startDate, start > now {
    return now...start
  }
  if (state.mode == .focus || state.mode == .current || state.mode == .test),
     state.isRunning,
     let end = state.endDate,
     end > now {
    return now...end
  }
  return nil
}

private func progressInterval(_ state: DatebookLiveAttributes.ContentState) -> ClosedRange<Date>? {
  guard state.isRunning,
        let start = state.startDate,
        let end = state.endDate,
        end > start,
        end > Date() else { return nil }
  return start...end
}

private func liveBackground(_ state: DatebookLiveAttributes.ContentState) -> Color {
  Color(hex: state.accentHex).opacity(0.12)
}
