// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ReadReceiptMemberState: Identifiable, Equatable {
  public var id: String { accountId }
  public var accountId: String
  public var displayName: String
  public var avatarName: String?
  public var subtitle: String?
  public var avatarURL: URL?

  public init(accountId: String,
              displayName: String? = nil,
              avatarName: String? = nil,
              subtitle: String? = nil,
              avatarURL: URL? = nil) {
    self.accountId = accountId
    self.displayName = displayName?.isEmpty == false ? displayName ?? accountId : accountId
    self.avatarName = avatarName
    self.subtitle = subtitle
    self.avatarURL = avatarURL
  }
}

public protocol ChatReadReceiptMemberProviding {
  func loadMembers(accountIds: [String],
                   teamId: String?,
                   completion: @escaping (Result<[ReadReceiptMemberState], Error>) -> Void)
}

public struct ChatReadReceiptMemberProvider: ChatReadReceiptMemberProviding {
  private let loader: ([String], String?, @escaping (Result<[ReadReceiptMemberState], Error>) -> Void) -> Void

  public init(_ loader: @escaping ([String], String?, @escaping (Result<[ReadReceiptMemberState], Error>) -> Void) -> Void) {
    self.loader = loader
  }

  public func loadMembers(accountIds: [String],
                          teamId: String?,
                          completion: @escaping (Result<[ReadReceiptMemberState], Error>) -> Void) {
    loader(accountIds, teamId, completion)
  }

  public static let chatKitDefault = ChatReadReceiptMemberProvider { accountIds, teamId, completion in
    NEChatKitReadReceiptMemberLoader(teamId: teamId).load(accountIds: accountIds, completion: completion)
  }
}

private final class NEChatKitReadReceiptMemberLoader {
  private let teamId: String?
  private let teamRepo: TeamRepo
  private let contactRepo: ContactRepo

  init(teamId: String?,
       teamRepo: TeamRepo = .shared,
       contactRepo: ContactRepo = .shared) {
    self.teamId = teamId
    self.teamRepo = teamRepo
    self.contactRepo = contactRepo
  }

  func load(accountIds: [String],
            completion: @escaping (Result<[ReadReceiptMemberState], Error>) -> Void) {
    let orderedAccountIds = accountIds.filter { !$0.isEmpty }
    guard !orderedAccountIds.isEmpty else {
      completion(.success([]))
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var teamMembers = [String: V2NIMTeamMember]()
    var users = [String: NEUserWithFriend]()
    var firstError: Error?

    func record(_ error: Error?) {
      guard let error else {
        return
      }
      lock.lock()
      if firstError == nil {
        firstError = error
      }
      lock.unlock()
    }

    if let teamId, !teamId.isEmpty {
      group.enter()
      teamRepo.getTeamMemberListByIds(teamId, .TEAM_TYPE_NORMAL, orderedAccountIds) { members, error in
        if let members {
          lock.lock()
          members.forEach { member in
            teamMembers[member.accountId] = member
          }
          lock.unlock()
        }
        record(error)
        group.leave()
      }
    }

    group.enter()
    contactRepo.getUserWithFriend(accountIds: orderedAccountIds) { userList, error in
      if let userList {
        lock.lock()
        userList.forEach { user in
          if let accountId = user.user?.accountId ?? user.friend?.accountId {
            users[accountId] = user
          }
        }
        lock.unlock()
      }
      record(error)
      group.leave()
    }

    group.notify(queue: .main) {
      let rows = orderedAccountIds.map { accountId in
        Self.memberState(
          accountId: accountId,
          teamMember: teamMembers[accountId],
          user: users[accountId]
        )
      }

      if let firstError, rows.allSatisfy({ $0.displayName == $0.accountId }) {
        completion(.failure(firstError))
      } else {
        completion(.success(rows))
      }
    }
  }

  private static func memberState(accountId: String,
                                  teamMember: V2NIMTeamMember?,
                                  user: NEUserWithFriend?) -> ReadReceiptMemberState {
    let displayName = [
      teamMember?.teamNick,
      user?.showName(),
      accountId,
    ].compactMap { value -> String? in
      guard let value, !value.isEmpty else {
        return nil
      }
      return value
    }.first ?? accountId

    let subtitle = displayName == accountId ? nil : accountId
    let avatarURL = ChatAvatarURLResolver.url(from: user?.user?.avatar)
    return ReadReceiptMemberState(
      accountId: accountId,
      displayName: displayName,
      avatarName: user?.showName(false),
      subtitle: subtitle,
      avatarURL: avatarURL
    )
  }
}
