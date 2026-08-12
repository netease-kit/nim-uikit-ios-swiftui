// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum AIWordSearchErrorMapper {
  public static func text(for result: NEAIModelCallResult) -> String {
    switch result.code {
    case operationSuccess:
      return result.text
    case protocolSendFailed, protocolTimeout:
      return localized(NEAISearchLocalizableKey.networkError, fallback: "Network error")
    case failedOperation:
      return localized(NEAISearchLocalizableKey.parameterSettingError, fallback: "Parameter setting error")
    case rateLimitExceeded:
      return localized(NEAISearchLocalizableKey.rateLimitExceeded, fallback: "Rate limit exceeded")
    case userNotExistCode:
      return localized(NEAISearchLocalizableKey.userNotExist, fallback: "User not found")
    case userBannedCode:
      return localized(NEAISearchLocalizableKey.userBanned, fallback: "user banned")
    case userChatBannedCode:
      return localized(NEAISearchLocalizableKey.userChatBanned, fallback: "user chat banned")
    case noFriendCode:
      return localized(NEAISearchLocalizableKey.friendNotExist, fallback: "friend not exist")
    case messageHitAntispam1, messageHitAntispam2:
      return localized(NEAISearchLocalizableKey.messageHitAntispam, fallback: "message hit antispam")
    case teamMemberNotExist:
      return localized(NEAISearchLocalizableKey.teamMemberNotExist, fallback: "team member not exist")
    case teamNormalMemberChatBanned:
      return localized(NEAISearchLocalizableKey.teamNormalMemberChatBanned, fallback: "team normal member chat banned")
    case teamMemberChatBanned:
      return localized(NEAISearchLocalizableKey.teamMemberChatBanned, fallback: "team member chat banned")
    case notAIAccount:
      return localized(NEAISearchLocalizableKey.notAIAccount, fallback: "It's not an AI account.")
    case cannotBlockAIAccount:
      return localized(NEAISearchLocalizableKey.cannotBlocklistAIAccount, fallback: "You cannot blocklist an AI account.")
    case aiMessagesDisabled:
      return localized(NEAISearchLocalizableKey.aiMessagesFunctionDisabled, fallback: "AI messages function disabled.")
    case aiMessageRequestFailed:
      return localized(NEAISearchLocalizableKey.failedRequestToLLM, fallback: "Failed request to the LLM.")
    default:
      return localized(NEAISearchLocalizableKey.requestException, fallback: "Request Exception")
    }
  }

  public static func text(for error: NSError) -> String {
    switch error.code {
    case protocolSendFailed, protocolTimeout:
      return localized(NEAISearchLocalizableKey.networkError, fallback: "Network error")
    case failedOperation:
      return localized(NEAISearchLocalizableKey.parameterSettingError, fallback: "Parameter setting error")
    case rateLimitExceeded:
      return localized(NEAISearchLocalizableKey.rateLimitExceeded, fallback: "Rate limit exceeded")
    case userNotExistCode:
      return localized(NEAISearchLocalizableKey.userNotExist, fallback: "User not found")
    case userBannedCode:
      return localized(NEAISearchLocalizableKey.userBanned, fallback: "user banned")
    case userChatBannedCode:
      return localized(NEAISearchLocalizableKey.userChatBanned, fallback: "user chat banned")
    case noFriendCode:
      return localized(NEAISearchLocalizableKey.friendNotExist, fallback: "friend not exist")
    case messageHitAntispam1, messageHitAntispam2:
      return localized(NEAISearchLocalizableKey.messageHitAntispam, fallback: "message hit antispam")
    case teamMemberNotExist:
      return localized(NEAISearchLocalizableKey.teamMemberNotExist, fallback: "team member not exist")
    case teamNormalMemberChatBanned:
      return localized(NEAISearchLocalizableKey.teamNormalMemberChatBanned, fallback: "team normal member chat banned")
    case teamMemberChatBanned:
      return localized(NEAISearchLocalizableKey.teamMemberChatBanned, fallback: "team member chat banned")
    case notAIAccount:
      return localized(NEAISearchLocalizableKey.notAIAccount, fallback: "It's not an AI account.")
    case cannotBlockAIAccount:
      return localized(NEAISearchLocalizableKey.cannotBlocklistAIAccount, fallback: "You cannot blocklist an AI account.")
    case aiMessagesDisabled:
      return localized(NEAISearchLocalizableKey.aiMessagesFunctionDisabled, fallback: "AI messages function disabled.")
    case aiMessageRequestFailed:
      return localized(NEAISearchLocalizableKey.failedRequestToLLM, fallback: "Failed request to the LLM.")
    default:
      return localized(NEAISearchLocalizableKey.requestException, fallback: "Request Exception")
    }
  }

  public static func isSuccess(_ result: NEAIModelCallResult) -> Bool {
    result.code == operationSuccess
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NEAISearchSwiftUIBundle.localized(key, value: fallback)
  }
}
