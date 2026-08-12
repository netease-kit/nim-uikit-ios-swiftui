// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NIMSDK

public enum AIRobotRouteKind: String, Equatable {
  case list
  case create
  case chatCard
  case detail
  case config
  case bind
  case nicknameEdit
}

public struct AIRobotRouteState: Identifiable, Equatable {
  public var kind: AIRobotRouteKind
  public var bot: V2NIMUserAIBot?
  public var defaultName: String?
  public var autoBindQrCode: String?
  public var previousBoundAccid: String?
  public var currentName: String?
  public var sourceURL: String?

  public init(kind: AIRobotRouteKind,
              bot: V2NIMUserAIBot? = nil,
              defaultName: String? = nil,
              autoBindQrCode: String? = nil,
              previousBoundAccid: String? = nil,
              currentName: String? = nil,
              sourceURL: String? = nil) {
    self.kind = kind
    self.bot = bot
    self.defaultName = defaultName
    self.autoBindQrCode = autoBindQrCode
    self.previousBoundAccid = previousBoundAccid
    self.currentName = currentName
    self.sourceURL = sourceURL
  }

  public var id: String {
    [
      kind.rawValue,
      bot?.accid ?? "",
      defaultName ?? "",
      autoBindQrCode ?? "",
      previousBoundAccid ?? "",
      currentName ?? "",
    ].joined(separator: ":")
  }

  public static func == (lhs: AIRobotRouteState, rhs: AIRobotRouteState) -> Bool {
    lhs.kind == rhs.kind &&
      lhs.bot?.accid == rhs.bot?.accid &&
      lhs.bot?.name == rhs.bot?.name &&
      lhs.bot?.icon == rhs.bot?.icon &&
      lhs.defaultName == rhs.defaultName &&
      lhs.autoBindQrCode == rhs.autoBindQrCode &&
      lhs.previousBoundAccid == rhs.previousBoundAccid &&
      lhs.currentName == rhs.currentName &&
      lhs.sourceURL == rhs.sourceURL
  }
}

public enum AIRobotAsyncPhase: Equatable {
  case idle
  case loading
  case failed(String)
}

public enum AIRobotFormMode: Equatable {
  case create
  case edit
  case nicknameEdit
}

public struct AIRobotConfigClipboardRequest: Equatable {
  public var configString: String

  public init(configString: String) {
    self.configString = configString
  }
}

public protocol AIRobotConfigClipboardHandling {
  func copyConfig(_ request: AIRobotConfigClipboardRequest,
                  completion: @escaping (Result<ChatToastState?, Error>) -> Void)
}

public struct AIRobotConfigClipboardHandler: AIRobotConfigClipboardHandling {
  private let handler: (AIRobotConfigClipboardRequest, @escaping (Result<ChatToastState?, Error>) -> Void) -> Void

  public init(_ handler: @escaping (AIRobotConfigClipboardRequest, @escaping (Result<ChatToastState?, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func copyConfig(_ request: AIRobotConfigClipboardRequest,
                         completion: @escaping (Result<ChatToastState?, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct AIRobotFormState: Equatable {
  public var mode: AIRobotFormMode
  public var name: String
  public var accid: String
  public var isAccidEditable: Bool
  public var avatarURL: URL?
  public var nameError: String?
  public var accidError: String?

  public init(mode: AIRobotFormMode,
              name: String,
              accid: String,
              isAccidEditable: Bool,
              avatarURL: URL? = nil,
              nameError: String? = nil,
              accidError: String? = nil) {
    self.mode = mode
    self.name = name
    self.accid = accid
    self.isAccidEditable = isAccidEditable
    self.avatarURL = avatarURL
    self.nameError = nameError
    self.accidError = accidError
  }
}

public struct AIRobotInfoFieldState: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var value: String
  public var isSensitive: Bool

  public init(id: String,
              title: String,
              value: String,
              isSensitive: Bool = false) {
    self.id = id
    self.title = title
    self.value = value
    self.isSensitive = isSensitive
  }
}

public struct AIRobotDetailState: Equatable {
  public var route: AIRobotRouteState
  public var title: String
  public var displayName: String
  public var subtitle: String?
  public var avatarURL: URL?
  public var avatarDisplayName: String?
  public var pendingNameEdit: AIRobotFormState?
  public var fields: [AIRobotInfoFieldState]
  public var form: AIRobotFormState?
  public var configString: String?
  public var canChat: Bool
  public var canRefreshToken: Bool
  public var canDelete: Bool
  public var canBind: Bool
  public var phase: AIRobotAsyncPhase
  public var toast: ChatToastState?

  public init(route: AIRobotRouteState,
              title: String,
              displayName: String,
              subtitle: String? = nil,
              avatarURL: URL? = nil,
              avatarDisplayName: String? = nil,
              pendingNameEdit: AIRobotFormState? = nil,
              fields: [AIRobotInfoFieldState] = [],
              form: AIRobotFormState? = nil,
              configString: String? = nil,
              canChat: Bool = false,
              canRefreshToken: Bool = false,
              canDelete: Bool = false,
              canBind: Bool = false,
              phase: AIRobotAsyncPhase = .idle,
              toast: ChatToastState? = nil) {
    self.route = route
    self.title = title
    self.displayName = displayName
    self.subtitle = subtitle
    self.avatarURL = avatarURL
    self.avatarDisplayName = avatarDisplayName
    self.pendingNameEdit = pendingNameEdit
    self.fields = fields
    self.form = form
    self.configString = configString
    self.canChat = canChat
    self.canRefreshToken = canRefreshToken
    self.canDelete = canDelete
    self.canBind = canBind
    self.phase = phase
    self.toast = toast
  }
}

public struct AIRobotRowState: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var avatarURL: URL?
  public var bot: V2NIMUserAIBot

  public init(bot: V2NIMUserAIBot) {
    self.bot = bot
    id = bot.accid
    title = (bot.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? bot.name : bot.accid) ?? bot.accid
    subtitle = bot.accid
    if let icon = bot.icon, !icon.isEmpty {
      avatarURL = URL(string: icon)
    }
  }

  public static func == (lhs: AIRobotRowState, rhs: AIRobotRowState) -> Bool {
    lhs.id == rhs.id &&
      lhs.title == rhs.title &&
      lhs.subtitle == rhs.subtitle &&
      lhs.avatarURL == rhs.avatarURL
  }
}
