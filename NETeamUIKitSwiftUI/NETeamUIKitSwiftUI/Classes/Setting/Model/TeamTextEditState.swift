// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum TeamTextEditField: Equatable {
  case name
  case nick
  case introduce

  public var limit: Int {
    switch self {
    case .name, .nick:
      return 30
    case .introduce:
      return 100
    }
  }
}

public struct TeamTextEditState: Equatable {
  public var phase: NETeamAsyncPhase
  public var text: String
  public var canEdit: Bool
  public var isSaving: Bool
  public var toast: NETeamToastState?
  public var didSave: Bool

  public init(phase: NETeamAsyncPhase = .idle,
              text: String = "",
              canEdit: Bool = false,
              isSaving: Bool = false,
              toast: NETeamToastState? = nil,
              didSave: Bool = false) {
    self.phase = phase
    self.text = text
    self.canEdit = canEdit
    self.isSaving = isSaving
    self.toast = toast
    self.didSave = didSave
  }

  public var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func canSubmit(field: TeamTextEditField) -> Bool {
    guard canEdit, !isSaving else {
      return false
    }
    switch field {
    case .name:
      return !text.isEmpty
    case .nick, .introduce:
      return true
    }
  }
}
