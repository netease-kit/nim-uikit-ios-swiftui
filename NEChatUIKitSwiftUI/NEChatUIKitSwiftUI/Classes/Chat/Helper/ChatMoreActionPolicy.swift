// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum ChatMoreActionPolicy {
  public static func actions(for context: ChatSessionContext,
                             config: ChatSwiftUIConfig) -> [ChatMoreActionState] {
    let sourceActions = config.moreActionsProvider?(context) ?? defaultUIKitMoreActions()
    return sanitize(sourceActions, context: context, config: config)
  }

  public static func action(for id: ChatMoreAction,
                            context: ChatSessionContext,
                            config: ChatSwiftUIConfig) -> ChatMoreActionState? {
    actions(for: context, config: config).first { $0.id == id }
  }

  private static func sanitize(_ actions: [ChatMoreActionState],
                               context: ChatSessionContext,
                               config: ChatSwiftUIConfig) -> [ChatMoreActionState] {
    var sanitized = [ChatMoreActionState]()
    var seenActionIds = Set<String>()

    for action in actions {
      guard !seenActionIds.contains(action.id.rawValue),
            isActionVisible(action.id, context: context, config: config) else {
        continue
      }
      seenActionIds.insert(action.id.rawValue)
      var next = action
      next.isEnabled = action.isEnabled && isActionEnabled(action.id, context: context, config: config)
      sanitized.append(next)
    }

    return sanitized
  }

  private static func defaultUIKitMoreActions() -> [ChatMoreActionState] {
    ChatInputState.defaultMoreActions().filter { $0.id != .location }
  }

  private static func isActionVisible(_ action: ChatMoreAction,
                                      context: ChatSessionContext,
                                      config: ChatSwiftUIConfig) -> Bool {
    switch action {
    case .photo, .takePicture, .file, .location:
      return true
    case .rtc:
      return isRTCActionVisible(context: context, config: config)
    case .translate:
      return isTranslateActionVisible()
    }
  }

  private static func isActionEnabled(_ action: ChatMoreAction,
                                      context: ChatSessionContext,
                                      config: ChatSwiftUIConfig) -> Bool {
    if action == .translate {
      return true
    }
    switch config.nativeBoundaryPolicy.disposition(for: action, context: context) {
    case .deferred:
      return false
    case .internalRoute, .appBoundaryRequired:
      return true
    }
  }

  private static func isTranslateActionVisible() -> Bool {
    guard IMKitConfigCenter.shared.enableAIUser,
          let accountId = NEAIUserManager.shared.getAITranslateUser()?.accountId else {
      return false
    }
    return !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func isRTCActionVisible(context: ChatSessionContext,
                                         config: ChatSwiftUIConfig) -> Bool {
    guard context.kind == .p2p else {
      return false
    }

    let hasSwiftUIHost = config.nativeBoundaryHandler != nil &&
      config.callInteractionHandler != nil
    guard hasSwiftUIHost ||
      NEChatKitClient.instance.isServiceRegistered("NERtcCallUIKit") else {
      return false
    }

    guard let sessionId = targetSessionId(from: context), !sessionId.isEmpty else {
      return false
    }

    if IMKitConfigCenter.shared.enableAIUser,
       NEAIUserManager.shared.isAIUser(sessionId) {
      return false
    }

    return !NEAIRobotManager.shared.isRobot(sessionId)
  }

  private static func targetSessionId(from context: ChatSessionContext) -> String? {
    if let sessionId = context.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !sessionId.isEmpty {
      return sessionId
    }
    return V2NIMConversationIdUtil.conversationTargetId(context.conversationId)
  }
}
