import ActivityKit
import Foundation

/// Must stay in lockstep with `modules/datebook-native/ios/DatebookAttributes.swift`.
/// ActivityKit matches Live Activities by the unqualified attributes type name
/// plus ContentState Codable keys — not by Swift module identity.
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
