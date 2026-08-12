// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI
import UIKit

public struct NEChatLimitedTextField: UIViewRepresentable {
  @Binding private var text: String
  @Binding private var isFocused: Bool
  private let placeholder: String
  private let characterLimit: Int?
  private let fontSize: CGFloat
  private let textColor: Color
  private let tintColor: Color?
  private let keyboardType: UIKeyboardType
  private let returnKeyType: UIReturnKeyType
  private let clearButtonMode: UITextField.ViewMode
  private let accessibilityIdentifier: String?
  private let isEnabled: Bool
  private let focusResetRevision: Int
  private let onSubmit: (() -> Void)?
  private let onLimitReached: (() -> Void)?

  public init(text: Binding<String>,
              isFocused: Binding<Bool> = .constant(false),
              placeholder: String = "",
              characterLimit: Int? = nil,
              fontSize: CGFloat = 16,
              textColor: Color = .primary,
              tintColor: Color? = nil,
              keyboardType: UIKeyboardType = .default,
              returnKeyType: UIReturnKeyType = .done,
              clearButtonMode: UITextField.ViewMode = .never,
              accessibilityIdentifier: String? = nil,
              isEnabled: Bool = true,
              focusResetRevision: Int = 0,
              onSubmit: (() -> Void)? = nil,
              onLimitReached: (() -> Void)? = nil) {
    _text = text
    _isFocused = isFocused
    self.placeholder = placeholder
    self.characterLimit = characterLimit
    self.fontSize = fontSize
    self.textColor = textColor
    self.tintColor = tintColor
    self.keyboardType = keyboardType
    self.returnKeyType = returnKeyType
    self.clearButtonMode = clearButtonMode
    self.accessibilityIdentifier = accessibilityIdentifier
    self.isEnabled = isEnabled
    self.focusResetRevision = focusResetRevision
    self.onSubmit = onSubmit
    self.onLimitReached = onLimitReached
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeUIView(context: Context) -> UITextField {
    let textField = UITextField()
    context.coordinator.attach(textField)
    textField.delegate = context.coordinator
    textField.borderStyle = .none
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.addTarget(
      context.coordinator,
      action: #selector(Coordinator.textDidChange(_:)),
      for: .editingChanged
    )
    return textField
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiView: UITextField,
                           context: Context) -> CGSize? {
    guard let proposedWidth = proposal.width else {
      return nil
    }
    let height = proposal.height ?? uiView.intrinsicContentSize.height
    return CGSize(width: max(0, proposedWidth), height: max(0, height))
  }

  public static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
    coordinator.detach(uiView)
  }

  public func updateUIView(_ textField: UITextField, context: Context) {
    context.coordinator.parent = self
    if textField.markedTextRange == nil, textField.text != text {
      textField.text = text
    }
    textField.placeholder = placeholder
    textField.font = .systemFont(ofSize: fontSize)
    textField.textColor = UIColor(textColor)
    textField.tintColor = tintColor.map(UIColor.init)
    textField.keyboardType = keyboardType
    textField.returnKeyType = returnKeyType
    textField.clearButtonMode = clearButtonMode
    textField.accessibilityIdentifier = accessibilityIdentifier
    textField.isEnabled = isEnabled
    context.coordinator.acceptCurrentTextIfValid(textField)
    context.coordinator.updateFocus(of: textField)
  }

  public final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: NEChatLimitedTextField
    private var requestedFocus: Bool?
    private weak var mountedTextField: UITextField?
    private var focusUpdateGeneration = 0
    private var lastFocusResetRevision: Int?
    private var normalizationGeneration = 0
    private var lastAcceptedText: String

    init(parent: NEChatLimitedTextField) {
      self.parent = parent
      lastAcceptedText = parent.text
    }

    func attach(_ textField: UITextField) {
      mountedTextField = textField
      requestedFocus = nil
    }

    func detach(_ textField: UITextField) {
      guard mountedTextField === textField else {
        return
      }
      focusUpdateGeneration += 1
      mountedTextField = nil
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
      guard mountedTextField === textField else {
        return
      }
      focusUpdateGeneration += 1
      requestedFocus = true
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
      guard mountedTextField === textField else {
        return
      }
      focusUpdateGeneration += 1
      let generation = focusUpdateGeneration
      DispatchQueue.main.async { [weak self, weak textField] in
        guard let self,
              let textField,
              self.mountedTextField === textField,
              self.focusUpdateGeneration == generation,
              !textField.isFirstResponder else {
          return
        }
        self.requestedFocus = false
        if self.parent.isFocused {
          self.parent.isFocused = false
        }
      }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      parent.onSubmit?()
      textField.resignFirstResponder()
      return false
    }

