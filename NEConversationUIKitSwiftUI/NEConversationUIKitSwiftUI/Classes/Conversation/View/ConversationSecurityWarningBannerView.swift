// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ConversationSecurityWarningBannerView: View {
  public var message: String

  public init(message: String) {
    self.message = message
  }

  public var body: some View {
    Text(message)
      .font(.system(size: 14))
      .foregroundColor(Color(hex: 0xEB9718))
      .lineLimit(2)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .frame(height: 56)
      .background(Color(hex: 0xFFF5E1))
      .accessibilityIdentifier("id.securityWarning")
  }
}
