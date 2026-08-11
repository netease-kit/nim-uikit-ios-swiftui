// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI
import WebKit

enum DemoSettingStyle {
    static func pageBackground(_ mode: ThemeMode) -> Color {
        mode == .normal
            ? NEUIKitSwiftUIStyle.ColorToken.lightBackground
            : NEUIKitSwiftUIStyle.ColorToken.funBackground
    }

    static func rowBackground(_ mode: ThemeMode) -> Color {
        .white
    }

    static func themeColor(_ mode: ThemeMode) -> Color {
        mode == .normal
            ? NEUIKitSwiftUIStyle.ColorToken.normalTheme
            : NEUIKitSwiftUIStyle.ColorToken.funTheme
    }

    static func profileEditActionColor(_ mode: ThemeMode) -> Color {
        mode == .normal
            ? NEUIKitSwiftUIStyle.ColorToken.greyText
            : NEUIKitSwiftUIStyle.ColorToken.funTheme
    }

    static func titleColor(_ mode: ThemeMode) -> Color {
        NEUIKitSwiftUIStyle.ColorToken.darkText
    }

    static let detailColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    static let secondaryColor = NEUIKitSwiftUIStyle.ColorToken.greyText
    static let destructiveColor = NEUIKitSwiftUIStyle.ColorToken.redText
    static let chevronColor = Color(hex: 0xC5C9D2)

    static func navigationBackground(_ mode: ThemeMode) -> Color {
        pageBackground(mode)
    }

    static func commonTheme(_ mode: ThemeMode) -> NECommonThemeToken {
        var token = mode == .normal ? NECommonThemeToken.normal : NECommonThemeToken.fun
        token.palette.pageBackground = pageBackground(mode)
        token.palette.rowBackground = rowBackground(mode)
        token.palette.elevatedBackground = navigationBackground(mode)
        token.palette.primaryText = titleColor(mode)
        token.palette.secondaryText = secondaryColor
        token.palette.tertiaryText = detailColor
        token.palette.accent = themeColor(mode)
        token.palette.separator = Color(hex: 0xDBE0E8)
        return token
    }

    static func navigationTextButtonWidth(_ title: String) -> CGFloat {
        min(max(CGFloat(title.count) * 9 + 24, 60), 96)
    }
}

private struct DemoNavigationPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.neCommonLocalBackAction) private var localBackAction
    @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    var background: Color?
    var trailingWidth: CGFloat = 60
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(title: String,
         background: Color? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.background = background
        trailing = nil
        self.content = content
    }

    init<Trailing: View>(title: String,
                         background: Color? = nil,
                         trailingWidth: CGFloat = 60,
                         @ViewBuilder trailing: @escaping () -> Trailing,
                         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.background = background
        self.trailingWidth = trailingWidth
        self.trailing = AnyView(trailing())
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((background ?? DemoSettingStyle.navigationBackground(environment.themeMode)).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.neChatChildRouteBackAction, nil)
    }

    @ViewBuilder
    private var navigationBar: some View {
        if let trailing {
            NECommonNavigationBarView(
                title: title,
                backAction: performBack,
                trailingWidth: trailingWidth,
                backgroundColor: DemoSettingStyle.navigationBackground(environment.themeMode),
                separatorColor: Color(hex: 0xDBE0E8),
                showsSeparator: false
            ) {
                trailing
            }
            .neCommonTheme(DemoSettingStyle.commonTheme(environment.themeMode))
        } else {
            NECommonNavigationBarView(
                title: title,
                backAction: performBack,
                backgroundColor: DemoSettingStyle.navigationBackground(environment.themeMode),
                separatorColor: Color(hex: 0xDBE0E8),
                showsSeparator: false
            )
            .neCommonTheme(DemoSettingStyle.commonTheme(environment.themeMode))
        }
    }

    private func performBack() {
        if let localBackAction {
            localBackAction()
        } else if let chatRouteBackAction {
            chatRouteBackAction()
        } else {
            dismiss()
        }
    }
}

private struct DemoNavigationTextButton: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    var foregroundColor: ((ThemeMode) -> Color)?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor((foregroundColor ?? DemoSettingStyle.themeColor)(environment.themeMode))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct DemoSettingSection<Content: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    var topPadding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(DemoSettingStyle.rowBackground(environment.themeMode))
            .clipShape(RoundedRectangle(cornerRadius: environment.themeMode == .normal ? 8 : 0, style: .continuous))
            .padding(.horizontal, environment.themeMode == .normal ? 20 : 0)
            .padding(.top, topPadding)
    }
}

struct DemoSettingRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    var iconName: String?
    var detail: String?
    var showChevron = true

    var body: some View {
        HStack(spacing: 14) {
            if let iconName {
                ExampleAssetIcon(name: iconName, size: 20)
            }
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
            Spacer(minLength: 12)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundColor(DemoSettingStyle.detailColor)
                    .lineLimit(1)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DemoSettingStyle.chevronColor)
            }
        }
        .frame(height: 52)
        .padding(.leading, iconName == nil ? 20 : 20)
        .padding(.trailing, 20)
    }
}

struct DemoSwitchRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    @Binding var isOn: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { value in
                isOn = value
                onChange(value)
            }
        )) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
        }
        .toggleStyle(SwitchToggleStyle(tint: DemoSettingStyle.themeColor(environment.themeMode)))
        .frame(height: 52)
        .padding(.horizontal, 20)
    }
}

struct DemoDivider: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Rectangle()
            .fill(Color(hex: 0xDBE0E8))
            .frame(height: 0.5)
            .padding(.leading, environment.themeMode == .normal ? 20 : 0)
    }
}

