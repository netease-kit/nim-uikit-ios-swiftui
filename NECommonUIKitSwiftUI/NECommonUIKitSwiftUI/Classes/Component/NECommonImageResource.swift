// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct NECommonImageResource: Equatable {
  public var imageName: String
  public var bundle: Bundle?
  public var renderingMode: NECommonImageRenderingMode

  public init(imageName: String,
              bundle: Bundle? = nil,
              renderingMode: NECommonImageRenderingMode = .template) {
    self.imageName = imageName
    self.bundle = bundle
    self.renderingMode = renderingMode
  }

  public static func == (lhs: NECommonImageResource,
                         rhs: NECommonImageResource) -> Bool {
    lhs.imageName == rhs.imageName &&
      lhs.bundle?.bundleURL == rhs.bundle?.bundleURL &&
      lhs.renderingMode == rhs.renderingMode
  }
}

public enum NECommonImageRenderingMode: Equatable {
  case template
  case original
}
