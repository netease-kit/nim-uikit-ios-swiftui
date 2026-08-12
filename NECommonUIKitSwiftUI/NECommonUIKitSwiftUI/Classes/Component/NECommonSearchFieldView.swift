// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSearchFieldView<Trailing: View>: View {
  @Environment(\.neCommonTheme) private var token
  @FocusState private var isFocused: Bool
  @Binding private var text: String
  private let placeholder: String
  private let height: CGFloat
  private let horizontalPadding: CGFloat
  private let submitLabel: SubmitLabel
  private let onSubmit: (() -> Void)?
  private let onClear: (() -> Void)?
  private let trailingContent: () -> Trailing

  public init(text: Binding<String>,
              placeholder: String,
              height: CGFloat = 34,
              horizontalPadding: CGFloat = 12,
              submitLabel: SubmitLabel = .search,
              onSubmit: (() -> Void)? = nil,
              onClear: (() -> Void)? = nil,
              @ViewBuilder trailingContent: @escaping () -> Trailing) {
    _text = text
    self.placeholder = placeholder
    self.height = height
    self.horizontalPadding = horizontalPadding
    self.submitLabel = submitLabel
    self.onSubmit = onSubmit
    self.onClear = onClear
    self.trailingContent = trailingContent
  }

  public var body: some View {
    HStack(spacing: token.spacing.small) {
      Image("textField_search_icon", bundle: NECommonUIKitSwiftUIBundle.bundle)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: 14, height: 14)

      TextField(placeholder, text: $text)
        .font(token.typography.body)
        .foregroundColor(token.palette.primaryText)
        .tint(token.palette.accent)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(submitLabel)
        .focused($isFocused)
        .onSubmit {
          isFocused = false
          onSubmit?()
        }

      if !text.isEmpty {
        Button {
          isFocused = false
          text = ""
          onClear?()
        } label: {
          Image("remove", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NECommonUIKitSwiftUIBundle.localized("common_clear", fallback: "Clear"))
      }

      trailingContent()
    }
    .padding(.horizontal, horizontalPadding)
    .frame(height: height)
    .background(token.palette.rowBackground, in: RoundedRectangle(cornerRadius: token.radius.medium, style: .continuous))
    .onDisappear {
      isFocused = false
    }
  }
}

public extension NECommonSearchFieldView where Trailing == EmptyView {
  init(text: Binding<String>,
       placeholder: String,
       height: CGFloat = 34,
       horizontalPadding: CGFloat = 12,
       submitLabel: SubmitLabel = .search,
       onSubmit: (() -> Void)? = nil,
       onClear: (() -> Void)? = nil) {
    self.init(text: text,
              placeholder: placeholder,
              height: height,
              horizontalPadding: horizontalPadding,
              submitLabel: submitLabel,
              onSubmit: onSubmit,
              onClear: onClear) {
      EmptyView()
    }
  }
}
