// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public extension View {
  func neCommonConfirmationDialog(_ dialog: NECommonDialogState?,
                                  onAction: @escaping (NECommonDialogAction) -> Void,
                                  onDismiss: @escaping () -> Void) -> some View {
    modifier(
      NECommonConfirmationDialogModifier(
        dialog: dialog,
        onAction: onAction,
        onDismiss: onDismiss
      )
    )
  }
}

private struct NECommonConfirmationDialogModifier: ViewModifier {
  var dialog: NECommonDialogState?
  var onAction: (NECommonDialogAction) -> Void
  var onDismiss: () -> Void

  func body(content: Content) -> some View {
    content
      .alert(
        dialog?.title ?? "",
        isPresented: presentationBinding(for: .alert)
      ) {
        if let dialog {
          ForEach(dialog.actions) { action in
            dialogButton(for: action)
          }
        }
      } message: {
        if let message = dialog?.message {
          Text(message)
        }
      }
      .confirmationDialog(
        dialog?.title ?? "",
        isPresented: presentationBinding(for: .actionSheet),
        titleVisibility: dialog?.showsTitle == false ? .hidden : .visible
      ) {
        if let dialog {
          ForEach(dialog.actions) { action in
            dialogButton(for: action)
          }
        }
      } message: {
        if let message = dialog?.message {
          Text(message)
        }
      }
      .tint(NEUIKitSwiftUIStyle.ColorToken.darkText)
  }

  private func presentationBinding(for style: NECommonDialogPresentationStyle) -> Binding<Bool> {
    Binding(
      get: { dialog?.presentationStyle == style },
      set: { isPresented in
        if !isPresented {
          onDismiss()
        }
      }
    )
  }

  @ViewBuilder
  private func dialogButton(for action: NECommonDialogAction) -> some View {
    Button(role: action.role.buttonRole) {
      onAction(action)
    } label: {
      if let imageName = action.imageName {
        HStack {
          Image(imageName, bundle: action.imageBundle)
          Text(action.title)
        }
      } else if let systemImageName = action.systemImageName {
        HStack {
          NECommonFallbackIconView(name: systemImageName)
            .frame(width: 16, height: 16)
          Text(action.title)
        }
      } else {
        Text(action.title)
      }
    }
    .disabled(!action.isEnabled)
  }
}
