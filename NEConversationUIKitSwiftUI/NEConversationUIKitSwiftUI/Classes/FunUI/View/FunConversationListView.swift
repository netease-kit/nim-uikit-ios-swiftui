// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct FunConversationListView: View {
  private let viewModel: ConversationListViewModel

  @MainActor
  public init(viewModel: ConversationListViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    ConversationListView(viewModel: viewModel, token: .fun)
  }
}
