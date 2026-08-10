// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import ImageIO
import SwiftUI
import UIKit

private enum NECommonAvatarImageDecoder {
  private static let maximumPixelSize = 256

  static func image(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return UIImage(data: data)
    }
    return thumbnail(from: source) ?? UIImage(data: data)
  }

  static func image(from fileURL: URL) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
      return UIImage(contentsOfFile: fileURL.path)
    }
    return thumbnail(from: source) ?? UIImage(contentsOfFile: fileURL.path)
  }

  private static func thumbnail(from source: CGImageSource) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}

public enum NECommonAvatarDisplayResolver {
  public static func displayText(_ displayName: String?,
                                 fallbackID: String? = nil,
                                 defaultText: String = "N") -> String {
    nonEmpty(displayName) ?? nonEmpty(fallbackID) ?? defaultText
  }

  public static func initials(displayName: String?,
                              fallbackID: String? = nil,
                              length: Int = 2,
                              defaultText: String = "N") -> String {
    shortText(displayText(displayName, fallbackID: fallbackID, defaultText: defaultText),
              length: length,
              defaultText: defaultText)
  }

  public static func shortText(_ text: String?,
                               length: Int = 2,
                               defaultText: String = "N") -> String {
    let source = nonEmpty(text) ?? defaultText
    guard length > 0, source.count > length else {
      return source
    }
    return String(source.suffix(length))
  }

  public static func url(from value: String?) -> URL? {
    guard let value else {
      return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
      return nil
    }

    if let url = URL(string: trimmedValue),
       let scheme = url.scheme?.lowercased(),
       !scheme.isEmpty {
      switch scheme {
      case "http", "https", "file":
        return url
      default:
        return nil
      }
    }

    return URL(fileURLWithPath: trimmedValue)
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmedValue.isEmpty ? nil : trimmedValue
  }
}

public struct NECommonAvatarView: View {
  @Environment(\.neCommonTheme) private var token
  private let imageURL: URL?
  private let initials: String
  private let size: CGFloat?
  private let cornerRadius: CGFloat?
  private let fallbackSystemImageName: String?
  private let fallbackImageResource: NECommonImageResource?
  /// User identifier hash for palette-based avatar background colour.
  private let hashID: String?

  /// 7-colour avatar palette shared by the classic avatar hash rule.
  /// Index 0: #60CFA7, 1: #53C3F3, 2: #537FF4, 3: #854FE2, 4: #BE65D9, 5: #E9749D, 6: #F9B751
  public static func avatarPaletteColor(for hashID: String?) -> Color {
    let ascii = hashID?.last?.asciiValue ?? 0
    let mod = UInt64(ascii) % 7
    switch mod {
    case 0: return Color(red: 0.376, green: 0.812, blue: 0.655)
    case 1: return Color(red: 0.325, green: 0.765, blue: 0.953)
    case 2: return Color(red: 0.325, green: 0.498, blue: 0.957)
    case 3: return Color(red: 0.522, green: 0.310, blue: 0.886)
    case 4: return Color(red: 0.745, green: 0.396, blue: 0.851)
    case 5: return Color(red: 0.914, green: 0.455, blue: 0.616)
    default: return Color(red: 0.976, green: 0.718, blue: 0.318)
    }
  }

  private var usePaletteColor: Bool {
    hashID != nil && !(hashID?.isEmpty ?? true)
  }

  public init(imageURL: URL? = nil,
              initials: String = "",
              size: CGFloat? = nil,
              cornerRadius: CGFloat? = nil,
              fallbackSystemImageName: String? = nil,
              hashID: String? = nil) {
    self.imageURL = imageURL
    self.initials = initials
    self.size = size
    self.cornerRadius = cornerRadius
    self.fallbackSystemImageName = fallbackSystemImageName
    fallbackImageResource = nil
    self.hashID = hashID
  }

  public init(imageURL: URL? = nil,
              initials: String = "",
              size: CGFloat? = nil,
              cornerRadius: CGFloat? = nil,
              fallbackImageName: String,
              fallbackBundle: Bundle? = nil,
              fallbackRenderingMode: NECommonImageRenderingMode = .original,
              hashID: String? = nil) {
    self.imageURL = imageURL
    self.initials = initials
    self.size = size
    self.cornerRadius = cornerRadius
    fallbackSystemImageName = nil
    fallbackImageResource = NECommonImageResource(
      imageName: fallbackImageName,
      bundle: fallbackBundle,
      renderingMode: fallbackRenderingMode
    )
    self.hashID = hashID
  }

