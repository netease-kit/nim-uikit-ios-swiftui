// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct FunChatView: View {
  private let viewModel: ChatSessionViewModel

  @MainActor
  public init(viewModel: ChatSessionViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    ChatView(viewModel: viewModel, token: viewModel.config.themeToken)
  }
}