struct MineView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var user: NEUserWithFriend?
    @State private var toast: NECommonToastState?
    @State private var showGenderPicker = false
    @State private var showBirthdayPicker = false
    @State private var isSavingAvatar = false

    private var accountId: String {
        environment.currentAccount ?? IMKitClient.instance.account()
    }

    private var displayName: String {
        user?.showName() ?? accountId
    }

    private var avatarName: String {
        user?.showName(false) ?? accountId
    }

    private var genderText: String {
        switch user?.user?.gender {
        case 1:
            return localizable("male")
        case 2:
            return localizable("female")
        default:
            return localizable("unknown")
        }
    }

    var body: some View {
        DemoNavigationPage(title: localizable("person_info")) {
            ScrollView {
                VStack(spacing: 0) {
                    personInfoSection
                    signatureSection
                }
                .padding(.bottom, 24)
                .padding(.top, environment.themeMode == .normal ? 12 : 0)
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .onAppear(perform: loadUser)
        .confirmationDialog(
            localizable("gender"),
            isPresented: $showGenderPicker,
            titleVisibility: .visible
        ) {
            Button(localizable("male")) {
                updateGender(.GENDER_MALE)
            }
            Button(localizable("female")) {
                updateGender(.GENDER_FEMALE)
            }
            Button(localizable("cancel"), role: .cancel) {}
        }
        .neCommonToastOverlay(toast, placement: .top, topPadding: 52) { toast in
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
        .neCommonBlockingLoadingOverlay(isPresented: isSavingAvatar, fallbackText: localizable("save"))
        .overlay {
            if showBirthdayPicker {
                BirthdayPickerSheet(
                    initialBirthday: user?.user?.birthday,
                    mode: environment.themeMode,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showBirthdayPicker = false
                        }
                    },
                    onConfirm: { birthday in
                        withAnimation(.easeOut(duration: 0.18)) {
                            showBirthdayPicker = false
                        }
                        updateProfile(.birthday, value: birthday)
                    }
                )
                .environmentObject(environment)
                .transition(.opacity)
            }
        }
    }

    private var personInfoSection: some View {
        DemoSettingSection(topPadding: 0) {
            Button {
                selectAvatar()
            } label: {
                avatarLine
            }
            .buttonStyle(.plain)
            DemoDivider()
            NavigationLink(
                destination: ProfileTextEditView(
                    editType: .nickname,
                    initialText: displayName,
                    onSave: { value, completion in
                        updateProfile(.nickname, value: value, completion: completion)
                    }
                )
                .demoHidesTabBar()
            ) {
                infoLine(localizable("nickname"), displayName, titleWidth: 90)
            }
            .buttonStyle(.plain)
            DemoDivider()
            accountLine
            DemoDivider()
            Button {
                showGenderPicker = true
            } label: {
                infoLine(localizable("gender"), genderText, titleWidth: 60)
            }
            .buttonStyle(.plain)
            DemoDivider()
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showBirthdayPicker = true
                }
            } label: {
                infoLine(localizable("birthday"), user?.user?.birthday ?? "", titleWidth: 80)
            }
            .buttonStyle(.plain)
            DemoDivider()
            NavigationLink(
                destination: ProfileTextEditView(
                    editType: .phone,
                    initialText: user?.user?.mobile ?? "",
                    onSave: { value, completion in
                        updateProfile(.phone, value: value, completion: completion)
                    }
                )
                .demoHidesTabBar()
            ) {
                infoLine(localizable("phone"), user?.user?.mobile ?? "", titleWidth: 60)
            }
            .buttonStyle(.plain)
            DemoDivider()
            NavigationLink(
                destination: ProfileTextEditView(
                    editType: .email,
                    initialText: user?.user?.email ?? "",
                    onSave: { value, completion in
                        guard value.isEmpty || Self.isValidEmail(value) else {
                            completion(.failure(ProfileSaveFailure(message: localizable("change_email_failure"))))
                            return
                        }
                        updateProfile(.email, value: value, completion: completion)
                    }
                )
                .demoHidesTabBar()
            ) {
                infoLine(localizable("email"), user?.user?.email ?? "", titleWidth: 60)
            }
            .buttonStyle(.plain)
        }
    }

    private var signatureSection: some View {
        DemoSettingSection {
            NavigationLink(
                destination: ProfileTextEditView(
                    editType: .signature,
                    initialText: user?.user?.sign ?? "",
                    onSave: { value, completion in
                        updateProfile(.signature, value: value, completion: completion)
                    }
                )
                .demoHidesTabBar()
            ) {
                infoLine(localizable("individuality_sign"), user?.user?.sign ?? "", titleWidth: NEAppLanguageUtil.getCurrentLanguage() == .english ? 76 : 64)
            }
            .buttonStyle(.plain)
        }
    }

    private var avatarLine: some View {
        HStack(spacing: 0) {
            Text(localizable("headImage"))
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x333333))
            Spacer(minLength: 16)
            DemoAvatarView(name: avatarName, accountId: accountId, url: user?.user?.avatar, size: 42, mode: environment.themeMode)
                .padding(.trailing, 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DemoSettingStyle.chevronColor)
                .frame(width: 7)
        }
        .frame(height: 64)
        .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
    }

    private var accountLine: some View {
        HStack(spacing: 0) {
            Text(localizable("account"))
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x333333))
                .frame(width: 60, alignment: .leading)
            Text(accountId)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xA6ADB6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 10)
            Button {
                copyAccount()
            } label: {
                ExampleAssetIcon(name: "copy_icon", size: 15)
                    .frame(width: 31, height: 46, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 46)
        .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
    }

    private func infoLine(_ title: String, _ value: String, titleWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x333333))
                .frame(width: titleWidth, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xA6ADB6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 10)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DemoSettingStyle.chevronColor)
                .frame(width: 7)
                .padding(.leading, 10)
        }
        .frame(height: 46)
        .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
    }

    private func loadUser() {
        if let cached = NEFriendUserCache.shared.getFriendInfo(accountId) {
            user = cached
        }
        ContactRepo.shared.getUserListFromCloud(accountIds: [accountId]) { users, _ in
            Task { @MainActor in
                if let loaded = users?.first {
                    user = loaded
                    NEFriendUserCache.shared.updateFriendInfo(loaded.user)
                }
            }
        }
    }

    private func copyAccount() {
        UIPasteboard.general.string = accountId
        toast = NECommonToastState(fallbackText: localizable("copy_success"), level: .success)
    }

    private func selectAvatar() {
        guard isNetworkReachable() else {
            toast = NECommonToastState(fallbackText: DemoNetworkPresentation.networkMessage(), level: .warning)
            return
        }
        guard let handler = ChatSwiftUIConfigCenter.shared.current().avatarSelectionHandler else {
            toast = NECommonToastState(fallbackText: localizable("setting_head_failure"), level: .warning)
            return
        }
        let request = ChatAvatarSelectionRequest(
            source: .profileEdit,
            currentAvatarURL: NECommonAvatarDisplayResolver.url(from: user?.user?.avatar),
            displayName: avatarName,
            accountId: accountId
        )
        handler.selectAvatar(request: request) { result in
            Task { @MainActor in
                switch result {
                case let .success(selection):
                    switch selection {
                    case let .selected(url):
                        isSavingAvatar = true
                        if url.isFileURL {
                            await uploadAndUpdateAvatar(localURL: url)
                        } else {
                            updateProfile(.avatar, value: url.absoluteString) { result in
                                isSavingAvatar = false
                                if case let .failure(error) = result {
                                    toast = NECommonToastState(fallbackText: error.message, level: .error)
                                }
                            }
                        }
                    case .cancelled:
                        isSavingAvatar = false
                    }
                case .failure:
                    isSavingAvatar = false
                    toast = NECommonToastState(fallbackText: localizable("setting_head_failure"), level: .error)
                }
            }
        }
    }

    private func uploadAndUpdateAvatar(localURL: URL) async {
        do {
            let uploadResult = try await ExampleChatPayloadBuilder.uploadFile(localURL)
            switch uploadResult {
            case let .success(urlString):
                guard let urlString, !urlString.isEmpty else {
                    isSavingAvatar = false
                    toast = NECommonToastState(fallbackText: localizable("setting_head_failure"), level: .error)
                    return
                }
                updateProfile(.avatar, value: urlString) { result in
                    isSavingAvatar = false
                    if case let .failure(error) = result {
                        toast = NECommonToastState(fallbackText: error.message, level: .error)
                    }
                }
            case .failure:
                isSavingAvatar = false
                toast = NECommonToastState(fallbackText: localizable("setting_head_failure"), level: .error)
            }
        } catch {
            isSavingAvatar = false
            toast = NECommonToastState(fallbackText: localizable("setting_head_failure"), level: .error)
        }
    }

    private func updateGender(_ gender: V2NIMGender) {
        let parameter = V2NIMUserUpdateParams()
        parameter.gender = gender
        saveProfile(parameter, failureKey: "change_gender_failure")
    }

    private func updateProfile(_ field: ProfileEditField,
                               value: String,
                               completion: ((ProfileSaveResult) -> Void)? = nil) {
        let parameter = V2NIMUserUpdateParams()
        switch field {
        case .avatar:
            parameter.avatar = value
        case .nickname:
            parameter.name = value.isEmpty ? accountId : value
        case .phone:
            parameter.mobile = value
        case .email:
            parameter.email = value
        case .signature:
            parameter.sign = value
        case .birthday:
            parameter.birthday = value
        }
        saveProfile(parameter, failureKey: field.failureKey, completion: completion)
    }

    private func saveProfile(_ parameter: V2NIMUserUpdateParams,
                             failureKey: String,
                             completion: ((ProfileSaveResult) -> Void)? = nil) {
        guard isNetworkReachable() else {
            let message = DemoNetworkPresentation.networkMessage()
            if completion == nil {
                toast = NECommonToastState(fallbackText: message, level: .warning)
            }
            completion?(.failure(ProfileSaveFailure(message: message)))
            return
        }
        ContactRepo.shared.updateSelfUserProfile(parameter) { error in
            Task { @MainActor in
                if let error {
                    let message = profileFailureMessage(error, fallbackKey: failureKey)
                    if completion == nil {
                        toast = NECommonToastState(fallbackText: message, level: .error)
                    }
                    completion?(.failure(ProfileSaveFailure(message: message)))
                } else {
                    loadUser()
                    completion?(.success(()))
                }
            }
        }
    }

    private func profileFailureMessage(_ error: NSError, fallbackKey: String) -> String {
        if error.code == antiErrorCode {
            return localizable("anti_error")
        }
        return DemoNetworkPresentation.message(for: error, fallbackKey: fallbackKey)
    }

    private func isNetworkReachable() -> Bool {
        DemoNetworkPresentation.allowsNetworkOperation
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^\w+@\w+\.[a-zA-Z]{2,}"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }
}

