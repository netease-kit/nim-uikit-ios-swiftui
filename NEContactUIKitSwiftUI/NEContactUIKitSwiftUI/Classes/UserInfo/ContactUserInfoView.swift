// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct ContactUserInfoView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neCommonLocalBackAction) private var localBackAction
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @StateObject private var viewModel: ContactUserInfoViewModel
  @State private var aliasDraft = ""
  @State private var isAliasEditorPresented = false
  @State private var isDeleteConfirmPresented = false
  @State private var aliasValidationToast: NECommonToast?
  @State private var identifierCopyToast: NECommonToastState?
  @State private var aliasEditorFocused = false
  private let token: ContactThemeToken
  private let clipboardService: NECommonClipboardService
  private let onOpenChat: ((String, String) -> Void)?

  private var initials: String {
    NECommonAvatarDisplayResolver.initials(
      displayName: viewModel.state.profileName,
      fallbackID: viewModel.state.accountId
    )
  }

  public init(viewModel: ContactUserInfoViewModel,
              token: ContactThemeToken,
              clipboardService: NECommonClipboardService = NECommonClipboardServiceCenter.shared.current(),
              onOpenChat: ((String, String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.clipboardService = clipboardService
    self.onOpenChat = onOpenChat
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: "",
        token: token,
        onBack: {
          if let localBackAction {
            localBackAction()
          } else if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        }
      )

      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .onChange(of: viewModel.state.aliasSaveSucceeded) { succeeded in
      guard succeeded else {
        return
      }
      aliasEditorFocused = false
      isAliasEditorPresented = false
      viewModel.consumeAliasSaveSucceeded()
    }
    .onChange(of: viewModel.state.shouldDismiss) { shouldDismiss in
      guard shouldDismiss else {
        return
      }
      dismiss()
    }
    .navigationDestination(isPresented: $isAliasEditorPresented) {
      aliasEditor
    }
    .neCommonConfirmationDialog(
      deleteFriendDialogState,
      onAction: handleDeleteFriendDialogAction,
      onDismiss: { isDeleteConfirmPresented = false }
    )
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 52,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .neCommonTransientOverlay(
      aliasValidationToast,
      placement: .top,
      topPadding: 52,
      onDismiss: { toast in
        if aliasValidationToast?.id == toast.id {
          aliasValidationToast = nil
        }
      }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .neCommonToastOverlay(
      identifierCopyToast,
      placement: .top,
      topPadding: 52,
      onDismiss: { toast in
        if identifierCopyToast?.id == toast.id {
          identifierCopyToast = nil
        }
      }
    )
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var deleteFriendDialogState: NECommonDialogState? {
    guard isDeleteConfirmPresented else {
      return nil
    }
    let titleFormat = NEContactUIKitSwiftUIBundle.localized("delete_title", value: "Delete \"%@\" Contact")
    return NECommonDialogState(
      id: "deleteFriend",
      title: String(format: titleFormat, viewModel.state.displayName),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "delete",
          title: NEContactUIKitSwiftUIBundle.localized("delete_friend", value: "Delete Contact"),
          role: .destructive
        ),
      ]
    )
  }

  private func handleDeleteFriendDialogAction(_ action: NECommonDialogAction) {
    defer { isDeleteConfirmPresented = false }
    guard action.id == "delete" else {
      return
    }
    viewModel.deleteFriend()
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(
        state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true),
        retry: { viewModel.load() }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      ScrollView {
        VStack(spacing: 0) {
          header
          rows
        }
      }
      .background(token.pageBackground)
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      NECommonAvatarView(
        imageURL: NECommonAvatarDisplayResolver.url(from: viewModel.state.avatarURL),
        initials: initials,
        size: 60,
        cornerRadius: token.styleMode == .fun ? 4 : 30,
        hashID: viewModel.state.accountId
      )
      .padding(.leading, 20)

      VStack(alignment: .leading, spacing: 0) {
        Text(viewModel.state.displayName)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(userInfoTitleColor)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(height: 22)
          .padding(.top, headerShowsAliasDetail ? 0 : 9)

        if headerShowsAliasDetail {
          Text(primaryHeaderDetail)
            .font(.system(size: 16))
            .foregroundColor(userInfoSubtitleColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 16)
            .padding(.top, 8)
        } else {
          accountDetailText
            .padding(.top, 8)
        }

        if headerShowsAliasDetail {
          accountDetailText
        }
      }
      .padding(.leading, headerShowsAliasDetail ? 20 : 16)
      .padding(.trailing, headerShowsAliasDetail ? 35 : 20)

      Spacer()
    }
    .frame(height: 113)
    .background(token.rowBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(headerSeparatorColor)
        .frame(height: token.styleMode == .fun ? 1 : 6)
        .padding(.leading, token.styleMode == .fun ? 96 : 0)
    }
  }

  private var rows: some View {
    VStack(spacing: 0) {
      if viewModel.state.isFriend {
        VStack(spacing: 0) {
          settingRow(title: NEContactUIKitSwiftUIBundle.localized("noteName", value: "Nick Name"), showsChevron: true) {
            aliasDraft = viewModel.state.alias ?? ""
            isAliasEditorPresented = true
          }
        }
        infoGroup
        VStack(spacing: 0) {
          Toggle(isOn: Binding(
            get: { viewModel.state.isBlocked },
            set: { viewModel.toggleBlock($0) }
          )) {
            Text(NEContactUIKitSwiftUIBundle.localized("add_blackList", value: "Block"))
              .font(.system(size: 16))
              .foregroundColor(userInfoTitleColor)
          }
          .tint(token.accentColor)
          .frame(height: rowHeight)
          .padding(.horizontal, 20)
          .background(token.rowBackground)
          .overlay(alignment: .bottom) {
            rowSeparator
          }
        }
        VStack(spacing: 0) {
          actionButton(title: NEContactUIKitSwiftUIBundle.localized("chat", value: "Chat"), color: chatActionColor, showsSeparator: true) {
            if let onOpenChat {
              onOpenChat(viewModel.state.accountId, viewModel.state.displayName)
            } else {
              dismiss()
            }
          }
          actionButton(title: NEContactUIKitSwiftUIBundle.localized("delete_friend", value: "Delete Contact"), color: token.destructiveColor) {
            isDeleteConfirmPresented = true
          }
        }
      } else if viewModel.state.isCurrentUser {
        EmptyView()
      } else if viewModel.state.isRobot || viewModel.state.isAIUser {
        actionButton(title: NEContactUIKitSwiftUIBundle.localized("chat", value: "Chat"), color: chatActionColor) {
          if let onOpenChat {
            onOpenChat(viewModel.state.accountId, viewModel.state.displayName)
          } else {
            dismiss()
          }
        }
      } else {
        actionButton(title: NEContactUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts"), color: chatActionColor) {
          viewModel.addFriend()
        }
      }
    }
  }

  private var infoGroup: some View {
    VStack(spacing: 0) {
      settingRow(title: NEContactUIKitSwiftUIBundle.localized("birthday", value: "Birthday"), value: viewModel.state.birthday)
      settingRow(title: NEContactUIKitSwiftUIBundle.localized("phone", value: "Mobile"), value: viewModel.state.phone)
      settingRow(title: NEContactUIKitSwiftUIBundle.localized("email", value: "E-mail"), value: viewModel.state.email)
      settingRow(title: NEContactUIKitSwiftUIBundle.localized("sign", value: "What's Up"), value: viewModel.state.sign)
    }
  }

  @ViewBuilder
  private func settingRow(title: String,
                          value: String? = nil,
                          showsChevron: Bool = false,
                          action: (() -> Void)? = nil) -> some View {
    if let action {
      Button(action: action) {
        settingRowContent(title: title, value: value, showsChevron: showsChevron)
      }
      .buttonStyle(.plain)
    } else {
      settingRowContent(title: title, value: value, showsChevron: showsChevron)
    }
  }

  private func settingRowContent(title: String,
                                 value: String?,
                                 showsChevron: Bool) -> some View {
    HStack(spacing: 0) {
      Text(title)
        .font(.system(size: 16))
        .foregroundColor(userInfoTitleColor)
        .frame(width: 90, alignment: .leading)
      if let value, !value.isEmpty {
        Text(value)
          .font(.system(size: 12))
          .foregroundColor(userInfoDetailColor)
          .multilineTextAlignment(.trailing)
          .lineLimit(title == NEContactUIKitSwiftUIBundle.localized("sign", value: "What's Up") ? 2 : 1)
          .frame(maxWidth: .infinity, alignment: .trailing)
      } else {
        Spacer()
      }
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(userInfoDetailColor)
          .frame(width: 20, height: 20)
      }
    }
    .frame(height: rowHeight)
    .padding(.horizontal, 20)
    .background(token.rowBackground)
    .overlay(alignment: .bottom) {
      rowSeparator
    }
  }

  private func actionButton(title: String,
                            color: Color,
                            showsSeparator: Bool = false,
                            action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 16))
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(token.rowBackground)
        .overlay(alignment: .bottom) {
          if showsSeparator {
            rowSeparator
          }
        }
    }
    .buttonStyle(.plain)
  }

  private var aliasEditor: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("noteName", value: "Nick Name"),
        token: token,
        onBack: {
          aliasEditorFocused = false
          isAliasEditorPresented = false
        }
      ) {
        Button {
          saveAlias()
        } label: {
          Text(NEContactUIKitSwiftUIBundle.localized("save", value: "Save"))
            .font(.system(size: 16))
            .foregroundColor(token.styleMode == .fun ? token.accentColor : Color(hex: 0x337EFF))
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
      }

      ZStack(alignment: .trailing) {
        NEChatLimitedTextField(
          text: $aliasDraft,
          isFocused: aliasEditorFocusBinding,
          placeholder: NEContactUIKitSwiftUIBundle.localized("input_noteName", value: "Please enter nick name"),
          characterLimit: 15,
          fontSize: 16,
          textColor: .primary,
          returnKeyType: .done,
          accessibilityIdentifier: "id.editText",
          onSubmit: {
            aliasEditorFocused = false
          },
          onLimitReached: {
            aliasValidationToast = NECommonToast(
              message: String(
                format: NEContactUIKitSwiftUIBundle.localized(
                  "contact_alias_limit",
                  value: "The remark can contain up to %d characters"
                ),
                15
              )
            )
          }
        )
          .padding(.leading, 16)
          .padding(.trailing, aliasDraft.isEmpty ? 16 : 38)
          .frame(height: 44)

        if !aliasDraft.isEmpty {
          Button {
            aliasDraft = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 16))
              .foregroundColor(Color.black.opacity(0.25))
              .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("clear", value: "Clear"))
          }
          .buttonStyle(.plain)
          .padding(.trailing, 12)
        }
      }
      .background(Color.white)
      .padding(.top, topInputInset)
      Spacer()
    }
    .background(Color(hex: 0xEFF1F4).ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      aliasEditorFocused = true
    }
    .onDisappear {
      aliasEditorFocused = false
    }
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 52,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .neCommonTransientOverlay(
      aliasValidationToast,
      placement: .top,
      topPadding: 52,
      onDismiss: { toast in
        if aliasValidationToast?.id == toast.id {
          aliasValidationToast = nil
        }
      }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var headerShowsAliasDetail: Bool {
    !(viewModel.state.alias?.isEmpty ?? true)
  }

  private var primaryHeaderDetail: String {
    if headerShowsAliasDetail {
      let name = (viewModel.state.profileName?.isEmpty == false ? viewModel.state.profileName : viewModel.state.accountId) ?? viewModel.state.accountId
      return "\(NEContactUIKitSwiftUIBundle.localized("nick", value: "Nick")):\(name)"
    }
    return accountHeaderDetail
  }

  private var accountHeaderDetail: String {
    "\(NEContactUIKitSwiftUIBundle.localized("account", value: "Account")):\(viewModel.state.accountId)"
  }

  private var accountDetailText: some View {
    Text(accountHeaderDetail)
      .font(.system(size: 16))
      .foregroundColor(userInfoSubtitleColor)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(height: 16)
      .contentShape(Rectangle())
      .onLongPressGesture {
        copyAccountId()
      }
  }

  private func copyAccountId() {
    Task { @MainActor in
      guard case .success = await clipboardService.copyText(viewModel.state.accountId) else {
        return
      }
      identifierCopyToast = NECommonToastState(
        textKey: "copy_success",
        fallbackText: NECommonUIKitSwiftUIBundle.localized("copy_success", fallback: "Copied!"),
        level: .success
      )
    }
  }

  private var rowHeight: CGFloat {
    token.styleMode == .fun ? 46 : 62
  }

  private var topInputInset: CGFloat {
    token.styleMode == .fun ? 0 : 12
  }

  private var chatActionColor: Color {
    token.styleMode == .fun ? Color(hex: 0x525C8C) : Color(hex: 0x337EFF)
  }

  private var userInfoTitleColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.darkText
  }

  private var userInfoSubtitleColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.greyText
  }

  private var userInfoDetailColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.detailText
  }

  private var headerSeparatorColor: Color {
    token.styleMode == .fun ? Color(hex: 0xF5F8FC) : Color(hex: 0xF5F8FC)
  }

  private var rowSeparator: some View {
    Rectangle()
      .fill(Color(hex: 0xF5F8FC))
      .frame(height: 1)
      .padding(.horizontal, 20)
  }

  private var aliasEditorFocusBinding: Binding<Bool> {
    Binding(
      get: { aliasEditorFocused },
      set: { aliasEditorFocused = $0 }
    )
  }

  private func saveAlias() {
    if !aliasDraft.isEmpty, aliasDraft.trimmingCharacters(in: .whitespaces).isEmpty {
      aliasValidationToast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("space_not_support", value: "All Spaces are not supported"))
      aliasDraft = ""
      return
    }
    aliasEditorFocused = false
    viewModel.updateAlias(aliasDraft) { succeeded in
      guard succeeded else { return }
      isAliasEditorPresented = false
      viewModel.consumeAliasSaveSucceeded()
    }
  }
}
