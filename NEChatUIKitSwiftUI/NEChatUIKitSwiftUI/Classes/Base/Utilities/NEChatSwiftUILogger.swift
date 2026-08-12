// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NEChatSwiftUILogger {
  private static let isVerboseEnabled: Bool = {
    #if DEBUG
      return ProcessInfo.processInfo.environment["NE_CHAT_SWIFTUI_DEBUG_LOGS"] == "1"
    #else
      return false
    #endif
  }()

  public static func log(_ message: @autoclosure () -> String) {
    #if DEBUG
      let text = message()
      guard isVerboseEnabled ||
        text.hasPrefix("messageJump") ||
        text.hasPrefix("offlineHistory") else {
        return
      }
      debugPrint("[NEChatUIKitSwiftUI] \(text)")
    #endif
  }
}