    public func textFieldShouldClear(_ textField: UITextField) -> Bool {
      parent.text = ""
      return true
    }

    public func textFieldDidChangeSelection(_ textField: UITextField) {
      scheduleNormalization(for: textField)
    }

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
      guard textField.markedTextRange == nil,
            let limit = parent.characterLimit,
            limit >= 0 else {
        return true
      }
      let current = textField.text ?? ""
      guard let swiftRange = Range(range, in: current) else {
        return true
      }
      let retainedLength = max(0, current.utf16.count - range.length)
      let availableLength = max(0, limit - retainedLength)
      guard string.utf16.count > availableLength else {
        return true
      }

      let acceptedReplacement = NECommonTextLimit.limitedUTF16(string, limit: availableLength)
      let next = current.replacingCharacters(in: swiftRange, with: acceptedReplacement)
      textField.text = next
      setSelection(
        NSRange(location: range.location + acceptedReplacement.utf16.count, length: 0),
        in: textField
      )
      lastAcceptedText = next
      parent.text = next
      parent.onLimitReached?()
      return false
    }

    @objc func textDidChange(_ textField: UITextField) {
      scheduleNormalization(for: textField)
    }

    private func scheduleNormalization(for textField: UITextField) {
      normalizationGeneration += 1
      let generation = normalizationGeneration
      if textField.markedTextRange == nil {
        normalize(textField)
        return
      }
      // UIKit's editingChanged callback can arrive one run loop before the
      // committed IME candidate clears markedTextRange. Recheck after commit
      // so the visible UITextField is truncated immediately, not only on save.
      DispatchQueue.main.async { [weak self, weak textField] in
        guard let self,
              let textField,
              self.normalizationGeneration == generation,
              textField.markedTextRange == nil else {
          return
        }
        self.normalize(textField)
      }
    }

    private func normalize(_ textField: UITextField) {
      let value = textField.text ?? ""
      guard let limit = parent.characterLimit,
            limit >= 0,
            value.utf16.count > limit else {
        lastAcceptedText = value
        if parent.text != value {
          parent.text = value
        }
        return
      }

      let normalized = limitedCommittedText(value, limit: limit)
      if value != normalized.text {
        textField.text = normalized.text
        setSelection(NSRange(location: normalized.caretOffset, length: 0), in: textField)
        parent.onLimitReached?()
      }
      lastAcceptedText = normalized.text
      if parent.text != normalized.text {
        parent.text = normalized.text
      }
    }

    func acceptCurrentTextIfValid(_ textField: UITextField) {
      guard mountedTextField === textField,
            textField.markedTextRange == nil else {
        return
      }
      let value = textField.text ?? ""
      guard parent.characterLimit.map({ value.utf16.count <= $0 }) ?? true else {
        return
      }
      lastAcceptedText = value
    }

    private func limitedCommittedText(_ value: String, limit: Int) -> (text: String, caretOffset: Int) {
      let previousCharacters = Array(lastAcceptedText)
      let currentCharacters = Array(value)
      var prefixCount = 0
      while prefixCount < previousCharacters.count,
            prefixCount < currentCharacters.count,
            previousCharacters[prefixCount] == currentCharacters[prefixCount] {
        prefixCount += 1
      }

      var suffixCount = 0
      while suffixCount < previousCharacters.count - prefixCount,
            suffixCount < currentCharacters.count - prefixCount,
            previousCharacters[previousCharacters.count - suffixCount - 1] ==
            currentCharacters[currentCharacters.count - suffixCount - 1] {
        suffixCount += 1
      }

      let prefix = String(currentCharacters.prefix(prefixCount))
      let suffix = suffixCount > 0 ? String(currentCharacters.suffix(suffixCount)) : ""
      let replacementEnd = currentCharacters.count - suffixCount
      let replacement = String(currentCharacters[prefixCount ..< replacementEnd])
      let availableLength = max(0, limit - prefix.utf16.count - suffix.utf16.count)
      let acceptedReplacement = NECommonTextLimit.limitedUTF16(replacement, limit: availableLength)
      let normalized = prefix + acceptedReplacement + suffix

      if normalized.utf16.count <= limit {
        return (normalized, prefix.utf16.count + acceptedReplacement.utf16.count)
      }
      let fallback = NECommonTextLimit.limitedUTF16(value, limit: limit)
      return (fallback, fallback.utf16.count)
    }

    private func setSelection(_ range: NSRange, in textField: UITextField) {
      guard let start = textField.position(from: textField.beginningOfDocument, offset: range.location),
            let end = textField.position(from: start, offset: range.length) else {
        return
      }
      textField.selectedTextRange = textField.textRange(from: start, to: end)
    }

    func updateFocus(of textField: UITextField) {
      guard mountedTextField === textField else {
        return
      }
      if let lastFocusResetRevision,
         lastFocusResetRevision != parent.focusResetRevision {
        self.lastFocusResetRevision = parent.focusResetRevision
        focusUpdateGeneration += 1
        requestedFocus = false
        if textField.isFirstResponder {
          textField.resignFirstResponder()
        }
        return
      }
      lastFocusResetRevision = parent.focusResetRevision
      guard parent.isEnabled else {
        focusUpdateGeneration += 1
        requestedFocus = false
        if textField.isFirstResponder {
          textField.resignFirstResponder()
        }
        return
      }
      let shouldFocus = parent.isFocused
      guard requestedFocus != shouldFocus || textField.isFirstResponder != shouldFocus else {
        return
      }
      requestedFocus = shouldFocus
      focusUpdateGeneration += 1
      let generation = focusUpdateGeneration
      DispatchQueue.main.async { [weak self, weak textField] in
        guard let self,
              let textField,
              self.mountedTextField === textField,
              self.focusUpdateGeneration == generation,
              self.parent.isEnabled,
              self.parent.isFocused == shouldFocus else {
          return
        }
        if shouldFocus, !textField.isFirstResponder {
          textField.becomeFirstResponder()
        } else if !shouldFocus, textField.isFirstResponder {
          textField.resignFirstResponder()
        }
      }
    }
  }
}

