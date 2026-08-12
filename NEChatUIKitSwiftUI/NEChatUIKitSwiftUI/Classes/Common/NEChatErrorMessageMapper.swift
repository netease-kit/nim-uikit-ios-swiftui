// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

enum NEChatErrorMessageMapper {
  static func message(for error: Error, fallbackKey: String = "failed_operation", fallbackValue: String = "Operation failed") -> String {
    let code = errorCode(for: error) ?? 0
    if containsTeamNormalMemberChatBanned(error) {
      return NEChatUIKitSwiftUIBundle.localized("team_normal_member_chat_banned", value: "群普通成员禁言")
    }
    switch code {
    case teamMemberChatBanned:
      return NEChatUIKitSwiftUIBundle.localized("team_member_chat_banned", value: "群成员被禁言")
    default:
      break
    }

    if let userVisibleError = error as? ChatUserVisibleError {
      return userVisibleError.userVisibleMessage
    }

    switch code {
    case protocolSendFailed, protocolTimeout:
      return networkMessage()
    case noPermissionCode, noPermissionOperationCode:
      return noPermissionMessage()
    case fileUploadFailed:
      return NEChatUIKitSwiftUIBundle.localized("file_upload_failed", value: "File upload failed")
    case aiMessagesNotExist:
      return NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found")
    default:
      return NEChatUIKitSwiftUIBundle.localized(fallbackKey, value: fallbackValue)
    }
  }

  static func errorState(for error: Error,
                         fallbackKey: String = "failed_operation",
                         fallbackValue: String = "Operation failed") -> NEChatKitErrorState {
    let nsError = error as NSError
    return NEChatKitErrorState(
      code: errorCode(for: error),
      message: message(for: error, fallbackKey: fallbackKey, fallbackValue: fallbackValue),
      underlyingError: nsError
    )
  }

  static func toast(for error: Error,
                    style: ChatToastState.Style = .error,
                    fallbackKey: String = "failed_operation",
                    fallbackValue: String = "Operation failed") -> ChatToastState {
    ChatToastState(
      message: message(for: error, fallbackKey: fallbackKey, fallbackValue: fallbackValue),
      style: style
    )
  }

  static func networkMessage() -> String {
    NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
  }

  static func noPermissionMessage() -> String {
    NEChatUIKitSwiftUIBundle.localized("no_permission_tip", value: "No Permission")
  }

  static func failedOperationMessage() -> String {
    NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
  }

  static func teamMuteToast(for error: Error,
                            style: ChatToastState.Style = .warning) -> ChatToastState? {
    let code = errorCode(for: error) ?? 0
    guard containsTeamNormalMemberChatBanned(error) || code == teamMemberChatBanned else {
      return nil
    }
    return toast(for: error, style: style)
  }

  static func aiMessage(for errorCode: Int) -> String? {
    switch errorCode {
    case failedOperation:
      return NEChatUIKitSwiftUIBundle.localized("parameter_setting_error", value: "Parameter setting error")
    case rateLimitExceeded:
      return NEChatUIKitSwiftUIBundle.localized("rate_limit_exceeded", value: "Rate limit exceeded")
    case userNotExistCode:
      return NEChatUIKitSwiftUIBundle.localized("user_not_exist", value: "User not found")
    case userBannedCode:
      return NEChatUIKitSwiftUIBundle.localized("user_banned", value: "user banned")
    case userChatBannedCode:
      return NEChatUIKitSwiftUIBundle.localized("user_chat_banned", value: "user chat banned")
    case noFriendCode:
      return NEChatUIKitSwiftUIBundle.localized("friend_not_exist", value: "friend not exist")
    case messageHitAntispam1, messageHitAntispam2:
      return NEChatUIKitSwiftUIBundle.localized("message_hit_antispam", value: "message hit antispam")
    case teamMemberNotExist:
      return NEChatUIKitSwiftUIBundle.localized("team_member_not_exist", value: "team member not exist")
    case teamNormalMemberChatBanned:
      return NEChatUIKitSwiftUIBundle.localized("team_normal_member_chat_banned", value: "群普通成员禁言")
    case teamMemberChatBanned:
      return NEChatUIKitSwiftUIBundle.localized("team_member_chat_banned", value: "team member chat banned")
    case notAIAccount:
      return NEChatUIKitSwiftUIBundle.localized("not_ai_account", value: "It's not an AI account.")
    case cannotBlockAIAccount:
      return NEChatUIKitSwiftUIBundle.localized("cannot_blocklist_ai_account", value: "You cannot blocklist an AI account.")
    case aiMessagesDisabled:
      return NEChatUIKitSwiftUIBundle.localized("ai_messages_function_disabled", value: "AI messages function disabled.")
    case aiMessageRequestFailed:
      return NEChatUIKitSwiftUIBundle.localized("failed_request_to_the_LLM", value: "Failed request to the LLM.")
    case aiMessageNotSupport:
      return NEChatUIKitSwiftUIBundle.localized("format_not_supported", value: "Invalid Type")
    default:
      return nil
    }
  }