  public var body: some View {
    let avatarSize = size ?? token.avatar.size
    let radius = cornerRadius ?? min(token.avatar.cornerRadius, avatarSize / 2)
    let resolvedImageURL = resolvedURL(from: imageURL)
    Group {
      if let resolvedImageURL {
        NECommonCachedAvatarImage(url: resolvedImageURL) { image in
          image
            .resizable()
            .scaledToFill()
            .frame(width: avatarSize, height: avatarSize)
            .clipped()
        } placeholder: {
          imageLoadingPlaceholder(avatarSize: avatarSize)
        }
        .id(resolvedImageURL.absoluteString)
      } else {
        avatarFallback(avatarSize: avatarSize)
      }
    }
    .frame(width: avatarSize, height: avatarSize)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .accessibilityHidden(initials.isEmpty)
  }

  @ViewBuilder
  private func avatarFallback(avatarSize: CGFloat) -> some View {
    ZStack {
      if usePaletteColor {
        Self.avatarPaletteColor(for: hashID)
      } else {
        token.avatar.background
      }
      fallback(avatarSize: avatarSize)
    }
    .frame(width: avatarSize, height: avatarSize)
  }

  private func imageLoadingPlaceholder(avatarSize: CGFloat) -> some View {
    Group {
      if usePaletteColor {
        Self.avatarPaletteColor(for: hashID)
      } else {
        token.avatar.background
      }
    }
    .frame(width: avatarSize, height: avatarSize)
  }

  @ViewBuilder
  private func fallback(avatarSize: CGFloat) -> some View {
    let fg = usePaletteColor ? Color.white : token.avatar.foreground
    if let fallbackImageResource {
      let image = Image(fallbackImageResource.imageName, bundle: fallbackImageResource.bundle)
      if fallbackImageResource.renderingMode == .template {
        image
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .foregroundColor(fg)
          .frame(width: avatarSize, height: avatarSize)
      } else {
        image
          .renderingMode(.original)
          .resizable()
          .scaledToFill()
          .frame(width: avatarSize, height: avatarSize)
      }
    } else if let fallbackSystemImageName, !fallbackSystemImageName.isEmpty {
      NECommonFallbackIconView(name: fallbackSystemImageName)
        .frame(width: 12, height: 12)
        .foregroundColor(fg)
    } else {
      Text(displayInitials)
        .font(.system(size: 12))
        .foregroundColor(fg)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  private var displayInitials: String {
    NECommonAvatarDisplayResolver.shortText(initials)
  }

  private func resolvedURL(from url: URL?) -> URL? {
    guard let url else {
      return nil
    }
    if let scheme = url.scheme, !scheme.isEmpty {
      return url
    }
    return URL(fileURLWithPath: url.absoluteString)
  }
}

private struct NECommonCachedAvatarImage<Content: View, Placeholder: View>: View {
  var url: URL
  var content: (Image) -> Content
  var placeholder: () -> Placeholder
  @State private var loadedImage: UIImage?
  @State private var loadedImageKey: String?

  init(url: URL,
       @ViewBuilder content: @escaping (Image) -> Content,
       @ViewBuilder placeholder: @escaping () -> Placeholder) {
    self.url = url
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = currentImage {
        content(Image(uiImage: image))
      } else {
        placeholder()
      }
    }
    .task(id: cacheKey) {
      await loadImageIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .neCommonAvatarImageCacheDidStore)) { notification in
      guard notification.object as? String == cacheKey,
            let cached = NECommonAvatarImageCache.shared.image(for: url) else {
        return
      }
      loadedImage = cached
      loadedImageKey = cacheKey
    }
  }

  private var currentImage: UIImage? {
    if loadedImageKey == cacheKey, let loadedImage {
      return loadedImage
    }
    return NECommonAvatarImageCache.shared.image(for: url)
  }

  private var cacheKey: String {
    Self.cacheKey(for: url)
  }

