// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

/// View for toggling between normal and fun theme modes.
struct ThemeSwitcherView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var selectedMode: ThemeMode = .normal

    var body: some View {
        Form {
            Section {
                Text("切换主题将改变应用的视觉风格")
                    .font(.system(size: 12))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            }

            Section("选择主题") {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedMode = mode
                        environment.setThemeMode(mode)
                    }) {
                        HStack {
                            Text(mode.displayName)
                                .font(.system(size: 16))
                                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
                            Spacer()
                            if selectedMode == mode {
                                ExampleAssetIcon(name: "language_select", size: 20)
                            }
                        }
                    }
                }
            }

            Section("当前主题") {
                HStack {
                    Text("当前")
                    Spacer()
                    Text(selectedMode.displayName)
                        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
                }
            }
        }
        .navigationTitle("主题切换")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedMode = environment.themeMode
        }
    }
}

#if DEBUG
struct ThemeSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ThemeSwitcherView()
                .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
        }
    }
}
#endif
