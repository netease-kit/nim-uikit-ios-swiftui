// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

struct ConversationActionMenuView: View {
  let token: ConversationThemeToken
  let showScanQREntry: Bool
  let onSelect: (ConversationAction) -> Void

  private var actions: [ConversationAction] {
    var actions: [ConversationAction] = [.addFriend]
    if IMKitConfigCenter.shared.enableTeam {
      actions.append(contentsOf: [.joinTeam, .createDiscussion, .createSeniorTeam])
    }
    if showScanQREntry {
      actions.append(.scanQR)
    }
    return actions
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(actions) { action in
        Button {
          onSelect(action)
        } label: {
          HStack(spacing: 8) {
            Image(ConversationImageResource.menuImageName(for: action, style: token.styleMode),
                  bundle: NEConversationUIKitSwiftUIBundle.bundle)
              .renderingMode(.original)
              .resizable()
              .scaledToFit()
              .frame(width: 20, height: 20)

            Text(title(for: action))
              .font(.system(size: 14))
              .foregroundColor(token.popoverTextColor)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .frame(maxWidth: .infinity, minHeight: token.popoverItemHeight, alignment: .leading)
          .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(width: menuWidth)
    .padding(.vertical, 6)
    .background(token.popoverBackground, in: RoundedRectangle(cornerRadius: token.styleMode == .fun ? 8 : 4, style: .continuous))
    .shadow(color: Color.black.opacity(token.styleMode == .fun ? 0.18 : 0.12), radius: 10, x: 0, y: 4)
  }

  private func title(for action: ConversationAction) -> String {
    switch action {
    case .addFriend:
      return NEConversationUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts")
    case .joinTeam:
      return NECommonUIKitSwiftUIBundle.localized("join_team", fallback: "Join Team")
    case .createDiscussion:
      return NEConversationUIKitSwiftUIBundle.localized("create_discussion_group", value: "Create Discussion")
    case .createSeniorTeam:
      return NEConversationUIKitSwiftUIBundle.localized("create_senior_group", value: "Create Group")
    case .scanQR:
      return NEConversationUIKitSwiftUIBundle.localized("scan_qr", value: "Scan QR")
    }
  }

  private var menuWidth: CGFloat {
    NEAppLanguageUtil.getCurrentLanguage() == .english ? 180 : 122
  }
}
