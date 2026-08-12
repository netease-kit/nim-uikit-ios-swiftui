// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct ContactIndexBarView: View {
  var titles: [String]
  var token: ContactThemeToken
  var onSelect: (String) -> Void

  public var body: some View {
    VStack(spacing: 2) {
      ForEach(Array(titles.enumerated()), id: \.element) { _, title in
        Text(title)
          .font(.system(size: token.indexFontSize, weight: .medium))
          .foregroundColor(token.secondaryTextColor)
          .frame(width: Metrics.width, height: Metrics.itemHeight)
          .contentShape(Rectangle())
          .onTapGesture {
            onSelect(title)
          }
      }
    }
    .padding(.vertical, Metrics.verticalPadding)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          selectTitle(at: value.location.y)
        }
    )
    .accessibilityElement(children: .contain)
  }

  private enum Metrics {
    static let width: CGFloat = 18
    static let itemHeight: CGFloat = 14
    static let itemSpacing: CGFloat = 2
    static let verticalPadding: CGFloat = 6
  }

  private func selectTitle(at y: CGFloat) {
    guard !titles.isEmpty else {
      return
    }
    let itemStride = Metrics.itemHeight + Metrics.itemSpacing
    let rawIndex = Int((y - Metrics.verticalPadding) / itemStride)
    let index = min(max(rawIndex, 0), titles.count - 1)
    onSelect(titles[index])
  }
}
