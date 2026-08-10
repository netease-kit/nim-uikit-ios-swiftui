// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSelectionIndicatorView: View {
  @Environment(\.neCommonTheme) private var token
  private let isSelected: Bool
  private let isEnabled: Bool
  private let size: CGFloat

  public init(isSelected: Bool,
              isEnabled: Bool = true,
              size: CGFloat = 20) {
    self.isSelected = isSelected
    self.isEnabled = isEnabled
    self.size = size
  }

  public var body: some View {
    Image(imageName, bundle: NECommonUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .opacity(isEnabled ? 1 : 0.45)
    .frame(width: size, height: size)
    .accessibilityLabel(accessibilityLabel)
  }

  private var imageName: String {
    switch (token.styleMode, isSelected) {
    case (.fun, true):
      return "fun_select"
    case (.fun, false):
      return "fun_unselect"
    case (.normal, true):
      return "select"
    case (.normal, false):
      return "unselect"
    }
  }

  private var accessibilityLabel: String {
    isSelected
      ? NECommonUIKitSwiftUIBundle.localized("common_selected", fallback: "Selected")
      : NECommonUIKitSwiftUIBundle.localized("common_unselected", fallback: "Not selected")
  }
}
