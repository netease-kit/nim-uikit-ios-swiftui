// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamSettingHeaderView: View {
  public var title: String
  public var subtitle: String
  public var avatarURL: String?
  public var hashID: String?
  public var token: NETeamThemeToken
  public var style: NETeamSwiftUIStyleMode
  public var onLongPressSubtitle: (() -> Void)?
  public var onOpenInfo: () -> Void

  public init(title: String,
              subtitle: String,
              avatarURL: String? = nil,
              hashID: String? = nil,
              token: NETeamThemeToken,
              style: NETeamSwiftUIStyleMode = .normal,
              onLongPressSubtitle: (() -> Void)? = nil,
              onOpenInfo: @escaping () -> Void = {}) {
    self.title = title
    self.subtitle = subtitle
    self.avatarURL = avatarURL
    self.hashID = hashID
    self.token = token
    self.style = style
    self.onLongPressSubtitle = onLongPressSubtitle
    self.onOpenInfo = onOpenInfo
  }

  public var body: some View {
    Button {
      onOpenInfo()
    } label: {
      HStack(spacing: 16) {
        NETeamCommonPresentation.avatarView(
          imageURL: NECommonAvatarDisplayResolver.url(from: avatarURL),
          initials: initials,
          token: token,
          size: token.headerAvatarSize,
          cornerRadius: token.headerAvatarCornerRadius,
          hashID: hashID ?? subtitle
        )

        VStack(alignment: .leading, spacing: 6) {
          Text(title.isEmpty ? subtitle : title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(token.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
          subtitleView
        }

        Spacer(minLength: 8)
        NETeamCommonPresentation.chevron(token: token)
      }
      .padding(.horizontal, 16)
      .frame(height: token.headerAvatarSize + 26)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(token.rowBackground)
  }

  private var initials: String {
    NECommonAvatarDisplayResolver.initials(
      displayName: title,
      fallbackID: hashID ?? subtitle,
      defaultText: "#"
    )
  }

  @ViewBuilder
  private var subtitleView: some View {
    if let onLongPressSubtitle {
      subtitleText
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onLongPressSubtitle)
    } else {
      subtitleText
    }
  }

  private var subtitleText: some View {
    Text(subtitle)
      .font(.system(size: 13))
      .foregroundStyle(token.secondaryText)
      .lineLimit(1)
      .truncationMode(.tail)
  }
}
