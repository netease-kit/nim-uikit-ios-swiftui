// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

struct ExampleAssetIcon: View {
    var name: String
    var size: CGFloat? = nil

    var body: some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct ExampleAssetLabel: View {
    var title: String
    var imageName: String
    var iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            ExampleAssetIcon(name: imageName, size: iconSize)
            Text(title)
        }
    }
}
