// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonFormTextFieldView: View {
  @Environment(\.neCommonTheme) private var token
  @FocusState private var isFocused: Bool
  @Binding private var text: String
  private let title: String?
  private let placeholder: String
  private let error: String?
  private let isEnabled: Bool
  private let submitLabel: SubmitLabel
  private let axis: Axis
  private let horizontalPadding: CGFloat
  private let verticalPadding: CGFloat
  private let minHeight: CGFloat?
  private let backgroundCornerRadius: CGFloat?
  private let characterLimit: Int?
  private let onSubmit: (() -> Void)?

  public init(title: String? = nil,
              text: Binding<String>,
              placeholder: String,
              error: String? = nil,
              isEnabled: Bool = true,
              submitLabel: SubmitLabel = .done,
              axis: Axis = .horizontal,
              horizontalPadding: CGFloat = 14,
              verticalPadding: CGFloat = 10,
              minHeight: CGFloat? = nil,
              backgroundCornerRadius: CGFloat? = nil,
              characterLimit: Int? = nil,
              onSubmit: (() -> Void)? = nil) {
    self.title = title
    _text = text
    self.placeholder = placeholder
    self.error = error
    self.isEnabled = isEnabled
    self.submitLabel = submitLabel
    self.axis = axis
    self.horizontalPadding = horizontalPadding
    self.verticalPadding = verticalPadding
    self.minHeight = minHeight
    self.backgroundCornerRadius = backgroundCornerRadius
    self.characterLimit = characterLimit
    self.onSubmit = onSubmit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: token.spacing.xsmall) {
      if let title, !title.isEmpty {
        Text(title)
          .font(token.typography.footnote)
          .foregroundColor(token.palette.secondaryText)
      }

      TextField(placeholder, text: limitedTextBinding, axis: axis)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(submitLabel)
        .font(token.typography.body)
        .foregroundColor(isEnabled ? token.palette.primaryText : token.palette.secondaryText.opacity(0.55))
        .tint(token.palette.accent)
        .disabled(!isEnabled)
        .focused($isFocused)
        .onSubmit {
          isFocused = false
          onSubmit?()
        }

      if let error, !error.isEmpty {
        Text(error)
          .font(token.typography.caption)
          .foregroundColor(token.palette.warning)
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, verticalPadding)
    .background(background)
    .onChange(of: isEnabled) { enabled in
      if !enabled {
        isFocused = false
      }
    }
    .onDisappear {
      isFocused = false
    }
  }

  private var limitedTextBinding: Binding<String> {
    Binding(
      get: { text },
      set: {
        let limitedText = NECommonTextLimit.limitedUTF16($0, limit: characterLimit)
        text = limitedText
        if limitedText.isEmpty {
          isFocused = false
        }
      }
    )
  }

  @ViewBuilder
  private var background: some View {
    if let backgroundCornerRadius {
      token.palette.rowBackground
        .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
    }
  }
}
