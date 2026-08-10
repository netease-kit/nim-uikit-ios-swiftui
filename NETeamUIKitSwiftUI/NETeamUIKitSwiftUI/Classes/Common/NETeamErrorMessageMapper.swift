// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

enum NETeamErrorMessageMapper {
  static func message(for error: Error,
                      fallbackMessage: String? = nil,
                      teamNotExistMessage: String? = nil) -> String {
    if let userVisibleError = error as? TeamUserVisibleError {
      return userVisibleError.userVisibleMessage
    }

    let nsError = error as NSError
    switch nsError.code {
    case protocolSendFailed, protocolTimeout:
      return networkMessage()
    case noPermissionCode, noPermissionOperationCode, noPermissionInviteCode:
      return noPermissionMessage()
    case teamNotExistCode:
      return teamNotExistMessage ?? Self.teamNotExistMessage()
    case teamMemberLimitExceededCode:
      return teamMemberLimitExceededMessage()
    case joinedTeamLimitExceededCode:
      return joinedTeamLimitExceededMessage()
    default:
      return fallbackMessage ?? failedOperationMessage()
    }
  }

  static func failedOperationMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed")
  }

  static func networkMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.networkError, value: "Network error")
  }

  static func noPermissionMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission")
  }

  static func teamNotExistMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist")
  }

  static func teamMemberLimitExceededMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberLimitExceeded, value: "Team member limit exceeded")
  }

  static func joinedTeamLimitExceededMessage() -> String {
    NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.joinedTeamLimitExceeded, value: "Joined team limit exceeded")
  }
}

enum NETeamNetworkGuard {
  static var allowsNetworkOperation: Bool {
    NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false
  }
}
