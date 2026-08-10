// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

public enum ReadReceiptSectionKind: String, Equatable, Identifiable {
  case read
  case unread

  public var id: String {
    rawValue
  }
}

public struct ReadReceiptSectionState: Identifiable, Equatable {
  public var id: ReadReceiptSectionKind
  public var title: String
  public var members: [ReadReceiptMemberState]

  public init(id: ReadReceiptSectionKind,
              title: String,
              members: [ReadReceiptMemberState]) {
    self.id = id
    self.title = title
    self.members = members
  }
}

@MainActor
public final class ReadReceiptViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var sections: [ReadReceiptSectionState] = []
  @Published public private(set) var summary = ""
  @Published public var toast: ChatToastState?

  private let messageId: String
  private let teamMemberAccountIds: Set<String>
  private let chatRepo: ChatRepo
  private let memberProvider: ChatReadReceiptMemberProviding
  private let networkOperationGuard: () -> Bool

  public init(messageId: String,
              teamMemberAccountIds: Set<String> = [],
              chatRepo: ChatRepo = .shared,
              memberProvider: ChatReadReceiptMemberProviding = ChatReadReceiptMemberProvider.chatKitDefault,
              networkOperationGuard: @escaping () -> Bool = { true }) {
    self.messageId = messageId
    self.teamMemberAccountIds = teamMemberAccountIds
    self.chatRepo = chatRepo
    self.memberProvider = memberProvider
    self.networkOperationGuard = networkOperationGuard
  }

  public func load() {
    guard phase != .loading else {
      return
    }
    guard networkOperationGuard() else {
      phase = .failed(NEChatKitErrorState(code: protocolSendFailed, message: NEChatErrorMessageMapper.networkMessage()))
      toast = Self.networkToast()
      return
    }
    phase = .loading

    chatRepo.getMessageListByIds([messageId]) { [weak self] messages, error in
      if let error {
        Task { @MainActor in
          self?.applyFailure(error)
        }
        return
      }

      guard let message = messages?.first else {
        Task { @MainActor in
          self?.phase = .empty
          self?.summary = NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found")
        }
        return
      }

      if message.conversationType == .CONVERSATION_TYPE_TEAM {
        self?.loadTeamReceipt(message)
      } else {
        self?.loadP2PReceipt(message)
      }
    }
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  private func loadP2PReceipt(_ message: V2NIMMessage) {
    chatRepo.getP2PMessageReceipt(conversationId: message.conversationId ?? "") { [weak self] receipt, error in
      Task { @MainActor in
        if let error {
          self?.applyFailure(error)
          return
        }

        let isRead = (receipt?.timestamp ?? 0) >= message.createTime
        self?.summary = isRead
          ? NEChatUIKitSwiftUIBundle.localized("chat_read", value: "Read")
          : NEChatUIKitSwiftUIBundle.localized("chat_unread", value: "Unread")
        self?.sections = []
        self?.phase = .loaded
      }
    }
  }

  private func loadTeamReceipt(_ message: V2NIMMessage) {
    chatRepo.getTeamMessageReceiptDetail(message: message, memberAccountIds: teamMemberAccountIds) { [weak self] detail, error in
      Task { @MainActor in
        if let error {
          self?.applyFailure(error)
          return
        }

        let read = detail?.readAccountList ?? []
        let unread = detail?.unreadAccountList ?? []
        self?.summary = String(
          format: NEChatUIKitSwiftUIBundle.localized("chat_read_receipt_summary_format", value: "%d read, %d unread"),
          read.count,
          unread.count
        )
        self?.loadTeamReceiptMembers(
          readAccountIds: read,
          unreadAccountIds: unread,
          teamId: V2NIMConversationIdUtil.conversationTargetId(message.conversationId ?? "")
        )
      }
    }
  }

  private func loadTeamReceiptMembers(readAccountIds: [String],
                                      unreadAccountIds: [String],
                                      teamId: String?) {
    let allAccountIds = readAccountIds + unreadAccountIds
    guard !allAccountIds.isEmpty else {
      sections = []
      finishTeamReceiptLoad()
      return
    }

    memberProvider.loadMembers(accountIds: allAccountIds, teamId: teamId) { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let members):
          self?.applyTeamReceiptMembers(
            members,
            readAccountIds: readAccountIds,
            unreadAccountIds: unreadAccountIds
          )
        case .failure(let error):
          self?.applyFailure(error)
        }
      }
    }
  }

  private func applyTeamReceiptMembers(_ members: [ReadReceiptMemberState],
                                       readAccountIds: [String],
                                       unreadAccountIds: [String]) {
    let memberMap = Dictionary(uniqueKeysWithValues: members.map { ($0.accountId, $0) })
    sections = [
      ReadReceiptSectionState(
        id: .read,
        title: NEChatUIKitSwiftUIBundle.localized("chat_read", value: "Read"),
        members: readAccountIds.map { memberMap[$0] ?? ReadReceiptMemberState(accountId: $0) }
      ),
      ReadReceiptSectionState(
        id: .unread,
        title: NEChatUIKitSwiftUIBundle.localized("chat_unread", value: "Unread"),
        members: unreadAccountIds.map { memberMap[$0] ?? ReadReceiptMemberState(accountId: $0) }
      ),
    ].filter { !$0.members.isEmpty }
    finishTeamReceiptLoad()
  }

  private func finishTeamReceiptLoad() {
    phase = sections.isEmpty ? .empty : .loaded
  }

  private func applyFailure(_ error: Error) {
    phase = .failed(
      NEChatErrorMessageMapper.errorState(
        for: error,
        fallbackKey: "chat_read_receipt_load_failed",
        fallbackValue: "Failed to load read receipt"
      )
    )
    toast = NEChatErrorMessageMapper.toast(
      for: error,
      fallbackKey: "chat_read_receipt_load_failed",
      fallbackValue: "Failed to load read receipt"
    )
  }

  private static func networkToast() -> ChatToastState {
    ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
      style: .warning
    )
  }
}
