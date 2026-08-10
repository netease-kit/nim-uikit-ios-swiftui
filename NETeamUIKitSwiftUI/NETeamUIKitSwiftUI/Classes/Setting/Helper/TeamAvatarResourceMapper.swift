// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum TeamAvatarResourceMapper {
  public static func imageName(for value: String?,
                               style: NETeamSwiftUIStyleMode) -> String {
    if let value,
       let index = defaultIndex(for: value) {
      return imageName(forDefaultIndex: index, style: style)
    }
    return imageName(forDefaultIndex: 0, style: style)
  }

  public static func imageName(forDefaultIndex index: Int,
                               style: NETeamSwiftUIStyleMode) -> String {
    let clampedIndex = max(0, min(4, index))
    return style == .fun ? "fun_icon_\(clampedIndex)" : "icon_\(clampedIndex)"
  }

  public static func defaultIndex(for value: String?) -> Int? {
    guard let value, !value.isEmpty else {
      return nil
    }
    let lowercased = value.lowercased()
    if let range = lowercased.range(of: "groupavatar"),
       let digit = lowercased[range.upperBound...].first(where: { $0.isNumber }),
       let number = Int(String(digit)) {
      return max(0, min(4, number - 1))
    }
    if lowercased.hasPrefix("icon_"),
       let number = Int(lowercased.dropFirst("icon_".count)) {
      return max(0, min(4, number))
    }
    if lowercased.hasPrefix("fun_icon_"),
       let number = Int(lowercased.dropFirst("fun_icon_".count)) {
      return max(0, min(4, number))
    }
    return nil
  }
}
