// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

private let richTextTitleCharacterLimit = 20
private let richTextExpandedDividerTop: CGFloat = 236
private let richTextExpandedDividerHeight: CGFloat = 1
private let richTextExpandedSendButtonSize = CGSize(width: 44, height: 40)
private let richTextExpandedSendIconSize = CGSize(width: 32, height: 32)
private let richTextExpandedPanelBottomPadding: CGFloat = 12

private enum ChatInputFocusTarget: Hashable {
  case body
  case title
}

private var richTextExpandedPanelHeight: CGFloat {
  richTextExpandedDividerTop +
    richTextExpandedDividerHeight +
    8 +
    richTextExpandedSendButtonSize.height +
    richTextExpandedPanelBottomPadding
}

public struct ChatInputBarView: View {
  @Binding private var state: ChatInputState
  @State private var lastReportedInputFocused = false
  @State private var focusedInput: ChatInputFocusTarget?
  @State private var focusRequestGeneration = 0
  public var token: ChatThemeToken
  public var layout: ChatInputBarLayout
  public var defaultPlaceholder: String?
  public var morePanelTopSpacing: CGFloat
  public var onTextChange: (String) -> Void
  public var onSelectionChange: (NSRange) -> Void
  public var onRichTextTitleChange: (String) -> Void
  public var onRichTextTitleLimitReached: () -> Void
  public var onRichTextExpandedChange: (Bool) -> Void
  public var onLineBreak: () -> Void
  public var onModeChange: (ChatInputMode) -> Void
  public var onInputFocusChange: (Bool) -> Void
  public var onCancelReply: () -> Void
  public var onEmojiSelect: (ChatEmojiState) -> Void
  public var onEmojiDelete: () -> Void
  public var onMoreAction: (ChatMoreActionState) -> Void
  public var onVoiceRecordStart: () -> Void
  public var onVoiceRecordCancelChange: (Bool) -> Void
  public var onVoiceRecordEnd: (Bool) -> Void
  public var onMentionTrigger: () -> Void
  public var onSend: () -> Void

  public init(state: Binding<ChatInputState>,
              token: ChatThemeToken,
              layout: ChatInputBarLayout = ChatInputBarLayout(),
              defaultPlaceholder: String? = nil,
              morePanelTopSpacing: CGFloat = 0,
              onTextChange: @escaping (String) -> Void,
              onSelectionChange: @escaping (NSRange) -> Void = { _ in },
              onRichTextTitleChange: @escaping (String) -> Void = { _ in },
              onRichTextTitleLimitReached: @escaping () -> Void = {},
              onRichTextExpandedChange: @escaping (Bool) -> Void = { _ in },
              onLineBreak: @escaping () -> Void = {},
              onModeChange: @escaping (ChatInputMode) -> Void,
              onInputFocusChange: @escaping (Bool) -> Void = { _ in },
              onCancelReply: @escaping () -> Void = {},
              onEmojiSelect: @escaping (ChatEmojiState) -> Void = { _ in },
              onEmojiDelete: @escaping () -> Void = {},
              onMoreAction: @escaping (ChatMoreActionState) -> Void = { _ in },
              onVoiceRecordStart: @escaping () -> Void = {},
              onVoiceRecordCancelChange: @escaping (Bool) -> Void = { _ in },
              onVoiceRecordEnd: @escaping (Bool) -> Void = { _ in },
              onMentionTrigger: @escaping () -> Void = {},
              onSend: @escaping () -> Void) {
    _state = state
    self.token = token
    self.layout = layout
    self.defaultPlaceholder = defaultPlaceholder
    self.morePanelTopSpacing = morePanelTopSpacing
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onRichTextTitleChange = onRichTextTitleChange
    self.onRichTextTitleLimitReached = onRichTextTitleLimitReached
    self.onRichTextExpandedChange = onRichTextExpandedChange
    self.onLineBreak = onLineBreak
    self.onModeChange = onModeChange
    self.onInputFocusChange = onInputFocusChange
    self.onCancelReply = onCancelReply
    self.onEmojiSelect = onEmojiSelect
    self.onEmojiDelete = onEmojiDelete
    self.onMoreAction = onMoreAction
    self.onVoiceRecordStart = onVoiceRecordStart
    self.onVoiceRecordCancelChange = onVoiceRecordCancelChange
    self.onVoiceRecordEnd = onVoiceRecordEnd
    self.onMentionTrigger = onMentionTrigger
    self.onSend = onSend
  }

