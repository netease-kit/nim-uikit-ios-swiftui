// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI

public struct ChatLinkTextView: View {
  public var text: String
  public var token: ChatThemeToken
  public var baseColor: Color?
  public var highlights: [MessageTextHighlightState]
  public var keywordColor: Color?
  public var maxLines: Int?
  public var onOpenURL: (URL, String) -> Void

  public init(text: String,
              token: ChatThemeToken,
              baseColor: Color? = nil,
              highlights: [MessageTextHighlightState] = [],
              keywordColor: Color? = nil,
              maxLines: Int? = nil,
              onOpenURL: @escaping (URL, String) -> Void) {
    self.text = text
    self.token = token
    self.baseColor = baseColor
    self.highlights = highlights
    self.keywordColor = keywordColor
    self.maxLines = maxLines
    self.onOpenURL = onOpenURL
  }

  public static func containsLink(in text: String) -> Bool {
    guard ChatLinkTextParser.mayContainLink(in: text) else {
      return false
    }
    return ChatLinkTextParser.runs(from: text).contains { $0.url != nil }
  }

  public var body: some View {
    let tokens = renderTokens
    if tokens.contains(where: { $0.url != nil }) {
      renderedText(tokens)
        .foregroundColor(baseColor)
        .lineLimit(maxLines)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, OpenURLAction { url in
          let displayText = tokens.first(where: { $0.url == url })?.accessibilityText
            ?? url.absoluteString
          onOpenURL(url, displayText)
          return .handled
        })
        .accessibilityLabel(text)
    } else {
      Text(text)
        .foregroundColor(baseColor)
        .lineLimit(maxLines)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var renderTokens: [ChatLinkTextToken] {
    ChatLinkTextParser.tokens(from: text, highlights: highlights)
  }

  private func renderedText(_ tokens: [ChatLinkTextToken]) -> Text {
    var result = Text("")
    for renderToken in tokens {
      guard let url = renderToken.url else {
        result = result + MessageEmoticonTextView
          .text(for: renderToken.text)
          .foregroundColor(color(for: renderToken.highlightKind))
        continue
      }
      var value = AttributedString(renderToken.text)
      value.link = url
      value.foregroundColor = token.mentionTextColor
      value.underlineStyle = .single
      result = result + Text(value)
    }
    return result
  }

  private func color(for kind: MessageTextHighlightKind?) -> Color? {
    switch kind {
    case .mention:
      return token.mentionTextColor
    case .keyword:
      return keywordColor ?? token.warningColor
    case .none:
      return baseColor
    }
  }

}

private struct ChatLinkTextRun: Equatable {
  var text: String
  var url: URL?
  var originalRange: Range<Int>?
}

private struct ChatLinkTextToken: Identifiable, Equatable {
  var id: String
  var text: String
  var url: URL?
  var originalRange: Range<Int>?
  var highlightKind: MessageTextHighlightKind?
  var accessibilityText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private enum ChatLinkTextParser {
  private static let runsCache = NSCache<NSString, ChatLinkTextRunsBox>()
  private static let tokensCache = NSCache<NSString, ChatLinkTextTokensBox>()
  private static let markdownLinkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\((\\S+?)(?=\\))\\)", options: [])
  private static let maxManualLinkCandidateUTF16Length = 2_048
  private static let leadingLinkTrimCharacters = CharacterSet(charactersIn: "([{<\"'")
  private static let trailingLinkTrimCharacters = CharacterSet(charactersIn: ".,;:!?)]}>\"'，。！？；：、")
  private static let manualLinkRegexes: [NSRegularExpression] = [
    try? NSRegularExpression(
      pattern: #"[a-z][a-z0-9+.-]{1,31}://[^\s<>"'，。！？；、,;]+"#,
      options: [.caseInsensitive]
    ),
    try? NSRegularExpression(
      pattern: #"www\.[^\s<>"'，。！？；、,;]+"#,
      options: [.caseInsensitive]
    ),
    try? NSRegularExpression(
      pattern: #"[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+"#,
      options: [.caseInsensitive]
    ),
    try? NSRegularExpression(
      pattern: #"(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?::[0-9]{1,5})?(?:/[^\s<>"'，。！？；、,;]*)?"#,
      options: []
    ),
    try? NSRegularExpression(
      pattern: #"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?(?::[0-9]{1,5})?(?:/[^\s<>"'，。！？；、,;]*)?"#,
      options: [.caseInsensitive]
    ),
    try? NSRegularExpression(
      pattern: #"\+?[0-9][0-9()\-]{3,}[0-9]"#,
      options: []
    ),
  ].compactMap { $0 }