  @MainActor
  private func loadImageIfNeeded() async {
    let key = cacheKey
    if let cached = await NECommonAvatarImageCache.shared.loadImage(for: url) {
      loadedImage = cached
      loadedImageKey = key
      return
    }

    guard let image = await Self.loadImage(from: url),
          !Task.isCancelled else {
      loadedImage = nil
      loadedImageKey = key
      return
    }

    NECommonAvatarImageCache.shared.store(image, for: url)
    loadedImage = image
    loadedImageKey = key
  }

  private static func loadImage(from url: URL) async -> UIImage? {
    if url.isFileURL {
      return await Task.detached(priority: .utility) {
        NECommonAvatarImageDecoder.image(from: url)
      }.value
    }

    do {
      let request = URLRequest(url: url)
      let (data, response) = try await URLSession.shared.data(for: request)
      if let httpResponse = response as? HTTPURLResponse,
         !(200 ..< 300).contains(httpResponse.statusCode) {
        return nil
      }
      URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
      return await Task.detached(priority: .utility) {
        NECommonAvatarImageDecoder.image(from: data)
      }.value
    } catch {
      debugPrint("[NECommonUIKitSwiftUI] avatar load failed url=\(url.absoluteString) error=\(error)")
      return nil
    }
  }

  private static func cacheKey(for url: URL) -> String {
    if url.isFileURL {
      return url.standardizedFileURL.absoluteString
    }
    return url.absoluteString
  }
}

private final class NECommonAvatarImageCache {
  static let shared = NECommonAvatarImageCache()

  private let cache = NSCache<NSURL, UIImage>()
  private let diskQueue = DispatchQueue(label: "com.netease.necommon.avatar.cache", qos: .utility)
  private let diskCacheDirectory: URL

  private init() {
    cache.countLimit = 300
    cache.totalCostLimit = 40 * 1024 * 1024
    let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ??
      FileManager.default.temporaryDirectory
    diskCacheDirectory = cachesURL.appendingPathComponent("NECommonAvatarImageCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
  }

  func image(for url: URL) -> UIImage? {
    cache.object(forKey: cacheKey(for: url))
  }

  func loadImage(for url: URL) async -> UIImage? {
    if let image = image(for: url) {
      return image
    }
    guard !url.isFileURL else {
      return nil
    }
    let key = cacheKey(for: url)
    let fileURL = diskCacheURL(for: url)
    return await withCheckedContinuation { continuation in
      diskQueue.async { [cache] in
        guard let image = NECommonAvatarImageDecoder.image(from: fileURL) else {
          continuation.resume(returning: nil)
          return
        }
        cache.setObject(image, forKey: key, cost: Self.cost(of: image))
        continuation.resume(returning: image)
      }
    }
  }

  func store(_ image: UIImage, for url: URL, postsNotification: Bool = true) {
    let key = cacheKey(for: url)
    cache.setObject(image, forKey: key, cost: cost(of: image))
    storeOnDisk(image, for: url)
    guard postsNotification else {
      return
    }
    NotificationCenter.default.post(
      name: .neCommonAvatarImageCacheDidStore,
      object: cacheKeyString(for: url)
    )
  }

  private func storeOnDisk(_ image: UIImage, for url: URL) {
    guard !url.isFileURL else {
      return
    }
    let fileURL = diskCacheURL(for: url)
    diskQueue.async { [diskCacheDirectory] in
      try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
      guard let data = image.pngData() else {
        return
      }
      try? data.write(to: fileURL, options: .atomic)
    }
  }

  private func cacheKey(for url: URL) -> NSURL {
    NSURL(string: cacheKeyString(for: url)) ?? url as NSURL
  }

  private func cacheKeyString(for url: URL) -> String {
    if url.isFileURL {
      return url.standardizedFileURL.absoluteString
    }
    return url.absoluteString
  }

  private func diskCacheURL(for url: URL) -> URL {
    diskCacheDirectory.appendingPathComponent(diskCacheFileName(for: url), isDirectory: false)
  }

  private func diskCacheFileName(for url: URL) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in cacheKeyString(for: url).utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: max(0, 16 - hex.count)) + hex + ".png"
  }

  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else {
      return 1
    }
    return max(1, cgImage.bytesPerRow * cgImage.height)
  }

  private func cost(of image: UIImage) -> Int {
    Self.cost(of: image)
  }
}

private extension Notification.Name {
  static let neCommonAvatarImageCacheDidStore = Notification.Name("NECommonAvatarImageCacheDidStore")
}
