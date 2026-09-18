import ActivityKit
import Foundation

struct DatebookLiveAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var kind: String
    var title: String
    var subtitle: String
    var start: Double
    var end: Double
    var color: String
    var running: Bool
  }

  var id: String
}
