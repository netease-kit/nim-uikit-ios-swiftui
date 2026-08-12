// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI
import UIKit

struct SelectableMessageTextOverlay: UIViewRepresentable {
  var text: String
  var fontSize: CGFloat
  var textColor: UIColor
  var isSelectionActive: Bool
  var onSelectionChange: (String?, Bool) -> Void

  func makeUIView(context: Context) -> SelectableMessageUITextView {
    let textView = SelectableMessageUITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.isScrollEnabled = false
    textView.showsHorizontalScrollIndicator = false
    textView.showsVerticalScrollIndicator = false
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.textContainer.maximumNumberOfLines = 0
    textView.contentInset = .zero
    textView.tintColor = .systemBlue
    textView.clipsToBounds = false
    textView.accessibilityElementsHidden = true
    return textView
  }

  func updateUIView(_ textView: SelectableMessageUITextView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self

    // SwiftUI remains the visual source of truth. TextKit is transparent and
    // only supplies the native selection range, handles, and highlight.
    let rendersContent = false
    let needsContentUpdate = coordinator.rawText != text ||
      abs(coordinator.fontSize - fontSize) > 0.1 ||
      coordinator.rendersContent != rendersContent ||
      !coordinator.textColor.isEqual(textColor)
    if needsContentUpdate {
      coordinator.rawText = text
      coordinator.fontSize = fontSize
      coordinator.rendersContent = rendersContent
      coordinator.textColor = textColor
      coordinator.isApplyingSelection = true
      textView.attributedText = SelectableMessageTextMapper.attributedText(
        from: text,
        fontSize: fontSize,
        textColor: textColor,
        rendersContent: rendersContent,
        displayScale: textView.traitCollection.displayScale
      )
      coordinator.isApplyingSelection = false
    }

    textView.isUserInteractionEnabled = isSelectionActive
    if isSelectionActive {
      coordinator.activateSelection(
        in: textView,
        selectingAll: needsContentUpdate || !coordinator.wasSelectionActive
      )
    } else if coordinator.wasSelectionActive {
      coordinator.deactivateSelection(in: textView)
    }
    coordinator.wasSelectionActive = isSelectionActive
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func sizeThatFits(_ proposal: ProposedViewSize,
                    uiView: SelectableMessageUITextView,
                    context: Context) -> CGSize? {
    guard let width = proposal.width,
          let height = proposal.height else {
      return nil
    }
    return CGSize(width: width, height: height)
  }

  static func dismantleUIView(_ textView: SelectableMessageUITextView,
                              coordinator: Coordinator) {
    coordinator.cancelPendingActivation()
    coordinator.cancelPendingNotification()
    textView.onDidMoveToWindow = nil
    textView.delegate = nil
    textView.resignFirstResponder()
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: SelectableMessageTextOverlay
    var rawText = ""
    var fontSize: CGFloat = 0
    var rendersContent = false
    var textColor: UIColor = .label
    var wasSelectionActive = false
    var isApplyingSelection = false
    private var isActivatingSelection = false
    private var hasActivatedSelection = false
    private var selectsAllOnNextActivation = false
    private var notificationGeneration = 0

    init(parent: SelectableMessageTextOverlay) {
      self.parent = parent
    }

    func activateSelection(in textView: SelectableMessageUITextView, selectingAll: Bool) {
      selectsAllOnNextActivation = selectsAllOnNextActivation || selectingAll
      guard !hasActivatedSelection || selectsAllOnNextActivation else {
        return
      }
      guard !isActivatingSelection else {
        return
      }
      guard textView.window != nil else {
        textView.onDidMoveToWindow = { [weak self, weak textView] in
          guard let self, let textView else {
            return
          }
          self.activateSelection(in: textView, selectingAll: false)
        }
        return
      }

      textView.onDidMoveToWindow = nil
      isActivatingSelection = true
      if selectsAllOnNextActivation {
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let visibleLength = textView.text.utf16.count
        let fullRange = NSRange(
          location: 0,
          length: min(visibleLength, textView.textStorage.length)
        )
        isApplyingSelection = true
        textView.selectedRange = fullRange
        isApplyingSelection = false
        publishSelection(textView.selectedRange, attributedText: textView.attributedText)
      }
      _ = textView.becomeFirstResponder()
      selectsAllOnNextActivation = false
      hasActivatedSelection = true
      isActivatingSelection = false
    }

    func deactivateSelection(in textView: SelectableMessageUITextView) {
      cancelPendingActivation()
      cancelPendingNotification()
      isApplyingSelection = true
      textView.selectedRange = NSRange(location: 0, length: 0)
      isApplyingSelection = false
      textView.resignFirstResponder()
      hasActivatedSelection = false
      parent.onSelectionChange(nil, false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      guard parent.isSelectionActive,
            !isApplyingSelection,
            !isActivatingSelection else {
        return
      }
      let displayRange = textView.selectedRange
      publishSelection(displayRange, attributedText: textView.attributedText)
    }

    func cancelPendingActivation() {
      selectsAllOnNextActivation = false
      hasActivatedSelection = false
      isActivatingSelection = false
    }

    func cancelPendingNotification() {
      notificationGeneration += 1
    }

    private func publishSelection(_ displayRange: NSRange,
                                  attributedText: NSAttributedString) {
      let rawRange = SelectableMessageTextMapper.rawRange(
        forDisplayRange: displayRange,
        in: attributedText
      )
      let rawLength = rawText.utf16.count
      let selectedText: String?
      if rawRange.length > 0,
         rawRange.location >= 0,
         NSMaxRange(rawRange) <= rawLength {
        selectedText = (rawText as NSString).substring(with: rawRange)
      } else {
        selectedText = nil
      }
      let isFullSelection = rawRange == NSRange(location: 0, length: rawLength)
      notificationGeneration += 1
      let generation = notificationGeneration
      DispatchQueue.main.async { [weak self] in
        guard let self,
              self.notificationGeneration == generation,
              self.parent.isSelectionActive else {
          return
        }
        self.parent.onSelectionChange(selectedText, isFullSelection)
      }
    }
  }
}

final class SelectableMessageUITextView: UITextView {
  var onDidMoveToWindow: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else {
      return
    }
    onDidMoveToWindow?()
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    false
  }

  override func addSubview(_ view: UIView) {
    let className = String(describing: type(of: view))
    if !className.contains("ScrollIndicator") {
      super.addSubview(view)
    }
  }
}

private enum SelectableMessageTextMapper {
  private static let emoticonTagKey = NSAttributedString.Key("com.netease.nim.selectableMessageEmoticonTag")
  private static let transparentAttachmentImage = UIGraphicsImageRenderer(
    size: CGSize(width: 1, height: 1)
  ).image { _ in }

