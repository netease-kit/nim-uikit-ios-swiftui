// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVFoundation
import Foundation
import ImageIO
import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI
import class UIKit.UIImage

public struct MessageBubbleView: View {
    @State private var suppressNextBodyTap = false
    @State private var bodyLongPressTapSuppressionGeneration = 0

    public var row: MessageRowState
    public var token: ChatThemeToken
    public var showsAvatar: Bool
    public var showsSenderName: Bool
    public var customContent: AnyView?
    public var customLayout: ChatCustomMessageLayout?
    public var onAvatarTap: (MessageRowState) -> Void
    public var onAvatarLongPress: (MessageRowState) -> Void
    public var onAIStreamAction: (AIStreamAction, MessageRowState) -> Void
    public var onReedit: (MessageRowState) -> Void
    public var onReplyTap: (MessageRowState) -> Void
    public var onOpenURL: (URL, String, ChatURLInteractionSource, MessageRowState) -> Void
    public var onReadReceiptTap: ((MessageRowState) -> Void)?
    public var onResendTap: (MessageRowState) -> Void
    public var onBodyTap: (MessageRowState) -> Void
    public var onBodyLongPress: (MessageRowState) -> Void
    public var isMultiSelecting: Bool
    public var isTextSelectionActive: Bool
    public var onTextSelectionChange: (MessageRowState, String?, Bool) -> Void
    public var keywordHighlightColor: Color?
    public var showsAIResponseActions: Bool
    public var showsRemoteVideoDownloadAction: Bool

    public init(row: MessageRowState,
                token: ChatThemeToken,
                showsAvatar: Bool = true,
                showsSenderName: Bool = true,
                customContent: AnyView? = nil,
                customLayout: ChatCustomMessageLayout? = nil,
                onAvatarTap: @escaping (MessageRowState) -> Void = { _ in },
                onAvatarLongPress: @escaping (MessageRowState) -> Void = { _ in },
                onAIStreamAction: @escaping (AIStreamAction, MessageRowState) -> Void = { _, _ in },
                onReedit: @escaping (MessageRowState) -> Void = { _ in },
	                onReplyTap: @escaping (MessageRowState) -> Void = { _ in },
	                onOpenURL: @escaping (URL, String, ChatURLInteractionSource, MessageRowState) -> Void = { _, _, _, _ in },
	                onReadReceiptTap: ((MessageRowState) -> Void)? = nil,
	                onResendTap: @escaping (MessageRowState) -> Void = { _ in },
	                onBodyTap: @escaping (MessageRowState) -> Void = { _ in },
	                onBodyLongPress: @escaping (MessageRowState) -> Void = { _ in },
	                isMultiSelecting: Bool = false,
	                isTextSelectionActive: Bool = false,
	                onTextSelectionChange: @escaping (MessageRowState, String?, Bool) -> Void = { _, _, _ in },
	                keywordHighlightColor: Color? = nil,
                    showsAIResponseActions: Bool = true,
                    showsRemoteVideoDownloadAction: Bool = false)
    {
        self.row = row
        self.token = token
        self.showsAvatar = showsAvatar
        self.showsSenderName = showsSenderName
        self.customContent = customContent
        self.customLayout = customLayout
        self.onAvatarTap = onAvatarTap
        self.onAvatarLongPress = onAvatarLongPress
        self.onAIStreamAction = onAIStreamAction
        self.onReedit = onReedit
        self.onReplyTap = onReplyTap
        self.onOpenURL = onOpenURL
        self.onReadReceiptTap = onReadReceiptTap
        self.onResendTap = onResendTap
        self.onBodyTap = onBodyTap
        self.onBodyLongPress = onBodyLongPress
        self.isMultiSelecting = isMultiSelecting
        self.isTextSelectionActive = isTextSelectionActive
        self.onTextSelectionChange = onTextSelectionChange
        self.keywordHighlightColor = keywordHighlightColor
        self.showsAIResponseActions = showsAIResponseActions
        self.showsRemoteVideoDownloadAction = showsRemoteVideoDownloadAction
    }

    public var body: some View {
        Group {
            if isFunRevokeMessage {
                funRevokeContent
            } else {
                regularMessageContent
            }
        }
        .padding(.horizontal, token.messageRowHorizontalPadding)
        .padding(.vertical, token.messageRowVerticalPadding)
        .background(row.isPinned ? token.signalBackgroundColor : Color.clear)
    }

