// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI
import YXLogin

/// Login screen matching IMUIKitExample NELoginViewController.
/// Four login paths: phone, email, POC direct, and node select.
struct LoginView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // App branding
                Image("launchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .cornerRadius(20)

                Text(localizable("appName"))
                    .font(.system(size: 24))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
                    .padding(.top, 12)

                Spacer()

                // Primary login button (phone register/login)
                Button(action: { environment.loginWithPhone() }) {
                    HStack {
                        if environment.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(localizable("register_login"))
                            .font(.system(size: 15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(NEUIKitSwiftUIStyle.ColorToken.normalTheme)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(environment.isAuthenticating)
                .padding(.horizontal, 32)

                // Error message
                if let error = environment.loginErrorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.redText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

                // Bottom action buttons (matching IMUIKitExample layout)
                HStack(spacing: 0) {
                    Spacer()
                    Button(localizable("email_login")) {
                        startEmailLogin()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)

                    Spacer()

                    NavigationLink(destination: NodeSelectionView()) {
                        Text(localizable("node_select"))
                            .font(.system(size: 12))
                            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
                    }

                    Spacer()

                    NavigationLink(destination: PrivateCloudConfigView()) {
                        Text(localizable("privatized_configuration"))
                            .font(.system(size: 12))
                            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
                    }

                    Spacer()

                    NavigationLink(destination: PocLoginView()) {
                        Text(localizable("login_by_account"))
                            .font(.system(size: 12))
                            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
                    }

                    Spacer()
                }
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }

    private func startEmailLogin() {
        let config = YXConfig()
        config.appKey = ServerConfig.getAppkey()
        config.parentScope = NSNumber(integerLiteral: 2)
        config.scope = NSNumber(integerLiteral: 7)
        #if DEBUG
        config.isOnline = false
        #else
        config.isOnline = true
        #endif
        config.type = .email
        config.supportInternationalize = false

        AuthorManager.shareInstance()?.initAuthor(with: config)
        AuthorManager.shareInstance()?.startLogin { userInfo, error in
            if let err = error as? NSError, err.code > 0 {
                Task { @MainActor in
                    environment.loginErrorMessage = DemoNetworkPresentation.message(
                        for: err,
                        fallbackKey: "login_failed"
                    )
                }
                return
            }
            guard let userInfo,
                  let accid = userInfo.imAccid,
                  let token = userInfo.imToken else {
                Task { @MainActor in
                    environment.loginErrorMessage = localizable("login_info_incomplete")
                }
                return
            }
            AppBootstrap.loginIM(accid: accid, token: token) {}
        }
    }
}

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(PreviewMocks.mockEnvironment())
    }
}
#endif