  static func mayContainLink(in text: String) -> Bool {
    mayContainMarkdownLink(in: text) || mayContainAutomaticLink(in: text)
  }

  static func runs(from text: String) -> [ChatLinkTextRun] {
    guard !text.isEmpty else {
      return [ChatLinkTextRun(text: text, url: nil, originalRange: 0 ..< 0)]
    }

    let cacheKey = text as NSString
    if let cached = runsCache.object(forKey: cacheKey) {
      return cached.runs
    }

    let result = parsedRuns(from: text)
    runsCache.setObject(ChatLinkTextRunsBox(result), forKey: cacheKey)
    return result
  }

  private static func parsedRuns(from text: String) -> [ChatLinkTextRun] {
    guard mayContainLink(in: text) else {
      return plainRun(text, baseOffset: 0)
    }

    guard mayContainMarkdownLink(in: text), let regex = markdownLinkRegex else {
      return automaticRuns(from: text, baseOffset: 0)
    }

    let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
    var result = [ChatLinkTextRun]()
    var cursor = text.startIndex

    for match in regex.matches(in: text, options: [], range: fullRange) {
      guard let matchRange = Range(match.range, in: text),
            matchRange.lowerBound >= cursor,
            let titleRange = Range(match.range(at: 1), in: text),
            let linkRange = Range(match.range(at: 2), in: text),
            let url = makeURL(from: String(text[linkRange])) else {
        continue
      }

      if cursor < matchRange.lowerBound {
        let prefix = String(text[cursor ..< matchRange.lowerBound])
        result.append(contentsOf: automaticRuns(from: prefix, baseOffset: text.distance(from: text.startIndex, to: cursor)))
      }

      result.append(ChatLinkTextRun(
        text: String(text[titleRange]),
        url: url,
        originalRange: text.distance(from: text.startIndex, to: titleRange.lowerBound) ..< text.distance(from: text.startIndex, to: titleRange.upperBound)
      ))
      cursor = matchRange.upperBound
    }

    if cursor < text.endIndex {
      let suffix = String(text[cursor ..< text.endIndex])
      result.append(contentsOf: automaticRuns(from: suffix, baseOffset: text.distance(from: text.startIndex, to: cursor)))
    }

    return result.isEmpty ? automaticRuns(from: text, baseOffset: 0) : result
  }

  static func tokens(from text: String,
                     highlights: [MessageTextHighlightState]) -> [ChatLinkTextToken] {
    let cacheKey = tokenCacheKey(text: text, highlights: highlights)
    if let cached = tokensCache.object(forKey: cacheKey) {
      return cached.tokens
    }

    var tokens = [ChatLinkTextToken]()
    var index = 0

    for run in runs(from: text) {
      for part in tokenParts(from: run, highlights: highlights) {
        tokens.append(ChatLinkTextToken(
          id: "\(index)-\(part.text.hashValue)",
          text: part.text,
          url: run.url,
          originalRange: part.originalRange,
          highlightKind: highlightKind(for: part.originalRange, highlights: highlights)
        ))
        index += 1
      }
    }

    let result = tokens.isEmpty
      ? [ChatLinkTextToken(id: "empty", text: text, url: nil, originalRange: nil, highlightKind: nil)]
      : tokens
    tokensCache.setObject(ChatLinkTextTokensBox(result), forKey: cacheKey)
    return result
  }

  private static func automaticRuns(from text: String,
                                    baseOffset: Int) -> [ChatLinkTextRun] {
    guard !text.isEmpty else {
      return []
    }

    guard mayContainAutomaticLink(in: text) else {
      return plainRun(text, baseOffset: baseOffset)
    }

    var result = [ChatLinkTextRun]()
    var runBaseOffset = baseOffset

    for run in MessageEmoticonParser.runs(from: text) {
      switch run.kind {
      case let .text(value):
        appendRuns(
          automaticRunsInText(value, baseOffset: runBaseOffset),
          to: &result
        )
        runBaseOffset += value.count
      case let .emoticon(tag, _):
        appendRuns(plainRun(tag, baseOffset: runBaseOffset), to: &result)
        runBaseOffset += tag.count
      }
    }

    return result.isEmpty ? plainRun(text, baseOffset: baseOffset) : result
  }