public struct ChatTextEditorView: View {
  @Binding private var text: String
  @Binding private var isFocused: Bool
  @Binding private var selectedRange: NSRange
  @State private var measuredTextHeight = NEChatUIKitSwiftUIConstants.inputMinHeight

  public var placeholder: String
  public var token: ChatThemeToken
  public var validation: ChatInputValidationState
  public var mentions: [ChatMentionState]
  public var minVisibleLines: Int
  public var maxVisibleLines: Int
  public var supportsRichTextMessage: Bool
  public var insertsLineBreakOnReturn: Bool
  public var isEditable: Bool
  public var characterLimit: Int?
  public var focusResetRevision: Int
  public var usesInputChrome: Bool
  public var onTextChange: (String) -> Void
  public var onMentionTrigger: () -> Void
  public var onLineBreak: () -> Void
  public var onSubmit: () -> Void

  public init(text: Binding<String>,
              isFocused: Binding<Bool> = .constant(false),
              selectedRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0)),
              placeholder: String,
              token: ChatThemeToken,
              validation: ChatInputValidationState = ChatInputValidationState(),
              mentions: [ChatMentionState] = [],
              minVisibleLines: Int = NEChatUIKitSwiftUIConstants.inputMinVisibleLines,
              maxVisibleLines: Int = NEChatUIKitSwiftUIConstants.inputMaxVisibleLines,
              supportsRichTextMessage: Bool = true,
              insertsLineBreakOnReturn: Bool = false,
              isEditable: Bool = true,
              characterLimit: Int? = nil,
              focusResetRevision: Int = 0,
              usesInputChrome: Bool = true,
              onTextChange: @escaping (String) -> Void,
              onMentionTrigger: @escaping () -> Void = {},
              onLineBreak: @escaping () -> Void = {},
              onSubmit: @escaping () -> Void = {}) {
    _text = text
    _isFocused = isFocused
    _selectedRange = selectedRange
    self.placeholder = placeholder
    self.token = token
    self.validation = validation
    self.mentions = mentions
    self.minVisibleLines = minVisibleLines
    self.maxVisibleLines = max(minVisibleLines, maxVisibleLines)
    self.supportsRichTextMessage = supportsRichTextMessage
    self.insertsLineBreakOnReturn = insertsLineBreakOnReturn
    self.isEditable = isEditable
    self.characterLimit = characterLimit
    self.focusResetRevision = focusResetRevision
    self.usesInputChrome = usesInputChrome
    self.onTextChange = onTextChange
    self.onMentionTrigger = onMentionTrigger
    self.onLineBreak = onLineBreak
    self.onSubmit = onSubmit
  }

  public var body: some View {
    VStack(alignment: .trailing, spacing: 3) {
      ZStack(alignment: .topLeading) {
        richTextEditor
        .frame(height: editorHeight)
        .background(measurementView)
        .opacity(isEditable ? 1 : 0.64)
        .contextMenu {
          if supportsRichTextMessage {
            Button(NEChatUIKitSwiftUIBundle.localized("line_break", value: "Line break")) {
              insertLineBreak()
            }
          }
        }
        if text.isEmpty {
          Text(placeholder)
            .font(.system(size: 16))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
      }
      .background(usesInputChrome ? token.inputFieldBackground : Color.clear)
      .clipShape(RoundedRectangle(
        cornerRadius: usesInputChrome ? token.controlCornerRadius : 0,
        style: .continuous
      ))

      if validation.shouldShowCounter {
        NEChatCommonPresentation.characterCounter(
          count: validation.characterCount,
          limit: validation.characterLimit,
          token: token,
          isWarning: validation.isOverLimit
        )
          .padding(.trailing, 2)
      }
    }
    .onPreferenceChange(ChatTextEditorHeightPreferenceKey.self) { height in
      scheduleMeasuredTextHeightUpdate(height)
    }
    .onChange(of: isEditable) { editable in
      if !editable {
        isFocused = false
      }
    }
  }

  private var measurementView: some View {
    MessageEmoticonTextView(text: measurementText, token: token, baseColor: token.incomingTextColor)
      .font(.system(size: 16))
      .lineLimit(effectiveMinVisibleLines...effectiveMaxVisibleLines)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        GeometryReader { proxy in
          Color.clear.preference(
            key: ChatTextEditorHeightPreferenceKey.self,
            value: proxy.size.height
          )
        }
      )
      .hidden()
  }

  private var richTextEditor: some View {
    ChatRichTextEditor(
      text: inputTextBinding,
      selectedRange: $selectedRange,
      isFocused: $isFocused,
      mentions: mentions,
      isEditable: isEditable,
      focusResetRevision: focusResetRevision,
      textColor: UIColor(token.incomingTextColor),
      mentionColor: UIColor(token.mentionTextColor),
      tintColor: UIColor(token.accentColor)
    )
  }

  private var inputTextBinding: Binding<String> {
    Binding(
      get: { text },
      set: { value in
        guard isEditable else {
          return
        }
        let previousText = text
        if shouldSubmitOnReturn(previousText: previousText, nextText: value) {
          if insertsLineBreakOnReturn {
            let limitedValue = NECommonTextLimit.limitedUTF16(value, limit: characterLimit)
            onTextChange(limitedValue)
            onLineBreak()
            return
          }
          submitCurrentText(previousText)
          return
        }
        let nextValue = supportsRichTextMessage ? value : value.replacingOccurrences(of: "\n", with: " ")
        let limitedValue = NECommonTextLimit.limitedUTF16(nextValue, limit: characterLimit)
        onTextChange(limitedValue)
        if limitedValue.count == previousText.count + 1,
           limitedValue.hasSuffix("@") || insertedSingleCharacter(from: previousText, to: limitedValue) == "@" {
          onMentionTrigger()
        }
      }
    )
  }

  private var editorHeight: CGFloat {
    min(max(measuredTextHeight, minHeight), maxHeight)
  }

  private func scheduleMeasuredTextHeightUpdate(_ height: CGFloat) {
    guard abs(measuredTextHeight - height) > 0.5 else {
      return
    }
    DispatchQueue.main.async {
      guard abs(measuredTextHeight - height) > 0.5 else {
        return
      }
      measuredTextHeight = height
    }
  }

  private var minHeight: CGFloat {
    CGFloat(effectiveMinVisibleLines) * NEChatUIKitSwiftUIConstants.inputTextLineHeight +
      NEChatUIKitSwiftUIConstants.inputTextVerticalPadding
  }

  private var maxHeight: CGFloat {
    CGFloat(effectiveMaxVisibleLines) * NEChatUIKitSwiftUIConstants.inputTextLineHeight +
      NEChatUIKitSwiftUIConstants.inputTextVerticalPadding
  }

  private var effectiveMaxVisibleLines: Int {
    supportsRichTextMessage ? max(maxVisibleLines, minVisibleLines) : 1
  }

  private var effectiveMinVisibleLines: Int {
    supportsRichTextMessage ? max(1, minVisibleLines) : 1
  }

  private var measurementText: String {
    if text.isEmpty {
      return " "
    }
    if text.hasSuffix("\n") {
      return text + " "
    }
    return text
  }

  private var shouldShowParsedText: Bool {
    isEditable && (!mentionHighlights.isEmpty || MessageEmoticonTextView.containsEmoticon(in: text))
  }

  private var mentionHighlights: [MessageTextHighlightState] {
    mentions.compactMap { mention in
      ChatMessageMapper.mentionHighlightRange(
        start: mention.start,
        end: mention.end,
        displayText: mention.displayText,
        in: text
      )
    }
  }

  private func insertedSingleCharacter(from previousText: String,
                                       to nextText: String) -> Character? {
    guard nextText.count == previousText.count + 1 else {
      return nil
    }
    let previousCharacters = Array(previousText)
    let nextCharacters = Array(nextText)
    var index = 0
    while index < previousCharacters.count,
          previousCharacters[index] == nextCharacters[index] {
      index += 1
    }
    return nextCharacters[index]
  }

  private func shouldSubmitOnReturn(previousText: String,
                                    nextText: String) -> Bool {
    insertedSingleCharacter(from: previousText, to: nextText) == "\n"
  }

  private func submitCurrentText(_ currentText: String) {
    let limitedText = NECommonTextLimit.limitedUTF16(currentText, limit: characterLimit)
    onTextChange(limitedText)
    onSubmit()
  }

  private func insertLineBreak() {
    let range = boundedSelection(in: text)
    let editedText = (text as NSString).replacingCharacters(in: range, with: "\n")
    let nextText = NECommonTextLimit.limitedUTF16(editedText, limit: characterLimit)
    selectedRange = NSRange(
      location: min(range.location + 1, nextText.utf16.count),
      length: 0
    )
    onTextChange(nextText)
    onLineBreak()
    isFocused = true
  }

  private func boundedSelection(in value: String) -> NSRange {
    let utf16Length = value.utf16.count
    let location = min(max(0, selectedRange.location), utf16Length)
    let length = min(max(0, selectedRange.length), utf16Length - location)
    return NSRange(location: location, length: length)
  }
}