private enum ProfileEditField {
    case avatar
    case nickname
    case phone
    case email
    case signature
    case birthday

    var failureKey: String {
        switch self {
        case .avatar:
            return "setting_head_failure"
        case .nickname:
            return "setting_nickname_failure"
        case .phone:
            return "change_phone_failure"
        case .email:
            return "change_email_failure"
        case .signature:
            return "change_sign_failure"
        case .birthday:
            return "setting_birthday_failure"
        }
    }
}

private enum ProfileTextEditType {
    case nickname
    case phone
    case email
    case signature

    var title: String {
        switch self {
        case .nickname:
            return localizable("nickname")
        case .phone:
            return localizable("phone")
        case .email:
            return localizable("email")
        case .signature:
            return localizable("individuality_sign")
        }
    }

    var limit: Int {
        switch self {
        case .nickname:
            return 15
        case .phone:
            return 11
        case .email:
            return 30
        case .signature:
            return 50
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .phone:
            return .phonePad
        case .email:
            return .emailAddress
        default:
            return .default
        }
    }
}

private struct ProfileSaveFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private typealias ProfileSaveResult = Result<Void, ProfileSaveFailure>

private struct ProfileTextEditView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var isFocused = false
    @State private var text: String
    @State private var toast: NECommonToastState?
    @State private var isSaving = false
    let editType: ProfileTextEditType
    let onSave: (String, @escaping (ProfileSaveResult) -> Void) -> Void

    init(editType: ProfileTextEditType,
         initialText: String,
         onSave: @escaping (String, @escaping (ProfileSaveResult) -> Void) -> Void) {
        self.editType = editType
        _text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        DemoNavigationPage(
            title: editType.title,
            trailingWidth: DemoSettingStyle.navigationTextButtonWidth(localizable("complete"))
        ) {
            DemoNavigationTextButton(
                title: localizable("complete"),
                foregroundColor: DemoSettingStyle.profileEditActionColor
            ) {
                save()
            }
        } content: {
            VStack(spacing: 0) {
                textField
                    .padding(.horizontal, environment.themeMode == .normal ? 20 : 0)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
        .neCommonToastOverlay(toast, placement: .top, topPadding: 52) { toast in
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
        .neCommonBlockingLoadingOverlay(isPresented: isSaving, fallbackText: localizable("save"))
    }

    private var textField: some View {
        HStack(spacing: 8) {
            NEChatLimitedTextField(
                text: profileTextBinding,
                isFocused: profileTextFocusBinding,
                characterLimit: editType.limit,
                fontSize: 14,
                textColor: Color(hex: 0x333333),
                keyboardType: editType.keyboardType,
                accessibilityIdentifier: "id.nickname",
                onLimitReached: showLimitToast
            )
            .frame(maxWidth: .infinity, minHeight: 50)

            if !text.isEmpty {
                Button {
                    isFocused = false
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: 0xC5C9D2))
                        .frame(width: 28, height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("id.clear")
            }
        }
        .frame(height: 50)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: environment.themeMode == .normal ? 8 : 0, style: .continuous))
    }

    private func showLimitToast() {
        let limit = editType.limit
        toast = NECommonToastState(
            fallbackText: String(format: localizable("text_count_limit"), limit),
            level: .warning
        )
    }

    private var profileTextFocusBinding: Binding<Bool> {
        Binding(
            get: { isFocused },
            set: { isFocused = $0 }
        )
    }

    private var profileTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { value in
                text = value
                if value.isEmpty {
                    isFocused = false
                }
            }
        )
    }

    private func save() {
        guard !isSaving else {
            return
        }
        isSaving = true
        onSave(text) { result in
            Task { @MainActor in
                isSaving = false
                switch result {
                case .success:
                    dismiss()
                case let .failure(error):
                    toast = NECommonToastState(fallbackText: error.message, level: .error)
                }
            }
        }
    }
}

private struct BirthdayPickerSheet: View {
    @State private var selectedDate: Date
    let mode: ThemeMode
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    private let actionBarHeight: CGFloat = 44
    private let actionButtonWidth: CGFloat = 45

