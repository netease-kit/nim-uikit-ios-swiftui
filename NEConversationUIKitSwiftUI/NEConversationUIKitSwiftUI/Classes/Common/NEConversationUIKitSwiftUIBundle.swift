// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI

public enum NEConversationUIKitSwiftUIBundle {
  public static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    let candidates: [Bundle] = [
      Bundle(for: NEConversationUIKitSwiftUIBundleMarker.self),
      Bundle.main,
    ]

    for candidate in candidates {
      if let url = candidate.url(forResource: "NEConversationUIKitSwiftUI", withExtension: "bundle"),
         let bundle = Bundle(url: url) {
        return bundle
      }
      if candidate.url(forResource: "NormalConversationUIKitSwiftUI", withExtension: "xcassets") != nil {
        return candidate
      }
    }

    return Bundle(for: NEConversationUIKitSwiftUIBundleMarker.self)
    #endif
  }()

  private static let localizedStringCacheLock = NSLock()
  private static var localizedStringCache = [String: String]()

  public static func localized(_ key: String, value: String? = nil) -> String {
    let fallback = value ?? key
    let language = NEUIKitSwiftUILocalization.currentLanguageIdentifier
    let cacheKey = "\(language)|\(key)|\(fallback)"
    localizedStringCacheLock.lock()
    if let cached = localizedStringCache[cacheKey] {
      localizedStringCacheLock.unlock()
      return cached
    }
    localizedStringCacheLock.unlock()
    let missingValue = "__NEConversationSwiftUIResourceMissing__"
    for localizedBundle in NEUIKitSwiftUILocalization.localizedBundles(in: bundle) {
      let text = localizedBundle.localizedString(forKey: key, value: missingValue, table: "Localizable")
      if text != missingValue {
        cacheLocalizedString(text, forKey: cacheKey)
        return text
      }
    }
    cacheLocalizedString(fallback, forKey: cacheKey)
    return fallback
  }

  private static func cacheLocalizedString(_ text: String, forKey key: String) {
    localizedStringCacheLock.lock()
    localizedStringCache[key] = text
    localizedStringCacheLock.unlock()
  }
}

private final class NEConversationUIKitSwiftUIBundleMarker {}

enum NEConversationErrorMessageMapper {
  static func message(for error: Error,
                      fallbackMessage: String? = nil) -> String {
    let nsError = error as NSError
    switch nsError.code {
    case protocolSendFailed, protocolTimeout:
      return networkMessage()
    default:
      return fallbackMessage ?? NECommonUIKitSwiftUIBundle.localized("failed_operation", fallback: "Failure")
    }
  }

  static func networkMessage() -> String {
    NEConversationUIKitSwiftUIBundle.localized(
      "network_error",
      value: "Network unavailable. Please check your connection."
    )
  }
}

enum NEConversationNetworkGuard {
  static var allowsNetworkOperation: Bool {
    NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false
  }
}