  public var body: some View {
    VStack(spacing: 0) {
      if state.reply != nil,
         token.styleMode == .normal,
         !state.isRichTextExpanded {
        replyBar
      }

      if state.isRichTextExpanded {
        richTextExpandedPanel
      } else {
        if token.styleMode == .normal {
          normalUILayout
        } else {
          funUILayout
          if state.reply != nil {
            replyBar
          }
        }

        if state.isEnabled && state.mode == .emoji {
          EmojiPanelView(
            emojis: state.emojis,
            token: token,
            onSelect: onEmojiSelect,
            onDelete: onEmojiDelete,
            onSend: onSend
          )
          .frame(height: bottomPanelHeight)
        } else if state.isEnabled && state.mode == .more {
          MoreActionGridView(
            actions: state.moreActions,
            token: token,
            styleMode: token.styleMode,
            onSelect: onMoreAction
          )
          .frame(height: bottomPanelHeight)
          .padding(.top, morePanelTopSpacing)
        } else if state.isEnabled && token.styleMode == .normal && state.mode == .voice {
          NormalVoiceRecordPanelView(
            state: $state,
            token: token,
            onVoiceRecordStart: onVoiceRecordStart,
            onVoiceRecordCancelChange: onVoiceRecordCancelChange,
            onVoiceRecordEnd: onVoiceRecordEnd
          )
          .frame(height: bottomPanelHeight)
        }
      }

      if state.inputRecordingOverlayVisible && shouldShowRecordingOverlay {
        VoiceRecordingOverlay(state: state.recording, token: token)
          .padding(.horizontal, 12)
          .padding(.bottom, 10)
      }
    }
    .background {
      token.inputBackground
    }
    .clipped()
    .transaction { transaction in
      transaction.disablesAnimations = true
      transaction.animation = nil
    }
    .onChange(of: state.mode) { mode in
      if mode != .text {
        collapseTextInput()
      }
    }
    .onChange(of: state.collapseRevision) { _ in
      collapseTextInput()
    }
    .onChange(of: state.focusRevision) { _ in
      guard state.isEnabled else {
        return
      }
      focusRequestGeneration &+= 1
      let generation = focusRequestGeneration
      let collapseRevision = state.collapseRevision
      focusedInput = nil
      DispatchQueue.main.async {
        guard focusRequestGeneration == generation,
              state.collapseRevision == collapseRevision,
              state.isEnabled else {
          return
        }
        focusedInput = .body
      }
    }
    .onChange(of: focusedInput) { target in
      scheduleInputFocusReport()
      guard target != nil, state.isEnabled, state.mode != .text else {
        return
      }
      onModeChange(.text)
    }
  }

  private var replyBar: some View {
    Group {
      if token.styleMode == .fun {
        HStack(spacing: 0) {
          MessageEmoticonTextView(
            text: state.reply?.displayText ?? "",
            token: token,
            baseColor: token.secondaryTextColor
          )
          .font(.system(size: 13))
          .lineLimit(2)
          .truncationMode(.tail)
          .padding(.leading, 5)

          Spacer(minLength: 0)
          replyCloseButton
            .frame(width: 40, height: 40)
        }
        .frame(height: 40)
        .background(token.replyBackground)
        .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
        .padding(.leading, 48)
        .padding(.trailing, 88)
        .padding(.bottom, 8)
      } else {
        HStack(spacing: 0) {
          replyCloseButton

          Rectangle()
            .fill(Color(hex: 0xD8DAE4))
            .frame(width: 1, height: 20)
            .padding(.trailing, 8)

          MessageEmoticonTextView(
            text: state.reply?.displayText ?? "",
            token: token,
            baseColor: token.secondaryTextColor
          )
          .font(.system(size: 13))
          .lineLimit(1)
          .truncationMode(.tail)
          Spacer()
        }
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(token.replyBackground)
      }
    }
  }

