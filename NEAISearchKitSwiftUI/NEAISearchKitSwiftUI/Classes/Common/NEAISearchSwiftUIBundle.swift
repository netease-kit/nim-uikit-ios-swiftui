// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import SwiftUI

public enum NEAISearchSwiftUIBundle {
  public static let moduleName = "NEAISearchKitSwiftUI"

  public static var bundle: Bundle {
    let candidates = [
      Bundle(for: BundleToken.self),
      Bundle.main,
    ]

    for candidate in candidates {
      if let path = candidate.path(forResource: moduleName, ofType: "bundle"),
         let bundle = Bundle(path: path) {
        return bundle
      }
    }

    return Bundle(for: BundleToken.self)
  }

  public static func localized(_ key: String, value: String? = nil) -> String {
    let missingValue = "__NEAISearchSwiftUIResourceMissing__"
    for localizedBundle in localizedBundles(in: bundle) {
      let localValue = localizedBundle.localizedString(forKey: key, value: missingValue, table: "Localizable")
      if localValue != missingValue {
        return localValue
      }
    }
    return value ?? key
  }

  public static func imageResource(named name: String) -> NEChatKitImageResource {
    NEChatKitImageResource(name: name, bundle: bundle)
  }

  public static func image(named name: String) -> Image {
    Image(name, bundle: bundle)
  }

  public static func resourceURL(named name: String, extension ext: String? = nil) -> URL? {
    bundle.url(forResource: name, withExtension: ext)
  }

  private static func localizedBundles(in bundle: Bundle) -> [Bundle] {
    let language = NEAppLanguageUtil.getCurrentLanguage() == .chinese ? "zh-Hans" : "en"
    var bundles = [Bundle]()
    for identifier in [language, language.split(separator: "-").first.map(String.init)].compactMap({ $0 }) {
      if let path = bundle.path(forResource: identifier, ofType: "lproj"),
         let localizedBundle = Bundle(path: path),
         !bundles.contains(where: { $0.bundlePath == localizedBundle.bundlePath }) {
        bundles.append(localizedBundle)
      }
    }
    bundles.append(bundle)
    return bundles
  }
}

private final class BundleToken {}
