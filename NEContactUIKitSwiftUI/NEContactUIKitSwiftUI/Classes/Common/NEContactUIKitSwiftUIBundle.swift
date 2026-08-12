// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI

public enum NEContactUIKitSwiftUIBundle {
  public static var bundle: Bundle {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    let candidates: [Bundle] = [
      Bundle(for: NEContactUIKitSwiftUIBundleMarker.self),
      Bundle.main,
    ]

    for candidate in candidates {
      if let url = candidate.url(forResource: "NEContactUIKitSwiftUI", withExtension: "bundle"),
         let bundle = Bundle(url: url) {
        return bundle
      }
      if candidate.url(forResource: "NormalContactUIKitSwiftUI", withExtension: "xcassets") != nil {
        return candidate
      }
    }

    return Bundle(for: NEContactUIKitSwiftUIBundleMarker.self)
    #endif
  }

  public static func localized(_ key: String, value: String? = nil) -> String {
    let fallback = value ?? key
    let missingValue = "__NEContactSwiftUIResourceMissing__"
    for localizedBundle in NEUIKitSwiftUILocalization.localizedBundles(in: bundle) {
      let text = localizedBundle.localizedString(forKey: key, value: missingValue, table: "Localizable")
      if text != missingValue {
        return text
      }
    }
    return fallback
  }
}

private final class NEContactUIKitSwiftUIBundleMarker {}

enum NEContactErrorMessageMapper {
  static func message(for error: Error,
                      fallbackMessage: String? = nil) -> String {
    let nsError = error as NSError
    switch nsError.code {
    case protocolSendFailed, protocolTimeout:
      return networkMessage()
    default:
      return fallbackMessage ?? NECommonUIKitSwiftUIBundle.localized("failed_operation", fallback: "Failure")
    }
  }

  static func networkMessage() -> String {
    NECommonUIKitSwiftUIBundle.localized("network_error", fallback: "No Network")
  }
}

enum NEContactOperationErrorMapper {
  static func message(for error: Error) -> String {
    let nsError = error as NSError
    switch nsError.code {
    case protocolSendFailed, protocolTimeout:
      return NEContactErrorMessageMapper.networkMessage()
    case teamNotExistCode:
      return NEContactUIKitSwiftUIBundle.localized("team_does_not_exist", value: "Team does not exist")
    case teamMemberLimitExceededCode:
      return NEContactUIKitSwiftUIBundle.localized("team_member_limit_exceeded", value: "Team member limit exceeded")
    case joinedTeamLimitExceededCode:
      return NEContactUIKitSwiftUIBundle.localized("joined_team_limit_exceeded", value: "Joined team limit exceeded")
    case alreadyInTeamCode:
      return NEContactUIKitSwiftUIBundle.localized("already_in_the_team", value: "Already in the team")
    case noPermissionCode, noPermissionInviteCode, noPermissionOperationCode:
      return NEContactUIKitSwiftUIBundle.localized("no_permission_tip", value: "No permission")
    case invitationExpiredCode:
      return NEContactUIKitSwiftUIBundle.localized("invitation_expired", value: "Invitation expired")
    default:
      return NEContactUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
    }
  }
}

enum NEContactNetworkGuard {
  static var allowsNetworkOperation: Bool {
    NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false
  }
}
