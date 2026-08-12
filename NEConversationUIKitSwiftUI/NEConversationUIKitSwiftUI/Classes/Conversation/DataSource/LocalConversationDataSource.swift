// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

final class LocalConversationDataSource: ConversationDataSource {
  let mode: ConversationMode = .local
  let allowsOfflineDelete = true

  private let repo: LocalConversationRepo
  private var offset = 0

  init(repo: LocalConversationRepo = .shared) {
    self.repo = repo
  }

  func reset() {
    offset = 0
  }

  func loadPage(limit: Int,
                completion: @escaping (Result<ConversationPageResult, NSError>) -> Void) {
    repo.getConversationList(offset, limit) { [weak self] conversations, nextOffset, finished, error in
      if let error {
        debugPrint("[NEConversationUIKitSwiftUI] localConversation loadPage failed error=\(error)")
        completion(.failure(error))
        return
      }
      if let nextOffset {
        self?.offset = nextOffset
      }
      completion(.success(ConversationPageResult(
        conversations: (conversations ?? []).map(ConversationItemSnapshot.init),
        finished: finished ?? false
      )))
    }
  }

  func reloadCurrent(limit: Int,
                     completion: @escaping (Result<ConversationPageResult, NSError>) -> Void) {
    repo.getConversationList(0, max(limit, 1)) { [weak self] conversations, nextOffset, finished, error in
      if let error {
        debugPrint("[NEConversationUIKitSwiftUI] localConversation reload failed error=\(error)")
        completion(.failure(error))
        return
      }
      if let nextOffset {
        self?.offset = nextOffset
      }
      completion(.success(ConversationPageResult(
        conversations: (conversations ?? []).map(ConversationItemSnapshot.init),
        finished: finished ?? false
      )))
    }
  }

  func setStickTop(conversationId: String,
                   stickTop: Bool,
                   completion: @escaping (NSError?) -> Void) {
    repo.setStickTop(conversationId, stickTop, completion)
  }

  func deleteConversation(conversationId: String,
                          completion: @escaping (NSError?) -> Void) {
    repo.deleteConversation(conversationId, false, completion)
  }

  func conversationIds(for accountIds: [String],
                       completion: @escaping ([ConversationItemSnapshot]) -> Void) {
    let ids = accountIds.compactMap { V2NIMConversationIdUtil.p2pConversationId($0) }
    guard !ids.isEmpty else {
      completion([])
      return
    }
    repo.getConversationListByIds(ids) { conversations, _ in
      completion((conversations ?? []).map(ConversationItemSnapshot.init))
    }
  }

  func addListener(onCreated: @escaping (ConversationItemSnapshot) -> Void,
                   onChanged: @escaping ([ConversationItemSnapshot]) -> Void,
                   onDeleted: @escaping ([String]) -> Void,
                   onSyncFinished: @escaping () -> Void,
                   onSyncFailed: @escaping (NSError) -> Void) -> NEChatKitListenerToken {
    repo.addLocalConversationEventListener(
      NELocalConversationEvent(
        syncFinished: onSyncFinished,
        syncFailed: { error in onSyncFailed(error.nserror as NSError) },
        conversationCreated: { onCreated(ConversationItemSnapshot($0)) },
        conversationDeleted: onDeleted,
        conversationChanged: { onChanged($0.map(ConversationItemSnapshot.init)) }
      )
    )
  }
}