    init(initialBirthday: String?,
         mode: ThemeMode,
         onCancel: @escaping () -> Void,
         onConfirm: @escaping (String) -> Void) {
        self.mode = mode
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        let formatter = Self.formatter
        let date = initialBirthday.flatMap { formatter.date(from: $0) } ?? Date()
        _selectedDate = State(initialValue: date)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: -10) {
                HStack {
                    Button(localizable("cancel")) {
                        onCancel()
                    }
                    .font(.system(size: 14))
                    .foregroundColor(DemoSettingStyle.themeColor(mode))
                    .frame(width: actionButtonWidth, height: actionBarHeight, alignment: .leading)
                    .buttonStyle(.plain)

                    Spacer()

                    Button(localizable("ok")) {
                        onConfirm(Self.formatter.string(from: selectedDate))
                    }
                    .font(.system(size: 14))
                    .foregroundColor(DemoSettingStyle.themeColor(mode))
                    .frame(width: actionButtonWidth, height: actionBarHeight, alignment: .trailing)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 15)
                .frame(height: actionBarHeight)

                Rectangle()
                    .fill(Color(hex: 0xDBE0E8))
                    .frame(height: 0.5)

                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 229)
            .background(Color.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct DemoAvatarView: View {
    var name: String
    var accountId: String
    var url: String?
    var size: CGFloat
    var mode: ThemeMode

    var body: some View {
        NECommonAvatarView(
            imageURL: NECommonAvatarDisplayResolver.url(from: url),
            initials: NECommonAvatarDisplayResolver.initials(displayName: name, fallbackID: accountId),
            size: size,
            cornerRadius: mode == .normal ? size / 2 : 4,
            hashID: accountId
        )
        .neCommonTheme(mode == .normal ? .normal : .fun)
    }
}

struct DemoSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showLogoutConfirm = false

    var body: some View {
        DemoNavigationPage(title: localizable("setting")) {
            ScrollView {
                VStack(spacing: 0) {
                    DemoSettingSection {
                        NavigationLink(destination: MessageReminderView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("message_remind"), iconName: nil)
                        }
                        DemoDivider()
                        NavigationLink(destination: StyleSelectionView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("style_selection"), iconName: nil)
                        }
                    }

                    DemoSettingSection {
                        MessageReadStatusRow(title: localizable("message_read_function"))
                        DemoDivider()
                        CloudConversationRow(title: localizable("cloud_conversation"))
                    }

                    DemoSettingSection {
                        NavigationLink(destination: GlobalConfigView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("global_config"), iconName: nil)
                        }
                        DemoDivider()
                        NavigationLink(destination: PrivateCloudConfigView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("private_cloud_config"), iconName: nil)
                        }
                        DemoDivider()
                        NavigationLink(destination: PushConfigView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("push_config"), iconName: nil)
                        }
                        DemoDivider()
                        NavigationLink(destination: LanguageSelectionView().demoHidesTabBar()) {
                            DemoSettingRow(title: localizable("app_language"), iconName: nil, detail: currentLanguageText())
                        }
                    }

                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Text(localizable("logout"))
                            .font(.system(size: 16))
                            .foregroundColor(DemoSettingStyle.destructiveColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: environment.themeMode == .normal ? 8 : 0, style: .continuous))
                    }
                    .padding(.horizontal, environment.themeMode == .normal ? 20 : 0)
                    .padding(.top, 24)

                }
                .padding(.bottom, 28)
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .id(environment.languageRevision)
        .alert(localizable("want_to_logout"), isPresented: $showLogoutConfirm) {
            Button(localizable("cancel"), role: .cancel) {}
            Button(localizable("ok")) {
                logout()
            }
        }
    }

    private func currentLanguageText() -> String {
        NEAppLanguageUtil.getCurrentLanguage() == .chinese ? localizable("app_language_zh") : localizable("app_language_en")
    }

    private func logout() {
        AppBootstrap.logout { _ in
            Task { @MainActor in
                environment.markLoggedOut()
            }
        }
    }
}

private struct MessageReadStatusRow: View {
    var title: String
    @State private var isOn = SettingRepo.shared.getShowReadStatus()

    var body: some View {
        DemoSwitchRow(title: title, isOn: $isOn) { value in
            SettingRepo.shared.setShowReadStatus(value)
        }
    }
}

private struct CloudConversationRow: View {
    var title: String
    @State private var isOn = IMKitClient.instance.isV2CloudConversationEnabled
    @State private var showRestartAlert = false
    @State private var pendingValue = IMKitClient.instance.isV2CloudConversationEnabled

    var body: some View {
        DemoSwitchRow(title: title, isOn: $isOn) { value in
            pendingValue = value
            showRestartAlert = true
        }
        .alert(localizable("restart_tips"), isPresented: $showRestartAlert) {
            Button(localizable("cancel"), role: .cancel) {
                isOn.toggle()
            }
            Button(localizable("exit"), role: .destructive) {
                UserDefaults.standard.set(pendingValue, forKey: keyEnableCloudConversation)
                UserDefaults.standard.synchronize()
                exit(0)
            }
        }
    }
}

@MainActor
private final class MessageReminderSettingsState: ObservableObject {
    static let shared = MessageReminderSettingsState()

    @Published private(set) var pushEnabled: Bool
    @Published private(set) var detailEnabled: Bool

    private let settingRepo: SettingRepo
    private var accountId: String?
    private var confirmedPushEnabled: Bool
    private var confirmedDetailEnabled: Bool
    private var expectedPushEnabled: Bool?
    private var expectedDetailEnabled: Bool?
    private var pushRequestGeneration = 0
    private var detailRequestGeneration = 0

    private init(settingRepo: SettingRepo = .shared) {
        self.settingRepo = settingRepo
        accountId = IMKitClient.instance.account()
        let pushEnabled = settingRepo.getPushEnable()
        let detailEnabled = settingRepo.getPushDetailEnable()
        self.pushEnabled = pushEnabled
        self.detailEnabled = detailEnabled
        confirmedPushEnabled = pushEnabled
        confirmedDetailEnabled = detailEnabled
    }

    func refresh() {
        let currentAccountId = IMKitClient.instance.account()
        if currentAccountId != accountId {
            accountId = currentAccountId
            expectedPushEnabled = nil
            expectedDetailEnabled = nil
            pushRequestGeneration += 1
            detailRequestGeneration += 1
        }

        let repositoryPushEnabled = settingRepo.getPushEnable()
        if let expectedPushEnabled,
           repositoryPushEnabled != expectedPushEnabled {
            pushEnabled = expectedPushEnabled
            confirmedPushEnabled = expectedPushEnabled
        } else {
            self.expectedPushEnabled = nil
            pushEnabled = repositoryPushEnabled
            confirmedPushEnabled = repositoryPushEnabled
        }

        let repositoryDetailEnabled = settingRepo.getPushDetailEnable()
        if let expectedDetailEnabled,
           repositoryDetailEnabled != expectedDetailEnabled {
            detailEnabled = expectedDetailEnabled
            confirmedDetailEnabled = expectedDetailEnabled
        } else {
            self.expectedDetailEnabled = nil
            detailEnabled = repositoryDetailEnabled
            confirmedDetailEnabled = repositoryDetailEnabled
        }
    }

