// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NECommonTextLimit {
  public static func utf16Count(of text: String) -> Int {
    text.utf16.count
  }

  public static func limitedUTF16(_ text: String, limit: Int?) -> String {
    guard let limit, limit >= 0, text.utf16.count > limit else {
      return text
    }
    var result = ""
    result.reserveCapacity(min(text.utf16.count, limit))
    var count = 0
    for character in text {
      let nextCount = count + character.utf16.count
      guard nextCount <= limit else {
        break
      }
      result.append(character)
      count = nextCount
    }
    return result
  }
}
