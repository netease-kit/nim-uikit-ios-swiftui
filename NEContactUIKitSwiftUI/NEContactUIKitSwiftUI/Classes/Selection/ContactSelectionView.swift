// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatKit
import NEChatUIKitSwiftUI
import SwiftUI

public struct ContactSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ContactSelectionViewModel
  private let token: ContactThemeToken
  private let dismissOnComplete: Bool
  private let onComplete: (ContactSelectionResult) -> Void

  public init(viewModel: ContactSelectionViewModel,
              token: ContactThemeToken,
              dismissOnComplete: Bool = true,
              onComplete: @escaping (ContactSelectionResult) -> Void) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.dismissOnComplete = dismissOnComplete
    self.onComplete = onComplete
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSelectionHeaderView(
        title: viewModel.context.title,
        token: token,
        doneTitle: doneTitle,
        isDoneEnabled: viewModel.isDoneEnabled,
        onBack: { dismiss() },
        onDone: {
          if let result = viewModel.makeResult() {
            onComplete(result)
            if dismissOnComplete {
              dismiss()
            }
          }
        }
      )

      if !viewModel.selectedRows.isEmpty {
        selectedStrip
      }

      if viewModel.showsTabs {
        ContactSelectionTabBar(
          tabs: viewModel.selectionTabs,
          selection: $viewModel.selectedTab,
          token: token
        )
      }

      content
    }
    .background(token.pageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .neCommonTransientOverlay(viewModel.toast, placement: .top, topPadding: 52, onDismiss: { viewModel.consumeToast($0) }) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var selectedStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(viewModel.selectedRows) { row in
          ContactRowAvatar(row: row, token: token, size: 32)
            .frame(width: 46, height: 36)
          .onTapGesture {
            viewModel.removeSelected(row)
          }
        }
      }
      .padding(.horizontal, 16)
    }
    .frame(height: 59)
    .background(token.rowBackground)
  }

  private var doneTitle: String {
    let baseTitle = NECommonUIKitSwiftUIBundle.localized("sure", fallback: "OK")
    guard viewModel.context.updatesDoneTitleWithCount,
          !viewModel.selectedRows.isEmpty else {
      return baseTitle
    }
    return "\(baseTitle)(\(viewModel.selectedRows.count))"
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true), retry: { viewModel.load() })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      if viewModel.sections.flatMap(\.entries).isEmpty {
        NECommonEmptyStateView(state: emptyState)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(viewModel.sections) { section in
              Section {
                ForEach(section.entries) { row in
                  ContactRowView(entry: row, token: token, showsSelection: true, showsOnlineStatus: false)
                    .onTapGesture { viewModel.toggle(row) }
                }
              } header: {
                if !section.title.isEmpty {
                  ContactSectionHeaderView(title: section.title, token: token)
                }
              }
            }
          }
        }
      }
    }
  }

  private var emptyState: NECommonEmptyState {
    switch viewModel.selectedTab {
    case .friends:
      return NECommonEmptyState(
        titleKey: "no_friend",
        fallbackTitle: NEContactUIKitSwiftUIBundle.localized("no_friend", value: "No Contact"),
        imageKind: .user
      )
    case .aiUsers:
      return NECommonEmptyState(
        titleKey: "no_ai_user",
        fallbackTitle: NEContactUIKitSwiftUIBundle.localized("no_ai_user", value: "No AI User"),
        imageKind: .user
      )
    }
  }
}

private struct ContactSelectionHeaderView: View {
  var title: String
  var token: ContactThemeToken
  var doneTitle: String
  var isDoneEnabled: Bool
  var onBack: () -> Void
  var onDone: () -> Void

  var body: some View {
    ZStack {
      Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(token.primaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 88)

      HStack(spacing: 0) {
        Button(action: onBack) {
          if token.styleMode == .fun {
            Text(NEContactUIKitSwiftUIBundle.localized("close", value: "Close"))
              .font(.system(size: 16))
              .foregroundColor(token.primaryTextColor)
              .lineLimit(1)
              .frame(width: 60, height: 44, alignment: .leading)
          } else {
            Image("back_arrow", bundle: NECommonUIKitSwiftUIBundle.bundle)
              .renderingMode(.original)
              .resizable()
              .scaledToFit()
              .frame(width: 10, height: 18)
              .frame(width: 50, height: 44, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("id.backArrow")

        Spacer(minLength: 0)

        Button(action: onDone) {
          Text(doneTitle)
            .font(.system(size: 16))
            .foregroundColor(doneForeground)
            .lineLimit(1)
            .frame(width: doneButtonWidth, height: 32)
            .background(doneBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .disabled(!isDoneEnabled)
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
    }
    .frame(height: 44)
    .background(token.navigationBackground)
  }

  private var doneButtonWidth: CGFloat {
    token.styleMode == .fun ? 90 : 76
  }

  private var doneForeground: Color {
    if isDoneEnabled {
      return token.styleMode == .fun ? .white : token.accentColor
    }
    return token.styleMode == .fun ? .white.opacity(0.75) : token.tertiaryTextColor
  }

  private var doneBackground: Color {
    if token.styleMode == .fun {
      return isDoneEnabled ? token.accentColor : token.tertiaryTextColor.opacity(0.45)
    }
    return .white
  }
}

private struct ContactSelectionTabBar: View {
  var tabs: [ContactSelectionTab]
  @Binding var selection: ContactSelectionTab
  var token: ContactThemeToken

  var body: some View {
    HStack(spacing: 0) {
      ForEach(tabs) { tab in
        Button {
          selection = tab
        } label: {
          VStack(spacing: 0) {
            Text(tab.title)
              .font(.system(size: 15))
              .foregroundColor(selection == tab ? token.accentColor : token.primaryTextColor)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
              .fill(selection == tab ? token.accentColor : Color.clear)
              .frame(height: 2)
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
      }
    }
    .frame(height: 44)
    .background(token.rowBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(token.rowSeparatorColor)
        .frame(height: 1)
    }
  }
}

private struct ContactRowAvatar: View {
  var row: ContactEntryState
  var token: ContactThemeToken
  var size: CGFloat

  var body: some View {
    if let imageName = row.imageName {
      ContactImageResource(name: imageName, size: size)
    } else {
      NECommonAvatarView(
        imageURL: resolvedAvatarURL,
        initials: NECommonAvatarDisplayResolver.initials(
          displayName: row.avatarName,
          fallbackID: row.accountId
        ),
        size: size,
        cornerRadius: token.avatarCornerRadius,
        hashID: row.accountId
      )
    }
  }

  private var resolvedAvatarURL: URL? {
    NECommonAvatarDisplayResolver.url(from: row.avatarURL) ??
      row.accountId
      .flatMap { NEFriendUserCache.shared.getFriendInfo($0)?.user?.avatar }
      .flatMap { NECommonAvatarDisplayResolver.url(from: $0) }
  }
}