private struct ChatRichTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  @Binding var isFocused: Bool
  var mentions: [ChatMentionState]
  var isEditable: Bool
  var focusResetRevision: Int
  var textColor: UIColor
  var mentionColor: UIColor
  var tintColor: UIColor

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 16)
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    textView.textContainer.lineFragmentPadding = 0
    textView.returnKeyType = .send
    textView.isScrollEnabled = true
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    textView.isEditable = isEditable
    textView.tintColor = tintColor
    textView.typingAttributes = ChatInputAttributedTextMapper.attributes(
      textColor: textColor
    )

    let renderedText = ChatInputAttributedTextMapper.rawText(from: textView.attributedText)
    if renderedText != text || context.coordinator.renderedMentions != mentions {
      context.coordinator.isApplyingState = true
      textView.attributedText = ChatInputAttributedTextMapper.attributedText(
        from: text,
        mentions: mentions,
        textColor: textColor,
        mentionColor: mentionColor
      )
      context.coordinator.renderedMentions = mentions
      context.coordinator.isApplyingState = false
    }

    if context.coordinator.pendingLocalText != nil,
       context.coordinator.pendingLocalText != text {
      context.coordinator.pendingLocalText = nil
      context.coordinator.pendingLocalSelection = nil
    }
    let isReflectingLocalEdit = context.coordinator.pendingLocalText == text
    if !isReflectingLocalEdit {
      let rawRange = ChatInputAttributedTextMapper.bounded(selectedRange, in: text)
      let displayRange = ChatInputAttributedTextMapper.displayRange(
        forRawRange: rawRange,
        in: textView.attributedText
      )
      if textView.selectedRange != displayRange {
        context.coordinator.isApplyingState = true
        textView.selectedRange = displayRange
        textView.scrollRangeToVisible(displayRange)
        context.coordinator.isApplyingState = false
      }
    } else if context.coordinator.pendingLocalSelection == selectedRange {
      context.coordinator.pendingLocalText = nil
      context.coordinator.pendingLocalSelection = nil
    }

    context.coordinator.updateFocus(of: textView)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: ChatRichTextEditor
    var isApplyingState = false
    var renderedMentions = [ChatMentionState]()
    var pendingLocalText: String?
    var pendingLocalSelection: NSRange?
    private var lastRequestedFocus: Bool?
    private var lastFocusResetRevision: Int?

    init(_ parent: ChatRichTextEditor) {
      self.parent = parent
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      if !parent.isFocused {
        parent.isFocused = true
      }
      syncSelection(textView)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      syncSelection(textView)
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self = self,
              let textView = textView,
              textView.window != nil,
              !textView.isFirstResponder else {
          return
        }
        self.parent.isFocused = false
      }
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
      guard parent.isEditable else {
        return false
      }
      if !parent.isFocused {
        parent.isFocused = true
      }
      return true
    }

    func textViewDidChange(_ textView: UITextView) {
      guard !isApplyingState else {
        return
      }
      let value = ChatInputAttributedTextMapper.rawText(from: textView.attributedText)
      let selection = rawSelection(in: textView)
      pendingLocalText = value
      pendingLocalSelection = selection
      parent.text = value
      parent.selectedRange = selection
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      guard ChatInputAttributedTextMapper.rawText(from: textView.attributedText) == parent.text else {
        return
      }
      syncSelection(textView)
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
      textView.typingAttributes = ChatInputAttributedTextMapper.attributes(
        textColor: parent.textColor
      )
      return true
    }

    func updateFocus(of textView: UITextView) {
      if let lastFocusResetRevision,
         lastFocusResetRevision != parent.focusResetRevision {
        self.lastFocusResetRevision = parent.focusResetRevision
        lastRequestedFocus = false
        if textView.isFirstResponder {
          textView.resignFirstResponder()
        }
        return
      }
      lastFocusResetRevision = parent.focusResetRevision
      guard parent.isEditable else {
        lastRequestedFocus = false
        if textView.isFirstResponder {
          textView.resignFirstResponder()
        }
        return
      }
      guard let lastRequestedFocus else {
        self.lastRequestedFocus = parent.isFocused
        if parent.isFocused, !textView.isFirstResponder {
          textView.becomeFirstResponder()
        }
        return
      }
      guard lastRequestedFocus != parent.isFocused else {
        return
      }
      self.lastRequestedFocus = parent.isFocused
      if parent.isFocused {
        if !textView.isFirstResponder {
          textView.becomeFirstResponder()
        }
      } else if textView.isFirstResponder {
        textView.resignFirstResponder()
      }
    }

    private func syncSelection(_ textView: UITextView) {
      guard !isApplyingState else {
        return
      }
      let range = rawSelection(in: textView)
      guard parent.selectedRange != range else {
        return
      }
      parent.selectedRange = range
    }

    private func rawSelection(in textView: UITextView) -> NSRange {
      ChatInputAttributedTextMapper.rawRange(
        forDisplayRange: textView.selectedRange,
        in: textView.attributedText
      )
    }
  }
}

