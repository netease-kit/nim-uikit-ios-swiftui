// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NECommonDialogActionRole: Equatable {
  case normal
  case destructive
  case cancel

  var buttonRole: ButtonRole? {
    switch self {
    case .normal:
      return nil
    case .destructive:
      return .destructive
    case .cancel:
      return .cancel
    }
  }
}

public struct NECommonDialogAction: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var systemImageName: String?
  public var imageName: String?
  public var imageBundle: Bundle?
  public var role: NECommonDialogActionRole
  public var isEnabled: Bool

  public init(id: String,
              title: String,
              systemImageName: String? = nil,
              imageName: String? = nil,
              imageBundle: Bundle? = nil,
              role: NECommonDialogActionRole = .normal,
              isEnabled: Bool = true) {
    self.id = id
    self.title = title
    self.systemImageName = systemImageName
    self.imageName = imageName
    self.imageBundle = imageBundle
    self.role = role
    self.isEnabled = isEnabled
  }

  public static func == (lhs: NECommonDialogAction,
                         rhs: NECommonDialogAction) -> Bool {
    lhs.id == rhs.id &&
      lhs.title == rhs.title &&
      lhs.systemImageName == rhs.systemImageName &&
      lhs.imageName == rhs.imageName &&
      lhs.imageBundle?.bundleURL == rhs.imageBundle?.bundleURL &&
      lhs.role == rhs.role &&
      lhs.isEnabled == rhs.isEnabled
  }
}

public enum NECommonDialogPresentationStyle: Equatable {
  case actionSheet
  case alert
}

public struct NECommonDialogState: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var message: String?
  public var showsTitle: Bool
  public var presentationStyle: NECommonDialogPresentationStyle
  public var actions: [NECommonDialogAction]

  public init(id: String,
              title: String,
              message: String? = nil,
              showsTitle: Bool = true,
              presentationStyle: NECommonDialogPresentationStyle = .actionSheet,
              actions: [NECommonDialogAction]) {
    self.id = id
    self.title = title
    self.message = message
    self.showsTitle = showsTitle
    self.presentationStyle = presentationStyle
    self.actions = actions
  }
}