  private static func automaticRunsInText(_ text: String,
                                          baseOffset: Int) -> [ChatLinkTextRun] {
    guard mayContainAutomaticLink(in: text) else {
      return plainRun(text, baseOffset: baseOffset)
    }

    var result = [ChatLinkTextRun]()
    var segmentStart = text.startIndex

    while segmentStart < text.endIndex {
      let separatorSegment = isAutomaticCandidateSeparator(text[segmentStart])
      var segmentEnd = text.index(after: segmentStart)
      while segmentEnd < text.endIndex,
            isAutomaticCandidateSeparator(text[segmentEnd]) == separatorSegment {
        segmentEnd = text.index(after: segmentEnd)
      }

      let segmentRange = segmentStart ..< segmentEnd
      if separatorSegment {
        appendPlainRun(text, range: segmentRange, baseOffset: baseOffset, to: &result)
      } else {
        appendRuns(
          automaticRunsInCandidate(
            String(text[segmentRange]),
            baseOffset: baseOffset + text.distance(from: text.startIndex, to: segmentRange.lowerBound)
          ),
          to: &result
        )
      }
      segmentStart = segmentEnd
    }

    return result.isEmpty ? plainRun(text, baseOffset: baseOffset) : result
  }

  private static func automaticRunsInCandidate(_ text: String,
                                               baseOffset: Int) -> [ChatLinkTextRun] {
    guard mayContainAutomaticLink(in: text) else {
      return plainRun(text, baseOffset: baseOffset)
    }
    return manualAutomaticRuns(from: text, baseOffset: baseOffset)
  }

  private static func manualAutomaticRuns(from text: String,
                                          baseOffset: Int) -> [ChatLinkTextRun] {
    let matches = manualLinkMatches(in: text)
    guard !matches.isEmpty else {
      return plainRun(text, baseOffset: baseOffset)
    }

    var result = [ChatLinkTextRun]()
    var cursor = text.startIndex
    for match in matches {
      if cursor < match.range.lowerBound {
        appendPlainRun(text, range: cursor ..< match.range.lowerBound, baseOffset: baseOffset, to: &result)
      }
      appendRun(ChatLinkTextRun(
        text: String(text[match.range]),
        url: match.url,
        originalRange: absoluteRange(in: text, range: match.range, baseOffset: baseOffset)
      ), to: &result)
      cursor = match.range.upperBound
    }
    if cursor < text.endIndex {
      appendPlainRun(text, range: cursor ..< text.endIndex, baseOffset: baseOffset, to: &result)
    }
    return result
  }

  private static func manualLinkMatches(in text: String) -> [ManualLinkMatch] {
    guard text.utf16.count <= maxManualLinkCandidateUTF16Length else {
      return []
    }

    let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
    var candidates = [ManualLinkMatch]()
    for regex in manualLinkRegexes {
      for match in regex.matches(in: text, options: [], range: fullRange) {
        guard let matchRange = Range(match.range, in: text),
              let linkRange = trimmedLinkCandidateRange(in: text, candidateRange: matchRange),
              let url = manualURL(from: String(text[linkRange])) else {
          continue
        }
        candidates.append(ManualLinkMatch(range: linkRange, url: url))
      }
    }

    let sorted = candidates.sorted { lhs, rhs in
      if lhs.range.lowerBound == rhs.range.lowerBound {
        return lhs.range.upperBound > rhs.range.upperBound
      }
      return lhs.range.lowerBound < rhs.range.lowerBound
    }
    var result = [ManualLinkMatch]()
    var cursor = text.startIndex
    for match in sorted where match.range.lowerBound >= cursor {
      result.append(match)
      cursor = match.range.upperBound
    }
    return result
  }

  private static func tokenParts(from run: ChatLinkTextRun,
                                 highlights: [MessageTextHighlightState]) -> [ChatLinkTextRun] {
    guard !run.text.isEmpty,
          let originalRange = run.originalRange else {
      return [run]
    }
    var boundaries: Set<Int> = [0, run.text.count]
    for highlight in highlights where highlight.start < highlight.end {
      let lower = max(originalRange.lowerBound, highlight.start)
      let upper = min(originalRange.upperBound, highlight.end)
      guard lower < upper else {
        continue
      }
      boundaries.insert(lower - originalRange.lowerBound)
      boundaries.insert(upper - originalRange.lowerBound)
    }
    let sortedBoundaries = boundaries
      .filter { $0 >= 0 && $0 <= run.text.count }
      .sorted()
    guard sortedBoundaries.count > 2 else {
      return [run]
    }

    return zip(sortedBoundaries, sortedBoundaries.dropFirst()).compactMap { pair in
      let (lower, upper) = pair
      guard lower < upper else {
        return nil
      }
      let lowerIndex = run.text.index(run.text.startIndex, offsetBy: lower)
      let upperIndex = run.text.index(run.text.startIndex, offsetBy: upper)
      return ChatLinkTextRun(
        text: String(run.text[lowerIndex ..< upperIndex]),
        url: run.url,
        originalRange: originalRange.lowerBound + lower ..< originalRange.lowerBound + upper
      )
    }
  }

