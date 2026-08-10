// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct FunContactListView: View {
  private let viewModel: ContactListViewModel

  @MainActor
  public init(viewModel: ContactListViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    ContactListView(viewModel: viewModel, token: .fun)
  }
}