    func stagePushEnabled(_ value: Bool) {
        expectedPushEnabled = value
        pushEnabled = value
    }

    func stageDetailEnabled(_ value: Bool) {
        expectedDetailEnabled = value
        detailEnabled = value
    }

    func rollbackPushEnabled() {
        expectedPushEnabled = nil
        pushEnabled = confirmedPushEnabled
    }

    func rollbackDetailEnabled() {
        expectedDetailEnabled = nil
        detailEnabled = confirmedDetailEnabled
    }

    func commitPushEnabled(_ value: Bool,
                           completion: @escaping (NSError?) -> Void) {
        pushRequestGeneration += 1
        let generation = pushRequestGeneration
        settingRepo.setMessageNotify(value) { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.pushRequestGeneration else {
                    return
                }
                if error == nil {
                    self.confirmedPushEnabled = value
                    self.expectedPushEnabled = value
                    self.pushEnabled = value
                } else {
                    self.expectedPushEnabled = nil
                    self.pushEnabled = self.confirmedPushEnabled
                }
                completion(error)
            }
        }
    }

    func commitDetailEnabled(_ value: Bool,
                             completion: @escaping (NSError?) -> Void) {
        detailRequestGeneration += 1
        let generation = detailRequestGeneration
        settingRepo.setPushShowDetail(value) { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.detailRequestGeneration else {
                    return
                }
                if error == nil {
                    self.confirmedDetailEnabled = value
                    self.expectedDetailEnabled = value
                    self.detailEnabled = value
                } else {
                    self.expectedDetailEnabled = nil
                    self.detailEnabled = self.confirmedDetailEnabled
                }
                completion(error)
            }
        }
    }
}

struct MessageReminderView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var settings = MessageReminderSettingsState.shared
    @State private var toast: String?

    var body: some View {
        DemoNavigationPage(title: localizable("message_remind")) {
            ScrollView {
                DemoSettingSection {
                    DemoSwitchRow(title: localizable("new_message_remind"), isOn: pushEnabledBinding) { value in
                        guard DemoNetworkPresentation.allowsNetworkOperation else {
                            settings.rollbackPushEnabled()
                            toast = DemoNetworkPresentation.networkMessage()
                            return
                        }
                        settings.commitPushEnabled(value) { error in
                            if let error {
                                toast = DemoNetworkPresentation.message(for: error)
                            }
                        }
                    }
                    DemoDivider()
                    DemoSwitchRow(title: localizable("display_message_detail"), isOn: detailEnabledBinding) { value in
                        guard DemoNetworkPresentation.allowsNetworkOperation else {
                            settings.rollbackDetailEnabled()
                            toast = DemoNetworkPresentation.networkMessage()
                            return
                        }
                        settings.commitDetailEnabled(value) { error in
                            if let error {
                                toast = DemoNetworkPresentation.message(for: error)
                            }
                        }
                    }
                }
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .onAppear {
            settings.refresh()
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            self.toast = nil
                        }
                    }
            }
        }
    }

    private var pushEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.pushEnabled },
            set: settings.stagePushEnabled
        )
    }

    private var detailEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.detailEnabled },
            set: settings.stageDetailEnabled
        )
    }
}

