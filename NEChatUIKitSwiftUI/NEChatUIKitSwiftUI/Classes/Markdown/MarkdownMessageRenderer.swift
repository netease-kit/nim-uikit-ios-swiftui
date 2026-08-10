// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI

public struct MarkdownMessageRenderer: View {
  public var text: String
  public var token: ChatThemeToken
  public var onOpenURL: ((URL, String) -> Void)?

  public init(text: String,
              token: ChatThemeToken,
              onOpenURL: ((URL, String) -> Void)? = nil) {
    self.text = text
    self.token = token
    self.onOpenURL = onOpenURL
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(blocks) { block in
        switch block.kind {
        case .heading:
          textBlock(block.content)
            .font(.system(size: token.incomingMessageFontSize, weight: .semibold))
            .foregroundColor(token.incomingTextColor)
        case .quote:
          textBlock(block.content)
            .font(.system(size: 14))
            .foregroundColor(token.secondaryTextColor)
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
              Rectangle()
                .fill(token.dividerColor)
                .frame(width: 3)
            }
        case .code:
          Text(block.content)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(token.incomingTextColor)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(token.dividerColor.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .bullet:
          HStack(alignment: .top, spacing: 6) {
            Text("-")
            textBlock(block.content)
          }
        case .table:
          MarkdownTableView(rows: block.tableRows, token: token)
        case .plain:
          textBlock(block.content)
        }
      }
    }
  }

  @ViewBuilder
  private func textBlock(_ text: String) -> some View {
    let kind = ChatMessageTextRenderClassifier.kind(for: text)
    if let handler = onOpenURL, kind == .link {
      ChatLinkTextView(text: text, token: token, onOpenURL: handler)
    } else if kind == .emoticon {
      MessageEmoticonTextView(text: text, token: token)
    } else {
      Text(text)
    }
  }

  private var blocks: [MarkdownMessageBlock] {
    MarkdownMessageParser.blocks(from: text)
  }
}

public enum MarkdownMessageBlockKind: Equatable {
  case heading
  case quote
  case code
  case bullet
  case table
  case plain
}

public struct MarkdownMessageBlock: Identifiable, Equatable {
  public var id: String
  public var kind: MarkdownMessageBlockKind
  public var content: String
  public var tableRows: [[String]]

  public init(id: String,
              kind: MarkdownMessageBlockKind,
              content: String,
              tableRows: [[String]] = []) {
    self.id = id
    self.kind = kind
    self.content = content
    self.tableRows = tableRows
  }
}

public enum MarkdownMessageParser {
  private static let blocksCache = NSCache<NSString, MarkdownMessageBlocksBox>()

  public static func mayContainMarkdown(in text: String) -> Bool {
    if text.contains("```") {
      return true
    }

    let lines = text.components(separatedBy: .newlines)
    if lines.filter({ isTableLine($0.trimmingCharacters(in: .whitespaces)) }).count >= 2 {
      return true
    }

    return lines.contains { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return trimmed.hasPrefix("#") ||
        trimmed.hasPrefix(">") ||
        trimmed.hasPrefix("- ") ||
        trimmed.hasPrefix("* ")
    }
  }

  public static func blocks(from text: String) -> [MarkdownMessageBlock] {
    guard mayContainMarkdown(in: text) else {
      return [MarkdownMessageBlock(id: "plain-0", kind: .plain, content: text)]
    }

    let cacheKey = text as NSString
    if let cached = blocksCache.object(forKey: cacheKey) {
      return cached.blocks
    }

    let result = parsedBlocks(from: text)
    blocksCache.setObject(MarkdownMessageBlocksBox(result), forKey: cacheKey)
    return result
  }

  private static func parsedBlocks(from text: String) -> [MarkdownMessageBlock] {
    let lines = text.components(separatedBy: .newlines)
    var blocks = [MarkdownMessageBlock]()
    var isCodeBlock = false
    var codeLines = [String]()

    var index = 0
    while index < lines.count {
      let line = lines[index]
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        if isCodeBlock {
          blocks.append(MarkdownMessageBlock(
            id: "code-\(index)",
            kind: .code,
            content: codeLines.joined(separator: "\n")
          ))
          codeLines.removeAll()
        }
        isCodeBlock.toggle()
        index += 1
        continue
      }

      if isCodeBlock {
        codeLines.append(line)
        index += 1
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else {
        index += 1
        continue
      }

      if isTableLine(trimmed) {
        let table = collectTableRows(from: lines, start: index)
        if !table.rows.isEmpty {
          blocks.append(MarkdownMessageBlock(
            id: "table-\(index)",
            kind: .table,
            content: table.rows.map { $0.joined(separator: " | ") }.joined(separator: "\n"),
            tableRows: table.rows
          ))
          index = table.nextIndex
          continue
        }
      }

      if trimmed.hasPrefix("#") {
        blocks.append(MarkdownMessageBlock(
          id: "heading-\(index)",
          kind: .heading,
          content: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        ))
      } else if trimmed.hasPrefix(">") {
        blocks.append(MarkdownMessageBlock(
          id: "quote-\(index)",
          kind: .quote,
          content: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        ))
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        blocks.append(MarkdownMessageBlock(
          id: "bullet-\(index)",
          kind: .bullet,
          content: String(trimmed.dropFirst(2))
        ))
      } else {
        blocks.append(MarkdownMessageBlock(
          id: "plain-\(index)",
          kind: .plain,
          content: line
        ))
      }
      index += 1
    }

    if !codeLines.isEmpty {
      blocks.append(MarkdownMessageBlock(
        id: "code-tail",
        kind: .code,
        content: codeLines.joined(separator: "\n")
      ))
    }

    return blocks.isEmpty
      ? [MarkdownMessageBlock(id: "empty", kind: .plain, content: text)]
      : blocks
  }

