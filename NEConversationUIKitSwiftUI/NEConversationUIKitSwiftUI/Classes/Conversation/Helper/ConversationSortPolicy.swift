// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

enum ConversationSortPolicy {
  static func sorted(_ snapshots: [ConversationItemSnapshot]) -> [ConversationItemSnapshot] {
    snapshots.sorted {
      if $0.stickTop != $1.stickTop {
        return $0.stickTop && !$1.stickTop
      }
      if $0.sortOrder == $1.sortOrder {
        return $0.conversationId < $1.conversationId
      }
      return $0.sortOrder > $1.sortOrder
    }
  }

  static func sortedRows(_ rows: [ConversationRowState]) -> [ConversationRowState] {
    rows.sorted {
      if $0.isStickTop != $1.isStickTop {
        return $0.isStickTop && !$1.isStickTop
      }
      if $0.sortOrder == $1.sortOrder {
        return $0.conversationId < $1.conversationId
      }
      return $0.sortOrder > $1.sortOrder
    }
  }
}
