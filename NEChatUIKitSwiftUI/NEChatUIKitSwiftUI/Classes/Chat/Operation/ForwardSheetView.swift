// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct ForwardSheetView: View {
  public var state: ChatForwardSheetState
  public var token: ChatThemeToken
  public var onToggleTarget: (ChatForwardTargetState) -> Void
  public var onCommentChange: (String) -> Void
  public var onConfirm: () -> Void
  public var onCancel: () -> Void

  @State private var comment: String

  public init(state: ChatForwardSheetState,
              token: ChatThemeToken,
              onToggleTarget: @escaping (ChatForwardTargetState) -> Void,
              onCommentChange: @escaping (String) -> Void,
              onConfirm: @escaping () -> Void,
              onCancel: @escaping () -> Void) {
    self.state = state
    self.token = token
    self.onToggleTarget = onToggleTarget
    self.onCommentChange = onCommentChange
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    _comment = State(initialValue: state.comment)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      content
      actionBar
    }
    .padding(18)
    .background(token.panelItemBackground)
    .onChange(of: comment) { next in
      onCommentChange(next)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(forwardTypeTitle)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(token.incomingTextColor)

      Text(String(format: NEChatUIKitSwiftUIBundle.localized("chat_forward_count_format", value: "%d messages"), state.request.messageIds.count))
        .font(.system(size: 14))
        .foregroundColor(token.secondaryTextColor)

      if state.request.merged {
        Text(NEChatUIKitSwiftUIBundle.localized("chat_forward_merged_desc", value: "Messages will be sent as one chat history card."))
          .font(NEUIKitSwiftUIStyle.FontToken.settingSubtitle)
          .foregroundColor(token.secondaryTextColor)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if !state.fixedTargets.isEmpty {
      fixedTargetsContent
    } else if state.recentTargets.isEmpty {
      NEChatCommonPresentation.inlineEmptyView(
        title: NEChatUIKitSwiftUIBundle.localized("chat_forward_no_recent_target", value: "No recent forward target"),
        token: token,
        imageName: "op_forward",
        message: NEChatUIKitSwiftUIBundle.localized("chat_forward_no_recent_target_desc", value: "Provide a SwiftUI forwardSelectionHandler to open the app selection page, or forward once to build recent targets.")
      )
      .frame(maxWidth: .infinity)
      .background(token.searchFieldBackground)
      .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Text(NEChatUIKitSwiftUIBundle.localized("chat_recent_forward", value: "Recent Forward"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(token.incomingTextColor)

        Text(String(format: NEChatUIKitSwiftUIBundle.localized("chat_recent_forward_count_format", value: "%d recent targets"), state.recentTargets.count))
          .font(.system(size: 12))
          .foregroundColor(token.secondaryTextColor)

        ForEach(state.recentTargets) { target in
          Button {
            onToggleTarget(target)
          } label: {
            forwardTargetRow(target, isSelectable: true)
          }
          .buttonStyle(.plain)
        }

        NEChatCommonPresentation.formTextField(
          text: $comment,
          placeholder: NEChatUIKitSwiftUIBundle.localized("chat_forward_comment_placeholder", value: "Leave a comment"),
          token: commentFieldToken,
          axis: .vertical,
          horizontalPadding: 10,
          verticalPadding: 10,
          backgroundCornerRadius: token.controlCornerRadius
        )
        .lineLimit(1...3)
      }
    }
  }

  private var fixedTargetsContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(NEChatUIKitSwiftUIBundle.localized("send_to", value: "Send to"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(token.incomingTextColor)

      ForEach(state.fixedTargets) { target in
        forwardTargetRow(target, isSelectable: false)
      }

      NEChatCommonPresentation.formTextField(
        text: $comment,
        placeholder: NEChatUIKitSwiftUIBundle.localized("chat_forward_comment_placeholder", value: "Leave a comment"),
        token: commentFieldToken,
        axis: .vertical,
        horizontalPadding: 10,
        verticalPadding: 10,
        backgroundCornerRadius: token.controlCornerRadius
      )
      .lineLimit(1...3)
    }
  }

  private func forwardTargetRow(_ target: ChatForwardTargetState,
                                isSelectable: Bool) -> some View {
    HStack(spacing: 10) {
      if isSelectable {
        NEChatCommonPresentation.selectionIndicator(
          isSelected: state.selectedTargetIds.contains(target.id),
          token: token,
          size: 22
        )
      }

      ForwardTargetAvatar(
        avatarName: target.avatarDisplayName,
        avatarURL: target.avatarURL,
        hashID: target.avatarHashID,
        token: token
      )

      Text(target.displayTitle)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer()
    }
    .padding(.vertical, 8)
  }

  private var actionBar: some View {
    HStack {
      NEChatCommonPresentation.actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
        token: token,
        style: .secondary,
        minHeight: 40,
        action: onCancel
      )

      NEChatCommonPresentation.actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("confirm", value: "Confirm"),
        token: token,
        isEnabled: !state.selectedTargets.isEmpty,
        minHeight: 40,
        action: onConfirm
      )
    }
  }

  private var commentFieldToken: ChatThemeToken {
    var fieldToken = token
    fieldToken.inputFieldBackground = token.searchFieldBackground
    return fieldToken
  }

  private var forwardTypeTitle: String {
    if state.request.merged {
      return NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
    }
    if state.request.isFromMessageMultiSelect {
      return NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One")
    }
    return NEChatUIKitSwiftUIBundle.localized("operation_forward", value: "Forward")
  }
}

private extension ChatForwardTargetState {
  var displayTitle: String {
    let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId)
    if let trimmedTitle,
       !trimmedTitle.isEmpty,
       trimmedTitle != conversationId,
       trimmedTitle != targetId {
      return trimmedTitle
    }
    return NEChatUIKitSwiftUIBundle.localized("chat_forward_target", value: "Forward target")
  }
}

private struct ForwardTargetAvatar: View {
  var avatarName: String?
  var avatarURL: URL?
  var hashID: String
  var token: ChatThemeToken

  var body: some View {
    NEChatCommonPresentation.avatarView(
      imageURL: avatarURL,
      initials: ChatAvatarDisplayResolver.initials(displayName: avatarName, accountId: hashID),
      token: token,
      size: 36,
      cornerRadius: 18,
      hashID: hashID
    )
  }
}