struct StyleSelectionView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        DemoNavigationPage(title: localizable("style_selection"), background: .white) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    styleCard(mode: .normal, imageName: "style_normal", selectedImageName: "clicked_normal", title: localizable("style_default"))
                    styleCard(mode: .fun, imageName: "style_fun", selectedImageName: "clicked_fun", title: localizable("style_fun"))
                }
                .padding(.top, 40)
            }
            .background(Color.white.ignoresSafeArea())
        }
    }

    private func styleCard(mode: ThemeMode, imageName: String, selectedImageName: String, title: String) -> some View {
        Button {
            environment.setThemeMode(mode)
            NotificationCenter.default.post(name: Notification.Name("change_ui"), object: nil)
        } label: {
            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ExampleAssetIcon(name: imageName)
                        .frame(width: 102, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    ExampleAssetIcon(name: environment.themeMode == mode ? selectedImageName : "unclicked", size: 22)
                        .padding(8)
                }
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct LanguageSelectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = NEAppLanguageUtil.getCurrentLanguage()

    var body: some View {
        let actionTitle = environment.themeMode == .normal ? localizable("save") : localizable("complete")
        DemoNavigationPage(
            title: localizable("app_language"),
            trailingWidth: DemoSettingStyle.navigationTextButtonWidth(actionTitle)
        ) {
            DemoNavigationTextButton(title: actionTitle) {
                NEAppLanguageUtil.setCurrentLanguage(selectedLanguage)
                AppBootstrap.syncSwiftUIModuleLanguage()
                environment.languageRevision += 1
                NotificationCenter.default.post(name: NENotificationName.changeLanguage, object: nil)
                dismiss()
            }
        } content: {
            ScrollView {
                DemoSettingSection {
                    languageRow(.chinese, title: localizable("app_language_zh"))
                    DemoDivider()
                    languageRow(.english, title: localizable("app_language_en"))
                }
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
    }

    private func languageRow(_ language: NEAppLanguage, title: String) -> some View {
        Button {
            selectedLanguage = language
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                Spacer()
                if selectedLanguage == language {
                    ExampleAssetIcon(name: "language_select", size: 20)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TranslationSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var autoTranslation = IMKitConfigCenter.shared.autoTranslationEnableTime > 0

    var body: some View {
        DemoNavigationPage(title: localizable("translation_setting")) {
            ScrollView {
                DemoSettingSection {
                    NavigationLink(destination: TranslationLanguageSelectionView().demoHidesTabBar()) {
                        DemoSettingRow(
                            title: localizable("translation_target_language"),
                            iconName: nil,
                            detail: translationLanguageName(IMKitConfigCenter.shared.translationTargetLanguage)
                        )
                    }
                    DemoDivider()
                    DemoSwitchRow(title: localizable("auto_translation"), isOn: $autoTranslation) { value in
                        if value {
                            let now = Date().timeIntervalSince1970
                            IMKitConfigCenter.shared.autoTranslationEnableTime = now
                            UserDefaults.standard.set(now, forKey: "autoTranslationEnableTime")
                        } else {
                            IMKitConfigCenter.shared.autoTranslationEnableTime = 0
                            UserDefaults.standard.set(0.0, forKey: "autoTranslationEnableTime")
                        }
                    }
                }
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
    }
}

struct TranslationLanguageSelectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCode = IMKitConfigCenter.shared.translationTargetLanguage

    var body: some View {
        let actionTitle = localizable("save")
        DemoNavigationPage(
            title: localizable("translation_target_language"),
            trailingWidth: DemoSettingStyle.navigationTextButtonWidth(actionTitle)
        ) {
            DemoNavigationTextButton(title: actionTitle) {
                IMKitConfigCenter.shared.translationTargetLanguage = selectedCode
                UserDefaults.standard.set(selectedCode, forKey: "translationTargetLanguage")
                dismiss()
            }
        } content: {
            ScrollView {
                DemoSettingSection {
                    ForEach(Array(Self.languages.enumerated()), id: \.offset) { index, language in
                        Button {
                            selectedCode = language.code
                        } label: {
                            HStack {
                                Text(localizable(language.key))
                                    .font(.system(size: 16))
                                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                                Spacer()
                                if selectedCode == language.code {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DemoSettingStyle.themeColor(environment.themeMode))
                                }
                            }
                            .frame(height: 52)
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        if index < Self.languages.count - 1 {
                            DemoDivider()
                        }
                    }
                }
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
    }

    static let languages: [(code: String, key: String)] = [
        ("zh-CHS", "lang_zh_chs"),
        ("zh-CHT", "lang_zh_cht"),
        ("en", "lang_en"),
        ("ja", "lang_ja"),
        ("ko", "lang_ko"),
        ("fr", "lang_fr"),
        ("de", "lang_de"),
        ("es", "lang_es"),
        ("it", "lang_it"),
        ("ru", "lang_ru"),
        ("pt", "lang_pt"),
        ("ar", "lang_ar"),
        ("th", "lang_th"),
        ("vi", "lang_vi"),
        ("id", "lang_id"),
    ]
}

private func translationLanguageName(_ code: String) -> String {
    let key = TranslationLanguageSelectionView.languages.first(where: { $0.code == code })?.key
    return key.map(localizable) ?? code
}

struct GlobalConfigView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var useSystemNav = UserDefaults.standard.bool(forKey: "useSystemNav")
    @State private var enableTeam = IMKitConfigCenter.shared.enableTeam
    @State private var enableTeamJoin = IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth
    @State private var enableCollection = IMKitConfigCenter.shared.enableCollectionMessage
    @State private var enablePin = IMKitConfigCenter.shared.enablePinMessage
    @State private var enableTop = IMKitConfigCenter.shared.enableTopMessage
    @State private var enableOnline = IMKitConfigCenter.shared.enableOnlineStatus
    @State private var enableRevokeTip = IMKitConfigCenter.shared.enableInsertLocalMsgWhenRevoke
    @State private var enableCloudSearch = IMKitConfigCenter.shared.enableCloudMessageSearch
    @State private var enableOnlyFriendCall = IMKitConfigCenter.shared.enableOnlyFriendCall
    @State private var enableDismissTeamDelete = IMKitConfigCenter.shared.enableDismissTeamDeleteConversation
    @State private var enableAIUser = IMKitConfigCenter.shared.enableAIUser
    @State private var enableAIStream = IMKitConfigCenter.shared.enableAIStream
    @State private var enableRichText = IMKitConfigCenter.shared.enableRichTextMessage
    @State private var enableAntiSpam = IMKitConfigCenter.shared.enableAntiSpamTipMessage
    @State private var recentForwardMax = "\(IMKitConfigCenter.shared.recentForwardListMaxCount)"
    @State private var teamManagerMax = "\(IMKitConfigCenter.shared.teamManagerMaxCount)"
    @State private var savedToast = false

    var body: some View {
        let actionTitle = localizable("save")
        DemoNavigationPage(
            title: localizable("global_config"),
            trailingWidth: DemoSettingStyle.navigationTextButtonWidth(actionTitle)
        ) {
            DemoNavigationTextButton(title: actionTitle) {
                save()
            }
        } content: {
            ScrollView {
                VStack(spacing: 0) {
                    Text(localizable("tap_save_to_apply"))
                        .font(.system(size: 14))
                        .foregroundColor(DemoSettingStyle.secondaryColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)

                    DemoSettingSection {
                        configSwitch(localizable("use_system_nav"), $useSystemNav) { UserDefaults.standard.set($0, forKey: "useSystemNav") }
                        DemoDivider()
                        configSwitch(localizable("show_team"), $enableTeam) { IMKitConfigCenter.shared.enableTeam = $0 }
                        DemoDivider()
                        configSwitch(localizable("team_join_auth"), $enableTeamJoin) { IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth = $0 }
                        DemoDivider()
                        configSwitch(localizable("show_collection"), $enableCollection) { IMKitConfigCenter.shared.enableCollectionMessage = $0 }
                        DemoDivider()
                        configSwitch(localizable("show_pin"), $enablePin) { IMKitConfigCenter.shared.enablePinMessage = $0 }
                        DemoDivider()
                        configSwitch(localizable("show_top"), $enableTop) { IMKitConfigCenter.shared.enableTopMessage = $0 }
                        DemoDivider()
                        configSwitch(localizable("show_online_status"), $enableOnline) { IMKitConfigCenter.shared.enableOnlineStatus = $0 }
                        DemoDivider()
                        configSwitch(localizable("insert_revoke_tip"), $enableRevokeTip) { IMKitConfigCenter.shared.enableInsertLocalMsgWhenRevoke = $0 }
                        DemoDivider()
                        configSwitch(localizable("cloud_message_search"), $enableCloudSearch) {
                            IMKitConfigCenter.shared.enableCloudMessageSearch = $0
                            UserDefaults.standard.set($0, forKey: keyEnableCloudMessageSearch)
                        }
                        DemoDivider()
                        configSwitch(localizable("only_friend_call"), $enableOnlyFriendCall) { IMKitConfigCenter.shared.enableOnlyFriendCall = $0 }
                        DemoDivider()
                        configSwitch(localizable("dismiss_team_delete_conversation"), $enableDismissTeamDelete) { IMKitConfigCenter.shared.enableDismissTeamDeleteConversation = $0 }
                        DemoDivider()
                        configSwitch(localizable("enable_ai_user"), $enableAIUser) { IMKitConfigCenter.shared.enableAIUser = $0 }
                        DemoDivider()
                        configSwitch(localizable("ai_stream_message"), $enableAIStream) { IMKitConfigCenter.shared.enableAIStream = $0 }
                        DemoDivider()
                        configSwitch(localizable("rich_text_message"), $enableRichText) { IMKitConfigCenter.shared.enableRichTextMessage = $0 }
                        DemoDivider()
                        configSwitch(localizable("anti_spam_tip"), $enableAntiSpam) { IMKitConfigCenter.shared.enableAntiSpamTipMessage = $0 }
                    }

                    DemoSettingSection {
                        numericRow(localizable("recent_forward_limit"), text: $recentForwardMax)
                        DemoDivider()
                        numericRow(localizable("team_manager_limit"), text: $teamManagerMax)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .overlay(alignment: .top) {
            if savedToast {
                Text(localizable("save_success"))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)
            }
        }
    }

    private func configSwitch(_ title: String, _ binding: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        DemoSwitchRow(title: title, isOn: binding, onChange: onChange)
    }

    private func numericRow(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
            Spacer(minLength: 16)
            TextField("", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .frame(width: 90)
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
    }

    private func save() {
        if let value = Int(recentForwardMax), value > 0 {
            IMKitConfigCenter.shared.recentForwardListMaxCount = value
        }
        if let value = Int(teamManagerMax), value >= -1 {
            IMKitConfigCenter.shared.teamManagerMaxCount = value
        }
        NotificationCenter.default.post(name: Notification.Name("change_ui"), object: nil)
        savedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            savedToast = false
        }
    }
}

private enum DemoConfigParseMode: Equatable {
    case manual
    case auto

    var title: String {
        switch self {
        case .manual:
            return localizable("manual_config")
        case .auto:
            return localizable("auto_parse_config")
        }
    }
}

private struct DemoUIKitConfigPage<Content: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    @Binding var savedToast: Bool
    @ViewBuilder var content: () -> Content
    var onSave: () -> Void

    var body: some View {
        DemoNavigationPage(title: title) {
            ScrollView {
                VStack(spacing: 0) {
                    content()
                    saveButton
                        .padding(.top, 10)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .overlay(alignment: .top) {
            if savedToast {
                Text(localizable("save_success_restart"))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)
            }
        }
    }

    private var saveButton: some View {
        Button {
            onSave()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                savedToast = false
            }
        } label: {
            Text(localizable("save"))
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(DemoSettingStyle.themeColor(environment.themeMode))
                .clipShape(RoundedRectangle(cornerRadius: environment.themeMode == .normal ? 8 : 0, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, environment.themeMode == .normal ? 20 : 0)
        .accessibilityIdentifier("id.save")
    }
}

private struct DemoConfigInputRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    @Binding var text: String
    var placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .lineLimit(1)
                .truncationMode(.tail)

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 8)
                .frame(height: 40)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(hex: 0xDBE0E8), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 100, alignment: .top)
        .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
        .padding(.top, 15)
    }
}

private struct DemoConfigTextEditorRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .lineLimit(1)
                .truncationMode(.tail)

            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(hex: 0xDBE0E8), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 200, alignment: .top)
        .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
        .padding(.top, 15)
        .padding(.bottom, 10)
    }
}

struct PrivateCloudConfigView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var config = DemoPrivateCloudConfigStore.getConfig()
    @State private var parseMode: DemoConfigParseMode = .auto
    @State private var showParseModeSheet = false
    @State private var savedToast = false

    var body: some View {
        DemoUIKitConfigPage(title: localizable("private_cloud_config"), savedToast: $savedToast) {
            DemoSettingSection {
                DemoSwitchRow(title: localizable("private_config_enable"), isOn: enableBinding) { _ in }
            }

            Text(localizable("private_config_params"))
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
                .padding(.top, 12)
                .padding(.bottom, 0)

            DemoSettingSection(topPadding: 10) {
                configModeRow
                if parseMode == .manual {
                    DemoDivider()
                    textRow("AppKey", text: binding(\.appKey))
                    DemoDivider()
                    textRow("Module", text: binding(\.module))
                    DemoDivider()
                    textRow(localizable("link_address"), text: binding(\.linkAddress))
                    DemoDivider()
                    textRow(localizable("lbs_address"), text: binding(\.lbsAddress))
                    DemoDivider()
                    textRow(localizable("nos_lbs_address"), text: binding(\.nosLbsAddress))
                    DemoDivider()
                    textRow(localizable("nos_upload_address"), text: binding(\.nosUploadAddress))
                    DemoDivider()
                    textRow(localizable("nos_download_address"), text: binding(\.nosDownloadAddress))
                    DemoDivider()
                    textRow(localizable("nos_upload_host"), text: binding(\.nosUploadHost))
                } else {
                    DemoDivider()
                    autoParseTextRow
                }
            }
        } onSave: {
            DemoPrivateCloudConfigStore.saveConfig(config)
            savedToast = true
        }
        .onAppear {
            parseMode = .auto
        }
        .neCommonConfirmationDialog(
            parseModeDialogState,
            onAction: handleParseModeDialogAction,
            onDismiss: { showParseModeSheet = false }
        )
    }

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { config.enableCustomConfig },
            set: { config.enableCustomConfig = $0 }
        )
    }

    private var configModeRow: some View {
        Button {
            showParseModeSheet = true
        } label: {
            HStack(spacing: 12) {
                Text(localizable("config_method"))
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                Spacer(minLength: 16)
                Text(parseMode.title)
                    .font(.system(size: 14))
                    .foregroundColor(DemoSettingStyle.detailColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DemoSettingStyle.chevronColor)
            }
            .frame(height: 49)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var autoParseTextRow: some View {
        DemoConfigTextEditorRow(
            title: localizable("private_config_content"),
            text: customJsonBinding
        )
    }

    private func textRow(_ title: String, text: Binding<String>) -> some View {
        DemoConfigInputRow(
            title: title,
            text: text,
            placeholder: localizable("please_fill")
        )
    }

    private var customJsonBinding: Binding<String> {
        Binding(
            get: { config.customJson ?? "" },
            set: { config.customJson = $0.isEmpty ? nil : $0 }
        )
    }

    private var parseModeDialogState: NECommonDialogState? {
        guard showParseModeSheet else {
            return nil
        }
        return NECommonDialogState(
            id: "privateCloudParseMode",
            title: "",
            showsTitle: false,
            presentationStyle: .actionSheet,
            actions: [
                NECommonDialogAction(id: "auto", title: localizable("auto_parse_config")),
                NECommonDialogAction(id: "manual", title: localizable("manual_config")),
                NECommonDialogAction(id: "cancel", title: localizable("cancel"), role: .cancel),
            ]
        )
    }

    private func handleParseModeDialogAction(_ action: NECommonDialogAction) {
        switch action.id {
        case "auto":
            parseMode = .auto
        case "manual":
            parseMode = .manual
        default:
            break
        }
        showParseModeSheet = false
    }

    private func binding(_ keyPath: WritableKeyPath<DemoPrivateCloudConfigModel, String>) -> Binding<String> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { config[keyPath: keyPath] = $0 }
        )
    }
}

struct PushConfigView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var config = DemoPushConfigStore.getConfig()
    @State private var parseMode: DemoConfigParseMode = .auto
    @State private var showParseModeSheet = false
    @State private var savedToast = false

    var body: some View {
        DemoUIKitConfigPage(title: localizable("push_config"), savedToast: $savedToast) {
            Text(localizable("push_config_params"))
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, environment.themeMode == .normal ? 36 : 20)
                .padding(.top, 12)
                .padding(.bottom, 0)

            DemoSettingSection(topPadding: 10) {
                configModeRow
                if parseMode == .manual {
                    DemoDivider()
                    DemoSwitchRow(title: localizable("push_enabled_desc"), isOn: binding(\.pushEnabled)) { _ in }
                    DemoDivider()
                    DemoSwitchRow(title: localizable("push_nick_enabled_desc"), isOn: binding(\.pushNickEnabled)) { _ in }
                    DemoDivider()
                    textRow("pushContent", text: binding(\.pushContent), placeholder: localizable("push_content_placeholder"))
                    DemoDivider()
                    textRow("pushPayload", text: binding(\.pushPayload), placeholder: localizable("push_payload_placeholder"))
                    DemoDivider()
                    DemoSwitchRow(title: localizable("force_push_desc"), isOn: binding(\.forcePush)) { _ in }
                    DemoDivider()
                    textRow("forcePushContent", text: binding(\.forcePushContent), placeholder: localizable("force_push_content_placeholder"))
                    DemoDivider()
                    textRow("forcePushAccountIds", text: binding(\.forcePushAccountIds), placeholder: localizable("force_push_accounts_placeholder"))
                } else {
                    DemoDivider()
                    autoParseTextRow
                }
            }
        } onSave: {
            DemoPushConfigStore.saveConfig(config)
            savedToast = true
        }
        .onAppear {
            parseMode = .auto
        }
        .neCommonConfirmationDialog(
            parseModeDialogState,
            onAction: handleParseModeDialogAction,
            onDismiss: { showParseModeSheet = false }
        )
    }

    private var configModeRow: some View {
        Button {
            showParseModeSheet = true
        } label: {
            HStack(spacing: 12) {
                Text(localizable("config_method"))
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                Spacer(minLength: 16)
                Text(parseMode.title)
                    .font(.system(size: 14))
                    .foregroundColor(DemoSettingStyle.detailColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DemoSettingStyle.chevronColor)
            }
            .frame(height: 49)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var autoParseTextRow: some View {
        DemoConfigTextEditorRow(
            title: localizable("push_config_content"),
            text: customJsonBinding
        )
    }

    private func textRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        DemoConfigInputRow(
            title: title,
            text: text,
            placeholder: placeholder
        )
    }

    private var customJsonBinding: Binding<String> {
        Binding(
            get: { config.customJson ?? "" },
            set: { config.customJson = $0.isEmpty ? nil : $0 }
        )
    }

    private var parseModeDialogState: NECommonDialogState? {
        guard showParseModeSheet else {
            return nil
        }
        return NECommonDialogState(
            id: "pushParseMode",
            title: "",
            showsTitle: false,
            presentationStyle: .actionSheet,
            actions: [
                NECommonDialogAction(id: "auto", title: localizable("auto_parse_config")),
                NECommonDialogAction(id: "manual", title: localizable("manual_config")),
                NECommonDialogAction(id: "cancel", title: localizable("cancel"), role: .cancel),
            ]
        )
    }

    private func handleParseModeDialogAction(_ action: NECommonDialogAction) {
        switch action.id {
        case "auto":
            parseMode = .auto
        case "manual":
            parseMode = .manual
        default:
            break
        }
        showParseModeSheet = false
    }

    private func binding(_ keyPath: WritableKeyPath<DemoPushConfigModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { config[keyPath: keyPath] = $0 }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<DemoPushConfigModel, String>) -> Binding<String> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { config[keyPath: keyPath] = $0 }
        )
    }
}

