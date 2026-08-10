// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI
import class UIKit.UIImage

public struct ContactImageResource: View {
  private let name: String
  private let size: CGFloat
  private let fallbackSystemImage: String

  public init(name: String,
              size: CGFloat,
              fallbackSystemImage: String = "person.fill") {
    self.name = name
    self.size = size
    self.fallbackSystemImage = fallbackSystemImage
  }

  public var body: some View {
    Image(name, bundle: NEContactUIKitSwiftUIBundle.bundle)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
      .overlay {
        if !Self.hasImage(named: name) {
          Image(systemName: fallbackSystemImage)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.gray, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        }
      }
  }

  private static func hasImage(named name: String) -> Bool {
    let bundle = NEContactUIKitSwiftUIBundle.bundle
    let key = "\(bundle.bundleURL.standardizedFileURL.path)|\(name)" as NSString
    if let cached = ContactImageResourceCache.shared.object(forKey: key) {
      return cached.boolValue
    }

    let exists = UIImage(named: name, in: bundle, compatibleWith: nil) != nil
    ContactImageResourceCache.shared.setObject(NSNumber(value: exists), forKey: key)
    return exists
  }

  public static func validationMessageName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_valid_message" : "valid_message"
  }

  public static func blacklistName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_blacklist" : "blacklist"
  }

  public static func teamName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_my_team" : "group"
  }

  public static func aiUserName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_ai_user" : "ai_user"
  }

  public static func aiRobotName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_ai_robot" : "ai_robot"
  }

  public static func addName(style: ContactStyleMode) -> String {
    style == .fun ? "fun_nav_add" : "add_black"
  }
}

private enum ContactImageResourceCache {
  static let shared = NSCache<NSString, NSNumber>()
}
