// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public final class ChatSwiftUIConfigCenter {
  public static let shared = ChatSwiftUIConfigCenter()

  private let lock = NSLock()
  private var config = ChatSwiftUIConfig()

  private init() {}

  public func update(_ config: ChatSwiftUIConfig) {
    lock.lock()
    self.config = config
    lock.unlock()
  }

  public func current() -> ChatSwiftUIConfig {
    lock.lock()
    let value = config
    lock.unlock()
    return value
  }
}
