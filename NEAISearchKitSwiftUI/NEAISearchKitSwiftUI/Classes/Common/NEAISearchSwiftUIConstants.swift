// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SwiftUI

enum NEAISearchSwiftUIConstants {
  static let moduleName = "NEAISearchKitSwiftUI"
  static let telemetryComponentName = "AISearchKitSwiftUI"
  static let telemetryLanguage = "swiftui"
  static let pluginVersion = "1.0.0"
  static let operationIconName = "op_ai_word"
  static let expandIconName = "ai_expand"
  static let aiModelTemperature: CGFloat = 0.8
  static let defaultPanelHeight: CGFloat = 406
  static let expandedPanelHeight: CGFloat = 700
  static let darkTextColor = Color(hex: 0x333333)
  static let titleTextColor = Color(hex: 0x333333)
  static let placeholderTextColor = Color(hex: 0xAAAAAA)
  static let titleBarLineColor = Color(hex: 0xE9EFF5)
  static let separatorColor = Color(hex: 0xEDEDED)
  static let inputBackgroundColor = Color(hex: 0xF5F5F5)
  static let actionColor = Color(hex: 0x2155EE)
}

enum NEAISearchLocalizableKey {
  static let operationAIWordSearch = "operation_ai_word_search"
  static let ok = "ok"
  static let complete = "complete"
  static let cancel = "cancel"
  static let aiWordSearch = "ai_word_search"
  static let aiWordSearching = "ai_word_searching"
  static let inputMoreButton = "input_more_button"
  static let inputMorePlaceholder = "input_more_placeholder"
  static let notSupported = "not_supported"
  static let requestException = "request_exception"
  static let networkError = "network_error"
  static let parameterSettingError = "parameter_setting_error"
  static let rateLimitExceeded = "rate_limit_exceeded"
  static let userNotExist = "user_not_exist"
  static let userBanned = "user_banned"
  static let userChatBanned = "user_chat_banned"
  static let friendNotExist = "friend_not_exist"
  static let messageHitAntispam = "message_hit_antispam"
  static let teamMemberNotExist = "team_member_not_exist"
  static let teamNormalMemberChatBanned = "team_normal_member_chat_banned"
  static let teamMemberChatBanned = "team_member_chat_banned"
  static let notAIAccount = "not_ai_account"
  static let cannotBlocklistAIAccount = "cannot_blocklist_ai_account"
  static let aiMessagesFunctionDisabled = "ai_messages_function_disabled"
  static let failedRequestToLLM = "failed_request_to_the_LLM"
}

private extension Color {
  init(hex: Int, opacity: Double = 1.0) {
    self.init(
      .sRGB,
      red: Double((hex & 0xFF0000) >> 16) / 255.0,
      green: Double((hex & 0x00FF00) >> 8) / 255.0,
      blue: Double(hex & 0x0000FF) / 255.0,
      opacity: opacity
    )
  }
}
