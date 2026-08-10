// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public final class ChatListenerBinder {
  private let bag = NEChatKitListenerBag()
  public private(set) var activeTokenCount = 0

  public init() {}

  deinit {
    cancel()
  }

  public var isActive: Bool {
    activeTokenCount > 0
  }

  public func bind(_ token: NEChatKitCancellable) {
    token.store(in: bag)
    activeTokenCount += 1
  }

  public func cancel() {
    guard activeTokenCount > 0 else {
      return
    }
    bag.cancelAll()
    activeTokenCount = 0
  }
}
