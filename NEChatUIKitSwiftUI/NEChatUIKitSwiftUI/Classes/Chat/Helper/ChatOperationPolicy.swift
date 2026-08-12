// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum ChatOperationPolicy {
  public static func operations(for row: MessageRowState,
                                context: ChatSessionContext,
                                config: ChatSwiftUIConfig) -> [MessageOperation] {
    operationDescriptors(for: row, context: context, config: config).map(\.operation)
  }

  public static func operationDescriptors(for row: MessageRowState,
                                          context: ChatSessionContext,
                                          config: ChatSwiftUIConfig) -> [ChatOperationDescriptor] {
    guard canPresentOperations(for: row) else {
      return []
    }

    let operations: [MessageOperation]
    if let custom = config.messageOperationsProvider?(row, context) {
      operations = sanitize(custom, for: row, context: context, config: config, allowsUnsupportedCustomOperations: false)
    } else {
      operations = defaultOperations(for: row, context: context, config: config)
    }

    return operations.map { descriptor(for: $0, row: row, context: context) }
  }

  public static func defaultOperations(for row: MessageRowState,
                                       context: ChatSessionContext) -> [MessageOperation] {
    defaultOperations(for: row, context: context, config: ChatSwiftUIConfig())
  }

  public static func defaultOperations(for row: MessageRowState,
                                       context: ChatSessionContext,
                                       config: ChatSwiftUIConfig) -> [MessageOperation] {
    guard canPresentOperations(for: row) else {
      return []
    }

    switch row.deliveryState {
    case .pending:
      return sanitize(deliveryLimitedOperations(for: row),
                      for: row,
                      context: context,
                      config: config,
                      allowsUnsupportedCustomOperations: true)
    case .failed:
      return sanitize(deliveryLimitedOperations(for: row),
                      for: row,
                      context: context,
                      config: config,
                      allowsUnsupportedCustomOperations: true)
    default:
      break
    }

    let content = primaryContent(row.content)
    if case .call = content {
      return sanitize(deliveryLimitedOperations(for: row),
                      for: row,
                      context: context,
                      config: config,
                      allowsUnsupportedCustomOperations: true)
    }

    let base: [MessageOperation]
    switch content {
    case .tip, .revoke:
      base = []
    case .text:
      base = [.copy, .reply, .forward, .pin, .delete, .revoke, .multiSelect, .collect]
    case .richText:
      base = [.copy, .reply, .forward, .pin, .delete, .revoke, .multiSelect, .collect]
    case .aiStream(_, let isFinished, _):
      base = isFinished
        ? [.copy, .reply, .forward, .pin, .delete, .revoke, .multiSelect, .collect]
        : []
    case .call:
      base = [.delete, .multiSelect]
    case .unsupported:
      base = row.customPayload == nil
        ? [.reply, .pin, .delete, .revoke, .multiSelect]
        : [.delete, .multiSelect, .collect]
    case .audio:
      base = [.reply, .pin, .delete, .revoke, .multiSelect, .collect, .voiceToText]
    case .location, .image, .video, .file, .custom, .multiForward:
      base = [.reply, .forward, .pin, .delete, .revoke, .multiSelect, .collect]
    default:
      base = [.reply, .pin, .delete, .revoke, .multiSelect]
    }

    var operations = sanitize(base, for: row, context: context, config: config, allowsUnsupportedCustomOperations: true)
    appendAudioRouteOperationIfNeeded(to: &operations, row: row, context: context, config: config)
    if supportsTopOperation(content) {
      appendTopOperationIfNeeded(to: &operations, row: row, context: context, config: config)
    }
    return operations
  }

  public static func descriptor(for operation: MessageOperation,
                                row: MessageRowState? = nil,
                                context: ChatSessionContext? = nil) -> ChatOperationDescriptor {
    if operation == .pin, row?.isPinned == true {
      return ChatOperationDescriptor(
        operation: operation,
        title: NEChatUIKitSwiftUIBundle.localized("operation_cancel_pin", value: "Unpin"),
        imageName: "op_pin",
        role: .normal
      )
    }

    if operation == .top, row?.isTopMessage == true {
      return ChatOperationDescriptor(
        operation: .untop,
        title: NEChatUIKitSwiftUIBundle.localized("operation_untop", value: "Untop"),
        imageName: "op_untop",
        role: .normal
      )
    }

    return ChatOperationDescriptor(operation: operation)
  }

  public static func title(for operation: MessageOperation) -> String {
    ChatOperationDescriptor.defaultTitle(for: operation)
  }

  public static func imageName(for operation: MessageOperation) -> String {
    ChatOperationDescriptor.defaultImageName(for: operation)
  }

  public static func isDestructive(_ operation: MessageOperation) -> Bool {
    ChatOperationDescriptor.defaultRole(for: operation) == .destructive
  }

  private static func deliveryLimitedOperations(for row: MessageRowState,
                                                includeResend: Bool = false) -> [MessageOperation] {
    var operations = [MessageOperation]()
    if isDeliveryLimitedCopyable(row.content) {
      operations.append(.copy)
    }
    operations.append(.delete)
    operations.append(.multiSelect)
    if includeResend, canResend(row.content) {
      operations.append(.resend)
    }
    return operations
  }

  private static func sanitize(_ operations: [MessageOperation],
                               for row: MessageRowState,
                               context: ChatSessionContext,
                               config: ChatSwiftUIConfig,
                               allowsUnsupportedCustomOperations: Bool) -> [MessageOperation] {
    var sanitized = [MessageOperation]()
    var seen = Set<MessageOperation>()

    for operation in operations {
      guard !seen.contains(operation),
            !config.disabledMessageOperations.contains(operation),
            isOperationSupported(operation,
                                 for: row,
                                 context: context,
                                 config: config,
                                 allowsUnsupportedCustomOperations: allowsUnsupportedCustomOperations) else {
        continue
      }
      seen.insert(operation)
      sanitized.append(operation)
    }

    return sanitized
  }

  private static func isOperationSupported(_ operation: MessageOperation,
                                           for row: MessageRowState,
                                           context: ChatSessionContext,
                                           config: ChatSwiftUIConfig,
                                           allowsUnsupportedCustomOperations: Bool) -> Bool {
    if case .system = row.direction {
      return false
    }

    if context.kind == .botSubSession,
       [.pin, .revoke].contains(operation) {
      return false
    }

    switch operation {
    case .copy:
      return isCopyable(row.content)
    case .delete:
      return true
    case .revoke:
      return row.direction == .outgoing && isRevocable(row.content) && isSent(row.deliveryState)
    case .reply:
      return isReplyable(row.content) && isSent(row.deliveryState)
    case .forward:
      return isForwardable(row.content) && isSent(row.deliveryState)
    case .collect:
      return IMKitConfigCenter.shared.enableCollectionMessage && isCollectable(row) && isSent(row.deliveryState)
    case .pin:
      return IMKitConfigCenter.shared.enablePinMessage && isPinable(row) && isSent(row.deliveryState)
    case .top, .untop:
      return IMKitConfigCenter.shared.enableTopMessage &&
        context.kind == .team &&
        isTopable(row) &&
        isSent(row.deliveryState)
    case .readReceipt:
      return row.direction == .outgoing &&
        context.kind != .history &&
        row.isReadReceiptEnabled &&
        isReadReceiptOperationEnabled(context: context, config: config) &&
        isSent(row.deliveryState)
    case .selectText:
      return isTextSelectable(row.content) && isSent(row.deliveryState)
    case .multiSelect:
      return row.direction != .system && isMultiSelectable(row.content)
    case .voiceToText:
      guard row.voiceToText?.text?.isEmpty != false else {
        return false
      }
      return isVoiceToTextable(row.content) && isSent(row.deliveryState)
    case .earpiece, .speaker:
      return isVoiceToTextable(row.content) && isSent(row.deliveryState)
    case .resend:
      if case .failed = row.deliveryState {
        return canResend(row.content)
      }
      return allowsUnsupportedCustomOperations
    case .plugin:
      return allowsUnsupportedCustomOperations && isSent(row.deliveryState)
    }
  }

  private static func isSent(_ deliveryState: MessageDeliveryState) -> Bool {
    switch deliveryState {
    case .none, .sent, .read:
      return true
    case .pending, .failed:
      return false
    }
  }

  private static func isCopyable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .text, .richText, .aiStream:
      return !displayText(for: content).isEmpty
    default:
      return false
    }
  }

  private static func isDeliveryLimitedCopyable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .text, .aiStream:
      return !displayText(for: content).isEmpty
    default:
      return false
    }
  }

  private static func isTextSelectable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .text, .richText:
      return !displayText(for: content).isEmpty
    default:
      return false
    }
  }

  private static func isRevocable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .tip, .revoke:
      return false
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isReplyable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .tip, .revoke:
      return false
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isForwardable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .tip, .revoke, .unsupported:
      return false
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isCollectable(_ row: MessageRowState) -> Bool {
    switch primaryContent(row.content) {
    case .tip, .revoke, .call:
      return false
    case .unsupported:
      return row.customPayload != nil
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isPinable(_ row: MessageRowState) -> Bool {
    switch primaryContent(row.content) {
    case .tip, .revoke:
      return false
    case .unsupported:
      return row.customPayload == nil
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isTopable(_ row: MessageRowState) -> Bool {
    isPinable(row)
  }

  private static func isMultiSelectable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .tip, .revoke:
      return false
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func isTranslatable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case .text, .richText:
      return !displayText(for: content).isEmpty
    case .aiStream(_, let isFinished, _):
      return isFinished && !displayText(for: content).isEmpty
    default:
      return false
    }
  }

  private static func isVoiceToTextable(_ content: MessageContentState) -> Bool {
    switch primaryContent(content) {
    case let .audio(audio):
      return audio.convertedText?.isEmpty != false
    default:
      return false
    }
  }

  private static func canResend(_ content: MessageContentState) -> Bool {
    if case .text = content {
      return true
    }
    return false
  }

  private static func displayText(for content: MessageContentState) -> String {
    ChatMessageMapper.previewText(for: content)
  }

  private static func canPresentOperations(for row: MessageRowState) -> Bool {
    guard row.direction != .system else {
      return false
    }
    switch primaryContent(row.content) {
    case .tip, .revoke:
      return false
    case .aiStream(_, let isFinished, _):
      return isFinished
    default:
      return true
    }
  }

  private static func primaryContent(_ content: MessageContentState) -> MessageContentState {
    if case let .reply(_, boxed) = content {
      return primaryContent(boxed.value)
    }
    return content
  }

  private static func supportsTopOperation(_ content: MessageContentState) -> Bool {
    switch content {
    case .text, .richText, .image, .audio, .video, .file, .location, .custom, .multiForward:
      return true
    case .aiStream(_, let isFinished, _):
      return isFinished
    case .call, .unsupported, .reply, .revoke, .tip:
      return false
    }
  }

  private static func appendTopOperationIfNeeded(to operations: inout [MessageOperation],
                                                 row: MessageRowState,
                                                 context: ChatSessionContext,
                                                 config: ChatSwiftUIConfig) {
    let operation: MessageOperation = row.isTopMessage ? .untop : .top
    guard IMKitConfigCenter.shared.enableTopMessage,
          !config.disabledMessageOperations.contains(operation),
          isOperationSupported(operation,
                               for: row,
                               context: context,
                               config: config,
                               allowsUnsupportedCustomOperations: true) else {
      return
    }

    if let insertIndex = operations.firstIndex(where: { $0 == .voiceToText }) {
      operations.insert(operation, at: insertIndex)
    } else {
      operations.append(operation)
    }
  }

  private static func appendAudioRouteOperationIfNeeded(to operations: inout [MessageOperation],
                                                        row: MessageRowState,
                                                        context: ChatSessionContext,
                                                        config: ChatSwiftUIConfig) {
    let audioRouteOperation: MessageOperation = SettingRepo.shared.getHandsetMode() ? .earpiece : .speaker
    guard !config.disabledMessageOperations.contains(audioRouteOperation),
          isOperationSupported(audioRouteOperation,
                               for: row,
                               context: context,
                               config: config,
                               allowsUnsupportedCustomOperations: true) else {
      return
    }

    operations.insert(audioRouteOperation, at: 0)
  }

  private static func isReadReceiptOperationEnabled(context: ChatSessionContext,
                                                    config: ChatSwiftUIConfig) -> Bool {
    switch context.kind {
    case .p2p, .botSubSession:
      return config.isP2PReadReceiptEnabled
    case .team, .topic:
      return config.isTeamReadReceiptEnabled
    case .history:
      return false
    }
  }
}
