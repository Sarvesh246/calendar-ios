import SwiftUI
import WidgetKit
import ActivityKit

struct SnapshotRow: Codable {
  var id: String
  var title: String
  var subtitle: String
  var color: String
}

struct SnapshotFile: Codable {
  var today: [SnapshotRow]?
  var upNext: [SnapshotRow]?
  var assignments: [SnapshotRow]?
  var classes: [SnapshotRow]?
}

func loadSnapshot() -> SnapshotFile {
  let defaults = UserDefaults(suiteName: "group.com.sarveshjagtap.datebook")
  guard let raw = defaults?.string(forKey: "datebook.snapshot"),
        let data = raw.data(using: .utf8),
        let file = try? JSONDecoder().decode(SnapshotFile.self, from: data) else {
    return SnapshotFile(today: [], upNext: [], assignments: [], classes: [])
  }
  return file
}

struct ListEntry: TimelineEntry {
  let date: Date
  let rows: [SnapshotRow]
  let title: String
  let deepLink: String
}

struct ListProvider: TimelineProvider {
  let keyPath: KeyPath<SnapshotFile, [SnapshotRow]?>
  let title: String
  let deepLink: String

  func placeholder(in context: Context) -> ListEntry {
    ListEntry(
      date: Date(),
      rows: [SnapshotRow(id: "1", title: "Datebook", subtitle: title, color: "#0A84FF")],
      title: title,
      deepLink: deepLink
    )
  }
  func getSnapshot(in context: Context, completion: @escaping (ListEntry) -> Void) {
    completion(entry())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ListEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
  }
  private func entry() -> ListEntry {
    let snap = loadSnapshot()
    return ListEntry(date: Date(), rows: snap[keyPath: keyPath] ?? [], title: title, deepLink: deepLink)
  }
}

struct ListWidgetView: View {
  var entry: ListEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        circularBody
      case .accessoryInline:
        Text(entry.rows.first?.title ?? entry.title).lineLimit(1)
      case .accessoryRectangular:
        listBody(limit: 2, compact: true)
      case .systemMedium:
        listBody(limit: 5, compact: false)
      default:
        listBody(limit: 3, compact: false)
      }
    }
    .widgetURL(URL(string: entry.deepLink))
    .widgetCanvas(tint: Color(hex: entry.rows.first?.color ?? "#0A84FF"), accessory: isAccessory)
  }

  private var isAccessory: Bool {
    switch family {
    case .accessoryCircular, .accessoryInline, .accessoryRectangular:
      return true
    default:
      return false
    }
  }

  private var circularBody: some View {
    VStack(spacing: 1) {
      Image(systemName: symbolName)
        .font(.caption.weight(.semibold))
        .widgetAccentable()
      Text("\(entry.rows.count)")
        .font(.headline.monospacedDigit())
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
  }

  private var symbolName: String {
    switch entry.title {
    case "Classes": return "graduationcap"
    case "Assignments": return "checklist"
    case "Up next": return "clock"
    default: return "calendar"
    }
  }

  @ViewBuilder
  private func listBody(limit: Int, compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 5 : 8) {
      HStack(spacing: 6) {
        Image(systemName: symbolName)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color(hex: entry.rows.first?.color ?? "#0A84FF"))
          .widgetAccentable()
        Text(entry.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(renderingMode == .accented ? .primary : .secondary)
          .widgetAccentable()
        Spacer(minLength: 0)
      }
      if entry.rows.isEmpty {
        Text(emptyCopy)
          .font(compact ? .caption : .subheadline)
          .foregroundStyle(.secondary)
          .frame(maxHeight: .infinity, alignment: .topLeading)
      } else {
        ForEach(entry.rows.prefix(limit), id: \.id) { row in
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
              .fill(Color(hex: row.color))
              .frame(width: compact ? 5 : 6, height: compact ? 12 : 16)
              .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
              Text(row.title)
                .font(compact ? .caption.weight(.medium) : .subheadline.weight(.semibold))
                .lineLimit(1)
              if !compact || family == .accessoryRectangular {
                Text(row.subtitle)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  private var emptyCopy: String {
    switch entry.title {
    case "Classes": return "No classes soon"
    case "Assignments": return "Nothing due"
    case "Up next": return "You're clear"
    default: return "Nothing on today"
    }
  }
}

extension View {
  /// iOS 17+: removable container background so Home Screen Liquid Glass / tinted
  /// / clear modes can replace it. iOS 16 keeps an opaque fill.
  @ViewBuilder
  func widgetCanvas(tint: Color, accessory: Bool = false) -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(for: .widget) {
        if accessory {
          AccessoryWidgetBackground()
        } else {
          LinearGradient(
            colors: [tint.opacity(0.28), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        }
      }
    } else if accessory {
      self
    } else {
      self
        .padding(12)
        .background(Color(.systemBackground))
    }
  }
}

private let widgetFamilies: [WidgetFamily] = [
  .systemSmall,
  .systemMedium,
  .accessoryCircular,
  .accessoryRectangular,
  .accessoryInline,
]

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "DatebookToday",
      provider: ListProvider(keyPath: \.today, title: "Today", deepLink: "datebook://today")
    ) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Today")
    .description("What's on today in Datebook.")
    .supportedFamilies(widgetFamilies)
  }
}

struct UpNextWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "DatebookUpNext",
      provider: ListProvider(keyPath: \.upNext, title: "Up next", deepLink: "datebook://today")
    ) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Up next")
    .description("The next things on your calendar.")
    .supportedFamilies(widgetFamilies)
  }
}

struct AssignmentsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "DatebookAssignments",
      provider: ListProvider(keyPath: \.assignments, title: "Assignments", deepLink: "datebook://agenda")
    ) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Assignments")
    .description("Open work, soonest due first.")
    .supportedFamilies(widgetFamilies)
  }
}

struct ClassesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "DatebookClasses",
      provider: ListProvider(keyPath: \.classes, title: "Classes", deepLink: "datebook://schedule")
    ) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Classes")
    .description("Upcoming class meetings.")
    .supportedFamilies(widgetFamilies)
  }
}

@main
struct DatebookWidgetBundle: WidgetBundle {
  var body: some Widget {
    TodayWidget()
    UpNextWidget()
    AssignmentsWidget()
    ClassesWidget()
    DatebookLiveActivity()
  }
}

extension Color {
  init(hex: String) {
    var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if h.count == 3 {
      h = h.map { "\($0)\($0)" }.joined()
    }
    var int: UInt64 = 0
    Scanner(string: h).scanHexInt64(&int)
    self.init(
      red: Double((int >> 16) & 0xFF) / 255,
      green: Double((int >> 8) & 0xFF) / 255,
      blue: Double(int & 0xFF) / 255
    )
  }
}
