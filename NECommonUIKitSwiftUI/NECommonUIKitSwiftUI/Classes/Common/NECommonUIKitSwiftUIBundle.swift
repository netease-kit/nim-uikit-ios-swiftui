// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import class UIKit.UIImage

public enum NEUIKitSwiftUILocalization {
  public static let languageDefaultsKey = "IMKitLanguage"

  public static var currentLanguageIdentifier: String {
    if let language = UserDefaults.standard.string(forKey: languageDefaultsKey),
       !language.isEmpty {
      return language
    }
    guard let preferredLanguage = Locale.preferredLanguages.first else {
      return "en"
    }
    return preferredLanguage.hasPrefix("zh") ? "zh-Hans" : "en"
  }

  public static func localizedBundles(in bundle: Bundle) -> [Bundle] {
    var bundles = [Bundle]()
    let language = currentLanguageIdentifier
    let identifiers = [language, language.split(separator: "-").first.map(String.init)]
      .compactMap { $0 }

    for identifier in identifiers where !bundles.contains(where: { $0.bundlePath.hasSuffix("/\(identifier).lproj") }) {
      if let path = bundle.path(forResource: identifier, ofType: "lproj"),
         let localizedBundle = Bundle(path: path) {
        bundles.append(localizedBundle)
      }
    }
    bundles.append(bundle)
    return bundles
  }
}

public enum NECommonUIKitSwiftUIBundle {
  public static let moduleName = "NECommonUIKitSwiftUI"

  public static let bundle: Bundle = {
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
  }()

  /// Cascading localized string lookup matching UIKit resource lookup pattern.
  /// Searches: own bundle → nested bundles → all NE* frameworks → main bundle.
  public static func localized(_ key: String, fallback: String? = nil) -> String {
    let missingValue = "__NECommonSwiftUIResourceMissing__"
    for bundle in candidateBundles {
      for localizedBundle in NEUIKitSwiftUILocalization.localizedBundles(in: bundle) {
        let value = localizedBundle.localizedString(forKey: key, value: missingValue, table: "Localizable")
        if value != missingValue {
          return value
        }
      }
    }
    return fallback ?? key
  }

  /// Cascading image lookup across own and NE* framework bundles.
  public static func loadImage(_ name: String) -> UIImage? {
    for bundle in candidateBundles {
      if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
        return image
      }
    }
    return nil
  }

  private static let candidateBundles: [Bundle] = {
    var bundles = [Bundle]()
    var seen = Set<String>()

    append(bundle, to: &bundles, seen: &seen)
    appendNestedBundles(in: bundle, to: &bundles, seen: &seen)
    appendNestedBundles(in: Bundle(for: BundleToken.self), to: &bundles, seen: &seen)

    // All NE* framework bundles (interface bundles matching UIKit pattern)
    for fw in Bundle.allFrameworks {
      let name = fw.bundleURL.deletingPathExtension().lastPathComponent
      if name.hasPrefix("NE") && name.contains("UIKit") {
        append(fw, to: &bundles, seen: &seen)
        appendNestedBundles(in: fw, to: &bundles, seen: &seen)
      }
    }

    append(Bundle.main, to: &bundles, seen: &seen)
    appendNestedBundles(in: Bundle.main, to: &bundles, seen: &seen)
    return bundles
  }()

  private static func append(_ bundle: Bundle?, to bundles: inout [Bundle], seen: inout Set<String>) {
    guard let bundle else { return }
    let key = bundle.bundleURL.standardizedFileURL.path
    if seen.insert(key).inserted {
      bundles.append(bundle)
    }
  }

  private static func appendNestedBundles(in bundle: Bundle, to bundles: inout [Bundle], seen: inout Set<String>) {
    guard let urls = bundle.urls(forResourcesWithExtension: "bundle", subdirectory: nil) else { return }
    for url in urls {
      let nested = Bundle(url: url)
      append(nested, to: &bundles, seen: &seen)
    }
  }
}

private final class BundleToken {}