  @ViewBuilder
  private var replyCloseButton: some View {
    if token.styleMode == .fun {
      NEChatCommonPresentation.iconButton(
        imageName: "fun_chat_input_reply_clear",
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_cancel_reply", value: "Cancel reply"),
        token: token,
        renderingMode: .original,
        size: CGSize(width: 14, height: 14),
        action: onCancelReply
      )
      .frame(width: 34)
    } else {
      NEChatCommonPresentation.commonIconButton(
        imageName: "remove",
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_cancel_reply", value: "Cancel reply"),
        token: token,
        renderingMode: .original,
        action: onCancelReply
      )
      .frame(width: 34)
    }
  }

  private var normalUILayout: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        inlineTextEditor(cornerRadius: token.controlCornerRadius)
        .frame(minHeight: token.minBubbleHeight)
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, layout.containerHorizontalPadding)
      .padding(.vertical, layout.containerVerticalPadding)
      .frame(minHeight: 46)

      HStack(spacing: 0) {
        Button {
          guard state.isEnabled else { return }
          let next: ChatInputMode = state.mode == .voice ? .text : .voice
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: state.mode == .voice ? "mic_selected" : "mic",
            accessibilityLabel: state.mode == .voice
            ? NEChatUIKitSwiftUIBundle.localized("chat_input_keyboard", value: "Keyboard")
            : NEChatUIKitSwiftUIBundle.localized("chat_input_voice", value: "Voice")
          )
        }
        .disabled(!state.isEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Button {
          guard state.isEnabled else { return }
          let next: ChatInputMode = state.mode == .emoji ? .text : .emoji
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: state.mode == .emoji ? "emoji_selected" : "emoji",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_emoji", value: "Emoji")
          )
        }
        .disabled(!state.isEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Button {
          guard state.isEnabled else { return }
          if let photoAction = state.moreActions.first(where: { $0.id == .photo }) {
            setMode(.text, focusTextInput: false)
            onMoreAction(photoAction)
          }
        } label: {
          inputIcon(
            imageName: "photo",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_photo", value: "Photo")
          )
        }
        .disabled(!state.isEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Button {
          guard state.isEnabled else { return }
          let next: ChatInputMode = state.mode == .more ? .text : .more
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: state.mode == .more ? "add_selected" : "add",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_more", value: "More")
          )
        }
        .disabled(!state.isEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(height: 54)
    }
  }

  private var funUILayout: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        Button {
          guard state.isEnabled else {
            return
          }
          let next: ChatInputMode = state.mode == .voice ? .text : .voice
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: state.mode == .voice ? "fun_chat_input_keyboard" : "fun_chat_input_change_record",
            accessibilityLabel: state.mode == .voice
            ? NEChatUIKitSwiftUIBundle.localized("chat_input_keyboard", value: "Keyboard")
            : NEChatUIKitSwiftUIBundle.localized("chat_input_voice", value: "Voice")
          )
        }
        .disabled(!state.isEnabled)
        .frame(width: 48, height: 40)

        if state.mode == .voice {
          voiceButton
            .frame(height: 40)
        } else {
          inlineTextEditor(
            cornerRadius: 4,
            leadingInset: layout.textLeadingInset,
            trailingInset: layout.textTrailingInset
          )
          .frame(minHeight: token.minBubbleHeight)
          .frame(maxWidth: .infinity)
        }

        Button {
          guard state.isEnabled else {
            return
          }
          let next: ChatInputMode = state.mode == .emoji ? .text : .emoji
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: "fun_chat_input_show_emoj",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_emoji", value: "Emoji")
          )
        }
        .disabled(!state.isEnabled)
        .frame(width: 44, height: 40)

        Button {
          guard state.isEnabled else {
            return
          }
          let next: ChatInputMode = state.mode == .more ? .text : .more
          setMode(next, focusTextInput: false)
        } label: {
          inputIcon(
            imageName: "fun_chat_input_show_more",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_more", value: "More")
          )
        }
        .disabled(!state.isEnabled)
        .frame(width: 44, height: 40)
      }
      .padding(.top, 8)
      .padding(.bottom, 2)
      .frame(minHeight: 50)
    }
  }

  private func inlineTextEditor(cornerRadius: CGFloat,
                                leadingInset: CGFloat = 0,
                                trailingInset: CGFloat = 0) -> some View {
    ZStack(alignment: shouldShowRichTextTitleField ? .topTrailing : .trailing) {
      VStack(spacing: 0) {
        if shouldShowRichTextTitleField {
          richTextTitleTextField(minHeight: 40)
            .padding(.leading, leadingInset + 10)
            .padding(.trailing, trailingInset + inlineRichTextButtonReserve + 10)
        }

        ChatTextEditorView(
          text: Binding(
            get: { state.text },
            set: { if state.isEnabled { state.text = $0 } }
          ),
          isFocused: bodyFocusBinding,
          selectedRange: Binding(
            get: { state.selectedRange },
            set: { onSelectionChange($0) }
          ),
          placeholder: inputPlaceholder,
          token: token,
          validation: state.validation,
          mentions: state.mentions,
          maxVisibleLines: shouldShowRichTextTitleField
            ? 1
            : NEChatUIKitSwiftUIConstants.inputMaxVisibleLines,
          supportsRichTextMessage: shouldEnableRichTextInput,
          insertsLineBreakOnReturn: state.isRichTextExpanded,
          isEditable: state.isEnabled,
          characterLimit: state.validation.characterLimit,
          focusResetRevision: state.collapseRevision,
          usesInputChrome: false,
          onTextChange: { value in
            guard state.isEnabled else {
              return
            }
            onTextChange(value)
          },
          onMentionTrigger: {
            guard state.isEnabled else {
              return
            }
            onMentionTrigger()
          },
          onLineBreak: {
            guard state.isEnabled else {
              return
            }
            expandRichTextInput(focusTextInput: true)
            onLineBreak()
          },
          onSubmit: {
            guard state.isEnabled else {
              return
            }
            onSend()
          }
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset + inlineRichTextButtonReserve)
      }

      richTextExpandButton
    }
    .background(state.isEnabled ? token.inputFieldBackground : token.mutedInputBackground)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private var voiceButton: some View {
    Text(NEChatUIKitSwiftUIBundle.localized("fun_hold_to_talk", value: "Hold to talk"))
      .font(.system(size: 15, weight: .medium))
      .frame(maxWidth: .infinity)
      .frame(height: 38)
      .background(token.inputFieldBackground)
      .foregroundColor(Color(hex: 0x222222))
      .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard state.isEnabled else {
              return
            }
            if !state.recording.isActive {
              state.isRecording = true
              state.recording = ChatVoiceRecordingState(phase: .preparing)
              onVoiceRecordStart()
            }
            let shouldCancel = inlineVoiceShouldCancel(value)
            state.recording.phase = shouldCancel ? .cancelling : .recording
            onVoiceRecordCancelChange(shouldCancel)
          }
          .onEnded { value in
            guard state.isEnabled else {
              return
            }
            let shouldCancel = inlineVoiceShouldCancel(value)
            state.isRecording = false
            state.recording.phase = shouldCancel ? .cancelling : .finishing
            onVoiceRecordEnd(shouldCancel)
          }
      )
      .opacity(state.isEnabled ? 1 : 0.55)
      .buttonStyle(.plain)
  }

  private var richTextExpandedPanel: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        richTextExpandedTitleField
          .frame(height: 40)
          .padding(.leading, 16)
          .padding(.trailing, 12)

        Button {
          guard state.isEnabled else {
            return
          }
          collapseRichTextInput()
        } label: {
          NEChatCommonPresentation.iconView(
            imageName: richTextFoldImageName,
            token: token,
            renderingMode: .original,
            size: CGSize(width: 20, height: 20),
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_input_keyboard", value: "Keyboard")
          )
          .frame(width: 44, height: 40)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .frame(width: 44, height: 40)
      }
      .frame(height: 40)
      .padding(.top, 5)

      ChatTextEditorView(
        text: Binding(
          get: { state.text },
          set: { if state.isEnabled { state.text = $0 } }
        ),
        isFocused: bodyFocusBinding,
        selectedRange: Binding(
          get: { state.selectedRange },
          set: { onSelectionChange($0) }
        ),
        placeholder: inputPlaceholder,
        token: token,
        validation: state.validation,
        mentions: state.mentions,
        minVisibleLines: 7,
        maxVisibleLines: 7,
        supportsRichTextMessage: IMKitConfigCenter.shared.enableRichTextMessage,
        insertsLineBreakOnReturn: true,
        isEditable: state.isEnabled,
        characterLimit: state.validation.characterLimit,
        focusResetRevision: state.collapseRevision,
        usesInputChrome: false,
        onTextChange: { value in
          guard state.isEnabled else {
            return
          }
          onTextChange(value)
        },
        onMentionTrigger: {
          guard state.isEnabled else {
            return
          }
          onMentionTrigger()
        },
        onLineBreak: {
          guard state.isEnabled else {
            return
          }
          onLineBreak()
        },
        onSubmit: {
          guard state.isEnabled else {
            return
          }
          onSend()
        }
      )
      .frame(height: 183)
      .padding(.leading, 13)
      .padding(.trailing, 16)
      .padding(.top, 3)

      Spacer(minLength: 0)
        .frame(height: 5)

      Rectangle()
        .fill(Color(hex: 0xECECEC))
        .frame(height: richTextExpandedDividerHeight)

      HStack(spacing: 0) {
        Spacer(minLength: 0)
        Button {
          guard state.isEnabled else {
            return
          }
          onSend()
        } label: {
          NEChatCommonPresentation.iconView(
            imageName: "multiple_send_image",
            token: token,
            renderingMode: .original,
            size: richTextExpandedSendIconSize,
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("send", value: "Send")
          )
          .frame(width: richTextExpandedSendButtonSize.width,
                 height: richTextExpandedSendButtonSize.height,
                 alignment: .center)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .frame(width: richTextExpandedSendButtonSize.width,
               height: richTextExpandedSendButtonSize.height,
               alignment: .center)
        .padding(.trailing, 16)
      }
      .frame(height: richTextExpandedSendButtonSize.height)
      .padding(.top, 8)

      Spacer(minLength: 0)
        .frame(height: richTextExpandedPanelBottomPadding)
    }
    .frame(height: richTextExpandedPanelHeight)
    .background(
      RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous)
        .fill(token.inputFieldBackground)
        .shadow(color: Color.black.opacity(0.5), radius: 5, x: 3, y: 3)
    )
    .padding(.top, 4)
  }

  private var richTextExpandedTitleField: some View {
    richTextTitleTextField(minHeight: 40)
  }

  private func richTextTitleTextField(minHeight: CGFloat) -> some View {
    NEChatLimitedTextField(
      text: Binding(
        get: { state.richTextTitle },
        set: updateRichTextTitle
      ),
      isFocused: richTextTitleFocusBinding,
      placeholder: NEChatUIKitSwiftUIBundle.localized("multiple_line_placleholder", value: "Enter title"),
      characterLimit: richTextTitleCharacterLimit,
      fontSize: 18,
      textColor: token.incomingTextColor,
      tintColor: token.accentColor,
      returnKeyType: .send,
      accessibilityIdentifier: "chat.richText.title",
      isEnabled: state.isEnabled,
      focusResetRevision: state.collapseRevision,
      onSubmit: {
        guard state.isEnabled else {
          return
        }
        onSend()
      },
      onLimitReached: onRichTextTitleLimitReached
    )
    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    .clipped()
  }

  private var richTextTitleFocusBinding: Binding<Bool> {
    Binding(
      get: { focusedInput == .title },
      set: { focused in
        if focused {
          focusedInput = .title
        } else if focusedInput == .title {
          focusedInput = nil
        }
      }
    )
  }

  private func updateRichTextTitle(_ value: String) {
    guard state.isEnabled else {
      return
    }
    let limitedValue = NECommonTextLimit.limitedUTF16(value, limit: richTextTitleCharacterLimit)
    state.richTextTitle = limitedValue
    onRichTextTitleChange(limitedValue)
  }

  @ViewBuilder
  private var richTextExpandButton: some View {
    if shouldEnableRichTextInput {
      Button {
        guard state.isEnabled else {
          return
        }
        if state.isRichTextExpanded {
          collapseRichTextInput()
        } else {
          expandRichTextInput(focusTextInput: false)
        }
      } label: {
        NEChatCommonPresentation.iconView(
          imageName: state.isRichTextExpanded ? richTextFoldImageName : richTextUnfoldImageName,
          token: token,
          renderingMode: .original,
          size: CGSize(width: 20, height: 20),
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("multiple_line_placleholder", value: "Enter title")
        )
        .frame(width: 44, height: 40)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!state.isEnabled)
      .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("multiple_line_placleholder", value: "Enter title"))
    }
  }

  private var inputPlaceholder: String {
    if let placeholder = state.placeholder ?? defaultPlaceholder {
      return placeholder
    }
    if token.styleMode == .fun {
      return NEChatUIKitSwiftUIBundle.localized(
        "fun_chat_input_placeholder",
        value: "Enter what you want to say..."
      )
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "chat_input_placeholder",
      value: "Message"
    )
  }

  private var shouldEnableRichTextInput: Bool {
    IMKitConfigCenter.shared.enableRichTextMessage
  }

  private var inlineRichTextButtonReserve: CGFloat {
    shouldEnableRichTextInput ? 44 : 0
  }

  private var shouldShowRichTextTitleField: Bool {
    shouldEnableRichTextInput && !state.richTextTitle.isEmpty
  }

  private var richTextFoldImageName: String {
    token.styleMode == .fun ? "fun_input_fold" : "normal_input_fold"
  }

  private var richTextUnfoldImageName: String {
    token.styleMode == .fun ? "fun_input_unfold" : "normal_input_unfold"
  }

  private func expandRichTextInput(focusTextInput: Bool) {
    withoutShortcutButtonAnimation {
      state.isRichTextExpanded = true
      onRichTextExpandedChange(true)
      if focusTextInput {
        state.mode = .text
        focusedInput = .body
        onModeChange(.text)
      }
    }
  }

  private func collapseRichTextInput() {
    withoutShortcutButtonAnimation {
      state.isRichTextExpanded = false
      onRichTextExpandedChange(false)
      focusedInput = nil
    }
  }

  private func setMode(_ mode: ChatInputMode, focusTextInput: Bool = false) {
    withoutShortcutButtonAnimation {
      if mode == .text, focusTextInput {
        focusedInput = .body
      } else {
        collapseTextInput()
      }
      resetRecordingIfNeeded()
      state.mode = mode
      onModeChange(mode)
    }
  }

  private func collapseTextInput() {
    focusRequestGeneration &+= 1
    withoutShortcutButtonAnimation {
      focusedInput = nil
    }
    DispatchQueue.main.async {
      withoutShortcutButtonAnimation {
        focusedInput = nil
      }
    }
  }

  private var bodyFocusBinding: Binding<Bool> {
    Binding(
      get: { focusedInput == .body },
      set: { focused in
        if focused {
          if state.mode != .text {
            onModeChange(.text)
          }
          focusedInput = .body
        } else if focusedInput == .body {
          focusedInput = nil
        }
      }
    )
  }

  private func scheduleInputFocusReport() {
    DispatchQueue.main.async {
      reportInputFocusIfNeeded(focusedInput != nil)
    }
  }

  private func reportInputFocusIfNeeded(_ focused: Bool) {
    guard lastReportedInputFocused != focused else {
      return
    }
    lastReportedInputFocused = focused
    onInputFocusChange(focused)
  }

  private func withoutShortcutButtonAnimation(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)
  }

  private func resetRecordingIfNeeded() {
    guard state.recording.isActive || state.isRecording else {
      return
    }
    state.isRecording = false
    state.recording = ChatVoiceRecordingState()
  }

  private func inputIcon(imageName: String,
                         selectedImageName: String? = nil,
                         isSelected: Bool = false,
                         imageSize: CGSize? = nil,
                         accessibilityLabel: String) -> some View {
    NEChatCommonPresentation.iconView(
      imageName: (isSelected ? selectedImageName : nil) ?? imageName,
      token: token,
      renderingMode: .original,
      size: imageSize ?? inputIconImageSize,
      accessibilityLabel: accessibilityLabel
    )
    .frame(width: NEChatUIKitSwiftUIConstants.inputIconSize.width,
           height: NEChatUIKitSwiftUIConstants.inputIconSize.height)
    .contentShape(Rectangle())
  }

  private var inputIconImageSize: CGSize {
    token.styleMode == .fun ? CGSize(width: 24, height: 24) : CGSize(width: 28, height: 28)
  }

  private var bottomPanelHeight: CGFloat {
    token.panelMaxHeight
  }

  private var shouldShowRecordingOverlay: Bool {
    token.styleMode == .normal && state.mode != .voice
  }

  private func inlineVoiceShouldCancel(_ value: DragGesture.Value) -> Bool {
    let threshold: CGFloat = state.recording.phase == .cancelling ? -28 : -56
    return value.translation.height < threshold
  }
}

