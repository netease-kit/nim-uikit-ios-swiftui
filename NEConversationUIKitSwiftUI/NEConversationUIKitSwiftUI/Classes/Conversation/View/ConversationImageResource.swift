// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

enum ConversationImageResource {
  static func normal(_ name: String) -> String {
    name
  }

  static func fun(_ name: String) -> String {
    "fun_\(name)"
  }

  static func menuImageName(for action: ConversationAction,
                            style: ConversationStyleMode) -> String {
    switch (action, style) {
    case (.addFriend, .normal): return "add_friend"
    case (.joinTeam, .normal): return "join_team"
    case (.createDiscussion, .normal): return "create_discussion"
    case (.createSeniorTeam, .normal): return "create_group"
    case (.scanQR, .normal): return "scan_qr"
    case (.addFriend, .fun): return "fun_add_friend"
    case (.joinTeam, .fun): return "fun_join_team"
    case (.createDiscussion, .fun): return "fun_create_discussion"
    case (.createSeniorTeam, .fun): return "fun_create_team"
    case (.scanQR, .fun): return "fun_scan_qr"
    }
  }
}