  private static func manualURL(from value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    if trimmed.range(of: "://") != nil ||
      trimmed.range(of: "www.", options: [.caseInsensitive]) != nil {
      return makeURL(from: normalizedWebURLString(trimmed))
    }

    if trimmed.contains("@"), isEmailCandidate(trimmed) {
      return URL(string: "mailto:\(trimmed)")
    }

    let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
    if digits.count >= 5,
       trimmed.unicodeScalars.allSatisfy({ isPhoneCandidateScalar($0) }) {
      return URL(string: "tel:\(trimmed)")
    }

    if trimmed.contains("."), hasDomainLikeSeparator(in: trimmed) {
      return makeURL(from: normalizedWebURLString(trimmed))
    }

    return nil
  }

  private static func makeURL(from value: String) -> URL? {
    URL(string: value)
      ?? value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
  }

  private static func normalizedWebURLString(_ value: String) -> String {
    if value.range(of: "://") != nil {
      return value
    }
    return "https://\(value)"
  }

  private static func absoluteRange(in text: String,
                                    range: Range<String.Index>,
                                    baseOffset: Int) -> Range<Int> {
    baseOffset + text.distance(from: text.startIndex, to: range.lowerBound) ..< baseOffset + text.distance(from: text.startIndex, to: range.upperBound)
  }

  private static func highlightKind(for range: Range<Int>?,
                                    highlights: [MessageTextHighlightState]) -> MessageTextHighlightKind? {
    guard let range = range else {
      return nil
    }
    return highlights.first { highlight in
      highlight.start < highlight.end && highlight.range.overlaps(range)
    }?.kind
  }

  private static func plainRun(_ text: String,
                               baseOffset: Int) -> [ChatLinkTextRun] {
    [ChatLinkTextRun(text: text, url: nil, originalRange: baseOffset ..< baseOffset + text.count)]
  }

  private static func appendPlainRun(_ text: String,
                                     range: Range<String.Index>,
                                     baseOffset: Int,
                                     to result: inout [ChatLinkTextRun]) {
    guard !range.isEmpty else {
      return
    }
    appendRun(ChatLinkTextRun(
      text: String(text[range]),
      url: nil,
      originalRange: absoluteRange(in: text, range: range, baseOffset: baseOffset)
    ), to: &result)
  }

  private static func appendRuns(_ runs: [ChatLinkTextRun],
                                 to result: inout [ChatLinkTextRun]) {
    runs.forEach { appendRun($0, to: &result) }
  }

  private static func appendRun(_ run: ChatLinkTextRun,
                                to result: inout [ChatLinkTextRun]) {
    guard !run.text.isEmpty else {
      return
    }
    if let last = result.last,
       last.url == nil,
       run.url == nil,
       let lastRange = last.originalRange,
       let runRange = run.originalRange,
       lastRange.upperBound == runRange.lowerBound {
      result[result.count - 1] = ChatLinkTextRun(
        text: last.text + run.text,
        url: nil,
        originalRange: lastRange.lowerBound ..< runRange.upperBound
      )
      return
    }
    result.append(run)
  }

  private static func mayContainMarkdownLink(in text: String) -> Bool {
    text.contains("[") && text.contains("](") && text.contains(")")
  }

  private static func mayContainAutomaticLink(in text: String) -> Bool {
    if text.range(of: "://") != nil ||
      text.range(of: "www.", options: [.caseInsensitive]) != nil ||
      text.contains("@") {
      return true
    }
    if text.contains("."), hasDomainLikeSeparator(in: text) {
      return true
    }
    return hasPhoneLikeDigits(in: text)
  }

  private static func isAutomaticCandidateSeparator(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }

