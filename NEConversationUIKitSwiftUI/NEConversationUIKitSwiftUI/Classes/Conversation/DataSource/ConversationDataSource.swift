// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

struct ConversationPageResult {
  var conversations: [ConversationItemSnapshot]
  var finished: Bool

  init(conversations: [ConversationItemSnapshot],
       finished: Bool) {
    self.conversations = conversations
    self.finished = finished
  }
}

protocol ConversationDataSource: AnyObject {
  var mode: ConversationMode { get }
  var allowsOfflineDelete: Bool { get }

  func reset()
  func loadPage(limit: Int,
                completion: @escaping (Result<ConversationPageResult, NSError>) -> Void)
  func reloadCurrent(limit: Int,
                     completion: @escaping (Result<ConversationPageResult, NSError>) -> Void)
  func setStickTop(conversationId: String,
                   stickTop: Bool,
                   completion: @escaping (NSError?) -> Void)
  func deleteConversation(conversationId: String,
                          completion: @escaping (NSError?) -> Void)
  func conversationIds(for accountIds: [String],
                       completion: @escaping ([ConversationItemSnapshot]) -> Void)
  func addListener(onCreated: @escaping (ConversationItemSnapshot) -> Void,
                   onChanged: @escaping ([ConversationItemSnapshot]) -> Void,
                   onDeleted: @escaping ([String]) -> Void,
                   onSyncFinished: @escaping () -> Void,
                   onSyncFailed: @escaping (NSError) -> Void) -> NEChatKitListenerToken
}
