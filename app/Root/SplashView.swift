// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

/// Simple splash / loading screen shown during app initialization.
struct SplashView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 20) {
            ExampleAssetIcon(name: "launchIcon", size: 64)

            Text(localizable("appName"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)

            Text(localizable("initializing"))
                .font(.system(size: 14))
                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#if DEBUG
struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .environmentObject(PreviewMocks.mockEnvironment())
    }
}
#endif
