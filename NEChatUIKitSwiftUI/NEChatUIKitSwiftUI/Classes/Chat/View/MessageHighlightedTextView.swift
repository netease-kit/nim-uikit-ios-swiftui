// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct MessageHighlightedTextView: View {
  public var text: String
  public var highlights: [MessageTextHighlightState]
  public var token: ChatThemeToken
  public var baseColor: Color?
  public var keywordColor: Color?

  public init(text: String,
              highlights: [MessageTextHighlightState],
              token: ChatThemeToken,
              baseColor: Color? = nil,
              keywordColor: Color? = nil) {
    self.text = text
    self.highlights = highlights
    self.token = token
    self.baseColor = baseColor
    self.keywordColor = keywordColor
  }

  public var body: some View {
    highlightedText
  }

  private var highlightedText: Text {
    textRuns.reduce(Text("")) { partial, run in
      var segment = text(for: run)
      if let kind = run.kind {
        segment = segment.foregroundColor(color(for: kind))
      } else if let baseColor {
        segment = segment.foregroundColor(baseColor)
      }
      return partial + segment
    }
  }

  private func text(for run: HighlightedTextRun) -> Text {
    if MessageEmoticonTextView.containsEmoticon(in: run.text) {
      return MessageEmoticonTextView.text(for: run.text)
    }
    return Text(run.text)
  }

  private var textRuns: [HighlightedTextRun] {
    var runs = [HighlightedTextRun]()

    var parserCursor = text.startIndex
    for parserRun in MessageEmoticonParser.runs(from: text) {
      let runText: String
      switch parserRun.kind {
      case let .text(value):
        runText = value
      case let .emoticon(tag, _):
        runText = tag
      }

      guard let sourceRange = text.range(of: runText, range: parserCursor ..< text.endIndex) else {
        continue
      }
      let runStart = text.distance(from: text.startIndex, to: sourceRange.lowerBound)
      let runEnd = text.distance(from: text.startIndex, to: sourceRange.upperBound)
      parserCursor = sourceRange.upperBound

      switch parserRun.kind {
      case .emoticon:
        runs.append(HighlightedTextRun(text: runText, kind: highlightKind(overlapping: runStart ..< runEnd)))
      case .text:
        appendTextRuns(from: runStart, to: runEnd, into: &runs)
      }
    }

    return runs.isEmpty ? [HighlightedTextRun(text: text, kind: nil)] : runs
  }

  private func appendTextRuns(from start: Int,
                              to end: Int,
                              into runs: inout [HighlightedTextRun]) {
    var cursor = start
    for highlight in normalizedHighlights where highlight.range.overlaps(start ..< end) {
      let highlightStart = max(start, highlight.start)
      let highlightEnd = min(end, highlight.end)
      if cursor < highlightStart, let text = substring(from: cursor, to: highlightStart) {
        runs.append(HighlightedTextRun(text: text, kind: nil))
      }
      if highlightStart < highlightEnd, let text = substring(from: highlightStart, to: highlightEnd) {
        runs.append(HighlightedTextRun(text: text, kind: highlight.kind))
      }
      cursor = highlightEnd
    }

    if cursor < end, let text = substring(from: cursor, to: end) {
      runs.append(HighlightedTextRun(text: text, kind: nil))
    }
  }

  private func highlightKind(overlapping range: Range<Int>) -> MessageTextHighlightKind? {
    normalizedHighlights.first { highlight in
      highlight.range.overlaps(range)
    }?.kind
  }

  private var normalizedHighlights: [MessageTextHighlightState] {
    var result = [MessageTextHighlightState]()
    for highlight in highlights.sorted(by: { left, right in
      if left.start == right.start {
        return left.end < right.end
      }
      return left.start < right.start
    }) {
      guard highlight.start >= 0,
            highlight.start < highlight.end,
            highlight.end <= text.count,
            result.last?.range.overlaps(highlight.range) != true else {
        continue
      }
      result.append(highlight)
    }
    return result
  }

  private func substring(from start: Int, to end: Int) -> String? {
    guard start >= 0, start <= end, end <= text.count else {
      return nil
    }
    let lowerBound = text.index(text.startIndex, offsetBy: start)
    let upperBound = text.index(text.startIndex, offsetBy: end)
    return String(text[lowerBound ..< upperBound])
  }

  private func color(for kind: MessageTextHighlightKind) -> Color {
    switch kind {
    case .mention:
      return token.mentionTextColor
    case .keyword:
      return keywordColor ?? token.warningColor
    }
  }
}

private struct HighlightedTextRun: Equatable {
  var text: String
  var kind: MessageTextHighlightKind?
}
