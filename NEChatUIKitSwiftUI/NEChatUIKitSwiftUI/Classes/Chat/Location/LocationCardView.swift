// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

private let locationCardCornerRadius: CGFloat = 4

public struct LocationCardView: View {
  public var location: MessageLocationState
  public var token: ChatThemeToken
  public var showsCoordinates: Bool

  public init(location: MessageLocationState,
              token: ChatThemeToken,
              showsCoordinates: Bool = false) {
    self.location = location
    self.token = token
    self.showsCoordinates = showsCoordinates
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(location.title)
          .font(.system(size: 16))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
          .lineLimit(1)
          .truncationMode(.tail)

        if let subtitle = location.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if showsCoordinates, let coordinateText = location.coordinateText {
          Text(coordinateText)
            .font(.system(size: 12))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(height: NEChatUIKitSwiftUIConstants.locationCardSize.height - NEChatUIKitSwiftUIConstants.locationThumbnailHeight,
             alignment: .topLeading)
      .padding(.horizontal, 16)
      .padding(.top, 10)

      mapThumbnail
        .frame(width: NEChatUIKitSwiftUIConstants.locationCardSize.width,
               height: NEChatUIKitSwiftUIConstants.locationThumbnailHeight)
        .clipped()
        .overlay(alignment: .bottom) {
          if location.thumbnailURL != nil {
            NEChatCommonPresentation.iconView(
              imageName: "location_point",
              token: token,
              renderingMode: .original,
              size: CGSize(width: 24, height: 40),
              accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_location_pin", value: "Pin")
            )
            .padding(.bottom, 30)
          }
        }
    }
    .frame(width: NEChatUIKitSwiftUIConstants.locationCardSize.width,
           height: NEChatUIKitSwiftUIConstants.locationCardSize.height,
           alignment: .topLeading)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: locationCardCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: locationCardCornerRadius, style: .continuous)
        .stroke(NEUIKitSwiftUIStyle.ColorToken.outline, lineWidth: 1)
    )
  }

  private var mapThumbnail: some View {
    ZStack {
      if let thumbnailURL = location.thumbnailURL {
        AsyncImage(url: thumbnailURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          default:
            locationPlaceholder
          }
        }
      } else {
        locationPlaceholder
        Text(NEChatUIKitSwiftUIBundle.localized("no_map_plugin", value: "No map plugin"))
          .font(.system(size: 16))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(1)
          .padding(.bottom, 40)
          .frame(maxHeight: .infinity, alignment: .bottom)
      }
    }
  }

  private var locationPlaceholder: some View {
    Image("map_placeholder_image", bundle: NEChatUIKitSwiftUIBundle.bundle)
      .resizable()
      .scaledToFill()
      .frame(width: NEChatUIKitSwiftUIConstants.locationCardSize.width,
             height: NEChatUIKitSwiftUIConstants.locationThumbnailHeight)
      .clipped()
      .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_location_static_preview", value: "Location"))
  }
}

public extension MessageLocationState {
  var coordinateText: String? {
    guard let latitude, let longitude else {
      return nil
    }
    return String(format: "%.6f, %.6f", latitude, longitude)
  }
}
