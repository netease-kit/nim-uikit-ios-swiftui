// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum P2PSettingPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}

public enum P2PSettingToggleKind: Equatable {
  case messageRemind
  case conversationPinned
  case aiUserPinned
}

public enum P2PSettingRowKind: String, Equatable {
  case pinnedMessages
  case historySearch
  case messageRemind
  case conversationPinned
  case aiUserPinned
}

public struct P2PSettingRowState: Identifiable, Equatable {
  public var id: String { kind.rawValue }
  public var kind: P2PSettingRowKind
  public var title: String
  public var subtitle: String?
  public var isToggle: Bool
  public var isOn: Bool
  public var isEnabled: Bool

  public init(kind: P2PSettingRowKind,
              title: String,
              subtitle: String? = nil,
              isToggle: Bool = false,
              isOn: Bool = false,
              isEnabled: Bool = true) {
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.isToggle = isToggle
    self.isOn = isOn
    self.isEnabled = isEnabled
  }
}

public struct P2PSettingState: Equatable {
  public var phase: P2PSettingPhase
  public var snapshot: NEChatSwiftUIP2PSettingSnapshot?
  public var rows: [P2PSettingRowState]
  public var toast: ChatToastState?
  public var route: NEChatSwiftUIRoute?
  public var isCreatingDiscuss: Bool
  public var isSubmittingToggle: Bool

  public init(phase: P2PSettingPhase = .idle,
              snapshot: NEChatSwiftUIP2PSettingSnapshot? = nil,
              rows: [P2PSettingRowState] = [],
              toast: ChatToastState? = nil,
              route: NEChatSwiftUIRoute? = nil,
              isCreatingDiscuss: Bool = false,
              isSubmittingToggle: Bool = false) {
    self.phase = phase
    self.snapshot = snapshot
    self.rows = rows
    self.toast = toast
    self.route = route
    self.isCreatingDiscuss = isCreatingDiscuss
    self.isSubmittingToggle = isSubmittingToggle
  }
}

@MainActor
public final class P2PSettingViewModel: ObservableObject {
  @Published public private(set) var state: P2PSettingState

  public let context: ChatSessionContext
  public let config: ChatSwiftUIConfig

  private let repo: ChatRepo
  private let networkOperationGuard: () -> Bool
  private let onOpenTeamChat: (ChatSessionContext) -> Void
  private var listenerBag: NEChatKitListenerBag?
  private var loadGeneration = 0
  private var refreshGeneration = 0
  private var toggleGeneration = 0
  private var discussGeneration = 0