  private static func trimmedLinkCandidateRange(in text: String,
                                                candidateRange: Range<String.Index>) -> Range<String.Index>? {
    var start = candidateRange.lowerBound
    var end = candidateRange.upperBound

    while start < end,
          isLeadingLinkTrimCharacter(text[start]) {
      start = text.index(after: start)
    }

    while start < end {
      let previous = text.index(before: end)
      let character = text[previous]
      guard isTrailingLinkTrimCharacter(character),
            !isBalancedTrailingDelimiter(character, in: text, range: start ..< end) else {
        break
      }
      end = previous
    }

    guard start < end,
          text[start ..< end].utf16.count <= maxManualLinkCandidateUTF16Length else {
      return nil
    }
    return start ..< end
  }

  private static func isLeadingLinkTrimCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { leadingLinkTrimCharacters.contains($0) }
  }

  private static func isTrailingLinkTrimCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { trailingLinkTrimCharacters.contains($0) }
  }

  private static func isBalancedTrailingDelimiter(_ character: Character,
                                                  in text: String,
                                                  range: Range<String.Index>) -> Bool {
    let opening: Character
    switch character {
    case ")":
      opening = "("
    case "]":
      opening = "["
    case "}":
      opening = "{"
    default:
      return false
    }
    let value = text[range]
    return value.filter { $0 == opening }.count >= value.filter { $0 == character }.count
  }

  private static func isEmailCandidate(_ text: String) -> Bool {
    let parts = text.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let local = parts.first,
          let domain = parts.last,
          !local.isEmpty,
          !domain.isEmpty,
          domain.contains(".") else {
      return false
    }
    return text.unicodeScalars.allSatisfy { scalar in
      isASCIILetterOrDigit(scalar) ||
        scalar == "." ||
        scalar == "_" ||
        scalar == "%" ||
        scalar == "+" ||
        scalar == "-" ||
        scalar == "@"
    }
  }

  private static func isPhoneCandidateScalar(_ scalar: UnicodeScalar) -> Bool {
    CharacterSet.decimalDigits.contains(scalar) ||
      scalar == "+" ||
      scalar == "-" ||
      scalar == "(" ||
      scalar == ")" ||
      scalar == " "
  }

  private static func hasDomainLikeSeparator(in text: String) -> Bool {
    var previousIsDomainCharacter = false
    var dotHasPreviousCharacter = false

    for scalar in text.unicodeScalars {
      if scalar == "." {
        dotHasPreviousCharacter = previousIsDomainCharacter
        previousIsDomainCharacter = false
        continue
      }

      let isDomainCharacter = isASCIILetterOrDigit(scalar)
      if dotHasPreviousCharacter, isDomainCharacter {
        return true
      }
      previousIsDomainCharacter = isDomainCharacter
      dotHasPreviousCharacter = false
    }
    return false
  }

  private static func hasPhoneLikeDigits(in text: String) -> Bool {
    var digitCount = 0
    for scalar in text.unicodeScalars {
      if CharacterSet.decimalDigits.contains(scalar) {
        digitCount += 1
        if digitCount >= 5 {
          return true
        }
      }
    }
    return false
  }

  private static func isASCIILetterOrDigit(_ scalar: UnicodeScalar) -> Bool {
    (48 ... 57).contains(Int(scalar.value)) ||
      (65 ... 90).contains(Int(scalar.value)) ||
      (97 ... 122).contains(Int(scalar.value))
  }

  private static func tokenCacheKey(text: String,
                                    highlights: [MessageTextHighlightState]) -> NSString {
    guard !highlights.isEmpty else {
      return text as NSString
    }
    let highlightSignature = highlights
      .map { "\($0.start):\($0.end):\(kindKey($0.kind))" }
      .joined(separator: ",")
    return "\(text)\u{1F}\(highlightSignature)" as NSString
  }

  private static func kindKey(_ kind: MessageTextHighlightKind) -> String {
    switch kind {
    case .mention:
      return "m"
    case .keyword:
      return "k"
    }
  }

  private struct ManualLinkMatch {
    var range: Range<String.Index>
    var url: URL
  }
}

private final class ChatLinkTextRunsBox {
  let runs: [ChatLinkTextRun]

  init(_ runs: [ChatLinkTextRun]) {
    self.runs = runs
  }
}

private final class ChatLinkTextTokensBox {
  let tokens: [ChatLinkTextToken]

  init(_ tokens: [ChatLinkTextToken]) {
    self.tokens = tokens
  }
}
