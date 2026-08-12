// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamSettingMemberPreviewView: View {
  public var snapshot: NETeamSwiftUISettingSnapshot
  public var token: NETeamThemeToken
  public var style: NETeamSwiftUIStyleMode
  public var onOpenMembers: () -> Void
  public var onInvite: () -> Void
  public var onMemberTap: (NETeamSwiftUIMemberState) -> Void

  public init(snapshot: NETeamSwiftUISettingSnapshot,
              token: NETeamThemeToken,
              style: NETeamSwiftUIStyleMode = .normal,
              onOpenMembers: @escaping () -> Void,
              onInvite: @escaping () -> Void,
              onMemberTap: @escaping (NETeamSwiftUIMemberState) -> Void) {
    self.snapshot = snapshot
    self.token = token
    self.style = style
    self.onOpenMembers = onOpenMembers
    self.onInvite = onInvite
    self.onMemberTap = onMemberTap
  }

  public var body: some View {
    VStack(spacing: 0) {
      Button {
        onOpenMembers()
      } label: {
        memberTitleRow
      }
      .buttonStyle(.plain)

      HStack(spacing: token.previewMemberSpacing) {
        if snapshot.canInviteMembers {
          inviteButton
        }

        ScrollView(.horizontal, showsIndicators: false) {
          memberAvatarRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scrollDisabled(true)
      }
      .padding(.leading, 16)
      .padding(.trailing, previewTrailingPadding)
      .frame(height: token.previewListHeight)
    }
    .background(token.rowBackground)
    .onAppear {
      debugPrint(
        "[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingMemberPreviewView appear teamId=\(snapshot.teamId) preview=\(snapshot.memberPreview.count) memberCount=\(snapshot.memberCount) canInvite=\(snapshot.canInviteMembers) main=\(Thread.isMainThread)"
      )
    }
  }

  private var memberTitleRow: some View {
    NETeamCommonPresentation.settingRow(
      title: memberTitle,
      value: "\(snapshot.memberCount)",
      token: token,
      minHeight: token.previewTitleHeight,
      leadingPadding: 16,
      trailingPadding: 16,
      verticalPadding: 0,
      titleLineLimit: 1
    ) {
      NETeamCommonPresentation.chevron(token: token)
    }
    .frame(height: token.previewTitleHeight)
    .contentShape(Rectangle())
  }

  private var inviteButton: some View {
    Button {
      onInvite()
    } label: {
      NETeamCommonPresentation.iconView(
        imageName: style == .fun ? "fun_setting_add" : "setting_add",
        token: token,
        renderingMode: .original,
        font: .system(size: 18, weight: .semibold),
        foregroundColor: token.accent,
        accessibilityLabel: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.inviteMember, value: "Invite Member")
      )
      .frame(width: token.previewAvatarSize, height: token.previewAvatarSize)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("team-setting-invite-member")
  }

  private var memberAvatarRow: some View {
    HStack(spacing: 0) {
      ForEach(snapshot.memberPreview, id: \.accountId) { member in
        Button {
          onMemberTap(member)
        } label: {
          NETeamCommonPresentation.avatarView(
            imageURL: NECommonAvatarDisplayResolver.url(from: member.avatarURL),
            initials: NECommonAvatarDisplayResolver.initials(
              displayName: member.avatarName,
              fallbackID: member.accountId
            ),
            token: token,
            size: token.previewAvatarSize,
            cornerRadius: token.previewAvatarCornerRadius,
            hashID: member.accountId
          )
        }
        .buttonStyle(.plain)
        .id(member.accountId)
        .frame(width: previewItemWidth(for: member), height: token.previewListHeight, alignment: previewItemAlignment)
        .accessibilityIdentifier("team-setting-preview-member-\(member.accountId)")
      }
    }
    .frame(height: token.previewListHeight)
  }

  private var previewTrailingPadding: CGFloat {
    style == .fun ? 16 : 15
  }

  private func previewItemWidth(for member: NETeamSwiftUIMemberState) -> CGFloat {
    if style == .fun {
      return snapshot.memberPreview.first?.accountId == member.accountId
        ? token.previewAvatarSize
        : token.previewAvatarSize + token.previewMemberSpacing
    }
    return token.previewAvatarSize + token.previewMemberSpacing
  }

  private var previewItemAlignment: Alignment {
    style == .fun ? .trailing : .leading
  }

  private var memberTitle: String {
    snapshot.kind.isDiscuss
      ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussMember, value: "Temp Group Member")
      : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.members, value: "Members")
  }
}
