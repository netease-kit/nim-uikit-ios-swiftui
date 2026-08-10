// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamTextEditView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamTextEditViewModel
  private let field: TeamTextEditField
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onBack: (() -> Void)?
  private let onSaved: () -> Void
  @FocusState private var textEditorFocused: Bool

  public init(teamId: String,
              field: TeamTextEditField,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onBack: (() -> Void)? = nil,
              onSaved: @escaping () -> Void = {}) {
    _viewModel = StateObject(wrappedValue: TeamTextEditViewModel(teamId: teamId, field: field, teamType: teamType))
    self.field = field
    self.style = style
    self.token = token ?? (style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default)
    self.onBack = onBack
    self.onSaved = onSaved
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: title,
          token: token,
          backAction: {
            textEditorFocused = false
            closeCurrentView()
          },
          trailingAction: viewModel.state.canEdit ? NETeamCommonPresentation.textNavigationAction(
            id: "save",
            title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.save, value: "Save")
          ) : nil,
          onTrailingAction: {
            guard viewModel.state.canSubmit(field: field) else {
              return
            }
            textEditorFocused = false
            viewModel.save()
          },
          trailingActionEnabled: viewModel.state.canSubmit(field: field),
          backgroundColor: token.pageBackground,
          showsSeparator: false
        )

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onDisappear {
      textEditorFocused = false
    }
    .onAppear {
      viewModel.refreshIfNeeded()
    }
    .onChange(of: viewModel.state.didSave) { didSave in
      guard didSave else {
        return
      }
      onSaved()
      closeCurrentView()
    }
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamTextEditSaving",
        isPresented: viewModel.state.isSaving
      )
    )
    .neCommonToastOverlay(
      NETeamCommonPresentation.toast(viewModel.state.toast),
      placement: .top,
      topPadding: 10,
      onDismiss: { _ in viewModel.consumeToast() }
    )
  }

  private func closeCurrentView() {
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NETeamCommonPresentation.loadingView()
    case .failed(let message):
      NETeamCommonPresentation.errorView(message) {
        viewModel.load()
      }
    case .loaded:
      editContainer
        .padding(.top, containerTopPadding)
    }
  }

  private var editContainer: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: Binding(
        get: { viewModel.state.text },
        set: { text in
          viewModel.updateText(text)
          if text.isEmpty {
            textEditorFocused = false
          }
        }
      ))
      .font(.system(size: 14))
      .foregroundStyle(token.primaryText)
      .disabled(!viewModel.state.canEdit || viewModel.state.isSaving)
      .focused($textEditorFocused)
      .frame(height: textInputHeight)
      .padding(.leading, 12)
      .padding(.trailing, textInputTrailingPadding)
      .padding(.top, textInputTopPadding)
      .scrollContentBackground(.hidden)

      if viewModel.state.text.isEmpty, !placeholder.isEmpty {
        Text(placeholder)
          .font(.system(size: 14))
          .foregroundStyle(token.secondaryText.opacity(0.55))
          .padding(.leading, 16)
          .padding(.top, placeholderTopPadding)
          .allowsHitTesting(false)
      }

      if !viewModel.state.text.isEmpty && viewModel.state.canEdit {
        HStack {
          Spacer()
          clearButton
            .padding(.top, clearButtonTopPadding)
            .padding(.trailing, clearButtonTrailingPadding)
        }
      }

      NETeamCommonPresentation.characterCounter(
        count: viewModel.state.text.utf16.count,
        limit: field.limit,
        token: token
      )
      .padding(.trailing, 16)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity)
    .frame(height: containerHeight)
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.textEditContainerCornerRadius, style: .continuous))
    .padding(.horizontal, token.textEditContainerHorizontalMargin)
    .onChange(of: viewModel.state.canEdit) { canEdit in
      if !canEdit {
        textEditorFocused = false
      }
    }
    .onChange(of: viewModel.state.isSaving) { isSaving in
      if isSaving {
        textEditorFocused = false
      }
    }
  }

  private var clearButton: some View {
    NETeamCommonPresentation.iconButton(
      imageName: "clear_btn",
      accessibilityLabel: NETeamUIKitSwiftUIBundle.localized("clear", value: "Clear"),
      token: token,
      renderingMode: .original,
      size: CGSize(width: 16, height: 16)
    ) {
      viewModel.clearText()
      textEditorFocused = false
    }
  }

  private var title: String {
    switch field {
    case .name:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamName, value: "Group Name")
    case .nick:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNick, value: "My Alias in Group")
    case .introduce:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamIntr, value: "Description")
    }
  }

  private var placeholder: String {
    switch field {
    case .name:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamName, value: "Group Name")
    case .nick:
      _ = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNick, value: "My Alias in Group")
      return ""
    case .introduce:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamIntr, value: "Description")
    }
  }

  private var containerHeight: CGFloat {
    field == .introduce ? token.introduceEditContainerHeight : token.textEditContainerHeight
  }

  private var containerTopPadding: CGFloat {
    token.textEditContainerTopPadding
  }

  private var textInputHeight: CGFloat {
    if field == .introduce {
      return style == .fun ? 110 : 120
    }
    return style == .fun ? 60 : 44
  }

  private var textInputTopPadding: CGFloat {
    if field == .introduce {
      return 8
    }
    return 0
  }

  private var textInputTrailingPadding: CGFloat {
    field == .introduce ? 28 : 40
  }

  private var placeholderTopPadding: CGFloat {
    if field == .introduce {
      return 16
    }
    return style == .fun ? 20 : 12
  }

  private var clearButtonTopPadding: CGFloat {
    field == .introduce ? (containerHeight - 8 - 16 - 6 - 16) : 16
  }

  private var clearButtonTrailingPadding: CGFloat {
    field == .introduce || style == .fun ? 16 : 32
  }

}
