// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatUIKitSwiftUI
import SwiftUI

public enum ConversationMode: String, CaseIterable, Identifiable {
  case cloud
  case local

  public var id: String { rawValue }
}

public enum ConversationAction: String, CaseIterable, Identifiable {
  case addFriend
  case joinTeam
  case createDiscussion
  case createSeniorTeam
  case scanQR

  public var id: String { rawValue }
}

public struct ConversationRouteContext: Equatable {
  public var conversationId: String
  public var targetId: String?
  public var kind: ChatSessionKind
  public var title: String?
  public var isRobot: Bool

  public init(conversationId: String,
              targetId: String?,
              kind: ChatSessionKind,
              title: String?,
              isRobot: Bool = false) {
    self.conversationId = conversationId
    self.targetId = targetId
    self.kind = kind
    self.title = title
    self.isRobot = isRobot
  }
}

public struct ConversationBodyTopContentContext: Equatable {
  public var mode: ConversationMode
  public var styleMode: ConversationStyleMode
  public var state: ConversationListState

  public init(mode: ConversationMode,
              styleMode: ConversationStyleMode,
              state: ConversationListState) {
    self.mode = mode
    self.styleMode = styleMode
    self.state = state
  }
}

public struct ConversationSwiftUIConfig {
  public var styleMode: ConversationStyleMode
  public var mode: ConversationMode?
  public var title: String?
  public var showTitleBar: Bool
  public var showTitleBarLeftIcon: Bool
  public var showTitleBarRightIcon: Bool
  public var showTitleBarSearchIcon: Bool
  public var showScanQREntry: Bool
  public var themeToken: ConversationThemeToken
  public var routeHandler: ((ConversationRouteContext) -> Void)?
  public var actionHandler: ((ConversationAction) -> Void)?
  public var searchHandler: (() -> Void)?
  public var qrScanHandler: (() -> Void)?
  public var bodyTopContentProvider: ((ConversationBodyTopContentContext) -> AnyView?)?
  public var onToast: ((String) -> Void)?

  public init(styleMode: ConversationStyleMode = .normal,
              mode: ConversationMode? = nil,
              title: String? = nil,
              showTitleBar: Bool = true,
              showTitleBarLeftIcon: Bool = true,
              showTitleBarRightIcon: Bool = true,
              showTitleBarSearchIcon: Bool = true,
              showScanQREntry: Bool = true,
              themeToken: ConversationThemeToken? = nil,
              routeHandler: ((ConversationRouteContext) -> Void)? = nil,
              actionHandler: ((ConversationAction) -> Void)? = nil,
              searchHandler: (() -> Void)? = nil,
              qrScanHandler: (() -> Void)? = nil,
              bodyTopContentProvider: ((ConversationBodyTopContentContext) -> AnyView?)? = nil,
              onToast: ((String) -> Void)? = nil) {
    self.styleMode = styleMode
    self.mode = mode
    self.title = title
    self.showTitleBar = showTitleBar
    self.showTitleBarLeftIcon = showTitleBarLeftIcon
    self.showTitleBarRightIcon = showTitleBarRightIcon
    self.showTitleBarSearchIcon = showTitleBarSearchIcon
    self.showScanQREntry = showScanQREntry
    self.themeToken = themeToken ?? (styleMode == .fun ? .fun : .normal)
    self.routeHandler = routeHandler
    self.actionHandler = actionHandler
    self.searchHandler = searchHandler
    self.qrScanHandler = qrScanHandler
    self.bodyTopContentProvider = bodyTopContentProvider
    self.onToast = onToast
  }

  public func resolvingStyle(_ style: ConversationStyleMode) -> ConversationSwiftUIConfig {
    var next = self
    next.styleMode = style
    next.themeToken = style == .fun ? .fun : .normal
    return next
  }
}

public final class ConversationSwiftUIConfigCenter {
  public static let shared = ConversationSwiftUIConfigCenter()

  private let lock = NSLock()
  private var config = ConversationSwiftUIConfig()

  private init() {}

  public func update(_ config: ConversationSwiftUIConfig) {
    lock.lock()
    self.config = config
    lock.unlock()
  }

  public func current() -> ConversationSwiftUIConfig {
    lock.lock()
    let value = config
    lock.unlock()
    return value
  }
}
