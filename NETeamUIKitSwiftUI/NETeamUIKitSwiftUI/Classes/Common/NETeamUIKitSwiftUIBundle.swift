// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NECommonUIKitSwiftUI
import class UIKit.UIImage

public enum NETeamUIKitSwiftUIBundle {
  public static let moduleName = "NETeamUIKitSwiftUI"

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

  /// Cascading localized string lookup across own bundle, NE* frameworks, and main bundle.
  public static func localized(_ key: String, value: String? = nil) -> String {
    let missingValue = "__NETeamSwiftUIResourceMissing__"
    for b in candidateBundles {
      for localizedBundle in NEUIKitSwiftUILocalization.localizedBundles(in: b) {
        let v = localizedBundle.localizedString(forKey: key, value: missingValue, table: "Localizable")
        if v != missingValue { return v }
      }
    }
    return value ?? key
  }

  /// Cascading image lookup across own and NE* framework bundles.
  public static func loadImage(_ name: String) -> UIImage? {
    for b in candidateBundles {
      if let image = UIImage(named: name, in: b, compatibleWith: nil) { return image }
    }
    return nil
  }


  private static let candidateBundles: [Bundle] = {
    var bundles = [Bundle]()
    var seen = Set<String>()

    append(bundle, to: &bundles, seen: &seen)
    appendNestedBundles(in: bundle, to: &bundles, seen: &seen)
    appendNestedBundles(in: Bundle(for: BundleToken.self), to: &bundles, seen: &seen)

    for fw in Bundle.allFrameworks {
      let name = fw.bundleURL.deletingPathExtension().lastPathComponent
      if name.hasPrefix("NE") && (name.contains("UIKit") || name == "NEChatKit") {
        append(fw, to: &bundles, seen: &seen)
        appendNestedBundles(in: fw, to: &bundles, seen: &seen)
      }
    }

    append(Bundle.main, to: &bundles, seen: &seen)
    appendNestedBundles(in: Bundle.main, to: &bundles, seen: &seen)
    return bundles
  }()

  private static func append(_ b: Bundle?, to bundles: inout [Bundle], seen: inout Set<String>) {
    guard let b else { return }
    let key = b.bundleURL.standardizedFileURL.path
    if seen.insert(key).inserted { bundles.append(b) }
  }

  private static func appendNestedBundles(in b: Bundle, to bundles: inout [Bundle], seen: inout Set<String>) {
    guard let urls = b.urls(forResourcesWithExtension: "bundle", subdirectory: nil) else { return }
    for url in urls {
      append(Bundle(url: url), to: &bundles, seen: &seen)
    }
  }
}

private final class BundleToken {}