    private var regularMessageContent: some View {
        Group {
            if row.direction == .system {
                content
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if row.direction == .outgoing {
                        Spacer(minLength: isMultiSelecting ? 0 : 40)
                    } else {
                        avatarSlot
                    }

                    content
                        .frame(maxWidth: contentMaxWidth, alignment: row.direction == .outgoing ? .trailing : .leading)
                        .frame(minHeight: customLayout?.rowHeight)

                    if row.direction == .outgoing {
                        avatarSlot
                    } else {
                        Spacer(minLength: isMultiSelecting ? 0 : 40)
                    }
                }
            }
        }
    }

    private var funRevokeContent: some View {
        HStack(spacing: 8) {
            if case .revoke = row.content {
                Text(funRevokeText)
                    .font(.system(size: 14))
                    .foregroundColor(token.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                if showsReeditAction {
                    Button {
                        onReedit(row)
                    } label: {
                        Text(NEChatUIKitSwiftUIBundle.localized("message_reedit", value: "Edit"))
                            .font(.system(size: 14))
                            .foregroundColor(token.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .center)
    }

    @ViewBuilder
    private var avatarSlot: some View {
        Group {
            if showsAvatar {
                avatar
            } else {
                Color.clear
            }
        }
        .frame(width: token.avatarSize, height: token.avatarSize)
        .layoutPriority(2)
    }

    private var avatar: some View {
        NEChatCommonPresentation.avatarView(
            imageURL: row.avatarURL,
            initials: avatarInitials,
            token: token,
            size: token.avatarSize,
            cornerRadius: token.avatarCornerRadius,
            hashID: row.senderId
        )
        .contentShape(RoundedRectangle(cornerRadius: token.avatarCornerRadius, style: .continuous))
        .onTapGesture {
            onAvatarTap(row)
        }
        .onLongPressGesture {
            onAvatarLongPress(row)
        }
        .accessibilityLabel(avatarAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        VStack(alignment: row.direction == .outgoing ? .trailing : .leading, spacing: 0) {
            if showsSenderName, let senderName = row.senderName, row.direction == .incoming {
                Text(senderName)
                    .font(.system(size: token.senderNameFontSize))
                    .foregroundColor(token.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: contentMaxWidth, minHeight: 20, maxHeight: 20, alignment: .leading)
            }

            messageBodyStack
        }
    }

    private var messageBodyStack: some View {
        VStack(alignment: row.direction == .outgoing ? .trailing : .leading, spacing: 4) {
            messageBodyRow
            pinnedIndicator
        }
    }

    private var messageBodyRow: some View {
        HStack(alignment: .bottom, spacing: 7) {
            if row.direction == .outgoing {
                deliveryStatusView
                    .frame(width: deliveryStatusSlotWidth, alignment: .trailing)
                    .padding(.bottom, row.direction == .system ? 0 : 1)
            }

            HStack(alignment: .top, spacing: 7) {
                bubbleContent
                aiStreamActions
                aiRegenButton
            }
        }
    }

    @inline(never)
    private var bubbleContent: AnyView {
        if token.styleMode == .fun, let reply = row.reply {
            let primaryContent = primaryBubbleContent
            let replyContent = replyPreview(reply)
            return AnyView(VStack(alignment: row.direction == .outgoing ? .trailing : .leading, spacing: 0) {
                primaryContent
                replyContent
                    .padding(.top, 8)
                    .padding(.leading, row.direction == .incoming ? token.funMargin : 0)
                    .padding(.trailing, row.direction == .outgoing ? token.funMargin : 0)
            })
        }
        return primaryBubbleContent
    }

    @inline(never)
    private var primaryBubbleContent: AnyView {
        let replyContent = primaryReplyContent()
        let messageContent = primaryMessageContent()
        let voiceContent = voiceToTextContent()
        let trailingReeditContent = primaryTrailingReeditContent()
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            replyContent
            messageContent
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBodyTap()
                }
            voiceContent
            trailingReeditContent
        }
        .padding(.leading, bubbleLeadingPadding)
        .padding(.trailing, bubbleTrailingPadding)
        .padding(.vertical, bubbleVerticalPadding)
        .frame(width: bubbleContentWidth,
               height: customLayout?.contentSize?.height,
               alignment: .leading)
        .frame(minWidth: minBubbleContentWidth, alignment: .leading)
        .frame(minHeight: customLayout?.minContentHeight, alignment: .leading)
        .frame(minHeight: minBubbleContentHeight, alignment: .leading)
        .background(bubbleBackground)
        .clipShape(bubbleClipShape)
        .overlay(selectionOverlay)
        .contentShape(bubbleContentShape)
        .onLongPressGesture(minimumDuration: 0.35) {
            handleBodyLongPress()
        })
    }

    @inline(never)
    private func primaryReplyContent() -> AnyView {
        guard token.styleMode == .normal, let reply = row.reply else {
            return AnyView(EmptyView())
        }
        return replyPreview(reply)
    }

    @inline(never)
    private func primaryMessageContent() -> AnyView {
        if let customContent {
            return customContent
        }
        if isNormalRevokeMessage, showsReeditAction {
            let reeditContent = reeditActionContent()
            return AnyView(HStack(spacing: 8) {
                contentText
                    .font(messageFont)
                    .foregroundColor(token.outgoingTextColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                reeditContent
            })
        }
        return AnyView(contentText
            .font(row.direction == .system ? .system(size: 14) : messageFont)
            .foregroundColor(row.direction == .system ? token.secondaryTextColor : (row.direction == .outgoing ? token.outgoingTextColor : token.incomingTextColor)))
    }

    @inline(never)
    private func primaryTrailingReeditContent() -> AnyView {
        guard !isNormalRevokeMessage else {
            return AnyView(EmptyView())
        }
        return reeditActionContent()
    }

    @inline(never)
    private func replyPreview(_ reply: MessageReplyState) -> AnyView {
        AnyView(Button {
            onReplyTap(row)
        } label: {
            ReplyPreviewView(reply: reply, token: token)
        }
        .buttonStyle(.plain))
    }

    private func handleBodyTap() {
        guard !isTextSelectionActive else {
            return
        }
        guard !suppressNextBodyTap else {
            bodyLongPressTapSuppressionGeneration += 1
            suppressNextBodyTap = false
            return
        }
        onBodyTap(row)
    }

    private func handleBodyLongPress() {
        bodyLongPressTapSuppressionGeneration += 1
        let generation = bodyLongPressTapSuppressionGeneration
        suppressNextBodyTap = true
        onBodyLongPress(row)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard bodyLongPressTapSuppressionGeneration == generation else {
                return
            }
            suppressNextBodyTap = false
        }
    }

    private var bubbleClipShape: some Shape {
        RoundedRectangle(cornerRadius: shouldClipBubbleBackground ? token.bubbleCornerRadius : 0, style: .continuous)
    }

    private var bubbleContentShape: some Shape {
        RoundedRectangle(cornerRadius: shouldClipBubbleBackground ? token.bubbleCornerRadius : 0, style: .continuous)
    }

    private var shouldClipBubbleBackground: Bool {
        guard row.direction != .system else {

            return false
        }
        return !usesBubbleImageBackground
    }

    private var bubbleLeadingPadding: CGFloat {
        guard row.direction != .system, usesBubbleChromePadding, !usesFullBleedBubbleContent else {
            return 0
        }
        return token.bubbleHorizontalPadding + (row.direction == .incoming ? token.funMargin : 0)
    }

    private var bubbleTrailingPadding: CGFloat {
        guard row.direction != .system, usesBubbleChromePadding, !usesFullBleedBubbleContent else {
            return 0
        }
        return token.bubbleHorizontalPadding + (row.direction == .outgoing ? token.funMargin : 0)
    }

    private var bubbleVerticalPadding: CGFloat {
        guard row.direction != .system, usesBubbleChromePadding, !usesFullBleedBubbleContent else {
            return 0
        }
        if isNormalRevokeMessage {
            return 0
        }
        return token.bubbleVerticalPadding
    }

    private var usesBubbleChromePadding: Bool {
        if case .audio = row.content {
            return false
        }
        guard hasOnlyPrimaryContent else {
            return true
        }

        switch row.content {
        case .audio, .file, .image, .video:
            return false
        default:
            return true
        }
    }

    private var usesFullBleedBubbleContent: Bool {
        guard hasOnlyPrimaryContent else {
            return false
        }

        switch row.content {
        case .multiForward, .location:
            return true
        default:
            return false
        }
    }

    private var hasOnlyPrimaryContent: Bool {
        row.reply == nil &&
            row.aiStreamActionPhase == .idle &&
            customContent == nil &&
            customLayout == nil
    }

    private var isRevokeMessage: Bool {
        if case .revoke = row.content {
            return true
        }
        return false
    }

    private var isNormalRevokeMessage: Bool {
        token.styleMode == .normal && isRevokeMessage
    }

    private var isFunRevokeMessage: Bool {
        token.styleMode == .fun && isRevokeMessage
    }

    private var showsReeditAction: Bool {
        guard row.direction == .outgoing,
              case .revoke = row.content,
              let reedit = row.reedit,
              !reedit.text.isEmpty,
              !reedit.isExpired else {
            return false
        }
        return true
    }

    private var isStandaloneTextMessage: Bool {
        guard hasOnlyPrimaryContent else {
            return false
        }
        if case .text = row.content {
            return true
        }
        if case .unsupported = row.content {
            return true
        }
        return false
    }

    private var isStandaloneFileMessage: Bool {
        guard hasOnlyPrimaryContent else {
            return false
        }
        if case .file = row.content {
            return true
        }
        return false
    }

    @inline(never)
    private func reeditActionContent() -> AnyView {
        guard showsReeditAction, !isFunRevokeMessage else {
            return AnyView(EmptyView())
        }
        return AnyView(Button {
            onReedit(row)
        } label: {
            HStack(spacing: 5) {
                Text(NEChatUIKitSwiftUIBundle.localized("message_reedit", value: "Edit"))
                    .font(.system(size: 16))
                    .foregroundColor(token.accentColor)
                    .lineLimit(1)
                NEChatCommonPresentation.iconView(
                    imageName: "right_arrow",
                    token: token,
                    size: CGSize(width: 16, height: 16),
                    foregroundColor: token.accentColor,
                    accessibilityLabel: nil
                )
            }
            .frame(height: token.minBubbleHeight)
        }
        .buttonStyle(.plain)
        .foregroundColor(token.accentColor))
    }

    @ViewBuilder
    private var pinnedIndicator: some View {
        if row.isPinned {
            HStack(spacing: 2) {
                NEChatCommonPresentation.iconView(
                    imageName: "msg_pin",
                    token: token,
                    size: CGSize(width: 10, height: 10),
                    foregroundColor: token.pinIndicatorColor,
                    accessibilityLabel: pinText
                )
                Text(pinText)
                    .font(.system(size: 12))
                    .foregroundColor(token.pinIndicatorColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: pinTextMaxWidth,
                           alignment: row.direction == .outgoing ? .trailing : .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: 16)
            .padding(.leading, row.direction == .incoming ? 2 : 0)
            .accessibilityIdentifier("id.signal")
        }
    }

    private var pinText: String {
        let currentAccount = IMKitClient.instance.account()
        let operatorName: String
        if row.pinOperatorId == nil || row.pinOperatorId == currentAccount {
            operatorName = NEChatUIKitSwiftUIBundle.localized("You", value: "you")
        } else {
            operatorName = row.pinOperatorName ??
                NEChatUIKitSwiftUIBundle.localized("You", value: "you")
        }
        return String(format: NEChatUIKitSwiftUIBundle.localized("pin_text", value: "Pinned by %@"), operatorName)
    }

    private var pinTextMaxWidth: CGFloat {
        row.direction == .outgoing ? 210 : 280
    }

    /// Aligned with UIKit NEUserHeaderView.setTitle: last 2 chars, original case.
    /// Falls back to senderId if senderName is nil or empty.
    private var avatarInitials: String {
        ChatAvatarDisplayResolver.initials(
            displayName: row.avatarName,
            accountId: row.senderId
        )
    }

    private var avatarAccessibilityLabel: String {
        row.senderName ??
            row.senderId ??
            NEChatUIKitSwiftUIBundle.localized("chat_avatar", value: "Avatar")
    }

    private var messageFont: Font {
        .system(size: row.direction == .outgoing ? token.outgoingMessageFontSize : token.incomingMessageFontSize)
    }

    private var contentMaxWidth: CGFloat {
        switch row.content {
        case .revoke:
            return isNormalRevokeMessage ? normalRevokeBubbleWidth : token.messageContentMaxWidth
        case .multiForward:
            return multiForwardCardWidth
        case .location:
            return max(token.messageContentMaxWidth, NEChatUIKitSwiftUIConstants.locationCardSize.width)
        case .file:
            return max(token.messageContentMaxWidth, token.fileBubbleWidth)
        default:
            return token.messageContentMaxWidth
        }
    }

    private var multiForwardCardWidth: CGFloat {
        token.styleMode == .fun ? 256 : NEChatUIKitSwiftUIConstants.multiForwardCardSize.width
    }

    private var bubbleContentWidth: CGFloat? {
        if case let .audio(audio) = row.content {
            return audioBubbleWidth(audio)
        }
        return customLayout?.contentSize?.width ?? (isNormalRevokeMessage ? normalRevokeBubbleWidth : nil)
    }

    private var normalRevokeBubbleWidth: CGFloat {
        let isEnglish = NEChatUIKitSwiftUIBundle.localized("message_recalled", value: "Message recalled") == "Message recalled"
        if showsReeditAction {
            return isEnglish ? 248 : 218
        }
        return isEnglish ? 160 : 130
    }

    @inline(never)
    private func voiceToTextContent() -> AnyView {
        guard let voiceToText = row.voiceToText,
              voiceToText.phase == .converted,
              let text = voiceToText.text,
              !text.isEmpty else {
            return AnyView(EmptyView())
        }
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(token.secondaryTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: voiceToTextInnerWidth, alignment: .leading)
        .padding(.horizontal, voiceToTextHorizontalInset)
        .frame(width: voiceToTextContentWidth, alignment: .leading)
        .clipped())
    }

    private var voiceToTextContentWidth: CGFloat? {
        guard case let .audio(audio) = row.content else {
            return nil
        }
        return audioBubbleWidth(audio)
    }

    private var voiceToTextHorizontalInset: CGFloat {
        16
    }

    private var voiceToTextInnerWidth: CGFloat? {
        guard let contentWidth = voiceToTextContentWidth else {
            return nil
        }
        return max(1, contentWidth - voiceToTextHorizontalInset * 2)
    }

    @ViewBuilder
    private var aiStreamActions: some View {
        if showsAIResponseActions,
           !isMultiSelecting,
           row.isAIStreamTriggeredByCurrentUser,
           case let .aiStream(_, isFinished, _) = row.content,
           !isFinished {
            Button {
                onAIStreamAction(.stop, row)
            } label: {
                NEChatCommonPresentation.iconView(
                    imageName: token.styleMode == .fun ? "fun_ai_stream_stop" : "ai_stream_stop",
                    token: token,
                    renderingMode: .original,
                    size: CGSize(width: 24, height: 24),
                    accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_ai_stream_stop", value: "Stop")
                )
            }
            .buttonStyle(.plain)
            .disabled(row.aiStreamActionPhase == .stopping)
        }
    }

    private var showRegenButton: Bool {
        row.isAIResponse && !row.isUnfinishedAIStream
    }

    @ViewBuilder
    private var aiRegenButton: some View {
        if showsAIResponseActions,
           !isMultiSelecting,
           row.isAIResponse,
           showRegenButton,
           row.direction == .incoming,
           row.isAIStreamTriggeredByCurrentUser {
            ZStack {
                Button {
                    onAIStreamAction(.regenerate, row)
                } label: {
                    NEChatCommonPresentation.iconView(
                        imageName: token.styleMode == .fun ? "fun_ai_stream_regen" : "ai_stream_regen",
                        token: token,
                        renderingMode: .original,
                        size: CGSize(width: 24, height: 24),
                        foregroundColor: token.accentColor,
                        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_ai_stream_regenerate", value: "Regenerate")
                    )
                }
                .buttonStyle(.plain)
                .disabled(row.aiStreamActionPhase == .regenerating)
                .opacity(row.aiStreamActionPhase == .regenerating ? 0 : 1)

                if case .regenerating = row.aiStreamActionPhase {
                    NEChatCommonPresentation.inlineLoadingView(token: token)
                }
            }
            .frame(width: 24, height: 24)
        }
    }

    private var contentText: AnyView {
        switch row.content {
        case let .text(text):
            return textMessageContent(text)
        case let .richText(title, body):
            return richTextMessageContent(title: title, body: body)
        case let .image(media):
            return imageMessageContent(media)
        case let .audio(audio):
            return audioMessageContent(audio)
        case let .video(media):
            return videoMessageContent(media)
        case let .file(file):
            return fileMessageContent(file)
        case let .location(location):
            return locationMessageContent(location)
        case let .call(call):
            return callMessageContent(call)
        case let .custom(title, body):
            return customMessageContent(title: title, body: body)
        case let .multiForward(multiForward):
            return multiForwardMessageContent(multiForward)
        case let .reply(preview, content):
            return replyMessageContent(preview: preview, content: content)
        case let .revoke(text):
            return revokeMessageContent(text)
        case let .tip(text):
            return tipMessageContent(text)
        case let .aiStream(text, isFinished, error):
            return aiStreamMessageContent(text: text, isFinished: isFinished, error: error)
        case let .unsupported(text):
            return unsupportedMessageContent(text)
        }
    }

    // Isolate generic SwiftUI construction from the dispatch switch. Otherwise
    // unoptimized device builds reserve every branch's temporaries in one frame.
    @inline(never)
    private func audioMessageContent(_ audio: MessageAudioState) -> AnyView {
        AnyView(audioBubble(audio))
    }

    @inline(never)
    private func locationMessageContent(_ location: MessageLocationState) -> AnyView {
        AnyView(LocationCardView(location: location, token: token))
    }

    @inline(never)
    private func callMessageContent(_ call: MessageCallState) -> AnyView {
        AnyView(CallMessageCardView(
            summary: call.summary,
            type: call.type,
            direction: row.direction,
            token: token
        ))
    }

    @inline(never)
    private func customMessageContent(title: String, body: String?) -> AnyView {
        AnyView(CustomMessageCardView(title: title, detail: body, token: token))
    }

    @inline(never)
    private func multiForwardMessageContent(_ multiForward: MessageMultiForwardState) -> AnyView {
        AnyView(MultiForwardCardView(
            multiForward: multiForward,
            direction: row.direction,
            token: token
        ))
    }

    @inline(never)
    private func revokeMessageContent(_ text: String) -> AnyView {
        AnyView(Text(text)
            .font(.system(size: isFunRevokeMessage ? 14 : 16))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .truncationMode(.tail))
    }

    private var funRevokeText: String {
        let withdrew = NEChatUIKitSwiftUIBundle.localized(
            "withdrew_message",
            value: " withdrew this message"
        )
        if row.direction == .outgoing {
            return NEChatUIKitSwiftUIBundle.localized("You", value: "you") + withdrew
        }
        return (row.senderName ?? "") + " " + withdrew
    }

    @inline(never)
    private func tipMessageContent(_ text: String) -> AnyView {
        AnyView(Text(text)
            .font(.system(size: 14))
            .foregroundColor(token.secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .center))
    }

    @inline(never)
    private func unsupportedMessageContent(_ text: String) -> AnyView {
        AnyView(messageText(text.isEmpty ? " " : text, source: .messageText))
    }

    private func textMessageContent(_ text: String) -> AnyView {
        let callbackRow = row
        let displayText = text.isEmpty ? " " : text
        let rendered: AnyView
        if callbackRow.textHighlights.isEmpty {
            rendered = plainTextMessageContent(displayText)
        } else if ChatLinkTextView.containsLink(in: text) {
            rendered = linkedTextMessageContent(displayText)
        } else {
            rendered = highlightedTextMessageContent(displayText)
        }
        return selectableTextContent(displayText, rendered: rendered)
    }

    @inline(never)
    private func plainTextMessageContent(_ text: String) -> AnyView {
        AnyView(messageText(text, source: .messageText))
    }

    @inline(never)
    private func linkedTextMessageContent(_ text: String) -> AnyView {
        let callbackRow = row
        let openURL = onOpenURL
        return AnyView(ChatLinkTextView(
            text: text,
            token: token,
            highlights: callbackRow.textHighlights,
            keywordColor: keywordHighlightColor
        ) { url, displayText in
            openURL(url, displayText, .messageText, callbackRow)
        })
    }

    @inline(never)
    private func highlightedTextMessageContent(_ text: String) -> AnyView {
        AnyView(MessageHighlightedTextView(
            text: text,
            highlights: row.textHighlights,
            token: token,
            keywordColor: keywordHighlightColor
        ))
    }

    private func selectableTextContent(_ text: String, rendered: AnyView) -> AnyView {
        let callbackRow = row
        let selectionChange = onTextSelectionChange
        return AnyView(SelectableMessageContentView(
            text: text,
            rendered: rendered,
            messageId: callbackRow.id,
            fontSize: callbackRow.direction == .outgoing
                ? token.outgoingMessageFontSize
                : token.incomingMessageFontSize,
            textColor: callbackRow.direction == .outgoing
                ? token.outgoingTextColor
                : token.incomingTextColor,
            isTextSelectionActive: isTextSelectionActive,
            onSelectionChange: { [selectionChange, callbackRow] selectedText, isFullSelection in
                selectionChange(callbackRow, selectedText, isFullSelection)
            }
        ))
    }

    private func aiStreamMessageContent(text: String,
                                        isFinished: Bool,
                                        error: String?) -> AnyView {
        if !isFinished, text.isEmpty, error == nil {
            return AnyView(AIStreamPlaceholderView())
        }
        let displayText = aiStreamDisplayText(text: text, isFinished: isFinished, error: error)
        let callbackRow = row
        let openURL = onOpenURL
        let rendered: AnyView
        if callbackRow.textHighlights.isEmpty {
            rendered = AnyView(MarkdownMessageRenderer(
                text: displayText,
                token: token
            ) { url, linkText in
                openURL(url, linkText, .aiStreamText, callbackRow)
            })
        } else if ChatLinkTextView.containsLink(in: displayText) {
            rendered = AnyView(ChatLinkTextView(
                text: displayText,
                token: token,
                highlights: callbackRow.textHighlights,
                keywordColor: keywordHighlightColor
            ) { url, linkText in
                openURL(url, linkText, .aiStreamText, callbackRow)
            })
        } else {
            rendered = AnyView(MessageHighlightedTextView(
                text: displayText,
                highlights: callbackRow.textHighlights,
                token: token,
                keywordColor: keywordHighlightColor
            ))
        }
        guard isFinished else {
            return rendered
        }
        return selectableTextContent(displayText, rendered: rendered)
    }

    private func aiStreamDisplayText(text: String,
                                     isFinished: Bool,
                                     error: String?) -> String {
        text + (error.map { "\n\($0)" } ?? "")
    }

    private func richTextMessageContent(title: String?, body: String) -> AnyView {
        let callbackRow = row
        let openURL = onOpenURL
        let selectionChange = onTextSelectionChange
        return AnyView(RichTextMessageCardView(
            title: title,
            messageBody: body,
            highlights: callbackRow.textHighlights,
            keywordColor: keywordHighlightColor,
            token: token,
            messageFontSize: callbackRow.direction == .outgoing
                ? token.outgoingMessageFontSize
                : token.incomingMessageFontSize,
            selectionTextColor: callbackRow.direction == .outgoing
                ? token.outgoingTextColor
                : token.incomingTextColor,
            selectionMessageId: callbackRow.id,
            isSelectionActive: isTextSelectionActive,
            onSelectionChange: { selectedText, isFullSelection in
                selectionChange(callbackRow, selectedText, isFullSelection)
            }
        ) { url, displayText in
            openURL(url, displayText, .richText, callbackRow)
        })
    }

    private func imageMessageContent(_ media: MessageMediaState) -> AnyView {
        AnyView(ZStack {
            MediaThumbnailView(
                media: media,
                label: NEChatUIKitSwiftUIBundle.localized("chat_message_image", value: "[Image]"),
                token: token
            )
            downloadProgressOverlay
        })
    }

    private func videoMessageContent(_ media: MessageMediaState) -> AnyView {
        AnyView(ZStack {
            VideoThumbnailView(media: media, token: token)
            videoStateOverlay(media: media)
        })
    }

    private func fileMessageContent(_ file: MessageFileState) -> AnyView {
        // Keep the HStack children concrete. Nesting their opaque SwiftUI return
        // types here can crash arm64 Debug builds while resolving view metadata.
        let iconContent = fileMessageIconContent(file)
        let detailsContent = fileMessageDetailsContent(file)
        return AnyView(HStack(spacing: 12) {
            iconContent
            detailsContent
        }
        .padding(.horizontal, 10)
        .frame(width: token.fileBubbleWidth,
               height: token.fileBubbleHeight,
               alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: fileBubbleCornerRadius, style: .continuous)
                .fill(token.panelItemBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: fileBubbleCornerRadius, style: .continuous)
                .stroke(fileBubbleBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: fileBubbleCornerRadius, style: .continuous)))
    }

    @inline(never)
    private func fileMessageIconContent(_ file: MessageFileState) -> AnyView {
        let icon = AnyView(NEChatCommonPresentation.iconView(
            imageName: ChatFileIconResource.imageName(for: file),
            token: token,
            renderingMode: .original,
            size: CGSize(width: 32, height: 32)
        )
        .frame(width: 32, height: 32))
        let progress = fileDownloadProgressContent()
        return AnyView(ZStack {
            icon
            progress
        }
        .frame(width: 32, height: 32))
    }

    @inline(never)
    private func fileMessageDetailsContent(_ file: MessageFileState) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
            if let sizeText = file.sizeText {
                Text(sizeText)
                    .font(.system(size: 10))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            }
        })
    }

    @inline(never)
    private func fileDownloadProgressContent() -> AnyView {
        guard case let .pending(progress) = row.deliveryState else {
            return AnyView(EmptyView())
        }
        return AnyView(FileMessageDownloadProgressView(progress: progress, token: token))
    }

    private func replyMessageContent(preview: String?, content: BoxedMessageContentState) -> AnyView {
        let callbackRow = row
        let openURL = onOpenURL
        let selectionChange = onTextSelectionChange
        return AnyView(ReplyMessageContentView(
            preview: callbackRow.reply == nil ? preview : nil,
            content: content.value,
            highlights: callbackRow.textHighlights,
            keywordColor: keywordHighlightColor,
            token: token,
            messageFontSize: callbackRow.direction == .outgoing
                ? token.outgoingMessageFontSize
                : token.incomingMessageFontSize,
            selectionTextColor: callbackRow.direction == .outgoing
                ? token.outgoingTextColor
                : token.incomingTextColor,
            messageId: callbackRow.id,
            isSelectionActive: isTextSelectionActive,
            onOpenURL: { [openURL, callbackRow] url, displayText in
                openURL(url, displayText, .inlineReply, callbackRow)
            },
            onSelectionChange: { [selectionChange, callbackRow] selectedText, isFullSelection in
                selectionChange(callbackRow, selectedText, isFullSelection)
            }
        ))
    }

    @ViewBuilder
    private func messageText(_ text: String,
                             source: ChatURLInteractionSource) -> some View
    {
        let callbackRow = row
        let openURL = onOpenURL
        switch ChatMessageTextRenderClassifier.kind(for: text) {
        case .link:
            ChatLinkTextView(text: text, token: token) { url, displayText in
                openURL(url, displayText, source, callbackRow)
            }
        case .emoticon:
            MessageEmoticonTextView(text: text, token: token)
        case .markdown:
            MarkdownMessageRenderer(text: text, token: token)
        case .plain:
            Text(text)
        }
    }

    private func audioTitle(_ audio: MessageAudioState) -> String {
        let title = audio.isPlaying
            ? NEChatUIKitSwiftUIBundle.localized("chat_audio_playing", value: "Playing")
            : NEChatUIKitSwiftUIBundle.localized("chat_message_audio", value: "[Audio]")
        return "\(title) \(audioDuration(audio))"
    }

    private func audioDuration(_ audio: MessageAudioState) -> String {
        ChatUnitFormatter.audioDurationText(audio.duration)
    }

    private func audioBubble(_ audio: MessageAudioState) -> some View {
        HStack(spacing: 12) {
            if row.direction == .outgoing {
                Spacer(minLength: 0)
                Text(audioDuration(audio))
                    .font(.system(size: 14))
                    .foregroundColor(row.direction == .outgoing ? token.outgoingTextColor : token.incomingTextColor)
                    .lineLimit(1)
                    .frame(width: audioDurationSlotWidth, alignment: .trailing)
                audioIcon(audio, imageName: "audio_play")
                    .frame(width: 28, height: 28, alignment: .trailing)
            } else {
                audioIcon(audio, imageName: "left_play_3")
                Text(audioDuration(audio))
                    .font(.system(size: 14))
                    .foregroundColor(row.direction == .outgoing ? token.outgoingTextColor : token.incomingTextColor)
                    .lineLimit(1)
                    .frame(width: audioDurationSlotWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: audioBubbleWidth(audio),
               height: audioBubbleHeight,
               alignment: row.direction == .outgoing ? .trailing : .leading)
    }

    private func audioIcon(_ audio: MessageAudioState,
                           imageName: String) -> some View
    {
        AudioPlaybackIconView(
            isPlaying: audio.isPlaying,
            direction: row.direction,
            staticImageName: imageName,
            token: token,
            size: CGSize(width: 28, height: 28),
            accessibilityLabel: audioTitle(audio)
        )
    }

    private var audioBubbleHeight: CGFloat {
        token.minBubbleHeight
    }

    private var audioDurationSlotWidth: CGFloat {
        40
    }

    private var minBubbleContentHeight: CGFloat? {
        guard row.direction != .system else {
            return nil
        }
        if let minContentHeight = customLayout?.minContentHeight {
            return minContentHeight
        }
        if customLayout?.contentSize?.height != nil {
            return nil
        }
        if !usesBubbleChromePadding {
            return nil
        }
        if token.styleMode == .normal, row.reply != nil {
            return token.minBubbleHeight + token.replyHeight + 8
        }
        if usesBubbleImageBackground, isStandaloneTextMessage {
            return max(token.minBubbleHeight, bubbleImageMinimumRenderableHeight)
        }
        return token.minBubbleHeight
    }

    private var bubbleImageMinimumRenderableHeight: CGFloat {
        46
    }

    private var minBubbleContentWidth: CGFloat? {
        if isNormalRevokeMessage {
            return normalRevokeBubbleWidth
        }
        guard row.direction != .system,
              customLayout?.contentSize?.width == nil,
              usesBubbleChromePadding,
              usesBubbleImageBackground,
              isStandaloneTextMessage
        else {
            return nil
        }
        return 32
    }

    private func audioBubbleWidth(_ audio: MessageAudioState) -> CGFloat {
        let base: CGFloat = 96
        let maxW: CGFloat = token.audioMaxWidth
        let duration = ChatUnitFormatter.audioDurationSeconds(audio.duration)
        guard duration > 2 else { return base }
        return min(CGFloat(duration) * 8 + base, maxW)
    }

    private var deliveryStatusIconSize: CGFloat {
        16
    }

    private var deliveryStatusSlotWidth: CGFloat {
        deliveryStatusIconSize + 8
    }

    private var backgroundColor: Color {
        if case .image = row.content { return .clear }
        if case .video = row.content { return .clear }
        if isStandaloneFileMessage { return .clear }
        if usesFullBleedBubbleContent { return .clear }
        switch row.direction {
        case .incoming:
            return token.incomingBubbleBackground
        case .outgoing:
            return token.outgoingBubbleBackground
        case .system:
            return token.dividerColor.opacity(0.5)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if row.direction == .system {
            Color.clear
        } else if isFunRevokeMessage {
            Color.clear
        } else if usesBubbleImageBackground {
            ChatResizableBubbleImage(
                imageName: bubbleBackgroundImageName,
                capInsets: bubbleImageCapInsets
            )
        } else {
            backgroundColor
        }
    }

    private var bubbleImageCapInsets: EdgeInsets {
        EdgeInsets(top: 35, leading: 25, bottom: 10, trailing: 25)
    }

    private var usesBubbleImageBackground: Bool {
        if isStandaloneFileMessage {
            return false
        }
        if usesFullBleedBubbleContent {
            return false
        }
        switch row.content {
        case .image, .video:
            return false
        default:
            return true
        }
    }

    private var bubbleBackgroundImageName: String {
        switch (token.styleMode, row.direction) {
        case (.fun, .outgoing):
            return "chat_message_send_fun"
        case (.fun, _):
            return "chat_message_receive_fun"
        case (_, .outgoing):
            return "chat_message_send"
        default:
            return "chat_message_receive"
        }
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        if row.direction == .outgoing {
            Group {
                switch row.deliveryState {
                case .pending:
                    NEChatCommonPresentation.inlineLoadingView(token: token)
                        .scaleEffect(deliveryStatusProgressScale)
                case .sent:
                    if shouldShowReadReceipt {
                        readReceiptButton
                    }
                case .read:
                    if shouldShowReadReceipt {
                        readReceiptButton
                    }
                case .failed:
                    if row.isSendFailureRetryable {
                        Button {
                            onResendTap(row)
                        } label: {
                            sendFailureIcon(color: token.warningColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_resend", value: "Resend"))
                    } else {
                        sendFailureIcon(color: token.secondaryTextColor)
                    }
                default:
                    EmptyView()
                }
            }
            .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
        }
    }

    private func sendFailureIcon(color: Color) -> some View {
        Image("sendMessage_failed", bundle: NEChatUIKitSwiftUIBundle.bundle)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
            .foregroundColor(color)
    }

    private var readReceiptButton: some View {
        Group {
            if canOpenReadReceipt {
                Button {
                    onReadReceiptTap?(row)
                } label: {
                    readReceiptIconView
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            } else {
                readReceiptIconView
            }
        }
        .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
        .contentShape(Rectangle())
        .accessibilityLabel(readReceiptText)
    }

    private var canOpenReadReceipt: Bool {
        guard let receipt = row.readReceipt, !receipt.isP2PRead else {
            return false
        }
        return receipt.unreadCount > 0 && receipt.shouldDisplayTeamProgress
    }

    private var shouldShowReadReceipt: Bool {
        // Keep this in sync with the UIKit message cell. The example
        // setting is global and may change while a chat is already visible.
        guard SettingRepo.shared.getShowReadStatus() else {
            return false
        }
        guard row.isReadReceiptEnabled else {
            return false
        }
        guard let receipt = row.readReceipt else {
            return true
        }
        return receipt.shouldDisplayTeamProgress
    }

    private var deliveryStatusProgressScale: CGFloat {
        max(0.5, min(1.0, token.deliveryStatusFontSize / 15))
    }

    @ViewBuilder
    private var downloadProgressOverlay: some View {
        if case let .pending(progress) = row.deliveryState {
            MessageDownloadProgressView(progress: progress, token: token)
        }
    }

    @ViewBuilder
    private func videoStateOverlay(media: MessageMediaState) -> some View {
        if case let .pending(progress) = row.deliveryState, let progress {
            VideoMessageStateView(phase: .downloading(progress), token: token)
        } else if showsRemoteVideoDownloadAction,
                  media.existingLocalPath == nil,
                  media.url != nil {
            VideoMessageStateView(phase: .download, token: token)
        } else {
            VideoMessageStateView(phase: .play, token: token)
        }
    }

    @ViewBuilder
    private var readReceiptIconView: some View {
        if let receipt = row.readReceipt {
            let total = receipt.totalCount
            let read = receipt.readCount
            let progress = total > 0 ? CGFloat(read) / CGFloat(total) : 0

            if read > 0, receipt.unreadCount == 0 {
                // All read: double checkmark
                Image("chat_read_all", bundle: NEChatUIKitSwiftUIBundle.bundle)
                    .resizable()
                    .scaledToFit()
                    .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
                    .accessibilityLabel(readReceiptText)
            } else if progress > 0, progress < 1.0 {
                // Partial read: sector + stroke circle
                ReadReceiptProgressView(progress: progress, token: token, size: deliveryStatusIconSize)
                    .accessibilityLabel(readReceiptText)
            } else {
                // Default: unread checkmark
                Image("chat_unread", bundle: NEChatUIKitSwiftUIBundle.bundle)
                    .resizable()
                    .scaledToFit()
                    .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
                    .accessibilityLabel(readReceiptText)
            }
        } else {
            Image("chat_unread", bundle: NEChatUIKitSwiftUIBundle.bundle)
                .resizable()
                .scaledToFit()
                .frame(width: deliveryStatusIconSize, height: deliveryStatusIconSize)
                .accessibilityLabel(readReceiptText)
        }
    }

    private var readReceiptText: String {
        guard let readReceipt = row.readReceipt else {
            return NEChatUIKitSwiftUIBundle.localized("chat_message_unread", value: "Unread")
        }
        if readReceipt.isP2PRead {
            return readReceipt.readCount > 0 && readReceipt.unreadCount == 0
                ? NEChatUIKitSwiftUIBundle.localized("chat_message_read", value: "Read")
                : NEChatUIKitSwiftUIBundle.localized("chat_message_unread", value: "Unread")
        }
        return String(
            format: NEChatUIKitSwiftUIBundle.localized("chat_team_read_receipt_summary", value: "%d read, %d unread"),
            readReceipt.readCount,
            readReceipt.unreadCount
        )
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if row.isSelected {
            if case .image = row.content {
                EmptyView()
            } else if case .video = row.content {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: token.bubbleCornerRadius, style: .continuous)
                    .stroke(token.accentColor, lineWidth: token.selectionBorderWidth)
            }
        }
    }

    private var fileBubbleCornerRadius: CGFloat {
        token.styleMode == .fun ? 4 : 8
    }

    private var fileBubbleBorderColor: Color {
        NEUIKitSwiftUIStyle.ColorToken.border
    }
}

private struct ReplyPreviewView: View {
    var reply: MessageReplyState
    var token: ChatThemeToken

    @ViewBuilder
    var body: some View {
        if token.styleMode == .fun {
            MessageEmoticonTextView(
                text: displayText,
                token: token,
                baseColor: token.secondaryTextColor
            )
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(height: token.replyHeight, alignment: .leading)
                .background(token.replyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            MessageEmoticonTextView(
                text: normalDisplayText,
                token: token,
                baseColor: token.secondaryTextColor
            )
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: token.replyHeight, alignment: .leading)
        }
    }

    private var displayText: String {
        reply.displayPreview ?? notFoundText
    }

    private var normalDisplayText: String {
        displayText == notFoundText ? displayText : "| \(displayText)"
    }

    private var notFoundText: String {
        NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found")
    }
}

private struct ChatResizableBubbleImage: View {
    var imageName: String
    var capInsets: EdgeInsets

    var body: some View {
        ChatResizableUIImageView(imageName: imageName, capInsets: capInsets)
    }
}

struct ChatResizableUIImageView: View {
    var imageName: String
    var capInsets: EdgeInsets

    var body: some View {
        GeometryReader { proxy in
            if let slices = ChatResizableImageSlices.cached(imageName: imageName, capInsets: capInsets) {
                resizableImage(slices, size: proxy.size)
            } else {
                Color.clear
            }
        }
    }

    private func resizableImage(_ slices: ChatResizableImageSlices,
                                size: CGSize) -> some View {
        let metrics = slices.metrics(for: size)
        return VStack(spacing: 0) {
            imageRow(
                leading: slices.topLeft,
                center: slices.top,
                trailing: slices.topRight,
                metrics: metrics,
                height: metrics.topHeight
            )
            imageRow(
                leading: slices.left,
                center: slices.center,
                trailing: slices.right,
                metrics: metrics,
                height: metrics.centerHeight
            )
            imageRow(
                leading: slices.bottomLeft,
                center: slices.bottom,
                trailing: slices.bottomRight,
                metrics: metrics,
                height: metrics.bottomHeight
            )
        }
        .frame(width: size.width, height: size.height)
    }

    private func imageRow(leading: UIImage?,
                          center: UIImage?,
                          trailing: UIImage?,
                          metrics: ChatResizableImageMetrics,
                          height: CGFloat) -> some View {
        HStack(spacing: 0) {
            imageSegment(leading)
                .frame(width: metrics.leftWidth, height: height)
            imageSegment(center)
                .frame(width: metrics.centerWidth, height: height)
            imageSegment(trailing)
                .frame(width: metrics.rightWidth, height: height)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func imageSegment(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable(resizingMode: .stretch)
        } else {
            Color.clear
        }
    }
}

private struct ChatResizableImageSlices {
    private static let cache = NSCache<NSString, ChatResizableImageSlicesBox>()

    let topLeft: UIImage?
    let top: UIImage?
    let topRight: UIImage?
    let left: UIImage?
    let center: UIImage?
    let right: UIImage?
    let bottomLeft: UIImage?
    let bottom: UIImage?
    let bottomRight: UIImage?
    let capInsets: EdgeInsets

    static func cached(imageName: String, capInsets: EdgeInsets) -> ChatResizableImageSlices? {
        let bundlePath = NEChatUIKitSwiftUIBundle.bundle.bundleURL.standardizedFileURL.path
        let key = [
            bundlePath,
            imageName,
            "\(capInsets.top)",
            "\(capInsets.leading)",
            "\(capInsets.bottom)",
            "\(capInsets.trailing)",
        ].joined(separator: "|") as NSString

        if let cached = cache.object(forKey: key) {
            return cached.slices
        }

        guard let slices = ChatResizableImageSlices(imageName: imageName, capInsets: capInsets) else {
            return nil
        }
        cache.setObject(ChatResizableImageSlicesBox(slices), forKey: key)
        return slices
    }

    init?(imageName: String, capInsets: EdgeInsets) {
        guard let image = UIImage(
            named: imageName,
            in: NEChatUIKitSwiftUIBundle.bundle,
            compatibleWith: nil
        ) else {
            return nil
        }

        let normalizedInsets = ChatResizableImageSlices.normalizedInsets(capInsets, imageSize: image.size)
        self.capInsets = normalizedInsets

        let imageWidth = image.size.width
        let imageHeight = image.size.height
        let left = normalizedInsets.leading
        let right = normalizedInsets.trailing
        let top = normalizedInsets.top
        let bottom = normalizedInsets.bottom
        let centerWidth = max(0, imageWidth - left - right)
        let centerHeight = max(0, imageHeight - top - bottom)

        topLeft = image.cropped(to: CGRect(x: 0, y: 0, width: left, height: top))
        self.top = image.cropped(to: CGRect(x: left, y: 0, width: centerWidth, height: top))
        topRight = image.cropped(to: CGRect(x: imageWidth - right, y: 0, width: right, height: top))
        self.left = image.cropped(to: CGRect(x: 0, y: top, width: left, height: centerHeight))
        center = image.cropped(to: CGRect(x: left, y: top, width: centerWidth, height: centerHeight))
        self.right = image.cropped(to: CGRect(x: imageWidth - right, y: top, width: right, height: centerHeight))
        bottomLeft = image.cropped(to: CGRect(x: 0, y: imageHeight - bottom, width: left, height: bottom))
        self.bottom = image.cropped(to: CGRect(x: left, y: imageHeight - bottom, width: centerWidth, height: bottom))
        bottomRight = image.cropped(to: CGRect(x: imageWidth - right, y: imageHeight - bottom, width: right, height: bottom))
    }

    func metrics(for size: CGSize) -> ChatResizableImageMetrics {
        let horizontalInsets = Self.normalizedInsetPair(
            leading: capInsets.leading,
            trailing: capInsets.trailing,
            total: size.width
        )
        let verticalInsets = Self.normalizedInsetPair(
            leading: capInsets.top,
            trailing: capInsets.bottom,
            total: size.height
        )
        let leftWidth = horizontalInsets.leading
        let rightWidth = horizontalInsets.trailing
        let topHeight = verticalInsets.leading
        let bottomHeight = verticalInsets.trailing

        return ChatResizableImageMetrics(
            leftWidth: leftWidth,
            centerWidth: max(0, size.width - leftWidth - rightWidth),
            rightWidth: rightWidth,
            topHeight: topHeight,
            centerHeight: max(0, size.height - topHeight - bottomHeight),
            bottomHeight: bottomHeight
        )
    }

    private static func normalizedInsets(_ capInsets: EdgeInsets,
                                         imageSize: CGSize) -> EdgeInsets {
        let horizontal = normalizedInsetPair(
            leading: capInsets.leading,
            trailing: capInsets.trailing,
            total: imageSize.width
        )
        let vertical = normalizedInsetPair(
            leading: capInsets.top,
            trailing: capInsets.bottom,
            total: imageSize.height
        )
        return EdgeInsets(
            top: vertical.leading,
            leading: horizontal.leading,
            bottom: vertical.trailing,
            trailing: horizontal.trailing
        )
    }

    private static func normalizedInsetPair(leading: CGFloat,
                                            trailing: CGFloat,
                                            total: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let minimumCenter = total > 1 ? CGFloat(1) : CGFloat(0)
        let available = max(0, total - minimumCenter)
        let normalizedLeading = min(max(0, leading), available)
        let normalizedTrailing = min(max(0, trailing), max(0, available - normalizedLeading))
        return (normalizedLeading, normalizedTrailing)
    }
}

private final class ChatResizableImageSlicesBox {
    let slices: ChatResizableImageSlices

    init(_ slices: ChatResizableImageSlices) {
        self.slices = slices
    }
}

private struct ChatResizableImageMetrics {
    let leftWidth: CGFloat
    let centerWidth: CGFloat
    let rightWidth: CGFloat
    let topHeight: CGFloat
    let centerHeight: CGFloat
    let bottomHeight: CGFloat
}

private extension UIImage {
    func cropped(to rect: CGRect) -> UIImage? {
        guard rect.width > 0,
              rect.height > 0,
              let cgImage = cgImage else {
            return nil
        }

        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        guard let croppedImage = cgImage.cropping(to: scaledRect) else {
            return nil
        }
        return UIImage(cgImage: croppedImage, scale: scale, orientation: imageOrientation)
    }
}

private struct MessageIconLabelView: View {
    var text: String
    var systemImageName: String?
    var imageName: String?
    var token: ChatThemeToken
    var font: Font = .system(size: 15)
    var foregroundColor: Color?

    init(text: String,
         systemImageName: String,
         token: ChatThemeToken,
         font: Font = .system(size: 15),
         foregroundColor: Color? = nil)
    {
        self.text = text
        self.systemImageName = systemImageName
        imageName = nil
        self.token = token
        self.font = font
        self.foregroundColor = foregroundColor
    }

    init(text: String,
         imageName: String,
         token: ChatThemeToken,
         font: Font = .system(size: 15),
         foregroundColor: Color? = nil)
    {
        self.text = text
        systemImageName = nil
        self.imageName = imageName
        self.token = token
        self.font = font
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        HStack(spacing: 5) {
            if let imageName {
                NEChatCommonPresentation.iconView(
                    imageName: imageName,
                    token: token,
                    font: iconFont,
                    foregroundColor: foregroundColor,
                    accessibilityLabel: text
                )
            } else if let systemImageName {
                NEChatCommonPresentation.iconView(
                    systemImageName: systemImageName,
                    token: token,
                    font: iconFont,
                    foregroundColor: foregroundColor,
                    accessibilityLabel: text
                )
            }
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
        }
    }

    private var iconFont: Font {
        if foregroundColor != nil {
            return font
        }
        return .system(size: 15, weight: .semibold)
    }
}

private struct MultiForwardCardView: View {
    var multiForward: MessageMultiForwardState
    var direction: MessageDirection
    var token: ChatThemeToken

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatResizableUIImageView(imageName: backgroundImageName, capInsets: backgroundCapInsets)
                .frame(width: cardWidth, height: cardHeight)

            titleRow
                .frame(width: titleRowWidth, height: 22, alignment: .leading)
                .offset(x: contentLeadingPadding, y: titleTop)

            summaryRows
                .frame(width: summaryContentWidth, alignment: .leading)
                .offset(x: contentLeadingPadding, y: summaryTop)

            Rectangle()
                .fill(token.multiForwardLineColor)
                .frame(width: dividerWidth, height: 1)
                .offset(x: dividerLeading, y: dividerTop)

            Text(NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History"))
                .font(.system(size: 12))
                .foregroundColor(historyColor)
                .frame(height: 14, alignment: .leading)
                .offset(x: contentLeadingPadding, y: historyTop)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 0) {
            if let titlePrefix {
                MessageEmoticonTextView(text: titlePrefix, token: token, baseColor: titleColor)
                    .font(titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Text(titleSuffix)
                .font(titleFont)
                .foregroundColor(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: titleSuffixWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var summaryRows: some View {
        MessageMultiForwardSummaryRowsView(
            texts: displaySummaries,
            context: .chat,
            width: summaryContentWidth,
            fontSize: summaryFontSize,
            color: summaryColor,
            token: token
        )
        .frame(height: summaryVisibleHeight, alignment: .top)
        .clipped()
    }

    private var displaySummaries: [String] {
        let summaries = multiForward.summaries.prefix(3).map(\.displayText)
        guard !summaries.isEmpty else {
            return [NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_no_summary", value: "No preview")]
        }
        return Array(summaries)
    }

    private var cardWidth: CGFloat {
        token.styleMode == .fun ? 256 : NEChatUIKitSwiftUIConstants.multiForwardCardSize.width
    }

    private var cardHeight: CGFloat {
        NEChatUIKitSwiftUIConstants.multiForwardCardSize.height
    }

    private var backgroundCapInsets: EdgeInsets {
        EdgeInsets(top: 35, leading: 25, bottom: 10, trailing: 25)
    }

    private var titlePrefix: String? {
        hasResolvedSessionName ? multiForward.title : nil
    }

    private var titleSuffix: String {
        if hasResolvedSessionName {
            return NEChatUIKitSwiftUIBundle.localized("chat_history_by", value: "`s messages")
        }
        return NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History")
    }

    private var hasResolvedSessionName: Bool {
        multiForward.hasSessionName
    }

    private var titleFont: Font {
        .system(size: titleFontSize, weight: titleFontWeight)
    }

    private var titleFontSize: CGFloat {
        token.styleMode == .fun ? 12 : 14
    }

    private var titleFontWeight: Font.Weight {
        token.styleMode == .fun ? .regular : .semibold
    }

    private var titleColor: Color {
        NEUIKitSwiftUIStyle.ColorToken.darkText
    }

    private var titleRowWidth: CGFloat {
        cardWidth - contentLeadingPadding - titleTrailingPadding
    }

    private var titleTrailingPadding: CGFloat {
        token.styleMode == .fun ? 14 : 10
    }

    private var titleSuffixWidth: CGFloat {
        if token.styleMode == .fun {
            return isEnglishLocalization ? 100 : 88
        }
        return isEnglishLocalization ? 90 : 74
    }

    private var isEnglishLocalization: Bool {
        NEChatUIKitSwiftUIBundle.localized("chat_history_by", value: "`s messages") == "`s messages"
    }

    private var summaryFontSize: CGFloat {
        token.styleMode == .fun ? 12 : 14
    }

    private var summaryColor: Color {
        token.styleMode == .fun ? Color(hex: 0xBBBBBB) : NEUIKitSwiftUIStyle.ColorToken.lightText
    }

    private var historyColor: Color {
        NEUIKitSwiftUIStyle.ColorToken.lightText
    }

    private var contentLeadingPadding: CGFloat {
        guard token.styleMode == .fun else { return 16 }
        return direction == .outgoing ? 12 : 12 + token.funMargin
    }

    private var titleTop: CGFloat {
        token.styleMode == .fun ? 12 : 10
    }

    private var summaryContentWidth: CGFloat {
        token.styleMode == .fun ? 228 : 234
    }

    private var summaryTop: CGFloat {
        token.styleMode == .fun ? 38 : 34
    }

    private var summaryVisibleHeight: CGFloat {
        min(dividerTop - summaryTop, MessageMultiForwardSummaryLayout.minimumRowHeight * 3)
    }

    private var historyTop: CGFloat {
        token.styleMode == .fun ? 108 : 104
    }

    private var dividerTop: CGFloat {
        token.styleMode == .fun ? 100 : 98
    }

    private var dividerLeading: CGFloat {
        guard token.styleMode == .fun else {
            return 6
        }
        return direction == .outgoing ? 0 : token.funMargin
    }

    private var dividerWidth: CGFloat {
        token.styleMode == .fun ? cardWidth - token.funMargin : cardWidth - 12
    }

    private var backgroundImageName: String {
        switch (token.styleMode, direction) {
        case (.fun, .outgoing):
            return "multiForward_message_send_fun"
        case (.fun, _):
            return "multiForward_message_receive_fun"
        case (_, .outgoing):
            return "multiForward_message_send"
        default:
            return "multiForward_message_receive"
        }
    }

}

private struct AIStreamPlaceholderView: View {
    var body: ProgressView<EmptyView, EmptyView> {
        ProgressView()
    }
}

private struct SelectableMessageContentView: View {
    var text: String
    var rendered: AnyView
    var messageId: String
    var fontSize: CGFloat
    var textColor: Color
    var isTextSelectionActive: Bool
    var onSelectionChange: (String?, Bool) -> Void

    var body: some View {
        rendered
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    SelectableMessageTextOverlay(
                        text: text,
                        fontSize: fontSize,
                        textColor: UIColor(textColor),
                        isSelectionActive: isTextSelectionActive,
                        onSelectionChange: onSelectionChange
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(isTextSelectionActive)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MessageSelectableTextFramePreferenceKey.self,
                        value: [messageId: geometry.frame(in: .named("chatTimeline"))]
                    )
                }
            }
    }

}

private struct RichTextMessageCardView: View {
    var title: String?
    var messageBody: String
    var highlights: [MessageTextHighlightState] = []
    var keywordColor: Color?
    var token: ChatThemeToken
    var messageFontSize: CGFloat
    var selectionTextColor: Color
    var selectionMessageId: String
    var isSelectionActive: Bool
    var onSelectionChange: (String?, Bool) -> Void
    var onOpenURL: (URL, String) -> Void = { _, _ in }

    private var highlightProjection: RichTextHighlightProjection {
        RichTextHighlightProjection(title: title, body: messageBody, highlights: highlights)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                let renderedTitle = titleContent(title)
                if messageBody.isEmpty {
                    selectableContent(title, rendered: renderedTitle)
                } else {
                    renderedTitle
                }
            }

            if !messageBody.isEmpty {
                selectableContent(messageBody, rendered: bodyContent(messageBody))
            }
        }
        .background {
            if isSelectionActive {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MessageSelectableTextFramePreferenceKey.self,
                        value: [selectionMessageId: geometry.frame(in: .named("chatTimeline"))]
                    )
                }
            }
        }
    }

    private func titleContent(_ text: String) -> AnyView {
        if highlightProjection.title.isEmpty {
            return AnyView(
                Text(text)
                    .font(.system(size: messageFontSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            )
        }
        return AnyView(
            MessageHighlightedTextView(
                text: text,
                highlights: highlightProjection.title,
                token: token,
                keywordColor: keywordColor
            )
            .font(.system(size: messageFontSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func bodyContent(_ text: String) -> AnyView {
        if !highlightProjection.body.isEmpty,
           ChatLinkTextView.containsLink(in: text) {
            return AnyView(
                ChatLinkTextView(
                    text: text,
                    token: token,
                    highlights: highlightProjection.body,
                    keywordColor: keywordColor,
                    onOpenURL: onOpenURL
                )
                .font(.system(size: messageFontSize))
                .fixedSize(horizontal: false, vertical: true)
            )
        }
        if !highlightProjection.body.isEmpty {
            return AnyView(
                MessageHighlightedTextView(
                    text: text,
                    highlights: highlightProjection.body,
                    token: token,
                    keywordColor: keywordColor
                )
                .font(.system(size: messageFontSize))
                .fixedSize(horizontal: false, vertical: true)
            )
        }
        switch ChatMessageTextRenderClassifier.kind(for: text) {
        case .link:
            return AnyView(
                ChatLinkTextView(text: text, token: token, onOpenURL: onOpenURL)
                    .font(.system(size: messageFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            )
        case .emoticon:
            return AnyView(
                MessageEmoticonTextView(text: text, token: token)
                    .font(.system(size: messageFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            )
        case .markdown:
            return AnyView(
                MarkdownMessageRenderer(text: text, token: token, onOpenURL: onOpenURL)
                    .font(.system(size: messageFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            )
        case .plain:
            return AnyView(
                Text(text)
                    .font(.system(size: messageFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            )
        }
    }

    private func selectableContent(_ text: String, rendered: AnyView) -> AnyView {
        return AnyView(
            rendered
                .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    SelectableMessageTextOverlay(
                        text: text,
                        fontSize: messageFontSize,
                        textColor: UIColor(selectionTextColor),
                        isSelectionActive: isSelectionActive,
                        onSelectionChange: onSelectionChange
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(isSelectionActive)
                }
            }
        )
    }
}

private struct CallMessageCardView: View {
    var summary: String
    var type: Int
    var direction: MessageDirection
    var token: ChatThemeToken

    private var iconImageName: String {
        type == 1 ? "audio_record" : "video_record"
    }

    private var iconSize: CGSize {
        type == 1 ? CGSize(width: 24, height: 24) : CGSize(width: 24, height: 14)
    }

    var body: some View {
        HStack(spacing: 0) {
            if direction == .incoming {
                iconView
                Text(" ")
            }
            Text(summary)
            if direction == .outgoing {
                Text(" ")
                iconView
            }
        }
    }

    private var iconView: some View {
        NEChatCommonPresentation.iconView(
            imageName: iconImageName,
            token: token,
            renderingMode: .original,
            size: iconSize,
            foregroundColor: token.accentColor,
            accessibilityLabel: summary
        )
    }
}

private struct CustomMessageCardView: View {
    var title: String
    var detail: String?
    var token: ChatThemeToken

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NEChatCommonPresentation.iconView(
                    imageName: "op_collection",
                    token: token,
                    renderingMode: .original,
                    font: .system(size: 15, weight: .semibold),
                    foregroundColor: token.accentColor,
                    accessibilityLabel: title
                )
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let detail, !detail.isEmpty {
                MessageEmoticonTextView(text: detail, token: token, baseColor: token.secondaryTextColor)
                    .font(.system(size: 12))
                    .lineLimit(3)
            }
        }
        .frame(width: NEChatUIKitSwiftUIConstants.multiForwardCardSize.width, alignment: .leading)
    }
}

private struct UnsupportedMessageCardView: View {
    var text: String
    var token: ChatThemeToken

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NEChatCommonPresentation.iconView(
                imageName: "sendMessage_failed",
                token: token,
                renderingMode: .original,
                font: .system(size: 15, weight: .semibold),
                foregroundColor: token.warningColor,
                accessibilityLabel: text
            )
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(token.secondaryTextColor)
        }
    }
}

private struct MediaThumbnailView: View {
    var media: MessageMediaState
    var label: String
    var token: ChatThemeToken

    @State private var resolvedImageSize: CGSize?

    var body: some View {
        ZStack {
            Color.clear

            if let url = media.thumbnailDisplayURL {
                fallbackAsyncImage(url: url)
            } else {
                placeholder
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipped()
        .background(token.dividerColor.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: token.bubbleCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func fallbackAsyncImage(url: URL) -> some View {
        ChatCachedAsyncImage(
            url: url,
            fallbackURL: media.fallbackDisplayURL == url ? nil : media.fallbackDisplayURL,
            contentMode: .fit
        ) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            placeholder
        } onImageLoaded: { image in
            resolvedImageSize = image.size
        }
    }

    private var placeholder: some View {
        Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
              bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 84, height: 84)
            .accessibilityLabel(label)
    }

    private var thumbnailSize: CGSize {
        ChatMediaThumbnailSizer.size(for: media, token: token, resolvedSize: resolvedImageSize)
    }
}

private struct VideoThumbnailView: View {
    var media: MessageMediaState
    var token: ChatThemeToken

    @State private var resolvedImageSize: CGSize?

    var body: some View {
        ZStack {
            placeholderBackground

            if let url = media.videoThumbnailDisplayURL {
                fallbackAsyncImage(url: url)
            } else {
                placeholder
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: token.bubbleCornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            durationBadge
                .padding(.trailing, 7)
                .padding(.bottom, 7)
        }
    }

    @ViewBuilder
    private func fallbackAsyncImage(url: URL) -> some View {
        ChatCachedAsyncImage(
            url: url,
            fallbackURL: media.videoFallbackDisplayURL == url ? nil : media.videoFallbackDisplayURL
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            placeholder
        } onImageLoaded: { image in
            resolvedImageSize = image.size
        }
    }

    private var placeholderBackground: some View {
        token.dividerColor.opacity(0.6)
    }

    private var placeholder: some View {
        Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
              bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 84, height: 84)
            .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_message_video", value: "[Video]"))
    }

    private var thumbnailSize: CGSize {
        ChatMediaThumbnailSizer.size(for: media, token: token, resolvedSize: resolvedImageSize)
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let duration = media.duration, duration > 0 {
            Text(ChatUnitFormatter.playTime(duration))
                .font(.system(size: 10))
                .foregroundColor(token.primaryButtonTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

private struct VideoMessageStateView: View {
    enum Phase: Equatable {
        case play
        case download
        case downloading(Double?)
    }

    var phase: Phase
    var token: ChatThemeToken

    var body: some View {
        ZStack {
            switch phase {
            case .play:
                Image("video_play", bundle: NECommonUIKitSwiftUIBundle.bundle)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            case .download, .downloading:
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 42, height: 42)

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(token.primaryButtonTextColor)
                        .frame(width: 3, height: 18)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(token.primaryButtonTextColor)
                        .frame(width: 3, height: 18)
                }

                Circle()
                    .stroke(token.primaryButtonTextColor.opacity(0.5), lineWidth: 4)
                    .frame(width: 42, height: 42)

                if case let .downloading(progress) = phase, let progress {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                        .stroke(token.primaryButtonTextColor, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 42, height: 42)
                } else if case .downloading = phase {
                    NEChatCommonPresentation.inlineLoadingView(token: token)
                        .scaleEffect(0.86)
                }
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .play:
            return NEChatUIKitSwiftUIBundle.localized("chat_message_video", value: "[Video]")
        case .download:
            return NEChatUIKitSwiftUIBundle.localized("chat_download", value: "Download")
        case .downloading:
            return NEChatUIKitSwiftUIBundle.localized("chat_downloading", value: "Downloading")
        }
    }
}

struct MessageDownloadProgressView: View {
    var progress: Double?
    var token: ChatThemeToken

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
            if let progress {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                    .stroke(token.primaryButtonTextColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
            } else {
                NEChatCommonPresentation.inlineLoadingView(token: token)
                    .scaleEffect(0.72)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_downloading", value: "Downloading"))
    }
}

private struct FileMessageDownloadProgressView: View {
    var progress: Double?
    var token: ChatThemeToken

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 32, height: 32)

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(token.primaryButtonTextColor)
                    .frame(width: 2, height: 10)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(token.primaryButtonTextColor)
                    .frame(width: 2, height: 10)
            }

            Circle()
                .stroke(token.primaryButtonTextColor.opacity(0.5), lineWidth: 2)
                .frame(width: 18, height: 18)

            if let progress {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                    .stroke(token.primaryButtonTextColor, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_downloading", value: "Downloading"))
    }
}

private enum ChatMediaThumbnailSizer {
    static func size(for media: MessageMediaState,
                     token: ChatThemeToken,
                     resolvedSize: CGSize? = nil) -> CGSize {
        let maxSize = CGSize(width: token.mediaThumbnailWidth, height: token.mediaThumbnailMaxHeight)
        guard let rawSize = rawSize(for: media, resolvedSize: resolvedSize) else {
            return maxSize
        }

        var realSize: CGSize
        if rawSize.width > rawSize.height {
            let width = min(maxSize.width, rawSize.width)
            realSize = CGSize(width: width, height: width * rawSize.height / rawSize.width)
        } else {
            let height = min(maxSize.height, rawSize.height)
            realSize = CGSize(width: height * rawSize.width / rawSize.height, height: height)
        }
        if min(realSize.width, realSize.height) < token.mediaThumbnailMinHeight {
            if realSize.width < realSize.height {
                realSize.width = token.mediaThumbnailMinHeight
            } else {
                realSize.height = token.mediaThumbnailMinHeight
            }
        }
        return realSize
    }

    private static func rawSize(for media: MessageMediaState,
                                resolvedSize: CGSize?) -> CGSize? {
        let mediaSize = mediaSize(from: media)
        guard let resolvedSize = validSize(resolvedSize) else {
            return mediaSize
        }
        guard let mediaSize else {
            return resolvedSize
        }
        let mediaIsLandscape = mediaSize.width > mediaSize.height
        let imageIsLandscape = resolvedSize.width > resolvedSize.height
        guard mediaIsLandscape != imageIsLandscape else {
            return mediaSize
        }
        return CGSize(width: mediaSize.height, height: mediaSize.width)
    }

    private static func mediaSize(from media: MessageMediaState) -> CGSize? {
        guard let width = media.width,
              let height = media.height else {
            return nil
        }
        return validSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

    private static func validSize(_ size: CGSize?) -> CGSize? {
        guard let size,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }
}
private extension MessageMediaState {
    var thumbnailDisplayURL: URL? {
        if let localPath, !localPath.isEmpty {
            return URL(fileURLWithPath: localPath)
        }
        return thumbnailURL ?? url
    }

    var fallbackDisplayURL: URL? {
        if let localPath, !localPath.isEmpty {
            return URL(fileURLWithPath: localPath)
        }
        return url ?? thumbnailURL
    }

    var videoThumbnailDisplayURL: URL? {
        thumbnailURL ?? url ?? localVideoFileURL
    }

    var videoFallbackDisplayURL: URL? {
        url ?? thumbnailURL ?? localVideoFileURL
    }

    var localVideoFileURL: URL? {
        guard let localPath, !localPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }
}

enum ChatImageContentMode {
    case fill
    case fit
}

struct ChatCachedAsyncImage<Content: View, Placeholder: View>: View {
    var url: URL?
    var fallbackURL: URL?
    var contentMode: ChatImageContentMode
    var content: (Image) -> Content
    var placeholder: () -> Placeholder
    var onImageLoaded: ((UIImage) -> Void)?
    @State private var loadedImage: UIImage?
    @State private var loadedImageKey: String?

    init(url: URL?,
         fallbackURL: URL? = nil,
         contentMode: ChatImageContentMode = .fill,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder,
         onImageLoaded: ((UIImage) -> Void)? = nil) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.contentMode = contentMode
        self.content = content
        self.placeholder = placeholder
        self.onImageLoaded = onImageLoaded
    }

    @ViewBuilder
    var body: some View {
        if let image = currentImage {
            if image.neChatIsAnimatedImage {
                ChatAnimatedImageView(image: image, contentMode: contentMode)
                    .task(id: imageSizeKey(for: image)) {
                        onImageLoaded?(image)
                    }
            } else {
                content(Image(uiImage: image))
                    .task(id: imageSizeKey(for: image)) {
                        onImageLoaded?(image)
                    }
            }
        } else {
            placeholder()
                .task(id: cacheKey) {
                    await loadImageIfNeeded()
                }
        }
    }

    private var currentImage: UIImage? {
        if loadedImageKey == cacheKey, let loadedImage {
            return loadedImage
        }
        return Self.cachedImage(for: candidates)
    }

    private var candidates: [URL] {
        var urls = [URL]()
        var seen = Set<String>()
        for candidate in [url, fallbackURL].compactMap({ $0 }) {
            let key = Self.cacheKey(for: candidate)
            guard seen.insert(key).inserted else {
                continue
            }
            urls.append(candidate)
        }
        return urls
    }

    private var cacheKey: String {
        candidates.map(Self.cacheKey(for:)).joined(separator: "|")
    }

    @MainActor
    private func loadImageIfNeeded() async {
        let key = cacheKey
        guard !candidates.isEmpty else {
            loadedImage = nil
            loadedImageKey = key
            return
        }
        if let cached = Self.cachedImage(for: candidates) {
            loadedImage = cached
            loadedImageKey = key
            return
        }

        for candidate in candidates {
            if Task.isCancelled {
                return
            }
            if let image = await Self.loadImage(from: candidate) {
                ChatMessageImageMemoryCache.shared.store(image, for: candidate)
                loadedImage = image
                loadedImageKey = key
                return
            }
        }

        if !Task.isCancelled {
            loadedImage = nil
            loadedImageKey = key
        }
    }

    private static func cachedImage(for urls: [URL]) -> UIImage? {
        for url in urls {
            if let image = ChatMessageImageMemoryCache.shared.image(for: url) {
                return image
            }
        }
        return nil
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                if isGIF(url),
                   let data = try? Data(contentsOf: url),
                   let image = decodedImage(from: data) {
                    return image
                }
                if let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
                if !videoFileExtensions.contains(url.pathExtension.lowercased()),
                   let data = try? Data(contentsOf: url),
                   let image = decodedImage(from: data) {
                    return image
                }
                return localVideoThumbnail(from: url)
            }.value
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                return nil
            }
            return decodedImage(from: data)
        } catch {
            debugPrint("[NEChatUIKitSwiftUI] message image download failed url=\(url.absoluteString) error=\(error)")
            return nil
        }
    }

    private static func cacheKey(for url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.absoluteString : url.absoluteString
    }

    private func imageSizeKey(for image: UIImage) -> String {
        "\(cacheKey)|\(image.size.width)x\(image.size.height)"
    }

    private static func localVideoThumbnail(from url: URL) -> UIImage? {
        guard videoFileExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static var videoFileExtensions: Set<String> {
      [
          "mp4", "avi", "wmv", "mpeg", "m4v", "mov",
          "asf", "flv", "f4v", "rmvb", "rm", "3gp"
      ]
    }

    private static func isGIF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gif"
    }

    private static func decodedImage(from data: Data) -> UIImage? {
        animatedImage(from: data) ?? UIImage(data: data)
    }

    private static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return nil
        }

        var frames = [UIImage]()
        var duration: TimeInterval = 0
        frames.reserveCapacity(count)

        for index in 0 ..< count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            duration += frameDuration(at: index, source: source)
            frames.append(UIImage(cgImage: cgImage))
        }

        guard frames.count > 1 else {
            return frames.first
        }
        return UIImage.animatedImage(with: frames, duration: duration > 0 ? duration : Double(frames.count) * 0.1)
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber
        let delay = unclamped?.doubleValue ?? clamped?.doubleValue ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

private struct ChatAnimatedImageView: View {
    var image: UIImage

    var contentMode: ChatImageContentMode

    var body: some View {
        if frames.count > 1 {
            TimelineView(.animation(minimumInterval: frameInterval)) { context in
                frameImage(frames[frameIndex(at: context.date)])
            }
        } else {
            frameImage(frames.first ?? image)
        }
    }

    @ViewBuilder
    private func frameImage(_ frame: UIImage) -> some View {
        switch contentMode {
        case .fill:
            Image(uiImage: frame)
                .resizable()
                .scaledToFill()
        case .fit:
            Image(uiImage: frame)
                .resizable()
                .scaledToFit()
        }
    }

    private var frames: [UIImage] {
        image.images ?? [image]
    }

    private var animationDuration: TimeInterval {
        image.duration > 0 ? image.duration : Double(max(frames.count, 1)) * 0.1
    }

    private var frameInterval: TimeInterval {
        max(animationDuration / Double(max(frames.count, 1)), 0.02)
    }

    private func frameIndex(at date: Date) -> Int {
        let count = frames.count
        guard count > 1 else {
            return 0
        }
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: animationDuration)
        return min(count - 1, max(0, Int(elapsed / frameInterval)))
    }
}

private extension UIImage {
    var neChatIsAnimatedImage: Bool {
        guard let images = images else {
            return false
        }
        return images.count > 1
    }
}

final class ChatMessageImageMemoryCache {
    static let shared = ChatMessageImageMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: cacheKey(for: url))
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: cacheKey(for: url), cost: cost(of: image))
    }

    private func cacheKey(for url: URL) -> NSURL {
        NSURL(string: url.standardizedFileURL.absoluteString) ?? url as NSURL
    }

    private func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 1
        }
        return max(1, cgImage.bytesPerRow * cgImage.height)
    }
}

struct AudioPlaybackIconView: View {
    @State private var frameIndex = 2

    var isPlaying: Bool
    var direction: MessageDirection
    var staticImageName: String
    var token: ChatThemeToken
    var size: CGSize
    var accessibilityLabel: String

    private let timer = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common).autoconnect()

    @ViewBuilder
    var body: some View {
        if isPlaying {
            iconView(currentImageName)
                .onReceive(timer) { _ in
                    frameIndex = (frameIndex + 1) % animationFrames.count
                }
                .onAppear {
                    frameIndex = 0
                }
        } else {
            iconView(staticImageName)
                .onAppear {
                    frameIndex = 2
                }
        }
    }

    private func iconView(_ imageName: String) -> some View {
        NEChatCommonPresentation.iconView(
            imageName: imageName,
            token: token,
            size: size,
            foregroundColor: direction == .outgoing ? token.outgoingTextColor : token.incomingTextColor,
            accessibilityLabel: accessibilityLabel
        )
    }

    private var currentImageName: String {
        animationFrames[frameIndex]
    }

    private var animationFrames: [String] {
        direction == .outgoing
            ? ["play_1", "play_2", "play_3"]
            : ["left_play_1", "left_play_2", "left_play_3"]
    }
}

private struct ReplyMessageContentView: View {
    var preview: String?
    var content: MessageContentState
    var highlights: [MessageTextHighlightState]
    var keywordColor: Color?
    var token: ChatThemeToken
    var messageFontSize: CGFloat
    var selectionTextColor: Color
    var messageId: String
    var isSelectionActive: Bool
    var onOpenURL: (URL, String) -> Void
    var onSelectionChange: (String?, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let preview {
                MessageEmoticonTextView(
                    text: preview,
                    token: token,
                    baseColor: token.secondaryTextColor
                )
                .font(.system(size: 13))
            }
            selectableReplyMessageContent(content)
        }
    }

    private func selectableReplyMessageContent(_ content: MessageContentState) -> AnyView {
        let rendered = AnyView(MessageInlinePreviewView(
            content: content,
            highlights: highlights,
            keywordColor: keywordColor,
            token: token,
            messageFontSize: messageFontSize,
            onOpenURL: onOpenURL
        ))
        guard let text = selectableReplyText(from: content) else {
            return rendered
        }
        return selectableTextContent(text, rendered: rendered)
    }

    private func selectableTextContent(_ text: String, rendered: AnyView) -> AnyView {
        AnyView(SelectableMessageContentView(
            text: text,
            rendered: rendered,
            messageId: messageId,
            fontSize: messageFontSize,
            textColor: selectionTextColor,
            isTextSelectionActive: isSelectionActive,
            onSelectionChange: onSelectionChange
        ))
    }

    private func selectableReplyText(from content: MessageContentState) -> String? {
        switch content {
        case let .text(text):
            return text.isEmpty ? " " : text
        case let .aiStream(text, isFinished, error):
            guard isFinished else {
                return nil
            }
            return text + (error.map { "\n\($0)" } ?? "")
        case let .reply(_, boxed):
            return selectableReplyText(from: boxed.value)
        default:
            return nil
        }
    }
}

private struct MessageInlinePreviewView: View {
    var content: MessageContentState
    var highlights: [MessageTextHighlightState] = []
    var keywordColor: Color?
    var token: ChatThemeToken
    var messageFontSize: CGFloat
    var onOpenURL: (URL, String) -> Void = { _, _ in }

    var body: some View {
        switch content {
        case let .text(text):
            let displayText = text.isEmpty ? " " : text
            if ChatMessageTextRenderClassifier.kind(for: displayText, allowsMarkdown: false) == .link {
                ChatLinkTextView(
                    text: displayText,
                    token: token,
                    highlights: highlights,
                    keywordColor: keywordColor,
                    onOpenURL: onOpenURL
                )
            } else if !highlights.isEmpty {
                MessageHighlightedTextView(
                    text: displayText,
                    highlights: highlights,
                    token: token,
                    keywordColor: keywordColor
                )
            } else if ChatMessageTextRenderClassifier.kind(for: displayText, allowsMarkdown: false) == .emoticon {
                MessageEmoticonTextView(text: displayText, token: token)
            } else {
                Text(displayText)
            }
        case let .richText(title, body):
            let projectedHighlights = RichTextHighlightProjection(
                title: title,
                body: body,
                highlights: highlights
            )
            VStack(alignment: .leading, spacing: 3) {
                if let title, !title.isEmpty {
                    if !projectedHighlights.title.isEmpty,
                       ChatLinkTextView.containsLink(in: title) {
                        ChatLinkTextView(
                            text: title,
                            token: token,
                            highlights: projectedHighlights.title,
                            keywordColor: keywordColor,
                            onOpenURL: onOpenURL
                        )
                        .font(.system(size: messageFontSize, weight: .semibold))
                    } else if !projectedHighlights.title.isEmpty {
                        MessageHighlightedTextView(
                            text: title,
                            highlights: projectedHighlights.title,
                            token: token,
                            keywordColor: keywordColor
                        )
                        .font(.system(size: messageFontSize, weight: .semibold))
                    } else {
                        Text(title)
                            .font(.system(size: messageFontSize, weight: .semibold))
                    }
                }
                if !body.isEmpty {
                    if !projectedHighlights.body.isEmpty,
                       ChatLinkTextView.containsLink(in: body) {
                        ChatLinkTextView(
                            text: body,
                            token: token,
                            highlights: projectedHighlights.body,
                            keywordColor: keywordColor,
                            onOpenURL: onOpenURL
                        )
                    } else if !projectedHighlights.body.isEmpty {
                        MessageHighlightedTextView(
                            text: body,
                            highlights: projectedHighlights.body,
                            token: token,
                            keywordColor: keywordColor
                        )
                    } else {
                        switch ChatMessageTextRenderClassifier.kind(for: body, allowsMarkdown: false) {
                    case .link:
                        ChatLinkTextView(text: body, token: token, onOpenURL: onOpenURL)
                    case .emoticon:
                        MessageEmoticonTextView(text: body, token: token)
                    case .plain, .markdown:
                        Text(body)
                        }
                    }
                }
            }
        case .image:
            MessageIconLabelView(
                text: NEChatUIKitSwiftUIBundle.localized("chat_message_image", value: "[Image]"),
                imageName: "photo",
                token: token
            )
        case let .audio(audio):
            MessageIconLabelView(
                text: "\(NEChatUIKitSwiftUIBundle.localized("chat_message_audio", value: "[Audio]")) \(ChatUnitFormatter.audioDurationText(audio.duration))",
                imageName: "audio_play",
                token: token
            )
        case let .video(media):
            MessageIconLabelView(
                text: media.duration.map { "\(NEChatUIKitSwiftUIBundle.localized("chat_message_video", value: "[Video]")) \(ChatUnitFormatter.playTime($0))" } ??
                    NEChatUIKitSwiftUIBundle.localized("chat_message_video", value: "[Video]"),
                imageName: "chat_video",
                token: token
            )
        case let .file(file):
            MessageIconLabelView(text: file.name, imageName: ChatFileIconResource.imageName(for: file), token: token)
        case let .location(location):
            MessageIconLabelView(text: location.title, imageName: "chat_location", token: token)
        case let .call(call):
            MessageIconLabelView(text: call.summary, imageName: "chat_rtc", token: token)
        case let .custom(title, body):
            MessageEmoticonTextView(text: [title, body].compactMap { $0 }.joined(separator: " "), token: token)
        case let .multiForward(multiForward):
            MessageIconLabelView(text: multiForward.title, imageName: token.styleMode == .fun ? "fun_select_multiForward" : "select_multiForward", token: token)
        case let .reply(preview, boxed):
            let displayText = preview ?? ChatMessageMapper.previewText(for: boxed.value)
            switch ChatMessageTextRenderClassifier.kind(for: displayText, allowsMarkdown: false) {
            case .link:
                ChatLinkTextView(text: displayText, token: token, onOpenURL: onOpenURL)
            case .emoticon:
                MessageEmoticonTextView(text: displayText, token: token)
            case .plain, .markdown:
                Text(displayText)
            }
        case let .revoke(text), let .tip(text), let .unsupported(text):
            Text(text)
        case let .aiStream(text, _, error):
            Text([text, error].compactMap { $0 }.joined(separator: " "))
        }
    }

    private func richTextDisplayText(title: String?, body: String) -> String {
        let displayTitle = title?.isEmpty == false ? title ?? "" : ""
        let separator = !displayTitle.isEmpty && !body.isEmpty ? "\n" : ""
        return displayTitle + separator + body
    }
}

private struct RichTextHighlightProjection {
    var title: [MessageTextHighlightState]
    var body: [MessageTextHighlightState]
    var combined: [MessageTextHighlightState]

    init(title: String?, body: String, highlights: [MessageTextHighlightState]) {
        let displayTitle = title?.isEmpty == false ? title ?? "" : ""
        let separatorLength = !displayTitle.isEmpty && !body.isEmpty ? 1 : 0
        let bodyOffset = displayTitle.count + separatorLength
        let usesCombinedRanges = highlights.contains { $0.kind == .keyword }

        if usesCombinedRanges {
            self.title = Self.project(highlights, into: 0 ..< displayTitle.count, offset: 0)
            self.body = Self.project(
                highlights,
                into: bodyOffset ..< (bodyOffset + body.count),
                offset: bodyOffset
            )
            self.combined = highlights
        } else {
            self.title = []
            self.body = highlights
            self.combined = highlights.map { highlight in
                MessageTextHighlightState(
                    start: highlight.start + bodyOffset,
                    end: highlight.end + bodyOffset,
                    kind: highlight.kind
                )
            }
        }
    }

    private static func project(_ highlights: [MessageTextHighlightState],
                                into range: Range<Int>,
                                offset: Int) -> [MessageTextHighlightState] {
        highlights.compactMap { highlight in
            let lowerBound = max(highlight.start, range.lowerBound)
            let upperBound = min(highlight.end, range.upperBound)
            guard lowerBound < upperBound else {
                return nil
            }
            return MessageTextHighlightState(
                start: lowerBound - offset,
                end: upperBound - offset,
                kind: highlight.kind
            )
        }
    }
}

// MARK: - Read Receipt Progress View

private struct ReadReceiptProgressView: View {
    var progress: CGFloat
    var token: ChatThemeToken
    var size: CGFloat

    var body: some View {
        let innerSize = max(12, size - 2)
        ZStack {
            Circle()
                .stroke(token.dividerColor, lineWidth: 2)
                .frame(width: innerSize, height: innerSize)
            ReadReceiptSector(progress: progress)
                .fill(token.accentColor)
                .frame(width: innerSize, height: innerSize)
        }
        .frame(width: size, height: size)
    }
}

private struct ReadReceiptSector: Shape {
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * Double(progress)),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
