// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NECommonErrorSeverity: Equatable {
  case info
  case warning
  case error
}

public struct NECommonErrorState: Equatable, Identifiable {
  public var id: String
  public var textKey: String
  public var fallbackText: String
  public var severity: NECommonErrorSeverity
  public var retryable: Bool

  public init(id: String = UUID().uuidString,
              textKey: String = "common_error",
              fallbackText: String = NECommonUIKitSwiftUIBundle.localized("common_error", fallback: "Operation failed"),
              severity: NECommonErrorSeverity = .error,
              retryable: Bool = false) {
    self.id = id
    self.textKey = textKey
    self.fallbackText = fallbackText
    self.severity = severity
    self.retryable = retryable
  }
}

public enum NECommonEmptyImageKind: Equatable {
  case generic
  case user
}

public struct NECommonEmptyState: Equatable {
  public var titleKey: String
  public var fallbackTitle: String
  public var messageKey: String?
  public var fallbackMessage: String?
  public var actionTitleKey: String?
  public var fallbackActionTitle: String?
  public var imageKind: NECommonEmptyImageKind

  public init(titleKey: String = "common_empty",
              fallbackTitle: String = NECommonUIKitSwiftUIBundle.localized("common_empty", fallback: "No content"),
              messageKey: String? = nil,
              fallbackMessage: String? = nil,
              actionTitleKey: String? = nil,
              fallbackActionTitle: String? = nil,
              imageKind: NECommonEmptyImageKind = .generic) {
    self.titleKey = titleKey
    self.fallbackTitle = fallbackTitle
    self.messageKey = messageKey
    self.fallbackMessage = fallbackMessage
    self.actionTitleKey = actionTitleKey
    self.fallbackActionTitle = fallbackActionTitle
    self.imageKind = imageKind
  }
}

public enum NECommonPlaceholderImage {
  public static func emptyImageName(kind: NECommonEmptyImageKind,
                                    styleMode: NECommonStyleMode) -> String {
    switch (kind, styleMode) {
    case (.generic, .normal):
      return "emptyView"
    case (.generic, .fun):
      return "fun_emptyView"
    case (.user, .normal):
      return "user_empty"
    case (.user, .fun):
      return "fun_user_empty"
    }
  }

  public static func mediaImageName(styleMode: NECommonStyleMode) -> String {
    styleMode == .fun ? "fun_default_image" : "default_image"
  }
}
