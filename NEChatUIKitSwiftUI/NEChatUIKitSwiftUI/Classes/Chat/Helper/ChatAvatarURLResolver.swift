// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI

enum ChatAvatarURLResolver {
  static func url(from value: String?) -> URL? {
    guard let value else {
      return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
      return nil
    }

    if let url = URL(string: trimmedValue),
       let scheme = url.scheme?.lowercased(),
       !scheme.isEmpty {
      switch scheme {
      case "http", "https", "file":
        return url
      default:
        return nil
      }
    }

    return URL(fileURLWithPath: trimmedValue)
  }
}

struct ChatAvatarDisplayInfo: Equatable {
  var accountId: String?
  var displayName: String?
  var avatarURL: URL?
}

enum ChatAvatarDisplayResolver {
  static func displayText(displayName: String?,
                          accountId: String?,
                          defaultText: String = "N") -> String {
    NECommonAvatarDisplayResolver.displayText(
      displayName,
      fallbackID: accountId,
      defaultText: defaultText
    )
  }

  static func initials(displayName: String?,
                       accountId: String?,
                       defaultText: String = "N") -> String {
    NECommonAvatarDisplayResolver.initials(
      displayName: displayName,
      fallbackID: accountId,
      defaultText: defaultText
    )
  }

  static func info(accountId: String?,
                   fallbackName: String? = nil,
                   fallbackAvatarURL: URL? = nil,
                   loadedUser: NEUserWithFriend? = nil,
                   showAlias: Bool = true) -> ChatAvatarDisplayInfo {
    let accountId = nonEmpty(accountId)
    if let accountId,
       let aiUser = NEAIUserManager.shared.getNEUserById(accountId) {
      return ChatAvatarDisplayInfo(
        accountId: accountId,
        displayName: nonEmpty(aiUser.showName()) ?? fallbackName ?? accountId,
        avatarURL: ChatAvatarURLResolver.url(from: aiUser.user?.avatar) ?? fallbackAvatarURL
      )
    }

    let cachedUser = accountId.flatMap { ChatRepo.cachedSwiftUIDisplayUser(accountId: $0) }
    let displayName = nonEmpty(cachedUser?.showName(showAlias)) ??
      nonEmpty(loadedUser?.showName(showAlias)) ??
      nonEmpty(fallbackName) ??
      accountId
    let avatarURL = ChatAvatarURLResolver.url(from: cachedUser?.user?.avatar) ??
      ChatAvatarURLResolver.url(from: loadedUser?.user?.avatar) ??
      fallbackAvatarURL

    return ChatAvatarDisplayInfo(
      accountId: accountId,
      displayName: displayName,
      avatarURL: avatarURL
    )
  }

  static func accountId(from user: NEUserWithFriend) -> String? {
    nonEmpty(user.user?.accountId) ?? nonEmpty(user.friend?.accountId)
  }

  static func nonEmpty(_ value: String?) -> String? {
    let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmedValue.isEmpty ? nil : trimmedValue
  }
}