  public init(context: ChatSessionContext,
              config: ChatSwiftUIConfig,
              repo: ChatRepo = .shared,
              networkOperationGuard: @escaping () -> Bool = { true },
              onOpenTeamChat: @escaping (ChatSessionContext) -> Void = { context in
                NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(context))
              }) {
    self.context = context
    self.config = config
    self.repo = repo
    self.networkOperationGuard = networkOperationGuard
    self.onOpenTeamChat = onOpenTeamChat
    state = P2PSettingState()
  }

  public var accountId: String {
    context.sessionId ?? context.conversationId.components(separatedBy: "|").last ?? context.conversationId
  }

  public func onAppear() {
    bindListenersIfNeeded()
    if case .idle = state.phase {
      load()
    }
  }

  public func onDisappear() {
    listenerBag?.cancelAll()
    listenerBag = nil
    loadGeneration += 1
    refreshGeneration += 1
    toggleGeneration += 1
    discussGeneration += 1
  }

  public func load() {
    let generation = nextLoadGeneration()
    state.phase = state.snapshot == nil ? .loading : state.phase
    repo.loadSwiftUIP2PSettingSnapshot(
      accountId: accountId,
      fromBotSubSession: context.kind == .botSubSession
    ) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.loadGeneration == generation else {
          return
        }
        if let snapshot {
          self.apply(snapshot)
          self.state.phase = .loaded
        } else {
          self.state.phase = .failed(self.message(for: error))
        }
      }
    }
  }

  public func select(_ row: P2PSettingRowState) {
    guard row.isEnabled else {
      showUnavailableToast()
      return
    }

    switch row.kind {
    case .pinnedMessages:
      state.route = .pinMessages(conversationId: context.conversationId)
    case .historySearch:
      state.route = .historySearch(conversationId: context.conversationId)
    default:
      break
    }
  }

  public func setToggle(_ kind: P2PSettingToggleKind, isOn: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }
    guard networkOperationGuard() else {
      showNetworkErrorToast()
      return
    }
    let previous = snapshot
    applyToggle(kind, isOn: isOn, to: &snapshot)
    state.snapshot = snapshot
    state.rows = Self.makeRows(snapshot: snapshot)
    state.isSubmittingToggle = true
    let generation = nextToggleGeneration()

    let finish: (NSError?) -> Void = { [weak self] error in
      Task { @MainActor in
        guard let self, self.toggleGeneration == generation else {
          return
        }
        self.state.isSubmittingToggle = false
        if let error {
          self.state.snapshot = previous
          self.state.rows = Self.makeRows(snapshot: previous)
          self.state.toast = self.toast(for: error)
        }
      }
    }

    switch kind {
    case .messageRemind:
      repo.setSwiftUIP2PMessageRemind(accountId: snapshot.accountId, isEnabled: isOn, completion: finish)
    case .conversationPinned:
      repo.setSwiftUIP2PConversationPinned(accountId: snapshot.accountId, isPinned: isOn, completion: finish)
    case .aiUserPinned:
      repo.setSwiftUIAIUserPinned(accountId: snapshot.accountId, isPinned: isOn, completion: finish)
    }
  }

  public func createDiscuss() {
    guard let snapshot = state.snapshot else {
      return
    }
    guard snapshot.canCreateDiscuss else {
      showUnavailableToast()
      return
    }
    guard networkOperationGuard() else {
      showNetworkErrorToast()
      return
    }
    guard let selectionHandler = config.p2pDiscussSelectionHandler else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_discuss_selection_requires_boundary", value: "Discuss member selection requires a SwiftUI host selector."),
        style: .warning
      )
      return
    }

    state.isCreatingDiscuss = true
    let generation = nextDiscussGeneration()
    let request = ChatP2PDiscussSelectionRequest(
      peerAccountId: snapshot.accountId,
      peerDisplayName: snapshot.displayName,
      filterAccountIds: snapshot.discussSelectionFilters,
      limit: snapshot.discussMemberLimit,
      allowsAIUser: IMKitConfigCenter.shared.enableAIUser
    )
    selectionHandler.selectDiscussMembers(request: request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.discussGeneration == generation else {
          return
        }
        switch result {
        case let .success(selection):
          guard !selection.selectedAccountIds.isEmpty else {
            self.state.isCreatingDiscuss = false
            return
          }
          self.submitDiscussSelection(selection, generation: generation)
        case let .failure(error):
          self.state.isCreatingDiscuss = false
          self.state.toast = self.toast(for: error)
        }
      }
    }
  }

  public func clearRoute() {
    state.route = nil
  }

  public func consumeToast(_ toast: ChatToastState) {
    if state.toast?.id == toast.id {
      state.toast = nil
    }
  }

  private func submitDiscussSelection(_ selection: ChatP2PDiscussSelectionResult, generation: Int) {
    guard networkOperationGuard() else {
      state.isCreatingDiscuss = false
      showNetworkErrorToast()
      return
    }
    repo.createSwiftUIDiscuss(
      fromP2P: accountId,
      selectedAccountIds: selection.selectedAccountIds,
      selectedNames: selection.selectedNames
    ) { [weak self] result, error in
      Task { @MainActor in
        guard let self, self.discussGeneration == generation else {
          return
        }
        self.state.isCreatingDiscuss = false
        if let error {
          self.state.toast = self.toast(for: error)
        } else if let result, let conversationId = result.conversationId {
          self.state.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("chat_discuss_create_success", value: "Discussion created"),
            style: .success
          )
          let context = ChatSessionContext(
            kind: .team,
            conversationId: conversationId,
            title: result.name,
            sessionId: result.teamId,
            sessionName: result.name
          )
          self.onOpenTeamChat(context)
        }
      }
    }
  }

  private func bindListenersIfNeeded() {
    guard listenerBag == nil else {
      return
    }
    listenerBag = repo.addSwiftUIP2PSettingListener(accountId: accountId) { [weak self] in
      Task { @MainActor in
        self?.refreshSettingSilently()
      }
    }
  }

  private func refreshSettingSilently() {
    guard state.phase == .loaded, !state.isSubmittingToggle, !state.isCreatingDiscuss else {
      return
    }
    let generation = nextRefreshGeneration()
    repo.loadSwiftUIP2PSettingSnapshot(
      accountId: accountId,
      fromBotSubSession: context.kind == .botSubSession
    ) { [weak self] snapshot, _ in
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation, let snapshot else {
          return
        }
        self.apply(snapshot)
      }
    }
  }

  private func apply(_ snapshot: NEChatSwiftUIP2PSettingSnapshot) {
    state.snapshot = snapshot
    state.rows = Self.makeRows(snapshot: snapshot)
  }

  private func applyToggle(_ kind: P2PSettingToggleKind,
                           isOn: Bool,
                           to snapshot: inout NEChatSwiftUIP2PSettingSnapshot) {
    switch kind {
    case .messageRemind:
      snapshot.isMessageRemindEnabled = isOn
    case .conversationPinned:
      snapshot.isConversationPinned = isOn
    case .aiUserPinned:
      snapshot.isAIUserPinned = isOn
    }
  }

  private func showUnavailableToast() {
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
      style: .warning
    )
  }

  private func showNetworkErrorToast() {
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
      style: .warning
    )
  }

  private func nextLoadGeneration() -> Int {
    loadGeneration += 1
    return loadGeneration
  }

  private func nextRefreshGeneration() -> Int {
    refreshGeneration += 1
    return refreshGeneration
  }

  private func nextToggleGeneration() -> Int {
    toggleGeneration += 1
    return toggleGeneration
  }

  private func nextDiscussGeneration() -> Int {
    discussGeneration += 1
    return discussGeneration
  }

  private func toast(for error: Error) -> ChatToastState {
    ChatToastState(message: message(for: error), style: .warning)
  }

  private func message(for error: Error?) -> String {
    guard let error else {
      return NEChatUIKitSwiftUIBundle.localized("chat_setting_load_failed", value: "Failed to load settings")
    }
    let nsError = error as NSError
    switch nsError.code {
    case protocolSendFailed, protocolTimeout:
      return NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
    case noPermissionCode, noPermissionOperationCode:
      return NEChatUIKitSwiftUIBundle.localized("no_permission_tip", value: "No Permission")
    case failedOperation:
      return NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
    default:
      return NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
    }
  }

  private static func makeRows(snapshot: NEChatSwiftUIP2PSettingSnapshot) -> [P2PSettingRowState] {
    var rows = [P2PSettingRowState]()
    if snapshot.canShowPinnedMessages {
      rows.append(P2PSettingRowState(
        kind: .pinnedMessages,
        title: NEChatUIKitSwiftUIBundle.localized("operation_pin", value: "Pin")
      ))
    }
    if snapshot.canShowHistorySearch {
      rows.append(P2PSettingRowState(
        kind: .historySearch,
        title: NEChatUIKitSwiftUIBundle.localized("historical_record", value: "Search chat history")
      ))
    }
    rows.append(P2PSettingRowState(
      kind: .messageRemind,
      title: NEChatUIKitSwiftUIBundle.localized("message_remind", value: "Notification"),
      isToggle: true,
      isOn: snapshot.isMessageRemindEnabled
    ))
    rows.append(P2PSettingRowState(
      kind: .conversationPinned,
      title: NEChatUIKitSwiftUIBundle.localized("session_set_top", value: "Sticky on Top"),
      isToggle: true,
      isOn: snapshot.isConversationPinned
    ))
    if snapshot.canToggleAIUserPin {
      rows.append(P2PSettingRowState(
        kind: .aiUserPinned,
        title: NEChatUIKitSwiftUIBundle.localized("ai_user_pin_top", value: "PIN"),
        isToggle: true,
        isOn: snapshot.isAIUserPinned
      ))
    }
    return rows
  }
}