  static func attributedText(from rawText: String,
                             fontSize: CGFloat,
                             textColor: UIColor,
                             rendersContent: Bool,
                             displayScale: CGFloat) -> NSAttributedString {
    let font = UIFont.systemFont(ofSize: fontSize)
    let paragraphStyle = NSMutableParagraphStyle()
    // Match SwiftUI Text and the UIKit example's UITextView behavior. Character
    // wrapping can split CJK punctuation from its preceding character, shifting
    // the final selection handle even though the complete range is selected.
    paragraphStyle.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: rendersContent ? textColor : UIColor.clear,
      .paragraphStyle: paragraphStyle,
    ]
    let result = NSMutableAttributedString()

    for run in MessageEmoticonParser.runs(from: rawText) {
      switch run.kind {
      case let .text(value):
        result.append(NSAttributedString(string: value, attributes: attributes))
      case let .emoticon(tag, fileName):
        guard let resource = MessageEmoticonCatalog.shared.imageResource(named: fileName) else {
          result.append(NSAttributedString(string: tag, attributes: attributes))
          continue
        }
        let attachmentSize = MessageEmoticonTextView.emoticonDisplaySize(named: fileName) ??
          CGSize(width: font.lineHeight, height: font.lineHeight)
        let baselineOffset = MessageEmoticonTextView.emoticonLayoutBaselineOffset
        // SwiftUI baselineOffset expands only the lines containing an Image.
        // Match that footprint while leaving half a pixel for SwiftUI rounding.
        let pixelTolerance = 0.5 / max(displayScale, 1)
        let selectionAttachmentHeight = max(
          attachmentSize.height,
          attachmentSize.height + abs(baselineOffset) * 2 - pixelTolerance
        )
        let attachment = NSTextAttachment()
        attachment.image = rendersContent
          ? UIImage(cgImage: resource.cgImage, scale: resource.scale, orientation: .up)
          : transparentAttachmentImage
        attachment.bounds = CGRect(
          x: 0,
          y: baselineOffset,
          width: attachmentSize.width,
          height: rendersContent ? attachmentSize.height : selectionAttachmentHeight
        )
        let value = NSMutableAttributedString(attachment: attachment)
        value.addAttributes([
          emoticonTagKey: tag,
          .font: font,
          .foregroundColor: rendersContent ? textColor : UIColor.clear,
          .paragraphStyle: paragraphStyle,
        ], range: NSRange(location: 0, length: value.length))
        result.append(value)
      }
    }
    return result
  }

  static func rawRange(forDisplayRange range: NSRange,
                       in attributedText: NSAttributedString) -> NSRange {
    let start = rawLocation(forDisplayLocation: range.location, in: attributedText)
    let end = rawLocation(forDisplayLocation: NSMaxRange(range), in: attributedText)
    return NSRange(location: start, length: max(0, end - start))
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

}
