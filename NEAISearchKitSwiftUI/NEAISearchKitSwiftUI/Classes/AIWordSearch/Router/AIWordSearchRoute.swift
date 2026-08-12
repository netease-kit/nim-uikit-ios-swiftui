// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum AIWordSearchSource: String, Equatable {
  case messageMenu
  case messageText
  case selectedText
  case manual
  case plugin
}

public struct AIWordSearchRoute: Identifiable, Equatable {
  public var id: String
  public var query: String
  public var source: AIWordSearchSource
  public var conversationId: String?
  public var messageClientId: String?

  public init(id: String = UUID().uuidString,
              query: String,
              source: AIWordSearchSource = .messageMenu,
              conversationId: String? = nil,
              messageClientId: String? = nil) {
    self.id = id
    self.query = query
    self.source = source
    self.conversationId = conversationId
    self.messageClientId = messageClientId
  }
}
