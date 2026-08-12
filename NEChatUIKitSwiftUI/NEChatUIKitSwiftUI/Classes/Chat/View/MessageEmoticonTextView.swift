// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import CoreText
import Foundation
import ImageIO
import SwiftUI

public struct MessageEmoticonTextView: View {
  private static let emoticonBaselineOffset: CGFloat = -4

  public var text: String
  public var token: ChatThemeToken
  public var baseColor: Color?

  public init(text: String,
              token: ChatThemeToken,
              baseColor: Color? = nil) {
    self.text = text
    self.token = token
    self.baseColor = baseColor
  }

  public static func containsEmoticon(in text: String) -> Bool {
    MessageEmoticonCatalog.shared.containsEmoticon(in: text)
  }

  public var body: some View {
    if Self.containsEmoticon(in: text) {
      Self.emoticonText(for: text)
        .foregroundColor(baseColor)
        .accessibilityLabel(text)
    } else {
      Text(text)
        .foregroundColor(baseColor)
    }
  }

  public static func text(for text: String) -> Text {
    if containsEmoticon(in: text) {
      return emoticonText(for: text)
    }
    return Text(text)
  }

  static func emoticonDisplaySize(named fileName: String) -> CGSize? {
    guard let resource = MessageEmoticonCatalog.shared.imageResource(named: fileName) else {
      return nil
    }
    return CGSize(
      width: CGFloat(resource.cgImage.width) / resource.scale,
      height: CGFloat(resource.cgImage.height) / resource.scale
    )
  }

  static var emoticonLayoutBaselineOffset: CGFloat {
    emoticonBaselineOffset
  }

  private static func emoticonText(for text: String) -> Text {
    MessageEmoticonParser.runs(from: text).reduce(Text("")) { partial, run in
      switch run.kind {
      case let .text(value):
        return partial + Text(value)
      case let .emoticon(tag, fileName):
        if let image = MessageEmoticonCatalog.shared.image(named: fileName) {
          return partial + Text(image).baselineOffset(Self.emoticonBaselineOffset)
        }
        return partial + Text(tag)
      }
    }
  }
}

enum MessageMultiForwardSummaryLayoutContext: Equatable {
  case chat
  case compact
}

struct MessageMultiForwardSummaryLineConfiguration: Equatable {
  var text: String
  var lineLimit: Int
  var height: CGFloat
}

enum MessageMultiForwardSummaryLayout {
  static let lineSpacing: CGFloat = 1
  static let minimumRowHeight: CGFloat = 20
  private static let inlineEmoticonSize: CGFloat = 18

  static func configurations(texts: [String],
                             width: CGFloat,
                             fontSize: CGFloat,
                             context: MessageMultiForwardSummaryLayoutContext) -> [MessageMultiForwardSummaryLineConfiguration] {
    let summaries = Array(texts.prefix(3))
    guard let first = summaries.first else {
      return []
    }

    let firstLineCount = measuredLineCount(for: first, width: width, fontSize: fontSize)
    var lineLimits = [(text: String, limit: Int)]()
    if firstLineCount <= 1 {
      lineLimits.append((first, 1))
      if summaries.indices.contains(1) {
        let second = summaries[1]
        lineLimits.append((second, 2))
        if measuredLineCount(for: second, width: width, fontSize: fontSize) == 1,
           summaries.indices.contains(2) {
          lineLimits.append((summaries[2], 1))
        }
      }
    } else if firstLineCount == 2 {
      lineLimits.append((first, 2))
      if summaries.indices.contains(1),
         (context == .chat || summaries.count < 3) {
        lineLimits.append((summaries[1], 1))
      }
    } else {
      lineLimits.append((first, 3))
    }

    return lineLimits.map { item in
      let visibleLineCount = min(
        item.limit,
        measuredLineCount(for: item.text, width: width, fontSize: fontSize)
      )
      return MessageMultiForwardSummaryLineConfiguration(
        text: item.text,
        lineLimit: item.limit,
        height: rowHeight(
          lineCount: visibleLineCount,
          fontSize: fontSize,
          usesTallInlineContent: usesTallInlineContent(item.text)
        )
      )
    }
  }

