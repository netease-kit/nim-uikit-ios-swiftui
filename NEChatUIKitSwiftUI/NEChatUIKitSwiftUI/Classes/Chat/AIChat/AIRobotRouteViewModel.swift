// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

private enum AIRobotTextLimit {
  static let name = 15
  static let accid = 32
}

@MainActor
public final class AIRobotRouteViewModel: ObservableObject {
  @Published public private(set) var state: AIRobotDetailState

  private let aiRepo: AIRepo
  private let robotManager: NEAIRobotManager
  private let networkOperationGuard: () -> Bool
  private var requestGeneration = 0
  private var avatarSelectionGeneration = 0
  private var isSubmittingForm = false
  private var isRefreshingToken = false
  private var isDeletingRobot = false
  private var isBindingRobot = false

  public init(route: AIRobotRouteState,
              aiRepo: AIRepo = .shared,
              robotManager: NEAIRobotManager = .shared,
              networkOperationGuard: @escaping () -> Bool = {
                IMKitClient.instance.swiftUICurrentNetworkAvailable
              }) {
    self.aiRepo = aiRepo
    self.robotManager = robotManager
    self.networkOperationGuard = networkOperationGuard
    state = Self.makeState(route: route)
  }

  public func chatRoute() -> NEChatSwiftUIRoute? {
    guard let bot = state.route.bot,
          let conversationId = V2NIMConversationIdUtil.p2pConversationId(bot.accid) else {
      showToast(
        NEChatUIKitSwiftUIBundle.localized("ai_robot_invalid_chat", value: "Unable to open this robot chat."),
        style: .error
      )
      return nil
    }

    let title = Self.displayName(for: bot)
    return .botSubSessionList(
      ChatSessionContext(
        kind: .botSubSession,
        conversationId: conversationId,
        title: title,
        sessionId: bot.accid,
        sessionName: title
      )
    )
  }

  public func detailRoute() -> NEChatSwiftUIRoute? {
    guard let bot = state.route.bot else {
      return nil
    }
    return .aiRobot(.init(kind: .detail, bot: bot, sourceURL: ContactAIRobotDetailRouter))
  }

  public func configRoute() -> NEChatSwiftUIRoute? {
    guard let bot = state.route.bot else {
      return nil
    }
    return .aiRobot(.init(kind: .config, bot: bot, sourceURL: ContactAIRobotConfigRouter))
  }

  public func editRoute() -> NEChatSwiftUIRoute? {
    guard let bot = state.route.bot else {
      return nil
    }
    return .aiRobot(.init(kind: .create, bot: bot, defaultName: Self.displayName(for: bot), sourceURL: ContactCreateAIRobotRouter))
  }

  public func bindSelectedRoute(for row: AIRobotRowState) -> NEChatSwiftUIRoute {
    .aiRobot(
      .init(
        kind: .bind,
        bot: row.bot,
        autoBindQrCode: state.route.autoBindQrCode,
        previousBoundAccid: state.route.previousBoundAccid,
        sourceURL: ContactAIRobotBindRouter
      )
    )
  }

  public func updateFormName(_ name: String) {
    guard state.form != nil else {
      return
    }
    let limitedName = NECommonTextLimit.limitedUTF16(name, limit: AIRobotTextLimit.name)
    state.form?.name = limitedName
    state.form?.nameError = nil
    state.displayName = limitedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? state.title : limitedName
    updateAvatarPlaceholderDisplayNameIfNeeded(name: limitedName)
  }

  public func updateFormAccid(_ accid: String) {
    guard state.form?.isAccidEditable == true else {
      return
    }
    let limitedAccid = NECommonTextLimit.limitedUTF16(accid, limit: AIRobotTextLimit.accid)
    state.form?.accid = limitedAccid
    state.form?.accidError = nil
    state.subtitle = limitedAccid
  }