  private static func collectTableRows(from lines: [String],
                                       start: Int) -> (rows: [[String]], nextIndex: Int) {
    var index = start
    var rows = [[String]]()

    while index < lines.count {
      let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
      guard isTableLine(trimmed) else {
        break
      }

      if !isTableSeparator(trimmed) {
        rows.append(tableCells(from: trimmed))
      }
      index += 1
    }

    return (rows.count >= 2 ? normalized(rows) : [], index)
  }

  private static func normalized(_ rows: [[String]]) -> [[String]] {
    let columnCount = rows.map(\.count).max() ?? 0
    guard columnCount > 0 else {
      return []
    }

    return rows.map { row in
      guard row.count < columnCount else {
        return Array(row.prefix(columnCount))
      }
      return row + Array(repeating: "", count: columnCount - row.count)
    }
  }

  private static func isTableLine(_ line: String) -> Bool {
    line.contains("|") && tableCells(from: line).count >= 2
  }

  private static func isTableSeparator(_ line: String) -> Bool {
    let cells = tableCells(from: line)
    guard !cells.isEmpty else {
      return false
    }

    return cells.allSatisfy { cell in
      let normalized = cell.replacingOccurrences(of: ":", with: "")
      return !normalized.isEmpty && normalized.allSatisfy { $0 == "-" }
    }
  }

  private static func tableCells(from line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") {
      trimmed.removeFirst()
    }
    if trimmed.hasSuffix("|") {
      trimmed.removeLast()
    }

    return trimmed
      .split(separator: "|", omittingEmptySubsequences: false)
      .map { String($0).trimmingCharacters(in: .whitespaces) }
  }
}

private final class MarkdownMessageBlocksBox {
  let blocks: [MarkdownMessageBlock]

  init(_ blocks: [MarkdownMessageBlock]) {
    self.blocks = blocks
  }
}

public enum ChatMessageTextRenderKind {
  case plain
  case emoticon
  case link
  case markdown
}

public enum ChatMessageTextRenderClassifier {
  private static let kindCache = NSCache<NSString, ChatMessageTextRenderKindBox>()

  public static func kind(for text: String,
                          allowsMarkdown: Bool = true) -> ChatMessageTextRenderKind {
    let cacheKey = "\(allowsMarkdown ? "m" : "p"):\(text)" as NSString
    if let cached = kindCache.object(forKey: cacheKey) {
      return cached.kind
    }

    let kind: ChatMessageTextRenderKind
    if ChatLinkTextView.containsLink(in: text) {
      kind = .link
    } else if MessageEmoticonTextView.containsEmoticon(in: text) {
      kind = .emoticon
    } else if allowsMarkdown, MarkdownMessageParser.mayContainMarkdown(in: text) {
      kind = .markdown
    } else {
      kind = .plain
    }

    kindCache.setObject(ChatMessageTextRenderKindBox(kind), forKey: cacheKey)
    return kind
  }
}

private final class ChatMessageTextRenderKindBox {
  let kind: ChatMessageTextRenderKind

  init(_ kind: ChatMessageTextRenderKind) {
    self.kind = kind
  }
}

private struct MarkdownTableView: View {
  var rows: [[String]]
  var token: ChatThemeToken

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
          HStack(alignment: .top, spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
              Text(cell.isEmpty ? " " : cell)
                .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                .foregroundColor(rowIndex == 0 ? token.incomingTextColor : token.secondaryTextColor)
                .lineLimit(3)
                .frame(minWidth: 72, maxWidth: 140, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(cellBackground(row: rowIndex, column: columnIndex))
                .overlay(
                  Rectangle()
                    .stroke(token.dividerColor.opacity(0.6), lineWidth: 0.5)
                )
            }
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }

  private func cellBackground(row: Int, column: Int) -> Color {
    if row == 0 {
      return token.dividerColor.opacity(0.45)
    }
    return (row + column).isMultiple(of: 2)
      ? token.dividerColor.opacity(0.16)
      : token.dividerColor.opacity(0.08)
  }
}
