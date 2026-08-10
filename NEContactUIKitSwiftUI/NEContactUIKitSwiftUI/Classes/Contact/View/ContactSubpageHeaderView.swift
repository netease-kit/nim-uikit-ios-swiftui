// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ContactSubpageHeaderView<Trailing: View>: View {
  var title: String
  var token: ContactThemeToken
  var onBack: (() -> Void)?
  @ViewBuilder var trailing: () -> Trailing

  public init(title: String,
              token: ContactThemeToken,
              onBack: (() -> Void)? = nil,
              @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
    self.title = title
    self.token = token
    self.onBack = onBack
    self.trailing = trailing
  }

  public var body: some View {
    NECommonNavigationBarView(
      title: title,
      backAction: onBack,
      trailingWidth: 60,
      backgroundColor: token.navigationBackground,
      separatorColor: token.rowSeparatorColor,
      showsSeparator: false
    ) {
      trailing()
    }
    .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
  }
}
