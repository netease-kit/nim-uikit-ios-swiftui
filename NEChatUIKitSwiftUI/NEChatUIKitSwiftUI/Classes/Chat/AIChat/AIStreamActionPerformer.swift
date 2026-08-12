// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum AIStreamAction: Equatable {
  case stop
  case regenerate
}

public struct AIStreamActionResult {
  public var message: String?

  public init(message: String? = nil) {
    self.message = message
  }
}

public protocol AIStreamActionPerforming {
  func perform(_ action: AIStreamAction,
               messageId: String,
               completion: @escaping (Result<AIStreamActionResult, Error>) -> Void)
}

public final class NEChatKitAIStreamActionPerformer: AIStreamActionPerforming {
  private let chatRepo: ChatRepo

  public init(chatRepo: ChatRepo = .shared) {
    self.chatRepo = chatRepo
  }

  public func perform(_ action: AIStreamAction,
                      messageId: String,
                      completion: @escaping (Result<AIStreamActionResult, Error>) -> Void) {
    resolveMessage(id: messageId) { [chatRepo] result in
      switch result {
      case .success(let message):
        switch action {
        case .stop:
          chatRepo.stopAIStreamMessage(message) { error in
            if let error {
              NEChatSwiftUILogger.log("aiStream stop failed messageId=\(messageId) error=\(error)")
              completion(.failure(error))
            } else {
              completion(.success(AIStreamActionResult(
                message: NEChatUIKitSwiftUIBundle.localized("chat_ai_stream_stopped", value: "AI response stopped")
              )))
            }
          }
        case .regenerate:
          chatRepo.regenAIMessage(message) { error in
            if let error {
              NEChatSwiftUILogger.log("aiStream regenerate failed messageId=\(messageId) error=\(error)")
              completion(.failure(error))
            } else {
              completion(.success(AIStreamActionResult(
                message: NEChatUIKitSwiftUIBundle.localized("chat_ai_stream_regenerating", value: "Regenerating")
              )))
            }
          }
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  private func resolveMessage(id: String,
                              completion: @escaping (Result<V2NIMMessage, Error>) -> Void) {
    chatRepo.getMessageListByIds([id]) { messages, error in
      if let error {
        NEChatSwiftUILogger.log("aiStream resolveMessage failed id=\(id) error=\(error)")
        completion(.failure(error))
        return
      }

      guard let message = messages?.first else {
        completion(.failure(Self.error(
          code: -1,
          message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found")
        )))
        return
      }

      completion(.success(message))
    }
  }

  private static func error(code: Int, message: String) -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
