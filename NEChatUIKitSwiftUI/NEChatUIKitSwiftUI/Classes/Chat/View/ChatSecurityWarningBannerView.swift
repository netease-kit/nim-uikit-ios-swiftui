// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import NECommonUIKitSwiftUI

public struct ChatSecurityWarningBannerView: View {
  public var message: String
  public var reportTitle: String?
  public var token: ChatThemeToken
  public var onReport: (() -> Void)?
  public var onDismiss: () -> Void

  public init(message: String = NEChatUIKitSwiftUIBundle.localized("security_warning", value: "Please stay alert to possible security risks."),
              reportTitle: String? = NEChatUIKitSwiftUIBundle.localized("click_to_report", value: "Report"),
              token: ChatThemeToken,
              onReport: (() -> Void)? = nil,
              onDismiss: @escaping () -> Void) {
    self.message = message
    self.reportTitle = reportTitle
    self.token = token
    self.onReport = onReport
    self.onDismiss = onDismiss
  }

  public var body: some View {
    HStack(alignment: .center, spacing: 0) {
      if showsP2PControls {
        NEChatCommonPresentation.commonIconView(
          imageName: "error",
          token: token,
          renderingMode: .original,
          size: CGSize(width: 16, height: 16),
          foregroundColor: warningTextColor,
          accessibilityLabel: message
        )
        .frame(width: 16, height: 16)
      }

      warningText
        .font(.system(size: warningFontSize))
        .lineLimit(showsP2PControls ? 2 : nil)
        .minimumScaleFactor(showsP2PControls ? 0.82 : 1)
        .allowsTightening(true)
        .multilineTextAlignment(.leading)
        .layoutPriority(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 0)

      if showsP2PControls {
        Button(action: onDismiss) {
          NEChatCommonPresentation.commonIconView(
            imageName: "remove",
            token: token,
            renderingMode: .original,
            size: CGSize(width: 16, height: 16),
            foregroundColor: warningTextColor,
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel")
          )
          .frame(width: 16, height: 16)
          .frame(width: 24, height: 44, alignment: .center)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"))
      }
    }
    .padding(.leading, 16)
    .padding(.trailing, showsP2PControls ? 12 : 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .frame(maxWidth: .infinity)
    .frame(height: 56)
    .background(Color(hex: 0xFFF5E1))
    .accessibilityIdentifier("id.securityWarning")
  }

  @ViewBuilder
  private var warningText: some View {
    if showsP2PControls, let reportTitle, let onReport {
      Button(action: onReport) {
        inlineWarningText(reportTitle: reportTitle)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(message)\(reportTitle)")
    } else {
      Text(message)
        .foregroundColor(warningTextColor)
    }
  }

  private func inlineWarningText(reportTitle: String) -> Text {
    Text(message)
      .foregroundColor(p2pWarningTextColor) +
      Text(reportTitle)
      .foregroundColor(reportLinkColor)
  }

  private var warningTextColor: Color {
    Color(hex: 0xEB9718)
  }

  private var reportLinkColor: Color {
    Color(uiColor: .link)
  }

  private var p2pWarningTextColor: Color {
    Color(hex: 0x222222)
  }

  private var showsP2PControls: Bool {
    reportTitle != nil && onReport != nil
  }

  private var warningFontSize: CGFloat {
    showsP2PControls ? 13 : 14
  }
}
