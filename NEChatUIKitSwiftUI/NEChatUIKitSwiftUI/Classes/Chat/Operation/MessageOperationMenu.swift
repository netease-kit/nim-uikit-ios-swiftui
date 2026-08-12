// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct MessageOperationMenu: View {
  fileprivate static let maxColumnCount = 5
  fileprivate static let itemWidth: CGFloat = 60
  fileprivate static let itemHeight: CGFloat = 56
  fileprivate static let horizontalPadding: CGFloat = 8
  fileprivate static let verticalPadding: CGFloat = 8

  public var menu: OperationMenuState
  public var token: ChatThemeToken
  public var onSelect: (MessageOperation, String) -> Void

  public init(menu: OperationMenuState,
              token: ChatThemeToken,
              onSelect: @escaping (MessageOperation, String) -> Void) {
    self.menu = menu
    self.token = token
    self.onSelect = onSelect
  }

  public var body: some View {
    let columns = Array(
      repeating: GridItem(.fixed(Self.itemWidth), spacing: 0),
      count: Self.columnCount(for: menu.descriptors.count)
    )

    LazyVGrid(columns: columns, spacing: 0) {
      ForEach(menu.descriptors) { descriptor in
        Button {
          onSelect(descriptor.operation, menu.messageId)
        } label: {
          MessageOperationItemView(descriptor: descriptor, token: token)
        }
        .buttonStyle(.plain)
        .disabled(!descriptor.isEnabled)
      }
    }
    .padding(.horizontal, Self.horizontalPadding)
    .padding(.vertical, Self.verticalPadding)
    .frame(
      width: Self.preferredSize(itemCount: menu.descriptors.count).width,
      height: Self.preferredSize(itemCount: menu.descriptors.count).height
    )
    .background(token.floatingPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.floatingPanelCornerRadius, style: .continuous))
    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    .accessibilityElement(children: .contain)
  }

  public static func preferredSize(itemCount: Int) -> CGSize {
    let count = max(1, itemCount)
    let columns = columnCount(for: count)
    let rows = Int(ceil(Double(count) / Double(max(1, columns))))
    return CGSize(
      width: CGFloat(columns) * itemWidth + horizontalPadding * 2,
      height: CGFloat(rows) * itemHeight + verticalPadding * 2
    )
  }

  private static func columnCount(for itemCount: Int) -> Int {
    min(max(1, itemCount), maxColumnCount)
  }
}

private struct MessageOperationItemView: View {
  var descriptor: ChatOperationDescriptor
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 8) {
      operationIcon

      Text(descriptor.title)
        .font(.system(size: 14))
        .foregroundColor(descriptor.isEnabled ? token.incomingTextColor : token.secondaryTextColor.opacity(0.65))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .truncationMode(.tail)
        .frame(width: MessageOperationMenu.itemWidth, height: 22, alignment: .top)
    }
    .frame(width: MessageOperationMenu.itemWidth, height: MessageOperationMenu.itemHeight)
    .contentShape(Rectangle())
    .opacity(descriptor.isEnabled ? 1 : 0.5)
  }

  @ViewBuilder
  private var operationIcon: some View {
    if let resource = descriptor.imageResource {
      NEChatCommonPresentation.iconView(
        resource: NECommonImageResource(
          imageName: resource.name,
          bundle: resource.bundle,
          renderingMode: .original
        ),
        token: token,
        isEnabled: descriptor.isEnabled,
        size: CGSize(width: 18, height: 18),
        accessibilityLabel: descriptor.title
      )
    } else if let imageName = descriptor.imageName {
      NEChatCommonPresentation.iconView(
        imageName: imageName,
        token: token,
        renderingMode: .original,
        isEnabled: descriptor.isEnabled,
        size: CGSize(width: 18, height: 18),
        accessibilityLabel: descriptor.title
      )
    } else {
      NEChatCommonPresentation.iconView(
        imageName: descriptor.operation.assetImageName,
        token: token,
        renderingMode: .original,
        isEnabled: descriptor.isEnabled,
        size: CGSize(width: 18, height: 18),
        accessibilityLabel: descriptor.title
      )
    }
  }
}

private extension MessageOperation {
  var assetImageName: String {
    switch self {
    case .copy:
      return "op_copy"
    case .delete:
      return "op_delete"
    case .revoke:
      return "op_recall"
    case .reply:
      return "op_replay"
    case .forward:
      return "op_forward"
    case .collect:
      return "op_collect"
    case .pin:
      return "op_pin"
    case .top:
      return "op_top"
    case .untop:
      return "op_untop"
    case .selectText:
      return "op_select"
    case .multiSelect:
      return "op_select"
    case .voiceToText:
      return "op_toText"
    case .earpiece:
      return "op_earpiece"
    case .speaker:
      return "op_speaker"
    case .readReceipt:
      return "chat_read_all"
    case .resend:
      return "sendMessage_failed"
    case .plugin:
      return "op_collection"
    }
  }
}
