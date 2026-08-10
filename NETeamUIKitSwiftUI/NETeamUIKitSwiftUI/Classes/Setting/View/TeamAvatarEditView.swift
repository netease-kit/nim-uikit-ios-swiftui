// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamAvatarEditView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamAvatarEditViewModel
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onSaved: () -> Void

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onSaved: @escaping () -> Void = {}) {
    _viewModel = StateObject(wrappedValue: TeamAvatarEditViewModel(teamId: teamId, style: style, teamType: teamType))
    self.style = style
    self.token = token ?? (style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default)
    self.onSaved = onSaved
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.modifyHeadImage, value: "Modify Avatar"),
          token: token,
          backAction: {
            dismiss()
          },
          trailingAction: viewModel.state.canEdit ? NETeamCommonPresentation.textNavigationAction(
            id: "save",
            title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.save, value: "Save")
          ) : nil,
          onTrailingAction: {
            guard viewModel.state.canSubmit else {
              return
            }
            viewModel.save()
          },
          trailingActionEnabled: viewModel.state.canSubmit,
          showsSeparator: false
        )

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      viewModel.refreshIfNeeded()
    }
    .onChange(of: viewModel.state.didSave) { didSave in
      guard didSave else {
        return
      }
      onSaved()
      dismiss()
    }
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamAvatarEditSaving",
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
      VStack(spacing: avatarSectionSpacing) {
        headerSection

        if viewModel.state.canEdit {
          defaultAvatarSection
        }

        Spacer(minLength: 0)
      }
      .padding(.top, avatarTopPadding)
    }
  }

  private var headerSection: some View {
    ZStack(alignment: .center) {
      token.rowBackground

      Button {
        guard shouldShowHostAvatarPicker, !viewModel.state.isSaving else {
          return
        }
        viewModel.selectAvatarFromHost()
      } label: {
        ZStack(alignment: .bottomTrailing) {
          avatarPreview

          if shouldShowHostAvatarPicker {
            NETeamCommonPresentation.iconView(
              imageName: "photo",
              token: token,
              renderingMode: .original,
              size: cameraIconSize,
              accessibilityLabel: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamHeader, value: "Profile Picture")
            )
            .offset(x: cameraIconOffset.width, y: cameraIconOffset.height)
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(!shouldShowHostAvatarPicker || viewModel.state.isSaving)
    }
    .frame(height: 128)
    .clipShape(RoundedRectangle(cornerRadius: avatarContainerCornerRadius, style: .continuous))
    .padding(.horizontal, avatarContainerHorizontalPadding)
  }

  @ViewBuilder
  private var avatarPreview: some View {
    NETeamCommonPresentation.avatarView(
      imageURL: viewModel.state.normalizedDraftURL.isEmpty
        ? nil
        : URL(string: viewModel.state.normalizedDraftURL),
      initials: "",
      token: token,
      size: token.avatarEditPreviewSize,
      cornerRadius: token.avatarEditPreviewCornerRadius,
      fallbackImageName: TeamAvatarResourceMapper.imageName(for: viewModel.state.normalizedDraftURL, style: style),
      hashID: viewModel.teamId
    )
  }

  private var defaultAvatarSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.defaultIcon, value: "Select Default icon"))
        .font(.system(size: 16))
        .foregroundStyle(token.primaryText)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
        ForEach(viewModel.state.defaultAvatarURLs, id: \.self) { url in
          defaultAvatarButton(url)
        }
      }
    }
    .padding(.leading, defaultAvatarLeadingPadding)
    .padding(.trailing, defaultAvatarTrailingPadding)
    .padding(.top, defaultAvatarTopPadding)
    .padding(.bottom, defaultAvatarBottomPadding)
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: avatarContainerCornerRadius, style: .continuous))
    .padding(.horizontal, avatarContainerHorizontalPadding)
  }

  private func defaultAvatarButton(_ url: String) -> some View {
    Button {
      viewModel.selectDefaultAvatar(url)
    } label: {
      defaultAvatarIcon(url)
      .frame(maxWidth: .infinity, minHeight: token.defaultAvatarSelectionSize)
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.state.canEdit || viewModel.state.isSaving)
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
    viewModel.state.normalizedDraftURL == url
      ? Color(hex: 0xF4F4F4)
      : Color.clear
  }

  private var avatarTopPadding: CGFloat {
    style == .fun ? 0 : 12
  }

  private var avatarSectionSpacing: CGFloat {
    style == .fun ? 8 : 12
  }

  private var avatarContainerHorizontalPadding: CGFloat {
    style == .fun ? 0 : 20
  }

  private var avatarContainerCornerRadius: CGFloat {
    style == .fun ? 0 : 8
  }

  private var defaultAvatarLeadingPadding: CGFloat {
    style == .fun ? 16 : 16
  }

  private var defaultAvatarTrailingPadding: CGFloat {
    style == .fun ? 16 : 18
  }

  private var defaultAvatarTopPadding: CGFloat {
    style == .fun ? 16 : 15
  }

  private var defaultAvatarBottomPadding: CGFloat {
    style == .fun ? 18 : 16
  }

  private var shouldShowHostAvatarPicker: Bool {
    viewModel.state.canEdit && NETeamUIKitSwiftUIClient.shared.avatarSelectionHandler != nil
  }

  private var cameraIconSize: CGSize {
    CGSize(width: 24, height: 24)
  }

  private var cameraIconOffset: CGSize {
    CGSize(width: 4, height: 4)
  }
}
