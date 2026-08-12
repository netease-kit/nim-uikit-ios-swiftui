// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum NEChatSwiftUIRoutePayloadAdapter {
  public static let supportedPatterns = [
    PushP2pChatVCRouter,
    PushTeamChatVCRouter,
    PushBotSubSessionListRouter,
    PushBotSubSessionChatRouter,
    PushPinMessageVCRouter,
    SearchMessageRouter,
    NERouterUrl.LocationVCRouter,
    MeSettingRouter,
    TeamSettingViewRouter,
    ContactUserInfoPageRouter,
    ContactAIRobotListRouter,
    ContactCreateAIRobotRouter,
    ContactRobotChatCardRouter,
    ContactRobotNicknameEditRouter,
    ContactAIRobotDetailRouter,
    ContactAIRobotConfigRouter,
    ContactAIRobotBindRouter,
  ]

  public static func route(for url: String,
                           parameters: [String: Any]? = nil) -> NEChatSwiftUIRoute {
    guard let request = Router.request(for: url, matching: supportedPatterns, parameters: parameters) else {
      return .unsupported(url: url, reason: "route_not_matched")
    }
    return route(for: request)
  }

  public static func route(for request: RouteRequest) -> NEChatSwiftUIRoute {
    guard let url = request.urlString else {
      return .unsupported(url: "", reason: "missing_url")
    }

    switch url {
    case PushP2pChatVCRouter:
      guard let context = chatContext(kind: .p2p, params: request.allParams) else {
        return .unsupported(url: url, reason: "missing_conversation_id")
      }
      return .p2pChat(context)

    case PushTeamChatVCRouter:
      guard let context = chatContext(kind: .team, params: request.allParams) else {
        return .unsupported(url: url, reason: "missing_conversation_id")
      }
      return .teamChat(context)

    case PushBotSubSessionListRouter:
      guard let context = chatContext(kind: .botSubSession, params: request.allParams, requiresSessionId: true) else {
        return .unsupported(url: url, reason: "missing_bot_session")
      }
      return .botSubSessionList(context)

    case PushBotSubSessionChatRouter:
      guard let context = chatContext(kind: .botSubSession, params: request.allParams, requiresSessionId: true) else {
        return .unsupported(url: url, reason: "missing_bot_session")
      }
      return .botSubSessionChat(context)

    case PushPinMessageVCRouter:
      guard let conversationId = request.allParams["conversationId"] as? String, !conversationId.isEmpty else {
        return .unsupported(url: url, reason: "missing_conversation_id")
      }
      return .pinMessages(conversationId: conversationId)

    case SearchMessageRouter:
      guard let conversationId = request.allParams["conversationId"] as? String, !conversationId.isEmpty else {
        return .unsupported(url: url, reason: "missing_conversation_id")
      }
      return .historySearch(conversationId: conversationId)

    case NERouterUrl.LocationVCRouter:
      return .locationDetail(location(from: request.allParams))

    case MeSettingRouter:
      return .userProfile(
        ChatUserProfileRequest(
          accountId: IMKitClient.instance.account(),
          source: .selfAvatar,
          context: emptyUserProfileContext(params: request.allParams)
        )
      )

    case TeamSettingViewRouter:
      guard let teamId = request.allParams["teamid"] as? String ?? request.allParams["teamId"] as? String,
            !teamId.isEmpty else {
        return .unsupported(url: url, reason: "missing_team_id")
      }
      return .teamSetting(
        teamId: teamId,
        context: chatSettingContext(kind: .team, sessionId: teamId, params: request.allParams)
      )

    case ContactUserInfoPageRouter:
      guard let accountId = request.allParams["uid"] as? String, !accountId.isEmpty else {
        return .unsupported(url: url, reason: "missing_user_id")
      }
      return .userProfile(
        ChatUserProfileRequest(
          accountId: accountId,
          source: .contactAvatar,
          isRobot: request.allParams["isRobot"] as? Bool ?? false,
          context: emptyUserProfileContext(params: request.allParams)
        )
      )

    case ContactAIRobotListRouter:
      return .aiRobot(.init(kind: .list, sourceURL: url))

    case ContactCreateAIRobotRouter:
      return .aiRobot(
        .init(
          kind: .create,
          bot: request.allParams["bot"] as? V2NIMUserAIBot,
          defaultName: request.allParams["defaultName"] as? String,
          autoBindQrCode: request.allParams["autoBindQrCode"] as? String,
          sourceURL: url
        )
      )

    case ContactRobotChatCardRouter:
      guard let bot = request.allParams["bot"] as? V2NIMUserAIBot else {
        return .unsupported(url: url, reason: "missing_ai_robot")
      }
      return .aiRobot(.init(kind: .chatCard, bot: bot, sourceURL: url))

    case ContactRobotNicknameEditRouter:
      return .aiRobot(
        .init(
          kind: .nicknameEdit,
          currentName: request.allParams["currentName"] as? String,
          sourceURL: url
        )
      )

    case ContactAIRobotDetailRouter:
      guard let bot = request.allParams["bot"] as? V2NIMUserAIBot else {
        return .unsupported(url: url, reason: "missing_ai_robot")
      }
      return .aiRobot(.init(kind: .detail, bot: bot, sourceURL: url))

    case ContactAIRobotConfigRouter:
      guard let bot = request.allParams["bot"] as? V2NIMUserAIBot else {
        return .unsupported(url: url, reason: "missing_ai_robot")
      }
      return .aiRobot(.init(kind: .config, bot: bot, sourceURL: url))

    case ContactAIRobotBindRouter:
      return .aiRobot(
        .init(
          kind: .bind,
          autoBindQrCode: request.allParams["qrCode"] as? String,
          previousBoundAccid: request.allParams["previousBoundAccid"] as? String,
          sourceURL: url
        )
      )

    default:
      return .unsupported(url: url, reason: "unsupported_chat_route")
    }
  }

  private static func chatContext(kind: ChatSessionKind,
                                  params: [String: Any],
                                  requiresSessionId: Bool = false) -> ChatSessionContext? {
    guard let conversationId = params["conversationId"] as? String, !conversationId.isEmpty else {
      return nil
    }
    let sessionId = params["sessionId"] as? String
    if requiresSessionId, (sessionId?.isEmpty ?? true) {
      return nil
    }

    return ChatSessionContext(
      kind: kind,
      conversationId: conversationId,
      title: params["title"] as? String,
      sessionId: sessionId,
      sessionName: params["sessionName"] as? String,
      anchorMessage: params["anchor"] as? V2NIMMessage,
      pendingMessages: params["onReceiveNewMsgs"] as? [V2NIMMessage] ?? [],
      topic: params["topic"] as? V2NIMTopic
    )
  }

  private static func location(from params: [String: Any]) -> MessageLocationState {
    let latitude = doubleValue(params["lat"])
    let longitude = doubleValue(params["lng"])
    let title = params["locationTitle"] as? String ?? params["title"] as? String ?? ""
    let subtitle = params["subTitle"] as? String ?? params["subtitle"] as? String
    return MessageLocationState(latitude: latitude,
                                longitude: longitude,
                                title: title,
                                subtitle: subtitle)
  }

  private static func emptyUserProfileContext(params: [String: Any]) -> ChatSessionContext {
    ChatSessionContext(
      kind: .p2p,
      conversationId: params["conversationId"] as? String ?? "",
      title: params["title"] as? String,
      sessionId: params["sessionId"] as? String,
      sessionName: params["sessionName"] as? String
    )
  }

  private static func chatSettingContext(kind: ChatSessionKind,
                                         sessionId: String,
                                         params: [String: Any]) -> ChatSessionContext {
    ChatSessionContext(
      kind: kind,
      conversationId: params["conversationId"] as? String ?? "",
      title: params["title"] as? String,
      sessionId: sessionId,
      sessionName: params["sessionName"] as? String
    )
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
      return value
    case let value as Float:
      return Double(value)
    case let value as Int:
      return Double(value)
    case let value as NSNumber:
      return value.doubleValue
    case let value as String:
      return Double(value)
    default:
      return nil
    }
  }
}
