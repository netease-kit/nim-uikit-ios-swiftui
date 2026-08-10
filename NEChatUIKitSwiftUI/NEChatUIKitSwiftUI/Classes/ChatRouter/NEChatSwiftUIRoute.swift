// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NIMSDK

public enum NEChatSwiftUIRoute: Identifiable, Equatable, Hashable {
  case p2pChat(ChatSessionContext)
  case teamChat(ChatSessionContext)
  case botSubSessionList(ChatSessionContext)
  case botSubSessionChat(ChatSessionContext)
  case pinMessages(conversationId: String)
  case historySearch(conversationId: String)
  case collectionMessages(conversationId: String)
  case forwardMessages(conversationId: String, messageIds: [String], merged: Bool)
  case readReceipt(messageId: String, conversationId: String)
  case aiRobot(AIRobotRouteState)
  case userSetting(ChatSessionContext)
  case teamSetting(teamId: String, context: ChatSessionContext)
  case userProfile(ChatUserProfileRequest)
  case mediaPreview(ChatMediaPreviewState)
  case filePreview(ChatFilePreviewState)
  case textPreview(ChatTextPreviewState)
  case multiForwardPreview(ChatMultiForwardPreviewState)
  case locationDetail(MessageLocationState)
  case moreAction(ChatMoreAction, ChatSessionContext)
  case unsupported(url: String, reason: String)

  public var id: String {
    switch self {
    case let .p2pChat(context),
         let .teamChat(context),
         let .botSubSessionList(context),
         let .botSubSessionChat(context):
      return context.id
    case let .pinMessages(conversationId):
      return "pin:\(conversationId)"
    case let .historySearch(conversationId):
      return "history:\(conversationId)"
    case let .collectionMessages(conversationId):
      return "collection:\(conversationId)"
    case let .forwardMessages(conversationId, messageIds, merged):
      return "forward:\(conversationId):\(merged):\(messageIds.sorted().joined(separator: ","))"
    case let .readReceipt(messageId, conversationId):
      return "receipt:\(conversationId):\(messageId)"
    case let .aiRobot(state):
      return "aiRobot:\(state.id)"
    case let .userSetting(context):
      return "userSetting:\(context.id)"
    case let .teamSetting(teamId, context):
      return "teamSetting:\(teamId):\(context.id)"
    case let .userProfile(request):
      return "userProfile:\(request.source.rawValue):\(request.accountId):\(request.isRobot)"
    case let .mediaPreview(preview):
      return "media:\(preview.kind.rawValue):\(preview.id)"
    case let .filePreview(preview):
      return "file:\(preview.id):\(preview.file.name)"
    case let .textPreview(preview):
      return preview.id
    case let .multiForwardPreview(preview):
      return preview.id
    case let .locationDetail(location):
      return "location:\(location.latitude ?? 0):\(location.longitude ?? 0):\(location.title)"
    case let .moreAction(action, context):
      return "more:\(action.rawValue):\(context.id)"
    case let .unsupported(url, reason):
      return "unsupported:\(url):\(reason)"
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