struct NodeSelectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedIsDomestic = SettingRepo.shared.getNodeValue()
    @State private var pendingIsDomestic: Bool?

    var body: some View {
        DemoNavigationPage(title: localizable("node_select")) {
            ScrollView {
                DemoSettingSection {
                    nodeRow(title: localizable("domestic_node"), isDomestic: true)
                    DemoDivider()
                    nodeRow(title: localizable("overseas_node"), isDomestic: false)
                }
            }
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .alert(
            localizable("change_node"),
            isPresented: Binding(
                get: { pendingIsDomestic != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingIsDomestic = nil
                    }
                }
            )
        ) {
            Button(localizable("cancel"), role: .cancel) {
                pendingIsDomestic = nil
            }
            Button(localizable("exit")) {
                if let pendingIsDomestic {
                    SettingRepo.shared.setNodeValue(pendingIsDomestic)
                    selectedIsDomestic = pendingIsDomestic
                }
                pendingIsDomestic = nil
                exit(0)
            }
        } message: {
            Text(localizable("restart_take_effect"))
        }
    }

    private func nodeRow(title: String, isDomestic: Bool) -> some View {
        Button {
            if selectedIsDomestic != isDomestic {
                pendingIsDomestic = isDomestic
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                Spacer()
                Image(systemName: selectedIsDomestic == isDomestic ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(
                        selectedIsDomestic == isDomestic
                            ? DemoSettingStyle.themeColor(environment.themeMode)
                            : DemoSettingStyle.chevronColor
                    )
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DemoFormPage<Content: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    @Binding var savedToast: Bool
    @ViewBuilder var content: () -> Content
    var onSave: () -> Void

    var body: some View {
        let actionTitle = localizable("save")
        DemoNavigationPage(
            title: title,
            trailingWidth: DemoSettingStyle.navigationTextButtonWidth(actionTitle)
        ) {
            DemoNavigationTextButton(title: actionTitle) {
                onSave()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    savedToast = false
                }
            }
        } content: {
            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
        .overlay(alignment: .top) {
            if savedToast {
                Text(localizable("save_success_restart"))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)
            }
        }
    }
}

struct AboutYunxinView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private static let productIntroductionURL = URL(string: "https://netease.im/m/")!

    private var appVersionText: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return "-"
        }
        return "V\(version)"
    }

    private var imVersionText: String {
        let version = NIMSDK.shared().sdkVersion()
        return version.isEmpty ? "-" : version
    }

    var body: some View {
        DemoNavigationPage(title: localizable("about_yunxin")) {
            VStack(spacing: 16) {
                Spacer().frame(height: 28)
                ExampleAssetIcon(name: "yunxin_logo", size: 72)
                Text(localizable("brand_des"))
                    .font(.system(size: 20))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                DemoSettingSection {
                    DemoSettingRow(
                        title: localizable("version"),
                        iconName: nil,
                        detail: appVersionText,
                        showChevron: false
                    )
                    DemoDivider()
                    DemoSettingRow(
                        title: localizable("im_version"),
                        iconName: nil,
                        detail: imVersionText,
                        showChevron: false
                    )
                    DemoDivider()
                    NavigationLink {
                        DemoWebPageView(
                            title: localizable("product_intro"),
                            url: Self.productIntroductionURL
                        )
                        .demoHidesTabBar()
                    } label: {
                        DemoSettingRow(
                            title: localizable("product_intro"),
                            iconName: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                ExampleAssetIcon(name: "copy_right")
                    .frame(width: 210, height: 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
        }
    }
}

struct DemoWebPageView: View {
    let title: String
    let url: URL

    var body: some View {
        DemoNavigationPage(title: title, background: .white) {
            DemoWebContentView(url: url)
                .background(Color.white.ignoresSafeArea())
        }
    }
}

private struct DemoWebContentView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        load(url, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else {
            return
        }
        load(url, in: webView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: URL?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased(),
                  ["http", "https", "about"].contains(scheme) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

#if DEBUG
struct MineView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DemoSettingsView()
                .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
        }
    }
}
#endif