private enum ChatInputAttributedTextMapper {
  private static let emoticonTagKey = NSAttributedString.Key("com.netease.nim.chatEmoticonTag")
  private static let font = UIFont.systemFont(ofSize: 16)

  static func attributes(textColor: UIColor) -> [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: textColor,
    ]
  }

  static func attributedText(from rawText: String,
                             mentions: [ChatMentionState],
                             textColor: UIColor,
                             mentionColor: UIColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for run in MessageEmoticonParser.runs(from: rawText) {
      switch run.kind {
      case let .text(value):
        result.append(NSAttributedString(string: value, attributes: attributes(textColor: textColor)))
      case let .emoticon(tag, fileName):
        guard let resource = MessageEmoticonCatalog.shared.imageResource(named: fileName) else {
          result.append(NSAttributedString(string: tag, attributes: attributes(textColor: textColor)))
          continue
        }
        let attachment = NSTextAttachment()
        attachment.image = UIImage(
          cgImage: resource.cgImage,
          scale: resource.scale,
          orientation: .up
        )
        attachment.bounds = CGRect(x: 0, y: -3, width: 18, height: 18)
        let value = NSMutableAttributedString(attachment: attachment)
        value.addAttributes([
          emoticonTagKey: tag,
          .font: font,
        ], range: NSRange(location: 0, length: value.length))
        result.append(value)
      }
    }

    for mention in mentions {
      guard let rawRange = rawRange(for: mention, in: rawText) else {
        continue
      }
      let range = displayRange(forRawRange: rawRange, in: result)
      guard NSMaxRange(range) <= result.length else {
        continue
      }
      result.addAttribute(.foregroundColor, value: mentionColor, range: range)
    }
    return result
  }

  static func rawText(from attributedText: NSAttributedString?) -> String {
    guard let attributedText, attributedText.length > 0 else {
      return ""
    }
    var result = ""
    attributedText.enumerateAttribute(
      emoticonTagKey,
      in: NSRange(location: 0, length: attributedText.length)
    ) { value, range, _ in
      if let tag = value as? String {
        result += String(repeating: tag, count: range.length)
      } else {
        result += attributedText.attributedSubstring(from: range).string
      }
    }
    return result
  }

  static func bounded(_ range: NSRange, in text: String) -> NSRange {
    let length = text.utf16.count
    let location = min(max(0, range.location), length)
    return NSRange(
      location: location,
      length: min(max(0, range.length), length - location)
    )
  }

  static func displayRange(forRawRange range: NSRange,
                           in attributedText: NSAttributedString) -> NSRange {
    let start = displayLocation(forRawLocation: range.location, in: attributedText)
    let end = displayLocation(forRawLocation: NSMaxRange(range), in: attributedText)
    return NSRange(location: start, length: max(0, end - start))
  }

  static func rawRange(forDisplayRange range: NSRange,
                       in attributedText: NSAttributedString) -> NSRange {
    let start = rawLocation(forDisplayLocation: range.location, in: attributedText)
    let end = rawLocation(forDisplayLocation: NSMaxRange(range), in: attributedText)
    return NSRange(location: start, length: max(0, end - start))
  }

  private static func displayLocation(forRawLocation location: Int,
                                      in attributedText: NSAttributedString) -> Int {
    var rawCursor = 0
    var displayCursor = 0
    var resolved = 0
    attributedText.enumerateAttribute(
      emoticonTagKey,
      in: NSRange(location: 0, length: attributedText.length)
    ) { value, range, stop in
      let tag = value as? String
      let tagLength = tag?.utf16.count ?? 0
      let rawLength = tag == nil ? range.length : tagLength * range.length
      if location <= rawCursor + rawLength {
        if tag == nil {
          resolved = displayCursor + max(0, location - rawCursor)
        } else {
          let relativeLocation = max(0, location - rawCursor)
          let completedAttachments = tagLength > 0 ? relativeLocation / tagLength : 0
          let isInsideTag = tagLength > 0 && relativeLocation % tagLength != 0
          resolved = displayCursor + min(
            range.length,
            completedAttachments + (isInsideTag ? 1 : 0)
          )
        }
        stop.pointee = true
        return
      }
      rawCursor += rawLength
      displayCursor += range.length
      resolved = displayCursor
    }
    return min(max(0, resolved), attributedText.length)
  }

  private static func rawLocation(forDisplayLocation location: Int,
                                  in attributedText: NSAttributedString) -> Int {
    var rawCursor = 0
    var resolved = 0
    attributedText.enumerateAttribute(
      emoticonTagKey,
      in: NSRange(location: 0, length: attributedText.length)
    ) { value, range, stop in
      let tag = value as? String
      let tagLength = tag?.utf16.count ?? 0
      let rawLength = tag == nil ? range.length : tagLength * range.length
      if location <= NSMaxRange(range) {
        let displayOffset = min(max(0, location - range.location), range.length)
        resolved = tag == nil
          ? rawCursor + displayOffset
          : rawCursor + displayOffset * tagLength
        stop.pointee = true
        return
      }
      rawCursor += rawLength
      resolved = rawCursor
    }
    return max(0, resolved)
  }

  private static func rawRange(for mention: ChatMentionState,
                               in text: String) -> NSRange? {
    let end = mention.end + 1
    guard mention.start >= 0,
          mention.start < end,
          end <= text.utf16.count else {
      return nil
    }
    return NSRange(location: mention.start, length: end - mention.start)
  }
}

private struct ChatTextEditorHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = NEChatUIKitSwiftUIConstants.inputMinHeight

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
