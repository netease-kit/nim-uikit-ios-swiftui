// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct TeamAvatarEditState: Equatable {
  public var phase: NETeamAsyncPhase
  public var currentAvatarURL: String?
  public var draftAvatarURL: String
  public var defaultAvatarURLs: [String]
  public var canEdit: Bool
  public var isSaving: Bool
  public var didSave: Bool
  public var toast: NETeamToastState?

  public init(phase: NETeamAsyncPhase = .idle,
              currentAvatarURL: String? = nil,
              draftAvatarURL: String = "",
              defaultAvatarURLs: [String] = [],
              canEdit: Bool = false,
              isSaving: Bool = false,
              didSave: Bool = false,
              toast: NETeamToastState? = nil) {
    self.phase = phase
    self.currentAvatarURL = currentAvatarURL
    self.draftAvatarURL = draftAvatarURL
    self.defaultAvatarURLs = defaultAvatarURLs
    self.canEdit = canEdit
    self.isSaving = isSaving
    self.didSave = didSave
    self.toast = toast
  }

  public var normalizedDraftURL: String {
    draftAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var canSubmit: Bool {
    canEdit && !isSaving && !normalizedDraftURL.isEmpty
  }
}