  static func aiMessage(for errorCode: Int, serverText: String) -> String? {
    if let message = aiMessage(for: errorCode) {
      return message
    }
    guard containsTeamNormalMemberChatBannedDescription(serverText) else {
      return nil
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "team_normal_member_chat_banned",
      value: "群普通成员禁言"
    )
  }

  private static func errorCode(for error: Error) -> Int? {
    if let errorState = error as? NEChatKitErrorState {
      return errorState.code ?? errorState.underlyingError?.code
    }
    return (error as NSError).code
  }

  private static func containsTeamNormalMemberChatBanned(_ error: Error) -> Bool {
    var visited = Set<ObjectIdentifier>()
    return containsTeamNormalMemberChatBanned(error, visited: &visited)
  }

  private static func containsTeamNormalMemberChatBanned(_ error: Error,
                                                         visited: inout Set<ObjectIdentifier>) -> Bool {
    // Some SwiftUI loading/operation paths carry the SDK NSError inside the
    // value-type error state. Inspect that state before bridging it to NSError,
    // otherwise its code and underlying error are lost in the bridge.
    if let errorState = error as? NEChatKitErrorState {
      if errorState.code == teamNormalMemberChatBanned {
        return true
      }
      if let underlyingError = errorState.underlyingError,
         containsTeamNormalMemberChatBanned(underlyingError, visited: &visited) {
        return true
      }
      return containsTeamNormalMemberChatBannedDescription(errorState.message)
    }

    return containsTeamNormalMemberChatBanned(error as NSError, visited: &visited)
  }

  private static func containsTeamNormalMemberChatBanned(_ error: NSError,
                                                         visited: inout Set<ObjectIdentifier>) -> Bool {
    let identifier = ObjectIdentifier(error)
    guard visited.insert(identifier).inserted else {
      return false
    }
    if error.code == teamNormalMemberChatBanned {
      return true
    }

    let descriptions = [error.localizedDescription] + error.userInfo.values.compactMap { $0 as? String }
    if descriptions.contains(where: containsTeamNormalMemberChatBannedDescription) {
      return true
    }

    for value in error.userInfo.values {
      if let underlying = value as? Error,
         containsTeamNormalMemberChatBanned(underlying, visited: &visited) {
        return true
      }
      if let underlyingValues = value as? [Any] {
        for underlyingValue in underlyingValues {
          guard let underlying = underlyingValue as? Error else { continue }
          if containsTeamNormalMemberChatBanned(underlying, visited: &visited) {
            return true
          }
        }
      }
      if let underlyingValues = value as? [AnyHashable: Any] {
        for underlyingValue in underlyingValues.values {
          guard let underlying = underlyingValue as? Error else { continue }
          if containsTeamNormalMemberChatBanned(underlying, visited: &visited) {
            return true
          }
        }
      }
    }
    return false
  }

  private static func containsTeamNormalMemberChatBannedDescription(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .contains("team normal member chat banned")
  }
}
