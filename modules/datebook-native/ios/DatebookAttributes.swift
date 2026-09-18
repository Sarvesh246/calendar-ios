import ActivityKit
import Foundation

public struct DatebookLiveAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var kind: String
    public var title: String
    public var subtitle: String
    public var start: Double
    public var end: Double
    public var color: String
    public var running: Bool

    public init(kind: String, title: String, subtitle: String, start: Double, end: Double, color: String, running: Bool) {
      self.kind = kind
      self.title = title
      self.subtitle = subtitle
      self.start = start
      self.end = end
      self.color = color
      self.running = running
    }
  }

  public var id: String

  public init(id: String) {
    self.id = id
  }
}
