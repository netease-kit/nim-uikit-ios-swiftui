// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamMemberRowView: View {
  public var member: NETeamSwiftUIMemberState
  public var token: NETeamThemeToken
  public var showsOwnerBadge: Bool
  public var style: NETeamSwiftUIStyleMode
  public var teamType: NETeamSwiftUITeamType
  public var displayScope: NETeamMemberDisplayScope
  public var config: NETeamSwiftUIConfig
  public var onTap: (() -> Void)?
  public var trailingAction: AnyView?

  public init(member: NETeamSwiftUIMemberState,
              token: NETeamThemeToken,
              showsOwnerBadge: Bool = true,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              displayScope: NETeamMemberDisplayScope = .all,
              config: NETeamSwiftUIConfig = NETeamSwiftUIConfigCenter.shared.current(),
              onTap: (() -> Void)? = nil,
              trailingAction: AnyView? = nil) {
    self.member = member
    self.token = token
    self.showsOwnerBadge = showsOwnerBadge
    self.style = style
    self.teamType = teamType
    self.displayScope = displayScope
    self.config = config
    self.onTap = onTap
    self.trailingAction = trailingAction
  }

  public init<TrailingAction: View>(member: NETeamSwiftUIMemberState,
                                    token: NETeamThemeToken,
                                    showsOwnerBadge: Bool = true,
                                    style: NETeamSwiftUIStyleMode = .normal,
                                    teamType: NETeamSwiftUITeamType = .normal,
                                    displayScope: NETeamMemberDisplayScope = .all,
                                    config: NETeamSwiftUIConfig = NETeamSwiftUIConfigCenter.shared.current(),
                                    onTap: (() -> Void)? = nil,
                                    @ViewBuilder trailingAction: () -> TrailingAction) {
    self.member = member
    self.token = token
    self.showsOwnerBadge = showsOwnerBadge
    self.style = style
    self.teamType = teamType
    self.displayScope = displayScope
    self.config = config
    self.onTap = onTap
    self.trailingAction = AnyView(trailingAction())
  }

  public var body: some View {
    rowContent
      .frame(height: rowHeight)
      .background(token.rowBackground)
      .accessibilityIdentifier("team-member-\(member.accountId)")
  }

  @ViewBuilder
  private var rowContent: some View {
    switch displayScope {
    case .selection, .transferOwner:
      selectionRowContent
    case .all, .managers:
      memberListRowContent
    }
  }

  private var memberListRowContent: some View {
    HStack(spacing: 14) {
      if config.shouldShowMemberAvatar(context) {
        avatar
      }

      titleContent

      Spacer(minLength: 8)

      roleBadgeView

      if member.isChatBanned {
        NETeamCommonPresentation.iconView(
          imageName: "clear_btn",
          token: token,
          renderingMode: .original,
          size: CGSize(width: 14, height: 14),
          font: .system(size: 14, weight: .semibold),
          foregroundColor: token.secondaryText,
          accessibilityLabel: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.chatBanned, value: "Muted")
        )
      }

      if let trailingAction {
        trailingAction
      }
    }
    .padding(.leading, 21)
    .padding(.trailing, style == .fun ? 16 : 20)
    .contentShape(Rectangle())
    .onTapGesture {
      onTap?()
    }
  }

  @ViewBuilder
  private var selectionRowContent: some View {
    let content = HStack(spacing: selectionSpacing) {
      if let trailingAction {
        trailingAction
      }

      if config.shouldShowMemberAvatar(context) {
        avatar
      }

      titleContent

      Spacer(minLength: 12)

      if member.isChatBanned {
        NETeamCommonPresentation.iconView(
          imageName: "clear_btn",
          token: token,
          renderingMode: .original,
          size: CGSize(width: 14, height: 14),
          font: .system(size: 14, weight: .semibold),
          foregroundColor: token.secondaryText,
          accessibilityLabel: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.chatBanned, value: "Muted")
        )
      }
    }
    .padding(.leading, selectionLeadingPadding)
    .padding(.trailing, selectionTrailingPadding)
    .contentShape(Rectangle())

    if let onTap {
      content.onTapGesture(perform: onTap)
    } else {
      content
    }
  }

  private var context: NETeamMemberContext {
    NETeamMemberContext(
      member: member,
      style: style,
      teamType: teamType,
      displayScope: displayScope
    )
  }

  @ViewBuilder
  private var titleContent: some View {
    if let customContent = config.memberRowContentProvider?(context) {
      customContent
    } else {
      Text(member.displayName)
        .font(.system(size: 16))
        .foregroundStyle(token.primaryText)
        .lineLimit(1)
        .truncationMode(.tail)

      if config.shouldShowMemberAccountId(context), shouldShowAccountIdText {
        Text(member.accountId)
          .font(.system(size: 12))
          .foregroundStyle(token.secondaryText)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }

  @ViewBuilder
  private var roleBadgeView: some View {
    if config.shouldShowMemberRoleBadge(context), displayScope == .all {
      if showsOwnerBadge, member.role == .owner {
        roleBadge(
          NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamOwner, value: "team owner"),
          role: .owner
        )
      } else if member.role == .manager {
        roleBadge(
          NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamManager, value: "Admin"),
          role: .manager
        )
      }
    }
  }

  @ViewBuilder
  private var avatar: some View {
    NETeamCommonPresentation.avatarView(
      imageURL: NECommonAvatarDisplayResolver.url(from: member.avatarURL),
      initials: NECommonAvatarDisplayResolver.initials(
        displayName: member.avatarName,
        fallbackID: member.accountId
      ),
      token: token,
      size: avatarSize,
      cornerRadius: avatarCornerRadius,
      hashID: member.accountId
    )
  }

  private func roleBadge(_ title: String, role: NETeamSwiftUIMemberRole) -> some View {
    NETeamCommonPresentation.badgeView(
      text: title,
      token: token,
      minSize: roleBadgeHeight,
      horizontalPadding: 0,
      verticalPadding: 0,
      background: roleBadgeBackgroundColor(for: role),
      foreground: roleBadgeTextColor(for: role)
    )
      .frame(width: roleBadgeWidth(for: role), height: roleBadgeHeight)
      .background(roleBadgeBackgroundColor(for: role))
      .overlay(
        RoundedRectangle(cornerRadius: roleBadgeCornerRadius, style: .continuous)
          .stroke(roleBadgeBorderColor(for: role), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: roleBadgeCornerRadius, style: .continuous))
  }

  private var rowHeight: CGFloat {
    switch displayScope {
    case .selection, .transferOwner:
      return style == .fun ? 64 : 50
    case .all:
      return token.memberRowHeight
    case .managers:
      return style == .fun ? 64 : 52
    }
  }

  private var avatarSize: CGFloat {
    switch displayScope {
    case .selection, .transferOwner:
      return style == .fun ? 40 : 36
    case .all, .managers:
      return token.memberAvatarSize
    }
  }

  private var avatarCornerRadius: CGFloat {
    switch displayScope {
    case .selection, .transferOwner:
      return style == .fun ? 4 : 18
    case .all, .managers:
      return token.memberAvatarCornerRadius
    }
  }

  private var selectionSpacing: CGFloat {
    style == .fun ? 16 : 14
  }

  private var selectionLeadingPadding: CGFloat {
    style == .fun ? 16 : 18
  }

  private var selectionTrailingPadding: CGFloat {
    style == .fun ? 16 : 18
  }

  private var shouldShowAccountIdText: Bool {
    !member.accountId.isEmpty && member.accountId != member.displayName
  }

  private var roleBadgeHeight: CGFloat {
    style == .fun ? 25 : 22
  }

  private var roleBadgeCornerRadius: CGFloat {
    style == .fun ? 4 : 11
  }

  private func roleBadgeWidth(for role: NETeamSwiftUIMemberRole) -> CGFloat {
    switch style {
    case .normal:
      switch role {
      case .owner:
        return isEnglish ? 86 : 40
      case .manager:
        return isEnglish ? 58 : 52
      default:
        return 0
      }
    case .fun:
      switch role {
      case .owner:
        return isEnglish ? 80 : 48
      case .manager:
        return 60
      default:
        return 0
      }
    }
  }

  private func roleBadgeTextColor(for role: NETeamSwiftUIMemberRole) -> Color {
    if style == .fun, role == .manager {
      return Color(hex: 0xEA8339)
    }
    return token.ownerText
  }

  private func roleBadgeBackgroundColor(for role: NETeamSwiftUIMemberRole) -> Color {
    if style == .fun, role == .manager {
      return Color(hex: 0xF2C46B).opacity(0.1)
    }
    return token.ownerBackground
  }

  private func roleBadgeBorderColor(for role: NETeamSwiftUIMemberRole) -> Color {
    if style == .fun, role == .manager {
      return Color(hex: 0xF2C46B)
    }
    return token.ownerBorder
  }

  private var isEnglish: Bool {
    let languageCode = Locale.current.languageCode?.lowercased() ?? ""
    return languageCode.hasPrefix("en")
  }
}