private struct NormalVoiceRecordPanelView: View {
  @Binding var state: ChatInputState
  @State private var recordGestureStartedInside = false
  @State private var recordGestureCancelling = false
  var token: ChatThemeToken
  var onVoiceRecordStart: () -> Void
  var onVoiceRecordCancelChange: (Bool) -> Void
  var onVoiceRecordEnd: (Bool) -> Void
  private let recordImageSize: CGFloat = 103
  private let tipHeight: CGFloat = 23
  private let verticalSpacing: CGFloat = 12
  private let cancelReentryPadding: CGFloat = 12

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: verticalSpacing) {
        Text(topTipText)
          .font(.system(size: 12))
          .foregroundColor(tipColor)
          .frame(height: tipHeight)
          .opacity(state.recording.isActive ? 1 : 0)

        recordImage
          .frame(width: recordImageSize, height: recordImageSize)
          .contentShape(Rectangle())

        Text(bottomTipText)
          .font(.system(size: 12))
          .foregroundColor(tipColor)
          .frame(height: tipHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(recordGesture(recordFrame: recordImageFrame(in: geometry.size)))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(token.pageBackground)
  }

  @ViewBuilder
  private var recordImage: some View {
    if isRecordAnimating {
      TimelineView(.periodic(from: .now, by: 0.27)) { context in
        recordImageView(imageName: recordAnimationImageName(at: context.date))
      }
    } else {
      recordImageView(imageName: state.recording.isActive ? activeRecordImageName : "chat_record")
    }
  }

  private func recordImageView(imageName: String) -> some View {
    NEChatCommonPresentation.iconView(
      imageName: imageName,
      token: token,
      renderingMode: .original,
      size: CGSize(width: recordImageSize, height: recordImageSize),
      accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_hold_to_talk", value: "Hold to talk")
    )
  }

  private func recordGesture(recordFrame: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard state.isEnabled else {
          return
        }
        if !recordGestureStartedInside {
          guard recordFrame.contains(value.startLocation) else {
            return
          }
          recordGestureStartedInside = true
        }
        if !state.recording.isActive {
          state.isRecording = true
          state.recording = ChatVoiceRecordingState(phase: .preparing)
          onVoiceRecordStart()
        }
        updateRecordCancelling(
          shouldCancelRecordGesture(value, recordFrame: recordFrame),
          ending: false
        )
      }
      .onEnded { value in
        guard state.isEnabled else {
          resetRecordGestureState()
          return
        }
        guard recordGestureStartedInside else {
          resetRecordGestureState()
          return
        }
        let shouldCancel = shouldCancelRecordGesture(value, recordFrame: recordFrame)
        state.isRecording = false
        state.recording.phase = shouldCancel ? .cancelling : .finishing
        recordGestureCancelling = shouldCancel
        onVoiceRecordEnd(shouldCancel)
        resetRecordGestureState()
      }
  }

  private func shouldCancelRecordGesture(_ value: DragGesture.Value,
                                         recordFrame: CGRect) -> Bool {
    let activeFrame = recordGestureCancelling
      ? recordFrame.insetBy(dx: cancelReentryPadding, dy: cancelReentryPadding)
      : recordFrame
    return !activeFrame.contains(value.location)
  }

  private func updateRecordCancelling(_ cancelling: Bool, ending: Bool) {
    recordGestureCancelling = cancelling
    state.recording.phase = cancelling ? .cancelling : (ending ? .finishing : .recording)
    onVoiceRecordCancelChange(cancelling)
  }

  private func resetRecordGestureState() {
    recordGestureStartedInside = false
    recordGestureCancelling = false
  }

  private func recordImageFrame(in size: CGSize) -> CGRect {
    let contentHeight = tipHeight * 2 + recordImageSize + verticalSpacing * 2
    let contentTop = max(0, (size.height - contentHeight) / 2)
    return CGRect(
      x: max(0, (size.width - recordImageSize) / 2),
      y: contentTop + tipHeight + verticalSpacing,
      width: recordImageSize,
      height: recordImageSize
    )
  }

  private var isRecordAnimating: Bool {
    switch state.recording.phase {
    case .preparing, .recording:
      return true
    case .idle, .cancelling, .finishing, .failed:
      return false
    }
  }

  private func recordAnimationImageName(at date: Date) -> String {
    let images = ["record_3", "record_2", "record_1"]
    let index = Int(date.timeIntervalSinceReferenceDate / 0.27) % images.count
    return images[index]
  }

  private var activeRecordImageName: String {
    switch state.recording.phase {
    case .cancelling:
      return "record_1"
    case .preparing, .recording:
      return "record_3"
    case .idle, .finishing, .failed:
      return "chat_record"
    }
  }

  private var topTipText: String {
    switch state.recording.phase {
    case .idle, .preparing, .recording, .cancelling, .finishing:
      return NEChatUIKitSwiftUIBundle.localized("send_after_let_go", value: "Release to send")
    case .failed(let message):
      return message
    }
  }

  private var bottomTipText: String {
    switch state.recording.phase {
    case .failed(let message):
      return message
    case .idle, .preparing, .recording, .cancelling, .finishing:
      return NEChatUIKitSwiftUIBundle.localized("press_speak", value: "Hold to Talk")
    }
  }

  private var tipColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.lightText
  }
}

