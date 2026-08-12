// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct AISearchLoadingIndicator: View {
  @State private var phase = false

  public init() {}

  public var body: some View {
    ZStack {
      Circle()
        .stroke(Color(red: 0.82, green: 0.86, blue: 0.94), lineWidth: 2)
      Circle()
        .trim(from: 0.12, to: 0.72)
        .stroke(
          Color(red: 0.13, green: 0.33, blue: 0.93),
          style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
        .rotationEffect(.degrees(phase ? 360 : 0))
    }
    .frame(width: 16, height: 16)
    .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: phase)
    .onAppear {
      phase = true
    }
    .accessibilityIdentifier("id.loadingView")
  }
}