  private static func measuredLineCount(for text: String,
                                        width: CGFloat,
                                        fontSize: CGFloat) -> Int {
    guard !text.isEmpty, width > 0 else {
      return 1
    }

    let font = coreTextFont(size: fontSize)
    let attributedText = measurementAttributedText(for: text, font: font)
    let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
    let path = CGPath(
      rect: CGRect(x: 0, y: 0, width: width, height: 10_000),
      transform: nil
    )
    let frame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: 0, length: attributedText.length),
      path,
      nil
    )
    return max(1, CFArrayGetCount(CTFrameGetLines(frame)))
  }

  private static func measurementAttributedText(for text: String, font: CTFont) -> NSAttributedString {
    let fontAttributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
    ]
    guard MessageEmoticonTextView.containsEmoticon(in: text) else {
      return NSAttributedString(string: text, attributes: fontAttributes)
    }

    let result = NSMutableAttributedString(string: "")
    for run in MessageEmoticonParser.runs(from: text) {
      switch run.kind {
      case let .text(value):
        result.append(NSAttributedString(string: value, attributes: fontAttributes))
      case .emoticon:
        var character = UniChar(0x3000)
        var glyph = CGGlyph()
        var advance = CGSize.zero
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        result.append(NSAttributedString(
          string: "　",
          attributes: fontAttributes.merging([
            NSAttributedString.Key(kCTKernAttributeName as String): max(0, inlineEmoticonSize - advance.width),
          ]) { current, _ in current }
        ))
      }
    }
    return result
  }

  private static func usesTallInlineContent(_ text: String) -> Bool {
    MessageEmoticonTextView.containsEmoticon(in: text) ||
      text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
  }

  private static func rowHeight(lineCount: Int,
                                fontSize: CGFloat,
                                usesTallInlineContent: Bool) -> CGFloat {
    let font = coreTextFont(size: fontSize)
    let fontLineHeight = ceil(
      CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    )
    let lineHeight = usesTallInlineContent ? max(inlineEmoticonSize, fontLineHeight) : fontLineHeight
    let lines = max(1, lineCount)
    return max(
      minimumRowHeight,
      lineHeight * CGFloat(lines) + lineSpacing * CGFloat(lines - 1)
    )
  }

  private static func coreTextFont(size: CGFloat) -> CTFont {
    CTFontCreateUIFontForLanguage(.system, size, nil) ??
      CTFontCreateWithName(".SFUI-Regular" as CFString, size, nil)
  }
}

struct MessageMultiForwardSummaryRowsView: View {
  var texts: [String]
  var context: MessageMultiForwardSummaryLayoutContext
  var width: CGFloat
  var fontSize: CGFloat
  var color: Color
  var token: ChatThemeToken

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(configurations.enumerated()), id: \.offset) { _, configuration in
        MessageEmoticonTextView(text: configuration.text, token: token, baseColor: color)
          .font(.system(size: fontSize))
          .lineLimit(configuration.lineLimit)
          .lineSpacing(MessageMultiForwardSummaryLayout.lineSpacing)
          .truncationMode(.tail)
          .frame(width: width, height: configuration.height, alignment: .topLeading)
          .clipped()
      }
    }
    .frame(width: width, alignment: .topLeading)
  }

  private var configurations: [MessageMultiForwardSummaryLineConfiguration] {
    MessageMultiForwardSummaryLayout.configurations(
      texts: texts,
      width: width,
      fontSize: fontSize,
      context: context
    )
  }
}

struct MessageEmoticonCatalogItem: Equatable, Identifiable {
  var id: String
  var catalogName: String
  var tag: String
  var fileName: String
  var resolvedImageName: String
  var scale: CGFloat

  var swiftUIImage: Image? {
    MessageEmoticonCatalog.shared.image(named: resolvedImageName)
  }
}

final class MessageEmoticonCatalog {
  static let shared = MessageEmoticonCatalog()
  private static let defaultInputCatalogName = "emoji_ios_cn"
  private static let parserCatalogNames = ["emoji_ios_cn", "emoji_ios_en"]

  let resourceBundle: Bundle?
  private let items: [MessageEmoticonCatalogItem]
  private let tagToItem: [String: MessageEmoticonCatalogItem]
  private let imageCache = NSCache<NSString, MessageEmoticonImageBox>()

  private init() {
    resourceBundle = Self.makeResourceBundle()
    items = Self.loadItems(from: resourceBundle)
    tagToItem = Dictionary(uniqueKeysWithValues: items.map { ($0.tag, $0) })
  }

  func containsEmoticon(in text: String) -> Bool {
    guard text.contains("[") && text.contains("]") else {
      return false
    }
    return MessageEmoticonParser.runs(from: text).contains { $0.isEmoticon }
  }

  func defaultEmojiStates() -> [ChatEmojiState] {
    defaultPanelItems().map {
      ChatEmojiState(
        id: $0.id,
        text: $0.tag,
        imageName: $0.resolvedImageName,
        accessibilityLabel: $0.tag
      )
    }
  }

