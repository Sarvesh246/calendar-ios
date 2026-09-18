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
}

struct ListProvider: TimelineProvider {
  let keyPath: KeyPath<SnapshotFile, [SnapshotRow]?>
  let title: String

  func placeholder(in context: Context) -> ListEntry {
    ListEntry(date: Date(), rows: [SnapshotRow(id: "1", title: "Datebook", subtitle: title, color: "#0A84FF")], title: title)
  }
  func getSnapshot(in context: Context, completion: @escaping (ListEntry) -> Void) {
    completion(entry())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ListEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
  }
  private func entry() -> ListEntry {
    let snap = loadSnapshot()
    return ListEntry(date: Date(), rows: snap[keyPath: keyPath] ?? [], title: title)
  }
}

struct ListWidgetView: View {
  var entry: ListEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if entry.rows.isEmpty {
        Text("Nothing yet")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxHeight: .infinity, alignment: .topLeading)
      } else {
        ForEach(entry.rows.prefix(4), id: \.id) { row in
          HStack(spacing: 8) {
            Circle().fill(Color(hex: row.color)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
              Text(row.title).font(.subheadline.weight(.medium)).lineLimit(1)
              Text(row.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(12)
    .widgetCanvas()
  }
}

extension View {
  @ViewBuilder
  func widgetCanvas() -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(for: .widget) { Color(.systemBackground) }
    } else {
      self.background(Color(.systemBackground))
    }
  }
}

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DatebookToday", provider: ListProvider(keyPath: \.today, title: "Today")) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Today")
    .description("What's on today in Datebook.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct UpNextWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DatebookUpNext", provider: ListProvider(keyPath: \.upNext, title: "Up next")) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Up next")
    .description("The next things on your calendar.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct AssignmentsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DatebookAssignments", provider: ListProvider(keyPath: \.assignments, title: "Assignments")) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Assignments")
    .description("Open work, soonest due first.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct ClassesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DatebookClasses", provider: ListProvider(keyPath: \.classes, title: "Classes")) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Classes")
    .description("Upcoming class meetings.")
    .supportedFamilies([.systemSmall, .systemMedium])
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
