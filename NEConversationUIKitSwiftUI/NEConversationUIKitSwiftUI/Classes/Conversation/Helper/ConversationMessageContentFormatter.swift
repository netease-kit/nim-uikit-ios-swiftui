// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

enum ConversationMessageContentFormatter {
  static func content(for lastMessage: V2NIMLastMessage?) -> String {
    guard let lastMessage else {
      return ""
    }

    switch lastMessage.messageType {
    case .MESSAGE_TYPE_TEXT:
      return lastMessage.text ?? ""
    case .MESSAGE_TYPE_TIP:
      return localized("tip", value: "[Reminder]")
    case .MESSAGE_TYPE_AUDIO:
      return localized("voice", value: "[Voice]")
    case .MESSAGE_TYPE_IMAGE:
      return localized("picture", value: "[Photo]")
    case .MESSAGE_TYPE_VIDEO:
      return localized("video", value: "[Video]")
    case .MESSAGE_TYPE_LOCATION:
      return localized("location", value: "[Location]") + " \(lastMessage.text ?? "")"
    case .MESSAGE_TYPE_NOTIFICATION:
      return localized("notification", value: "[Tip]")
    case .MESSAGE_TYPE_FILE:
      return localized("file", value: "[File]")
    case .MESSAGE_TYPE_CUSTOM:
      return contentOfCustomMessage(lastMessage.attachment)
    case .MESSAGE_TYPE_CALL:
      if let attachment = lastMessage.attachment as? V2NIMMessageCallAttachment {
        return attachment.type == 1
          ? localized("internet_phone", value: "[Voice Call]")
          : localized("video_chat", value: "[Video Call]")
      }
      return localized("unknown", value: "[Unknown Message]")
    default:
      return localized("unknown", value: "[Unknown Message]")
    }
  }

  private static func contentOfCustomMessage(_ attachment: V2NIMMessageAttachment?) -> String {
    guard let customType = NECustomUtils.typeOfCustomMessage(attachment) else {
      return localized("unknown", value: "[Unknown Message]")
    }
    if customType == customMultiForwardType {
      return localized("chat_history", value: "[Chat History]")
    }
    if customType == customRichTextType,
       let data = NECustomUtils.dataOfCustomMessage(attachment),
       let title = data["title"] as? String {
      return title
    }
    return localized("custom", value: "[Custom Message]")
  }

  private static func localized(_ key: String, value: String) -> String {
    NEConversationUIKitSwiftUIBundle.localized(key, value: value)
  }
}
