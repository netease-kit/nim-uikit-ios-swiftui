// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public final class NETeamSwiftUIConfigCenter {
  public static let shared = NETeamSwiftUIConfigCenter()

  private let lock = NSLock()
  private var config = NETeamSwiftUIConfig()

  private init() {}

  public func update(_ config: NETeamSwiftUIConfig) {
    lock.lock()
    self.config = config
    lock.unlock()
  }

  public func current() -> NETeamSwiftUIConfig {
    lock.lock()
    let value = config
    lock.unlock()
    return value
  }
}