  public func openNicknameEditor() {
    guard let form = state.form else {
      return
    }
    state.pendingNameEdit = form
    state.route = AIRobotRouteState(
      kind: .nicknameEdit,
      bot: state.route.bot,
      defaultName: state.route.defaultName,
      autoBindQrCode: state.route.autoBindQrCode,
      previousBoundAccid: state.route.previousBoundAccid,
      currentName: form.name,
      sourceURL: ContactRobotNicknameEditRouter
    )
    state.title = Self.fallbackTitle(for: .nicknameEdit)
    state.displayName = form.name
    state.form = AIRobotFormState(
      mode: .nicknameEdit,
      name: form.name,
      accid: "",
      isAccidEditable: false
    )
  }

  public func cancelNicknameEdit() {
    guard let restored = state.pendingNameEdit else {
      return
    }
    state.route = AIRobotRouteState(
      kind: .create,
      bot: restored.mode == .edit ? state.route.bot : nil,
      defaultName: restored.name,
      autoBindQrCode: state.route.autoBindQrCode,
      previousBoundAccid: state.route.previousBoundAccid,
      sourceURL: ContactCreateAIRobotRouter
    )
    state.title = restored.mode == .edit
      ? NEChatUIKitSwiftUIBundle.localized("edit_ai_robot", value: "Edit Robot")
      : NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot")
    state.form = restored
    state.pendingNameEdit = nil
    state.displayName = restored.name
    updateAvatarPlaceholderDisplayNameIfNeeded(name: restored.name)
  }

  public func saveNicknameEdit(onSaved: @escaping () -> Void) {
    guard let editForm = state.form else {
      return
    }
    let name = editForm.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      showToast(
        NEChatUIKitSwiftUIBundle.localized("ai_robot_name_placeholder", value: "Enter robot name"),
        style: .warning
      )
      return
    }

