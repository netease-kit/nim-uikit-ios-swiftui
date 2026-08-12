// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct BotSubSessionRowState: Identifiable, Equatable {
  public var id: String
  public var topic: V2NIMTopic
  public var title: String
  public var summary: String
  public var updateTime: TimeInterval
  public var hasSummary: Bool
  public var latestMessageFromSelf: Bool
  public var hasUnread: Bool

  public init(id: String,
              topic: V2NIMTopic,
              title: String,
              summary: String = "",
              updateTime: TimeInterval = 0,
              hasSummary: Bool = false,
              latestMessageFromSelf: Bool = false,
              hasUnread: Bool = false) {
    self.id = id
    self.topic = topic
    self.title = title
    self.summary = summary
    self.updateTime = updateTime
    self.hasSummary = hasSummary
    self.latestMessageFromSelf = latestMessageFromSelf
    self.hasUnread = hasUnread
  }

  public static func == (lhs: BotSubSessionRowState, rhs: BotSubSessionRowState) -> Bool {
    lhs.id == rhs.id &&
      lhs.title == rhs.title &&
      lhs.summary == rhs.summary &&
      lhs.updateTime == rhs.updateTime &&
      lhs.hasSummary == rhs.hasSummary &&
      lhs.latestMessageFromSelf == rhs.latestMessageFromSelf &&
      lhs.hasUnread == rhs.hasUnread
  }
}

extension BotSubSessionRowState {
  var botSubSessionSummary: NEBotSubSessionSummary? {
    guard hasSummary else {
      return nil
    }
    return NEBotSubSessionSummary(
      text: summary,
      updateTime: updateTime,
      latestMessageFromSelf: latestMessageFromSelf
    )
  }
}

public struct BotSubSessionRenameState: Identifiable, Equatable {
  public var id: String
  public var row: BotSubSessionRowState
  public var name: String
  public var error: String?
  public var isSaving: Bool

  public init(row: BotSubSessionRowState,
              name: String,
              error: String? = nil,
              isSaving: Bool = false) {
    id = "rename:\(row.id)"
    self.row = row
    self.name = name
    self.error = error
    self.isSaving = isSaving
  }
}

public struct BotSubSessionDeleteState: Equatable {
  public var row: BotSubSessionRowState
  public var isDeleting: Bool

  public init(row: BotSubSessionRowState,
              isDeleting: Bool = false) {
    self.row = row
    self.isDeleting = isDeleting
  }
}
