// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

/// POC direct login view matching IMUIKitExample PocLoginViewController.
/// Logs into the public IM SDK directly with an account and token.
struct PocLoginView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var account = AppKey.accountId
    @State private var token = AppKey.token
    @State private var showClearConfigConfirm = false
    @State private var feedback: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable {
        case account
        case token
    }

    var body: some View {
        Form {
            Section {
                TextField(localizable("poc_account_placeholder"), text: $account)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .account)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .token
                    }

                SecureField(localizable("poc_token_placeholder"), text: $token)
                    .focused($focusedField, equals: .token)
                    .submitLabel(.done)
                    .onSubmit(login)
            } header: {
                Text(localizable("poc_direct_login"))
            } footer: {
                Text(localizable("poc_login_desc"))
            }

            Section {
                Button(action: login) {
                    HStack {
                        Spacer()
                        if environment.isAuthenticating {
                            ProgressView()
                        }
                        Text(localizable("poc_login_action"))
                        Spacer()
                    }
                }
                .disabled(environment.isAuthenticating || account.isEmpty || token.isEmpty)
            }

            Section {
                Button(localizable("clear_private_config"), role: .destructive) {
                    showClearConfigConfirm = true
                }
            }

            if let error = environment.loginErrorMessage {
                Section {
                    Text(error)
                        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.redText)
                        .font(.system(size: 12))
                }
            }

            if let feedback {
                Section {
                    Text(feedback)
                        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                        .font(.system(size: 12))
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(localizable("login_by_account"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            focusedField = nil
        }
        .alert(localizable("clear_private_config_confirm"), isPresented: $showClearConfigConfirm) {
            Button(localizable("cancel"), role: .cancel) {}
            Button(localizable("ok"), role: .destructive) {
                DemoPrivateCloudConfigStore.clearConfig()
                account = AppKey.accountId
                token = AppKey.token
                feedback = localizable("clear_private_config_success")
                focusedField = nil
            }
        }
    }

    private func login() {
        guard !account.trimmingCharacters(in: .whitespaces).isEmpty else {
            environment.loginErrorMessage = localizable("poc_account_required")
            return
        }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            environment.loginErrorMessage = localizable("poc_token_required")
            return
        }
        focusedField = nil
        environment.loginWithPOC(account: account, token: token)
    }
}

#if DEBUG
struct PocLoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PocLoginView()
                .environmentObject(PreviewMocks.mockEnvironment())
        }
    }
}
#endif
