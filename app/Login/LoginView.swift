// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI
import UIKit

/// Login screen matching IMUIKitExample NELoginViewController.
/// The GitHub demo logs in directly with an IM account and token.
struct LoginView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Color.white
                        .ignoresSafeArea()

                    loginContent
                        .padding(.top, geometry.safeAreaInsets.top + LoginLayout.brandTop)

                    bottomActions
                        .padding(.horizontal, LoginLayout.bottomHorizontalInset)
                        .position(
                            x: geometry.size.width / 2,
                            y: bottomActionCenterY(in: geometry)
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var loginContent: some View {
        VStack(spacing: 0) {
            Image("launchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: LoginLayout.brandWidth, height: LoginLayout.brandHeight)

            Text(localizable("appName"))
                .font(.system(size: 24))
                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
                .padding(.top, LoginLayout.titleOverlap)

            Button(action: loginWithConfiguredAccount) {
                HStack(spacing: 8) {
                    if environment.isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(localizable("register_login"))
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.white)
                .background(NEUIKitSwiftUIStyle.ColorToken.normalTheme)
                .clipShape(RoundedRectangle(cornerRadius: LoginLayout.loginButtonCornerRadius))
            }
            .buttonStyle(.plain)
            .frame(height: LoginLayout.loginButtonHeight)
            .disabled(environment.isAuthenticating)
            .padding(.horizontal, LoginLayout.loginButtonHorizontalInset)
            .padding(.top, LoginLayout.loginButtonTop)
            .accessibilityIdentifier("id.loginButton")

            if let error = environment.loginErrorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.redText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, LoginLayout.loginButtonHorizontalInset)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomActions: some View {
        HStack(spacing: 8) {
            NavigationLink(destination: NodeSelectionView()) {
                bottomActionLabel("node_select")
            }
            .accessibilityIdentifier("id.serverConfig")

            NavigationLink(destination: PrivateCloudConfigView()) {
                bottomActionLabel("privatized_configuration")
            }
            .accessibilityIdentifier("id.pocSetting")

            NavigationLink(destination: PocLoginView()) {
                bottomActionLabel("login_by_account")
            }
            .accessibilityIdentifier("id.pocLogin")
        }
        .frame(height: LoginLayout.bottomActionHeight)
    }

    private func bottomActionLabel(_ key: String) -> some View {
        Text(localizable(key))
            .font(.system(size: 12))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private func loginWithConfiguredAccount() {
        let account = AppKey.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = AppKey.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else {
            environment.loginErrorMessage = localizable("poc_account_required")
            return
        }
        guard !token.isEmpty else {
            environment.loginErrorMessage = localizable("poc_token_required")
            return
        }
        environment.loginWithPOC(account: account, token: token)
    }

    private func bottomActionCenterY(in geometry: GeometryProxy) -> CGFloat {
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.height ?? geometry.frame(in: .global).maxY
        return windowHeight
            - LoginLayout.bottomInset
            - LoginLayout.bottomActionHeight / 2
    }
}

private enum LoginLayout {
    static let brandTop: CGFloat = 145
    static let brandWidth: CGFloat = 120
    static let brandHeight: CGFloat = 154
    static let titleOverlap: CGFloat = -12
    static let loginButtonTop: CGFloat = 20
    static let loginButtonHeight: CGFloat = 44
    static let loginButtonHorizontalInset: CGFloat = 40
    static let loginButtonCornerRadius: CGFloat = 8
    static let bottomActionHeight: CGFloat = 44
    static let bottomHorizontalInset: CGFloat = 20
    static let bottomInset: CGFloat = 70
}

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(PreviewMocks.mockEnvironment())
    }
}
#endif
