// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

public final class NETeamUIKitSwiftUIClient: ObservableObject {
  public static let shared = NETeamUIKitSwiftUIClient()

  @Published public var route: NETeamSwiftUIRoute?
  public var onOpenTeamChat: ((String) -> Void)?
  public var onOpenPinMessages: ((String) -> Void)?
  public var onOpenHistorySearch: ((String) -> Void)?
  public var onLeaveTeam: ((String) -> Void)?
  public var avatarSelectionHandler: TeamAvatarSelectionHandling?
  public var memberInviteSelectionHandler: TeamMemberInviteSelectionHandling?
  public var memberProfileRouter: TeamMemberProfileRouting?
  private let setupLock = NSLock()
  private var didSetup = false

  private init() {}

  public func setup() {
    setupLock.lock()
    let shouldSetup = !didSetup
    if shouldSetup {
      didSetup = true
    }
    setupLock.unlock()
    guard shouldSetup else {
      return
    }

    ChatKitClient.shared.buryDataPoints(
      NETeamUIKitSwiftUIConstants.telemetryComponentName,
      language: NETeamUIKitSwiftUIConstants.telemetryLanguage
    )
  }

  public func openTeamSetting(teamId: String,
                              style: NETeamSwiftUIStyleMode = .normal,
                              teamType: NETeamSwiftUITeamType = .normal) {
    route = .setting(teamId: teamId, style: style, teamType: teamType)
  }

  public func openJoinTeam(teamId: String? = nil,
                           teamType: NETeamSwiftUITeamType = .normal) {
    route = .joinTeam(teamId: teamId, teamType: teamType)
  }

  public func openCreateAdvancedTeam() {
    route = .createAdvancedTeam
  }

  public func openTeamDetail(teamId: String,
                             teamType: NETeamSwiftUITeamType = .normal) {
    route = .teamDetail(teamId: teamId, teamType: teamType)
  }

  public func openTeamChat(conversationId: String) {
    onOpenTeamChat?(conversationId)
  }

  public func openPinMessages(conversationId: String) {
    onOpenPinMessages?(conversationId)
  }

  public func openHistorySearch(conversationId: String) {
    onOpenHistorySearch?(conversationId)
  }

  public func leaveTeam(teamId: String) {
    onLeaveTeam?(teamId)
  }

  public func openTeamMemberProfile(_ request: TeamMemberProfileRequest,
                                    completion: @escaping (Result<TeamMemberProfileRouteResult, Error>) -> Void = { _ in }) {
    guard let memberProfileRouter else {
      completion(.success(.cancelled))
      return
    }
    memberProfileRouter.openTeamMemberProfile(request, completion: completion)
  }

  public func dismissRoute() {
    route = nil
  }
}
