// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

enum ConversationTimeFormatter {
  private static let formatterLock = NSLock()
  private static var formatterCache = [String: DateFormatter]()

  static func string(from timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }

    let date = Date(timeIntervalSince1970: timestamp)
    if Calendar.current.isDateInToday(date) {
      return formattedString(from: date, format: "HH:mm")
    }

    let format: String
    if isThisYear(date) {
      format = NEConversationUIKitSwiftUIBundle.localized("mdhm", value: "MM.dd HH:mm")
    } else {
      format = NEConversationUIKitSwiftUIBundle.localized("ymdhm", value: "yyyy.MM.dd HH:mm")
    }
    return formattedString(from: date, format: format)
  }

  private static func formattedString(from date: Date, format: String) -> String {
    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let formatter = formatterCache[format] {
      return formatter.string(from: date)
    }
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatterCache[format] = formatter
    return formatter.string(from: date)
  }

  private static func isThisYear(_ date: Date) -> Bool {
    Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
  }
}
