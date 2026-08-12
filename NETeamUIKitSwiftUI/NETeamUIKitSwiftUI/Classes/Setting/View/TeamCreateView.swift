// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamCreateView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamCreateViewModel
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onCreated: () -> Void

  public init(style: NETeamSwiftUIStyleMode = .normal,
              token: NETeamThemeToken? = nil,
              onCreated: @escaping () -> Void = {}) {
    _viewModel = StateObject(wrappedValue: TeamCreateViewModel(style: style))
    self.style = style
    self.token = token ?? (style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default)
    self.onCreated = onCreated
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.createTeam, value: "Create Team"),
          token: token,
          backAction: {
            dismiss()
          },
          showsSeparator: false
        )

        ScrollView {
          VStack(spacing: 18) {
            avatarPreview
            formContent
            createButton
          }
          .padding(.horizontal, 16)
          .padding(.top, 24)
          .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.immediately)
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onChange(of: viewModel.state.didCreate) { didCreate in
      guard didCreate else {
        return
      }
      onCreated()
      dismiss()
    }
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamCreateSubmitting",
        isPresented: viewModel.state.isCreating
      )
    )
    .neCommonToastOverlay(
      NETeamCommonPresentation.toast(viewModel.state.toast),
      placement: .top,
      topPadding: 10,
      onDismiss: { _ in viewModel.consumeToast() }
    )
  }

  private var avatarPreview: some View {
    VStack(spacing: 12) {
      NETeamCommonPresentation.avatarView(
        imageURL: viewModel.state.normalizedAvatarURL.isEmpty ? nil : URL(string: viewModel.state.normalizedAvatarURL),
        initials: "",
        token: token,
        size: token.avatarEditPreviewSize,
        cornerRadius: token.avatarEditPreviewCornerRadius,
        fallbackImageName: TeamAvatarResourceMapper.imageName(for: viewModel.state.normalizedAvatarURL, style: style),
        hashID: viewModel.state.normalizedName
      )

      defaultAvatarSection

      NETeamCommonPresentation.actionButton(
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamAvatar, value: "Team Avatar"),
        token: token,
        imageName: "photo",
        renderingMode: .original,
        style: .secondary,
        isEnabled: !viewModel.state.isCreating,
        isLoading: viewModel.state.isSelectingAvatar,
        minHeight: 40
      ) {
        viewModel.selectAvatarFromHost()
      }
    }
  }

  private var defaultAvatarSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.defaultIcon, value: "Select Default icon"))
        .font(.system(size: 15))
        .foregroundStyle(token.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
        ForEach(viewModel.state.defaultAvatarURLs, id: \.self) { url in
          defaultAvatarButton(url)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .background(token.rowBackground)
  }

  private func defaultAvatarButton(_ url: String) -> some View {
    Button {
      viewModel.selectDefaultAvatar(url)
    } label: {
      ZStack(alignment: .bottomTrailing) {
        defaultAvatarIcon(url)
        NETeamCommonPresentation.selectionIndicator(
          isSelected: viewModel.state.normalizedAvatarURL == url,
          isEnabled: !viewModel.state.isCreating,
          token: token,
          size: 16
        )
        .background(Circle().fill(token.rowBackground))
      }
      .frame(maxWidth: .infinity, minHeight: token.defaultAvatarSelectionSize)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.state.isCreating)
  }

  private func defaultAvatarIcon(_ url: String) -> some View {
    NETeamCommonPresentation.avatarView(
      imageURL: URL(string: url),
      initials: "",
      token: token,
      size: token.defaultAvatarIconSize,
      cornerRadius: token.defaultAvatarIconCornerRadius,
      fallbackImageName: TeamAvatarResourceMapper.imageName(for: url, style: style),
      hashID: url
    )
    .frame(width: token.defaultAvatarSelectionSize, height: token.defaultAvatarSelectionSize)
    .background(selectionBackground(for: url))
    .clipShape(RoundedRectangle(cornerRadius: token.defaultAvatarIconCornerRadius, style: .continuous))
  }

  private func selectionBackground(for url: String) -> Color {
    viewModel.state.normalizedAvatarURL == url
      ? token.separator.opacity(0.55)
      : Color.clear
  }

  private var formContent: some View {
    VStack(spacing: 12) {
      NETeamCommonPresentation.formTextField(
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamName, value: "Team Name"),
        text: Binding(
          get: { viewModel.state.draftName },
          set: { viewModel.updateName($0) }
        ),
        placeholder: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.seniorTeam, value: "Group"),
        token: token,
        isEnabled: !viewModel.state.isCreating,
        horizontalPadding: 12,
        verticalPadding: 0,
        minHeight: 44,
        characterLimit: 30
      )

      HStack {
        Spacer()
        NETeamCommonPresentation.characterCounter(
          count: viewModel.state.nameUTF16Count,
          limit: 30,
          token: token,
          isWarning: viewModel.state.nameUTF16Count > 30
        )
      }

      NETeamCommonPresentation.settingRow(
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.selectedMembers, value: "Selected Members"),
        value: "\(viewModel.state.selectedAccountIds.count)",
        token: token,
        isEnabled: !viewModel.state.isCreating,
        minHeight: 48,
        action: {
          viewModel.selectMembersFromHost()
        }
      ) {
        if viewModel.state.isSelectingMembers {
          NETeamCommonPresentation.inlineLoadingView()
        } else {
          NETeamCommonPresentation.chevron(token: token)
        }
      }

      if !viewModel.state.selectedAccountIds.isEmpty {
        Text(viewModel.state.selectedAccountIds.joined(separator: ", "))
          .font(.system(size: 12))
          .foregroundStyle(token.secondaryText)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      NETeamCommonPresentation.formTextField(
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamAvatar, value: "Team Avatar"),
        text: Binding(
          get: { viewModel.state.draftAvatarURL },
          set: { viewModel.updateAvatarURL($0) }
        ),
        placeholder: "https://",
        token: token,
        isEnabled: !viewModel.state.isCreating,
        horizontalPadding: 12,
        verticalPadding: 0,
        minHeight: 42
      )
    }
  }

  private var createButton: some View {
    NETeamCommonPresentation.actionButton(
      title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.createTeam, value: "Create Team"),
      token: token,
      imageName: TeamAvatarResourceMapper.imageName(for: viewModel.state.normalizedAvatarURL, style: style),
      renderingMode: .original,
      isEnabled: viewModel.state.canSubmit,
      isLoading: viewModel.state.isCreating,
      minHeight: 48
    ) {
      viewModel.createTeam()
    }
    .padding(.top, 8)
  }
}
