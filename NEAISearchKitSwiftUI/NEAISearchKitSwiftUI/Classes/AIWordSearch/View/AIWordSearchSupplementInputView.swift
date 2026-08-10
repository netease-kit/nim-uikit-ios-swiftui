// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct AIWordSearchSupplementInputView: View {
  @Binding public var text: String
  public var canSubmit: Bool
  public var onSubmit: () -> Void
  @FocusState private var textEditorFocused: Bool

  public init(text: Binding<String>,
              canSubmit: Bool,
              onSubmit: @escaping () -> Void) {
    _text = text
    self.canSubmit = canSubmit
    self.onSubmit = onSubmit
  }

  public var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 4)
        .fill(NEAISearchSwiftUIConstants.inputBackgroundColor)

      TextEditor(text: $text)
        .font(.system(size: 16))
        .foregroundStyle(NEAISearchSwiftUIConstants.darkTextColor)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .focused($textEditorFocused)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 90, maxHeight: 90)

      if text.isEmpty {
        Text(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.inputMorePlaceholder, value: "Please provide more information."))
          .font(.system(size: 16))
          .foregroundStyle(NEAISearchSwiftUIConstants.placeholderTextColor)
          .padding(.horizontal, 16)
          .padding(.vertical, 15)
          .allowsHitTesting(false)
      }

      VStack {
        Spacer()
        HStack {
          Spacer()
          Button {
            textEditorFocused = false
            onSubmit()
          } label: {
            Text(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.ok, value: "OK"))
              .font(.system(size: 16))
              .foregroundStyle(NEAISearchSwiftUIConstants.actionColor.opacity(canSubmit ? 1 : 0.5))
          }
          .disabled(!canSubmit)
          .accessibilityIdentifier("id.sureButton")
        }
        .padding(.trailing, 12)
        .padding(.bottom, 12)
      }
    }
    .frame(height: 120)
    .onDisappear {
      textEditorFocused = false
    }
  }
}
