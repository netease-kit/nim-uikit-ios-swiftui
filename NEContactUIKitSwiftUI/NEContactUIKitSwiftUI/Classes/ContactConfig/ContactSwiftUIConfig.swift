// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct ContactRouteRequest: Hashable, Identifiable {
  public enum Kind: Hashable {
    case addFriend
    case searchContact
    case validation
    case blackList
    case teamList
    case aiUserList
    case aiRobotList
    case userInfo(accountId: String, isCurrentUser: Bool)
    case team(teamId: String)
    case teamChat(teamId: String, title: String?)
    case chat(accountId: String, title: String?)
  }

  public var id = UUID()
  public var kind: Kind

  public init(kind: Kind) {
    self.kind = kind
  }
}

public struct ContactSelectionContext: Equatable {
  public var title: String
  public var filterAccountIds: Set<String>
  public var limit: Int
  public var allowsAIUsers: Bool
  public var updatesDoneTitleWithCount: Bool
  public var disablesDoneWhenEmpty: Bool

  public init(title: String,
              filterAccountIds: Set<String> = [],
              limit: Int = 10,
              allowsAIUsers: Bool = false,
              updatesDoneTitleWithCount: Bool = true,
              disablesDoneWhenEmpty: Bool = true) {
    self.title = title
    self.filterAccountIds = filterAccountIds
    self.limit = limit
    self.allowsAIUsers = allowsAIUsers
    self.updatesDoneTitleWithCount = updatesDoneTitleWithCount
    self.disablesDoneWhenEmpty = disablesDoneWhenEmpty
  }
}

public struct ContactSelectionResult: Equatable {
  public var accountIds: [String]
  public var names: String

  public init(accountIds: [String], names: String) {
    self.accountIds = accountIds
    self.names = names
  }
}

public struct ContactSwiftUIConfig {
  public var styleMode: ContactStyleMode
  public var title: String?
  public var showTitleBar: Bool
  public var showHeader: Bool
  public var showSearchEntry: Bool
  public var showAddEntry: Bool
  public var showsOnlineStatus: Bool
  public var showsAIUserEntry: Bool
  public var showsAIRobotEntry: Bool
  public var themeTokenProvider: ((ContactStyleMode) -> ContactThemeToken)?
  public var routeHandler: ((ContactRouteRequest) -> Void)?
  public var selectionResultHandler: ((ContactSelectionResult) -> Void)?
  public var currentUserInfoViewProvider: ((ContactThemeToken) -> AnyView)?

  public init(styleMode: ContactStyleMode = .normal,
              title: String? = nil,
              showTitleBar: Bool = true,
              showHeader: Bool = true,
              showSearchEntry: Bool = true,
              showAddEntry: Bool = true,
              showsOnlineStatus: Bool = true,
              showsAIUserEntry: Bool = true,
              showsAIRobotEntry: Bool = true,
              themeTokenProvider: ((ContactStyleMode) -> ContactThemeToken)? = nil,
              routeHandler: ((ContactRouteRequest) -> Void)? = nil,
              selectionResultHandler: ((ContactSelectionResult) -> Void)? = nil,
              currentUserInfoViewProvider: ((ContactThemeToken) -> AnyView)? = nil) {
    self.styleMode = styleMode
    self.title = title
    self.showTitleBar = showTitleBar
    self.showHeader = showHeader
    self.showSearchEntry = showSearchEntry
    self.showAddEntry = showAddEntry
    self.showsOnlineStatus = showsOnlineStatus
    self.showsAIUserEntry = showsAIUserEntry
    self.showsAIRobotEntry = showsAIRobotEntry
    self.themeTokenProvider = themeTokenProvider
    self.routeHandler = routeHandler
    self.selectionResultHandler = selectionResultHandler
    self.currentUserInfoViewProvider = currentUserInfoViewProvider
  }

  public var themeToken: ContactThemeToken {
    themeTokenProvider?(styleMode) ?? (styleMode == .fun ? .fun : .normal)
  }
}

public final class ContactSwiftUIConfigCenter {
  public static let shared = ContactSwiftUIConfigCenter()
  public private(set) var config = ContactSwiftUIConfig()

  private init() {}

  public func update(_ config: ContactSwiftUIConfig) {
    self.config = config
  }
}
