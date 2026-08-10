// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

@MainActor
public final class AIRobotEntryViewModel: ObservableObject {
  public static var maxRobotCount = 10

  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [AIRobotRowState] = []
  @Published public var toast: ChatToastState?

  private let robotManager: NEAIRobotManager

  public init(robotManager: NEAIRobotManager = .shared) {
    self.robotManager = robotManager
    rows = robotManager.sortedBots.map(AIRobotRowState.init(bot:))
    phase = rows.isEmpty ? .idle : .loaded
  }

  public func load() {
    if !rows.isEmpty {
      phase = .loaded
    } else {
      phase = .loading
    }

    robotManager.loadAll { [weak self] error in
      Task { @MainActor in
        if let error {
          self?.phase = .failed(
            NEChatErrorMessageMapper.errorState(
              for: error,
              fallbackKey: "ai_robot_load_failed",
              fallbackValue: "Failed to load AI robots"
            )
          )
          self?.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "ai_robot_load_failed",
            fallbackValue: "Failed to load AI robots"
          )
          return
        }
        self?.rows = self?.robotManager.sortedBots.map(AIRobotRowState.init(bot:)) ?? []
        self?.phase = self?.rows.isEmpty == true ? .empty : .loaded
      }
    }
  }

  public var canCreateRobot: Bool {
    rows.count < Self.maxRobotCount
  }

  public var robotCount: Int {
    rows.count
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  public var defaultCreateName: String {
    "Bot_Claw"
  }

  public func createRoute() -> NEChatSwiftUIRoute {
    if !canCreateRobot {
      showCreateLimitToast()
    }
    return .aiRobot(.init(kind: .create, defaultName: defaultCreateName, sourceURL: ContactCreateAIRobotRouter))
  }

  public func showCreateLimitToast() {
    toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("ai_robot_exceed_limit", value: "Robot limit reached. Please select an existing robot or delete one"),
      style: .warning
    )
  }

  public func detailRoute(for row: AIRobotRowState) -> NEChatSwiftUIRoute {
    .aiRobot(.init(kind: .detail, bot: row.bot, sourceURL: ContactAIRobotDetailRouter))
  }

  public func chatCardRoute(for row: AIRobotRowState) -> NEChatSwiftUIRoute {
    .aiRobot(.init(kind: .chatCard, bot: row.bot, sourceURL: ContactRobotChatCardRouter))
  }

  public func configRoute(for row: AIRobotRowState) -> NEChatSwiftUIRoute {
    .aiRobot(.init(kind: .config, bot: row.bot, sourceURL: ContactAIRobotConfigRouter))
  }

  public func botSubSessionRoute(for row: AIRobotRowState) -> NEChatSwiftUIRoute {
    guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(row.bot.accid) else {
      return .unsupported(url: PushBotSubSessionListRouter, reason: "invalid_bot_conversation")
    }
    return .botSubSessionList(
      ChatSessionContext(
        kind: .botSubSession,
        conversationId: conversationId,
        title: row.title,
        sessionId: row.bot.accid,
        sessionName: row.title
      )
    )
  }
}