    var restored = state.pendingNameEdit ?? editForm
    restored.name = name
    restored.nameError = nil
    state.route = AIRobotRouteState(
      kind: .create,
      bot: restored.mode == .edit ? state.route.bot : nil,
      defaultName: restored.name,
      sourceURL: ContactCreateAIRobotRouter
    )
    state.title = restored.mode == .edit
      ? NEChatUIKitSwiftUIBundle.localized("edit_ai_robot", value: "Edit Robot")
      : NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot")
    state.form = restored
    state.pendingNameEdit = nil
    state.displayName = name
    updateAvatarPlaceholderDisplayNameIfNeeded(name: name)
    onSaved()
  }

  public func selectAvatar(handler: ChatAvatarSelectionHandling?) {
    guard let handler else {
      showToast(
        NEChatUIKitSwiftUIBundle.localized("ai_robot_avatar_requires_host", value: "Avatar selection requires a SwiftUI host handler."),
        style: .warning
      )
      return
    }

    let generation = nextAvatarSelectionGeneration()
    let form = state.form
    let request = ChatAvatarSelectionRequest(
      source: form?.mode == .edit ? .aiRobotEdit : .aiRobotCreate,
      currentAvatarURL: form?.avatarURL ?? state.avatarURL,
      displayName: state.displayName,
      accountId: state.route.bot?.accid ?? form?.accid
    )

    handler.selectAvatar(request: request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.avatarSelectionGeneration == generation else {
          return
        }

        switch result {
        case .success(.selected(let url)):
          self.state.form?.avatarURL = url
          self.state.avatarURL = url
          self.state.avatarDisplayName = nil
          self.showToast(
            NEChatUIKitSwiftUIBundle.localized("ai_robot_avatar_selected", value: "Avatar selected."),
            style: .success
          )
        case .success(.cancelled):
          self.showToast(
            NEChatUIKitSwiftUIBundle.localized("ai_robot_avatar_selection_cancelled", value: "Avatar selection cancelled."),
            style: .info
          )
        case .failure(let error):
          self.showToast(
            NEChatErrorMessageMapper.message(
              for: error,
              fallbackKey: "ai_robot_avatar_selection_failed",
              fallbackValue: "Avatar selection failed"
            ),
            style: .error
          )
        }
      }
    }
  }

  public func submitForm(onSaved: @escaping (V2NIMUserAIBot?) -> Void) {
    guard !isSubmittingForm else {
      return
    }
    guard allowsNetworkOperation() else {
      return
    }
    guard var form = state.form else {
      return
    }

    form.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
    form.accid = form.accid.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validate(form: form) else {
      return
    }
    isSubmittingForm = true

    switch form.mode {
    case .create:
      createRobot(form: form, onSaved: onSaved)
    case .edit:
      updateRobot(form: form, onSaved: onSaved)
    case .nicknameEdit:
      state.form = form
      isSubmittingForm = false
      showToast(
        NEChatUIKitSwiftUIBundle.localized("ai_robot_name_updated", value: "Name updated."),
        style: .success
      )
      onSaved(nil)
    }
  }

  public func refreshToken() {
    guard !isRefreshingToken else {
      return
    }
    guard allowsNetworkOperation() else {
      return
    }
    guard let bot = state.route.bot else {
      return
    }

    isRefreshingToken = true
    let generation = nextGeneration()
    state.phase = .loading

    let params = V2NIMRefreshUserAIBotTokenParams()
    params.accid = bot.accid
    aiRepo.refreshUserAIBotToken(params) { [weak self] result, error in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        self.isRefreshingToken = false

        if let error {
          self.applyFailure(error, fallbackKey: "ai_robot_token_refresh_failed", fallbackValue: "Refresh failed. Please try again.")
          return
        }

        if let token = result?.token {
          bot.token = token
        }
        self.robotManager.update(bot)
        self.state = Self.makeState(route: self.state.route)
        self.showToast(
          NEChatUIKitSwiftUIBundle.localized("ai_robot_token_refresh_success", value: "Token refreshed."),
          style: .success
        )
      }
    }
  }

  public func deleteRobot(onDeleted: @escaping () -> Void) {
    guard !isDeletingRobot else {
      return
    }
    guard allowsNetworkOperation() else {
      return
    }
    guard let bot = state.route.bot else {
      return
    }

    isDeletingRobot = true
    let generation = nextGeneration()
    state.phase = .loading

    let params = V2NIMDeleteUserAIBotParams()
    params.accid = bot.accid
    aiRepo.deleteUserAIBot(params) { [weak self] error in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        self.isDeletingRobot = false

        if let error {
          self.applyFailure(error, fallbackKey: "ai_robot_delete_failed", fallbackValue: "Delete failed. Please try again.")
          return
        }

        self.robotManager.remove(accid: bot.accid)
        self.state.phase = .idle
        onDeleted()
      }
    }
  }

  public func bindRobot(bot selectedBot: V2NIMUserAIBot? = nil,
                        onBound: ((V2NIMUserAIBot) -> Void)? = nil) {
    guard !isBindingRobot else {
      return
    }
    guard allowsNetworkOperation() else {
      return
    }
    guard let bot = selectedBot ?? state.route.bot,
          let qrCode = state.route.autoBindQrCode,
          !qrCode.isEmpty else {
      showToast(
        NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_missing_qrcode", value: "QR code is missing or expired."),
        style: .error
      )
      return
    }

    isBindingRobot = true
    let generation = nextGeneration()
    state.phase = .loading

    aiRepo.bindUserAIBot(accid: bot.accid, token: bot.token ?? "", qrCode: qrCode) { [weak self] error in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        self.isBindingRobot = false

        if let error {
          self.isSubmittingForm = false
          self.applyFailure(error, fallbackKey: "ai_robot_bind_failed", fallbackValue: "Bind failed. Please try again.")
          return
        }

        self.state.phase = .idle
        self.showToast(
          NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_success", value: "Robot bound."),
          style: .success
        )
        onBound?(bot)
      }
    }
  }

  public func clearToast() {
    state.toast = nil
  }

  public func showToast(_ toast: ChatToastState) {
    state.toast = toast
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard state.toast?.id == toast.id else {
      return
    }
    state.toast = nil
  }

  private func validate(form: AIRobotFormState) -> Bool {
    var updated = form
    if form.name.isEmpty {
      updated.nameError = NEChatUIKitSwiftUIBundle.localized("ai_robot_name_empty", value: "Robot name is required.")
    }
    if form.isAccidEditable, form.accid.isEmpty {
      updated.accidError = NEChatUIKitSwiftUIBundle.localized("ai_robot_accid_empty", value: "Robot account is required.")
    }
    if form.isAccidEditable, NECommonTextLimit.utf16Count(of: form.accid) > AIRobotTextLimit.accid {
      updated.accidError = NEChatUIKitSwiftUIBundle.localized("ai_robot_accid_too_long", value: "Robot account must be no longer than 32 characters.")
    }

    state.form = updated
    if let message = updated.nameError ?? updated.accidError {
      showToast(message, style: .warning)
      return false
    }
    return true
  }

  private func createRobot(form: AIRobotFormState,
                           onSaved: @escaping (V2NIMUserAIBot?) -> Void) {
    let generation = nextGeneration()
    state.phase = .loading

    let params = V2NIMCreateUserAIBotParams()
    params.accid = form.accid
    params.name = form.name
    params.icon = form.avatarURL?.absoluteString

    aiRepo.createUserAIBot(params) { [weak self] _, error in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        if let error {
          self.isSubmittingForm = false
          self.applyFailure(error, fallbackKey: "ai_robot_create_failed", fallbackValue: "Create failed. Please try again.")
          return
        }

        self.fetchLatestBot(accid: form.accid, generation: generation) { bot in
          if let bot {
            self.robotManager.add(bot)
            if let qrCode = self.state.route.autoBindQrCode, !qrCode.isEmpty {
              self.state = Self.makeState(route: .init(kind: .bind, bot: bot, autoBindQrCode: qrCode, previousBoundAccid: self.state.route.previousBoundAccid, sourceURL: ContactAIRobotBindRouter))
              self.bindRobot {
                self.state = Self.makeState(route: .init(kind: .detail, bot: $0, sourceURL: ContactAIRobotDetailRouter))
                self.isSubmittingForm = false
                onSaved($0)
              }
              return
            } else {
              self.state = Self.makeState(route: .init(kind: .detail, bot: bot, sourceURL: ContactAIRobotDetailRouter))
            }
          } else {
            self.state.phase = .idle
          }
          self.showToast(
            NEChatUIKitSwiftUIBundle.localized("ai_robot_create_success", value: "Robot created."),
            style: .success
          )
          self.isSubmittingForm = false
          onSaved(bot)
        }
      }
    }
  }

  private func updateRobot(form: AIRobotFormState,
                           onSaved: @escaping (V2NIMUserAIBot?) -> Void) {
    guard let bot = state.route.bot else {
      return
    }

    let generation = nextGeneration()
    state.phase = .loading

    let params = V2NIMUpdateUserAIBotParams()
    params.accid = bot.accid
    params.name = form.name
    params.icon = form.avatarURL?.absoluteString

    aiRepo.updateUserAIBot(params) { [weak self] error in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        self.isSubmittingForm = false

        if let error {
          self.applyFailure(error, fallbackKey: "ai_robot_update_failed", fallbackValue: "Update failed. Please try again.")
          return
        }

        self.fetchLatestBot(accid: bot.accid, generation: generation) { latestBot in
          if let latestBot {
            self.robotManager.update(latestBot)
            self.state = Self.makeState(route: .init(kind: .detail, bot: latestBot, sourceURL: ContactAIRobotDetailRouter))
          } else {
            bot.name = form.name
            self.robotManager.update(bot)
            self.state = Self.makeState(route: .init(kind: .detail, bot: bot, sourceURL: ContactAIRobotDetailRouter))
          }
          self.showToast(
            NEChatUIKitSwiftUIBundle.localized("ai_robot_update_success", value: "Robot updated."),
            style: .success
          )
          onSaved(latestBot ?? bot)
        }
      }
    }
  }

  private func fetchLatestBot(accid: String,
                              generation: Int,
                              completion: @escaping (V2NIMUserAIBot?) -> Void) {
    let queryParams = V2NIMGetUserAIBotParams()
    queryParams.accid = accid
    aiRepo.getUserAIBot(queryParams) { [weak self] bot, _ in
      Task { @MainActor in
        guard let self, self.requestGeneration == generation else {
          return
        }
        completion(bot)
      }
    }
  }

  private func nextGeneration() -> Int {
    requestGeneration += 1
    return requestGeneration
  }

  private func nextAvatarSelectionGeneration() -> Int {
    avatarSelectionGeneration += 1
    return avatarSelectionGeneration
  }

  private func showToast(_ message: String, style: ChatToastState.Style) {
    state.toast = ChatToastState(message: message, style: style)
  }

  private func allowsNetworkOperation() -> Bool {
    guard networkOperationGuard() else {
      showToast(NEChatErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }

  private func applyFailure(_ error: Error,
                            fallbackKey: String,
                            fallbackValue: String) {
    let message = NEChatErrorMessageMapper.message(
      for: error,
      fallbackKey: fallbackKey,
      fallbackValue: fallbackValue
    )
    state.phase = .failed(message)
    showToast(message, style: .error)
  }

  private static func makeState(route: AIRobotRouteState) -> AIRobotDetailState {
    let bot = route.bot
    let name = bot.map(displayName(for:)) ?? route.defaultName ?? route.currentName ?? fallbackTitle(for: route.kind)
    let avatarURL = bot?.icon.flatMap { URL(string: $0) }
    let fields = makeFields(route: route)
    let form = makeForm(route: route)
    let config = makeConfigString(bot: bot)

    return AIRobotDetailState(
      route: route,
      title: title(for: route),
      displayName: name,
      subtitle: bot?.accid ?? route.previousBoundAccid ?? route.autoBindQrCode,
      avatarURL: avatarURL,
      avatarDisplayName: avatarURL == nil ? name : nil,
      fields: fields,
      form: form,
      configString: config,
      canChat: bot != nil && route.kind != .bind,
      canRefreshToken: bot != nil && (route.kind == .detail || route.kind == .config),
      canDelete: bot != nil && route.kind == .detail,
      canBind: bot != nil && route.kind == .bind && route.autoBindQrCode?.isEmpty == false
    )
  }

  private static func makeForm(route: AIRobotRouteState) -> AIRobotFormState? {
    switch route.kind {
    case .create:
      if let bot = route.bot {
        return AIRobotFormState(
          mode: .edit,
          name: displayName(for: bot),
          accid: bot.accid,
          isAccidEditable: false,
          avatarURL: bot.icon.flatMap { URL(string: $0) }
        )
      }
      return AIRobotFormState(
        mode: .create,
        name: route.defaultName ?? "",
        accid: generateDefaultAccid(),
        isAccidEditable: true
      )
    case .nicknameEdit:
      return AIRobotFormState(
        mode: .nicknameEdit,
        name: route.currentName ?? "",
        accid: "",
        isAccidEditable: false
      )
    default:
      return nil
    }
  }

  private static func makeFields(route: AIRobotRouteState) -> [AIRobotInfoFieldState] {
    var fields: [AIRobotInfoFieldState] = []
    if let bot = route.bot {
      append("accid", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_accid", value: "Accid"), value: bot.accid, to: &fields)
      append("name", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_name", value: "Name"), value: bot.name, to: &fields)
      append("sign", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_sign", value: "Signature"), value: bot.sign, to: &fields)
      append("owner", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_owner", value: "Owner"), value: bot.ownerid, to: &fields)
      append("level", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_level", value: "Level"), value: string(bot.level), to: &fields)
      append("type", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_type", value: "Type"), value: string(bot.type), to: &fields)
      append("business", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_business", value: "Business"), value: string(bot.business), to: &fields)
      append("created", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_created", value: "Created"), value: dateString(bot.createTime), to: &fields)
      append("updated", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_updated", value: "Updated"), value: dateString(bot.updateTime), to: &fields)
      append("model", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_model_config", value: "Model Config"), value: bot.modelConfigStr, to: &fields)
      append("yunxin", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_yunxin_config", value: "Yunxin Config"), value: bot.yunxinConfig, to: &fields)
      append("extension", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_extension", value: "Extension"), value: bot.ex, to: &fields)
      append("token", title: "Token", value: bot.token, isSensitive: true, to: &fields)
    }

    append("defaultName", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_default_name", value: "Default Name"), value: route.defaultName, to: &fields)
    append("qrCode", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_qrcode", value: "QR Code"), value: route.autoBindQrCode, to: &fields)
    append("previousBoundAccid", title: NEChatUIKitSwiftUIBundle.localized("ai_robot_previous_bound", value: "Previous Robot"), value: route.previousBoundAccid, to: &fields)
    return fields
  }

  private static func makeConfigString(bot: V2NIMUserAIBot?) -> String? {
    guard let bot else {
      return nil
    }
    return "\(IMKitClient.instance.appKey())|\(bot.accid)|\(bot.token ?? "")"
  }

  private static func append(_ id: String,
                             title: String,
                             value: String?,
                             isSensitive: Bool = false,
                             to fields: inout [AIRobotInfoFieldState]) {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return
    }
    fields.append(AIRobotInfoFieldState(id: id, title: title, value: value, isSensitive: isSensitive))
  }

  private static func string(_ value: Int) -> String? {
    value == 0 ? nil : String(value)
  }

  private static func dateString(_ milliseconds: UInt64) -> String? {
    guard milliseconds > 0 else {
      return nil
    }
    return ChatUnitFormatter.messageTimeText(TimeInterval(milliseconds) / 1000)
  }

  private static func displayName(for bot: V2NIMUserAIBot) -> String {
    let name = bot.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    return name?.isEmpty == false ? name! : bot.accid
  }

  private static func generateDefaultAccid() -> String {
    let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    return "Bot_" + String(uuid.prefix(28))
  }

  private static func fallbackTitle(for kind: AIRobotRouteKind) -> String {
    switch kind {
    case .list:
      return NEChatUIKitSwiftUIBundle.localized("my_ai_robot", value: "My AI Robots")
    case .create:
      return NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot")
    case .chatCard:
      return NEChatUIKitSwiftUIBundle.localized("ai_robot_card", value: "AI Robot Card")
    case .detail:
      return NEChatUIKitSwiftUIBundle.localized("ai_robot_detail_title", value: "AI Robot Detail")
    case .config:
      return NEChatUIKitSwiftUIBundle.localized("ai_robot_config_title", value: "Config String")
    case .bind:
      return NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_title", value: "Bind Robot")
    case .nicknameEdit:
      return NEChatUIKitSwiftUIBundle.localized("ai_robot_name", value: "Name")
    }
  }

  private static func title(for route: AIRobotRouteState) -> String {
    if route.kind == .create, route.bot != nil {
      return NEChatUIKitSwiftUIBundle.localized("edit_ai_robot", value: "Edit Robot")
    }
    return fallbackTitle(for: route.kind)
  }

  private func updateAvatarPlaceholderDisplayNameIfNeeded(name: String) {
    guard state.avatarURL == nil else {
      return
    }
    state.avatarDisplayName = name
  }
}
