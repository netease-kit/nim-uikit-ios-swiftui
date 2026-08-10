// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation

public protocol NECommonRouteValue: Hashable, Identifiable {}

public struct NECommonNavigationIconResource: Equatable {
  public var systemImageName: String?
  public var assetName: String?
  public var bundle: Bundle?

  public init(systemImageName: String) {
    self.systemImageName = systemImageName
    assetName = nil
    bundle = nil
  }

  public init(assetName: String,
              bundle: Bundle? = nil) {
    systemImageName = nil
    self.assetName = assetName
    self.bundle = bundle
  }

  public static let back = NECommonNavigationIconResource(assetName: "back_arrow", bundle: NECommonUIKitSwiftUIBundle.bundle)

  public static func == (lhs: NECommonNavigationIconResource,
                         rhs: NECommonNavigationIconResource) -> Bool {
    lhs.systemImageName == rhs.systemImageName &&
      lhs.assetName == rhs.assetName &&
      lhs.bundle?.bundleURL == rhs.bundle?.bundleURL
  }
}

public struct NECommonNavigationAction: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var systemImage: String?
  public var imageName: String?
  public var imageBundle: Bundle?
  public var imageSize: CGSize?

  public init(id: String,
              title: String,
              systemImage: String? = nil,
              imageName: String? = nil,
              imageBundle: Bundle? = nil,
              imageSize: CGSize? = nil) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.imageName = imageName
    self.imageBundle = imageBundle
    self.imageSize = imageSize
  }

  public static func == (lhs: NECommonNavigationAction,
                         rhs: NECommonNavigationAction) -> Bool {
    lhs.id == rhs.id &&
      lhs.title == rhs.title &&
      lhs.systemImage == rhs.systemImage &&
      lhs.imageName == rhs.imageName &&
      lhs.imageBundle?.bundleURL == rhs.imageBundle?.bundleURL &&
      lhs.imageSize == rhs.imageSize
  }
}