private struct VoiceRecordingOverlay: View {
  var state: ChatVoiceRecordingState
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.system(size: 12))
        .foregroundColor(textColor)

      NEChatCommonPresentation.linearProgress(
        value: state.progress.level,
        token: token,
        foregroundColor: textColor,
        accessibilityLabel: title
      )

      Text(durationText)
        .font(.system(size: 12))
        .foregroundColor(token.secondaryTextColor)
    }
    .padding(10)
    .background(token.pageBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
  }

  private var title: String {
    switch state.phase {
    case .preparing:
      return NEChatUIKitSwiftUIBundle.localized("chat_recording_preparing", value: "Preparing")
    case .recording:
      return NEChatUIKitSwiftUIBundle.localized("release_to_send", value: "Release to send")
    case .cancelling:
      return NEChatUIKitSwiftUIBundle.localized("release_to_cancel", value: "Release to cancel")
    case .finishing:
      return NEChatUIKitSwiftUIBundle.localized("chat_recording_finishing", value: "Finishing")
    case .failed(let message):
      return message
    case .idle:
      return NEChatUIKitSwiftUIBundle.localized("chat_hold_to_talk", value: "Hold to talk")
    }
  }

  private var textColor: Color {
    state.phase == .cancelling ? token.warningColor : token.accentColor
  }

  private var durationText: String {
    if let remainingTime = state.progress.remainingTime, remainingTime > 0 {
      return ChatUnitFormatter.recordingStopText(remainingTime: remainingTime)
    }
    return ChatUnitFormatter.audioDurationText(state.progress.duration)
  }
}

private extension ChatInputState {
  var inputRecordingOverlayVisible: Bool {
    recording.isActive
  }
}
