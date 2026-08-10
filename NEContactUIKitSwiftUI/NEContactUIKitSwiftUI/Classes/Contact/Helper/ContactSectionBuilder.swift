// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum ContactSectionBuilder {
  public static func headerEntries(unreadCount: Int,
                                   config: ContactSwiftUIConfig) -> [ContactEntryState] {
    guard config.showHeader else {
      return []
    }

    var entries: [ContactEntryState] = [
      ContactEntryState(
        id: "header.validation",
        kind: .validation,
        title: NEContactUIKitSwiftUIBundle.localized("validation_message", value: "Verifications"),
        imageName: ContactImageResource.validationMessageName(style: config.styleMode),
        unreadCount: unreadCount
      ),
      ContactEntryState(
        id: "header.blacklist",
        kind: .blackList,
        title: NEContactUIKitSwiftUIBundle.localized("blacklist", value: "Blocklist"),
        imageName: ContactImageResource.blacklistName(style: config.styleMode)
      ),
    ]

    if IMKitConfigCenter.shared.enableTeam {
      entries.append(
        ContactEntryState(
          id: "header.teams",
          kind: .team,
          title: NEContactUIKitSwiftUIBundle.localized("my_teams", value: "My Groups"),
          imageName: ContactImageResource.teamName(style: config.styleMode)
        )
      )
    }

    if config.showsAIRobotEntry {
      entries.append(
        ContactEntryState(
          id: "header.aiRobot",
          kind: .aiRobot,
          title: NEContactUIKitSwiftUIBundle.localized("my_ai_robot", value: "My Robot"),
          imageName: ContactImageResource.aiRobotName(style: config.styleMode)
        )
      )
    }

    if config.showsAIUserEntry, IMKitConfigCenter.shared.enableAIUser {
      entries.append(
        ContactEntryState(
          id: "header.aiUser",
          kind: .aiUser,
          title: NEContactUIKitSwiftUIBundle.localized("my_ai_user", value: "My AI User"),
          imageName: ContactImageResource.aiUserName(style: config.styleMode)
        )
      )
    }

    return entries
  }

  public static func sections(friends: [NEUserWithFriend],
                              unreadCount: Int,
                              onlineStatus: [String: Bool],
                              selectedAccountIds: Set<String> = [],
                              disabledAccountIds: Set<String> = [],
                              config: ContactSwiftUIConfig) -> [ContactSectionState] {
    var sections: [ContactSectionState] = []
    let headers = headerEntries(unreadCount: unreadCount, config: config)
    if !headers.isEmpty {
      sections.append(ContactSectionState(title: "", entries: headers))
    }

    let friendSections = groupedFriendSections(
      friends: friends,
      onlineStatus: onlineStatus,
      selectedAccountIds: selectedAccountIds,
      disabledAccountIds: disabledAccountIds
    )
    sections.append(contentsOf: friendSections)
    return sections
  }

  public static func groupedFriendSections(friends: [NEUserWithFriend],
                                           onlineStatus: [String: Bool],
                                           selectedAccountIds: Set<String>,
                                           disabledAccountIds: Set<String>) -> [ContactSectionState] {
    var dict = [String: [ContactEntryState]]()
    var special = [ContactEntryState]()

    for friend in friends {
      guard let accountId = friend.user?.accountId ?? friend.friend?.accountId,
            !NEFriendUserCache.shared.isBlockAccount(accountId) else {
        continue
      }
      let displayUser = mergedDisplayUser(friend, accountId: accountId)
      let title = displayName(for: displayUser)
      let initial = normalizedInitial(for: title)
      let entry = ContactEntryState(
        id: "friend.\(accountId)",
        kind: .friend,
        accountId: accountId,
        title: title,
        subtitle: accountId,
        avatarURL: avatarURL(for: displayUser, accountId: accountId),
        avatarName: displayUser.showName(false),
        unreadCount: 0,
        isOnline: onlineStatus[accountId] ?? false,
        isSelected: selectedAccountIds.contains(accountId),
        isDisabled: disabledAccountIds.contains(accountId),
        user: displayUser
      )
      if initial == "#" || initial == "0" {
        special.append(entry)
      } else {
        dict[initial, default: []].append(entry)
      }
    }

    var result = dict.keys.sorted().map { key in
      ContactSectionState(
        title: key,
        entries: (dict[key] ?? []).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
      )
    }

    let specialEntries = special.sorted(by: compareSpecialEntries)
    if !specialEntries.isEmpty {
      result.append(ContactSectionState(title: "#", entries: specialEntries))
    }
    return result
  }

  public static func indexTitles(for sections: [ContactSectionState]) -> [String] {
    let az = (UnicodeScalar("A").value ... UnicodeScalar("Z").value)
      .map { String(UnicodeScalar($0)!) }
    return az + ["#"]
  }

  public static func scrollTitle(for indexTitle: String,
                                 sections: [ContactSectionState],
                                 previousTitle: String?) -> String? {
    if sections.contains(where: { $0.title == indexTitle }) {
      return indexTitle
    }
    if let previousTitle,
       sections.contains(where: { $0.title == previousTitle }) {
      return previousTitle
    }
    return sections.first(where: { !$0.title.isEmpty })?.title
  }

  public static func displayName(for user: NEUserWithFriend) -> String {
    user.showName(true) ?? user.user?.accountId ?? user.friend?.accountId ?? ""
  }

  public static func displayName(for aiUser: V2NIMAIUser) -> String {
    if let name = aiUser.name, !name.isEmpty {
      return name
    }
    return aiUser.accountId ?? ""
  }

  private static func normalizedInitial(for name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = trimmed.first, first.isNumber {
      return "0"
    }
    let initial = trimmed.initalLetter() ?? ""
    guard let first = initial.first else {
      return "#"
    }
    let letter = String(first).uppercased()
    if letter.range(of: "^[A-Z]$", options: .regularExpression) != nil {
      return letter
    }
    return "#"
  }

  private static func compareSpecialEntries(_ lhs: ContactEntryState,
                                            _ rhs: ContactEntryState) -> Bool {
    let lhsPriority = specialSortPriority(lhs.title)
    let rhsPriority = specialSortPriority(rhs.title)
    if lhsPriority != rhsPriority {
      return lhsPriority < rhsPriority
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  private static func mergedDisplayUser(_ user: NEUserWithFriend,
                                        accountId: String) -> NEUserWithFriend {
    guard let cached = NEFriendUserCache.shared.getFriendInfo(accountId) else {
      return user
    }
    return NEUserWithFriend(
      user: cached.user ?? user.user,
      friend: cached.friend ?? user.friend
    )
  }

  private static func avatarURL(for user: NEUserWithFriend,
                                accountId: String) -> String? {
    let cachedAvatar = NEFriendUserCache.shared.getFriendInfo(accountId)?.user?.avatar
    return nonEmpty(cachedAvatar) ?? nonEmpty(user.user?.avatar)
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func specialSortPriority(_ title: String) -> Int {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else {
      return 2
    }
    return first.isNumber ? 1 : 2
  }
}