  private func defaultPanelItems() -> [MessageEmoticonCatalogItem] {
    let defaultItems = items.filter { $0.catalogName == Self.defaultInputCatalogName }
    guard defaultItems.isEmpty else {
      return defaultItems
    }

    var seenImages = Set<String>()
    return items.filter { seenImages.insert($0.resolvedImageName).inserted }
  }

  func fileName(for tag: String) -> String? {
    tagToItem[tag]?.resolvedImageName
  }

  func trailingEmoticonRange(in text: String) -> Range<String.Index>? {
    guard text.hasSuffix("]"),
          let openBracket = text.lastIndex(of: "[") else {
      return nil
    }
    let range = openBracket ..< text.endIndex
    let tag = String(text[range])
    return tagToItem[tag] == nil ? nil : range
  }

  func image(named imageName: String) -> Image? {
    imageBox(named: imageName)?.image
  }

  func imageResource(named imageName: String) -> (cgImage: CGImage, scale: CGFloat)? {
    guard let imageBox = imageBox(named: imageName) else {
      return nil
    }
    return (imageBox.cgImage, imageBox.scale)
  }

  private func imageBox(named imageName: String) -> MessageEmoticonImageBox? {
    if let cached = imageCache.object(forKey: imageName as NSString) {
      return cached
    }
    guard let imageURL = imageURL(named: imageName),
          let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }
    let imageBox = MessageEmoticonImageBox(
      cgImage: cgImage,
      scale: displayScale(for: imageName, image: cgImage)
    )
    imageCache.setObject(imageBox, forKey: imageName as NSString, cost: imageBox.cost)
    return imageBox
  }

  func hasImage(named imageName: String) -> Bool {
    imageURL(named: imageName) != nil
  }

  private func imageURL(named imageName: String) -> URL? {
    resourceBundle?.url(forResource: imageName, withExtension: nil)
  }

  private func scale(for imageName: String) -> CGFloat {
    if imageName.contains("@3x") {
      return 3
    }
    if imageName.contains("@2x") {
      return 2
    }
    return 1
  }

  private func displayScale(for imageName: String,
                            image: CGImage) -> CGFloat {
    let naturalScale = scale(for: imageName)
    let targetTextHeight: CGFloat = 18
    let textScale = CGFloat(image.height) / targetTextHeight
    return max(naturalScale, textScale)
  }

  private static func makeResourceBundle() -> Bundle? {
    let candidates = [
      NEChatUIKitSwiftUIBundle.bundle,
      Bundle(for: BundleToken.self),
      Bundle.main,
    ]

    for candidate in candidates {
      if let bundle = emoticonBundle(in: candidate) {
        return bundle
      }
    }
    if let bundle = sourceTreeEmoticonBundle() {
      return bundle
    }
    return nil
  }

  private static func emoticonBundle(in candidate: Bundle) -> Bundle? {
    if let url = candidate.url(forResource: "NIMKitEmoticon", withExtension: "bundle"),
       let bundle = Bundle(url: url) {
      return bundle
    }
    if let url = candidate.resourceURL?.appendingPathComponent("NIMKitEmoticon.bundle"),
       let bundle = Bundle(url: url) {
      return bundle
    }
    return nil
  }

  private static func sourceTreeEmoticonBundle() -> Bundle? {
    let fileURL = URL(fileURLWithPath: #filePath)
    let candidates = [
      fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Assets/NIMKitEmoticon.bundle"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("IMUIKitSwiftUI/NEChatUIKitSwiftUI/NEChatUIKitSwiftUI/Assets/NIMKitEmoticon.bundle"),
    ]
    return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
      .flatMap(Bundle.init(url:))
  }

  private static func loadItems(from bundle: Bundle?) -> [MessageEmoticonCatalogItem] {
    guard let bundle else {
      return []
    }

    var result = [MessageEmoticonCatalogItem]()
    var seenTags = Set<String>()
    for catalogName in parserCatalogNames {
      guard let url = bundle.url(forResource: catalogName, withExtension: "plist", subdirectory: "Emoji"),
            let array = NSArray(contentsOf: url) as? [[String: Any]] else {
        continue
      }
      for catalog in array {
        guard let items = catalog["data"] as? [[String: Any]] else {
          continue
        }
        for item in items {
          guard let id = item["id"] as? String,
                let tag = item["tag"] as? String,
                let fileName = item["file"] as? String,
                !id.isEmpty,
                !tag.isEmpty,
                !fileName.isEmpty,
                seenTags.insert(tag).inserted,
                let resolvedImage = resolvedImage(for: fileName, in: bundle) else {
            continue
          }
          result.append(MessageEmoticonCatalogItem(
            id: "\(catalogName):\(id)",
            catalogName: catalogName,
            tag: tag,
            fileName: fileName,
            resolvedImageName: resolvedImage.name,
            scale: resolvedImage.scale
          ))
        }
      }
    }
    return result
  }

  private static func resolvedImage(for fileName: String, in bundle: Bundle) -> (name: String, scale: CGFloat)? {
    let nsFileName = fileName as NSString
    let ext = nsFileName.pathExtension.isEmpty ? "png" : nsFileName.pathExtension
    let baseName = nsFileName.deletingPathExtension
    let candidates = [
      "Emoji/\(fileName)",
      "Emoji/\(baseName)@3x.\(ext)",
      "Emoji/\(baseName)@2x.\(ext)",
      "Emoji/\(baseName).\(ext)",
    ]
    guard let name = candidates.first(where: { bundle.url(forResource: $0, withExtension: nil) != nil }) else {
      return nil
    }
    let scale: CGFloat
    if name.contains("@3x") {
      scale = 3
    } else if name.contains("@2x") {
      scale = 2
    } else {
      scale = 1
    }
    return (name, scale)
  }
}

