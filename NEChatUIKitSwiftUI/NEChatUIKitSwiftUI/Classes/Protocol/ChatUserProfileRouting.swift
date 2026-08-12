// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum ChatUserProfileSource: String, Equatable {
  case selfAvatar
  case contactAvatar
}

public struct ChatUserProfileRequest: Equatable {
  public var accountId: String
  public var displayName: String?
  public var avatarURL: URL?
  public var source: ChatUserProfileSource
  public var isRobot: Bool
  public var message: MessageRowState?
  public var context: ChatSessionContext

  public init(accountId: String,
              displayName: String? = nil,
              avatarURL: URL? = nil,
              source: ChatUserProfileSource,
              isRobot: Bool = false,
              message: MessageRowState? = nil,
              context: ChatSessionContext) {
    self.accountId = accountId
    self.displayName = displayName
    self.avatarURL = avatarURL
    self.source = source
    self.isRobot = isRobot
    self.message = message
    self.context = context
  }
}

public enum ChatUserProfileRouteResult: Equatable {
  case route(NEChatSwiftUIRoute)
  case toast(ChatToastState)
  case handled
}

public protocol ChatUserProfileRouting {
  func openUserProfile(_ request: ChatUserProfileRequest,
                       completion: @escaping (Result<ChatUserProfileRouteResult, Error>) -> Void)
}

public struct ChatUserProfileRouter: ChatUserProfileRouting {
  private let handler: (ChatUserProfileRequest, @escaping (Result<ChatUserProfileRouteResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatUserProfileRequest, @escaping (Result<ChatUserProfileRouteResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func openUserProfile(_ request: ChatUserProfileRequest,
                              completion: @escaping (Result<ChatUserProfileRouteResult, Error>) -> Void) {
    handler(request, completion)
  }
}