private final class MessageEmoticonImageBox {
  let cgImage: CGImage
  let scale: CGFloat

  init(cgImage: CGImage, scale: CGFloat) {
    self.cgImage = cgImage
    self.scale = scale
  }

  var image: Image {
    Image(decorative: cgImage, scale: scale, orientation: .up)
  }

  var cost: Int {
    max(1, cgImage.bytesPerRow * cgImage.height)
  }
}

struct MessageEmoticonRun: Identifiable, Equatable {
  var id: Int
  var kind: Kind

  enum Kind: Equatable {
    case text(String)
    case emoticon(tag: String, fileName: String)
  }

  var isEmoticon: Bool {
    if case .emoticon = kind {
      return true
    }
    return false
  }
}

enum MessageEmoticonParser {
  private static let runCache = NSCache<NSString, MessageEmoticonRunsBox>()
  private static let bracketRegex = try? NSRegularExpression(pattern: "\\[[^\\[\\]]+\\]", options: [])

  static func runs(from text: String) -> [MessageEmoticonRun] {
    guard !text.isEmpty else {
      return [MessageEmoticonRun(id: 0, kind: .text(text))]
    }
    guard text.contains("[") && text.contains("]") else {
      return [MessageEmoticonRun(id: 0, kind: .text(text))]
    }

    let cacheKey = text as NSString
    if let cached = runCache.object(forKey: cacheKey) {
      return cached.runs
    }

    var runs = [MessageEmoticonRun]()
    var cursor = text.startIndex
    var runId = 0

    for match in bracketMatches(in: text) {
      guard match.lowerBound >= cursor else {
        continue
      }

      if cursor < match.lowerBound {
        runs.append(MessageEmoticonRun(
          id: runId,
          kind: .text(String(text[cursor ..< match.lowerBound]))
        ))
        runId += 1
      }

      let tag = String(text[match])
      if let fileName = MessageEmoticonCatalog.shared.fileName(for: tag) {
        runs.append(MessageEmoticonRun(id: runId, kind: .emoticon(tag: tag, fileName: fileName)))
      } else {
        runs.append(MessageEmoticonRun(id: runId, kind: .text(tag)))
      }
      runId += 1
      cursor = match.upperBound
    }

    if cursor < text.endIndex {
      runs.append(MessageEmoticonRun(
        id: runId,
        kind: .text(String(text[cursor ..< text.endIndex]))
      ))
    }

    let parsedRuns = runs.isEmpty ? [MessageEmoticonRun(id: 0, kind: .text(text))] : runs
    runCache.setObject(MessageEmoticonRunsBox(parsedRuns), forKey: cacheKey, cost: text.utf16.count)
    return parsedRuns
  }

  private static func bracketMatches(in text: String) -> [Range<String.Index>] {
    guard let regex = bracketRegex else {
      return []
    }
    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return regex.matches(in: text, options: [], range: range).compactMap { match in
      Range(match.range, in: text)
    }
  }
}

private final class MessageEmoticonRunsBox {
  let runs: [MessageEmoticonRun]

  init(_ runs: [MessageEmoticonRun]) {
    self.runs = runs
  }
}

private final class BundleToken {}
