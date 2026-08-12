// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamSettingViewModel: ObservableObject {
  @Published public private(set) var state = TeamSettingState()

  public let teamId: String
  public let style: NETeamSwiftUIStyleMode

  private let teamRepo: TeamRepo
  private let client: NETeamUIKitSwiftUIClient
  private let teamType: NETeamSwiftUITeamType
  private let config: NETeamSwiftUIConfig
  private var listenerToken: NEChatKitListenerToken?
  private var settingListenerBag: NEChatKitListenerBag?
  private var profileListenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()
  private var settingRefreshGeneration = UUID()
  private var toggleGeneration = [TeamSettingToggleKind: UUID]()
  private var destructiveGeneration = UUID()
  private var inviteSelectionGeneration = UUID()
  private var inviteGeneration = UUID()
  private var didBindEvents = false
  private var memberPreviewGeneration = UUID()
  private var isLoadingMemberPreview = false
  private var eventCurrentRoleOverride: NETeamSwiftUIMemberRole?

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared,
              client: NETeamUIKitSwiftUIClient = .shared,
              config: NETeamSwiftUIConfig = NETeamSwiftUIConfigCenter.shared.current()) {
    self.teamId = teamId
    self.style = style
    self.teamType = teamType
    self.teamRepo = teamRepo
    self.client = client
    self.config = config
    trace(
      "init teamId=\(teamId) style=\(style) teamType=\(teamType) main=\(Thread.isMainThread)"
    )
  }

  deinit {
    debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel deinit teamId=\(teamId)")
    listenerToken?.cancel()
    settingListenerBag?.cancelAll()
    profileListenerToken?.cancel()
  }

  public func load() {
    guard !state.didLeaveTeam else {
      trace("load skip completedLifecycle teamId=\(teamId)")
      return
    }
    trace(
      "load begin teamId=\(teamId) didBindEvents=\(didBindEvents) phase=\(Self.phaseTraceName(state.phase)) snapshot=\(state.snapshot != nil) main=\(Thread.isMainThread)"
    )
    bindEventsIfNeeded()
    trace("load afterBind teamId=\(teamId) didBindEvents=\(didBindEvents)")
    let generation = UUID()
    loadGeneration = generation
    state.phase = .loading
    trace("load requestSnapshot teamId=\(teamId) generation=\(generation)")

    teamRepo.loadSwiftUISettingSnapshot(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel load completionCallback selfAlive=\(self != nil) snapshot=\(snapshot != nil) memberPreview=\(snapshot?.memberPreview.count ?? -1) hasError=\(error != nil) errorCode=\(error?.code ?? 0) main=\(Thread.isMainThread)")
      if Thread.isMainThread {
        self?.handleLoadResult(snapshot: snapshot, error: error, generation: generation)
      } else {
        Task { @MainActor in
          self?.handleLoadResult(snapshot: snapshot, error: error, generation: generation)
        }
      }
    }
  }

  public func refreshIfNeeded() {
    guard state.snapshot == nil else {
      trace("refreshIfNeeded skip teamId=\(teamId) phase=\(Self.phaseTraceName(state.phase))")
      return
    }
    trace("refreshIfNeeded load teamId=\(teamId) phase=\(Self.phaseTraceName(state.phase))")
    load()
  }

  public func select(_ row: TeamSettingRowState) {
    guard row.isEnabled else {
      unavailableToast()
      return
    }

    switch row.kind {
    case let .navigation(route):
      state.route = route
    case let .hostAction(action):
      perform(action)
    case let .toggle(kind):
      setToggle(kind, isOn: !row.isOn)
    case let .destructive(action):
      state.pendingDestructiveAction = action
    case let .customAction(action):
      performCustomAction(action)
    }
  }

  public func setToggle(_ kind: TeamSettingToggleKind, isOn: Bool) {
    guard ensureNetworkForMutation() else {
      return
    }
    switch kind {
    case .messageMute:
      setMessageMute(isOn)
    case .conversationPinned:
      setConversationPinned(isOn)
    case .chatBanned:
      setChatBanned(isOn)
    }
  }

  public func dismissRoute() {
    state.route = nil
  }

  public func dismissConfirmation() {
    guard !state.isSubmittingDestructiveAction else {
      return
    }
    state.pendingDestructiveAction = nil
  }

  public func confirmDestructiveAction() {
    guard state.pendingDestructiveAction != nil, !state.isSubmittingDestructiveAction else {
      return
    }
    guard ensureNetworkForMutation() else {
      state.pendingDestructiveAction = nil
      return
    }

    let generation = UUID()
    destructiveGeneration = generation
    state.pendingDestructiveAction = nil
    state.isSubmittingDestructiveAction = true
    postTeamLifecycleNotification(NENotificationName.localTeamLifecycleExitStarted)
    teamRepo.leaveOrDismissSwiftUITeam(teamId: teamId, teamType: teamType) { [weak self] result, error in
      Task { @MainActor in
        guard let self, self.destructiveGeneration == generation else {
          return
        }
        self.state.isSubmittingDestructiveAction = false
        if let error {
          self.postTeamLifecycleNotification(NENotificationName.localTeamLifecycleExitFailed)
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        guard result != nil else {
          self.postTeamLifecycleNotification(NENotificationName.localTeamLifecycleExitFailed)
          self.state.toast = NETeamToastState(
            message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed"),
            style: .error
          )
          return
        }
        self.completeLocalTeamLifecycleExit()
      }
    }
  }

  public func openMemberProfile(_ member: NETeamSwiftUIMemberState) {
    let request = TeamMemberProfileRequest(
      teamId: teamId,
      accountId: member.accountId,
      isCurrentUser: member.isCurrentUser,
      source: .settingPreview,
      teamType: teamType
    )
    client.openTeamMemberProfile(request)
  }

  public func openMemberInviteSelection() {
    guard state.snapshot != nil else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }
    guard let handler = client.memberInviteSelectionHandler else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.inviteMemberUnavailable, value: "Member invitation requires a host selection handler"),
        style: .info
      )
      return
    }

    let generation = UUID()
    inviteSelectionGeneration = generation
    teamRepo.loadSwiftUIMemberList(
      teamId: teamId,
      teamType: teamType,
      scope: .all,
      forceRefresh: true
    ) { [weak self] memberSnapshot, error in
      Task { @MainActor in
        guard let self, self.inviteSelectionGeneration == generation else {
          return
        }
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        guard let memberSnapshot else {
          self.unavailableToast()
          return
        }
        self.applyInviteMembershipSnapshot(memberSnapshot)
        guard memberSnapshot.canInviteMembers else {
          if memberSnapshot.remainingInviteCount <= 0 {
            self.state.toast = NETeamToastState(
              message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberLimitExceeded, value: "Team member limit exceeded"),
              style: .warning
            )
          } else {
            self.state.toast = NETeamToastState(
              message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission"),
              style: .warning
            )
          }
          return
        }
        let request = TeamMemberInviteSelectionRequest(
          teamId: memberSnapshot.teamId,
          memberLimit: memberSnapshot.memberLimit,
          remainingInviteCount: memberSnapshot.remainingInviteCount,
          existingAccountIds: memberSnapshot.existingAccountIds,
          allowsAIUserInvite: memberSnapshot.allowsAIUserInvite
        )
        handler.selectTeamMembersToInvite(request: request) { [weak self] result in
          Task { @MainActor in
            guard let self, self.inviteSelectionGeneration == generation else {
              return
            }
            switch result {
            case let .success(.selected(accountIds)):
              self.inviteMembers(
                accountIds,
                existingAccountIds: request.existingAccountIds,
                remainingInviteCount: request.remainingInviteCount
              )
            case .success(.cancelled):
              break
            case let .failure(error):
              self.state.toast = NETeamToastState(message: self.message(for: error as NSError), style: .error)
            }
          }
        }
      }
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  public func confirmRemoteTeamDismissal() {
    guard state.isRemoteTeamDismissedAlertPresented, !state.didLeaveTeam else {
      return
    }
    state.isRemoteTeamDismissedAlertPresented = false
    state.didLeaveTeam = true
    postTeamLifecycleNotification(NENotificationName.popGroupChatVC)
  }

  private func completeLocalTeamLifecycleExit() {
    guard !state.didLeaveTeam else {
      return
    }
    invalidateRequestsAfterTeamExit()
    state.pendingDestructiveAction = nil
    state.isSubmittingDestructiveAction = false
    state.isInviting = false
    state.route = nil
    state.didLeaveTeam = true
    postTeamLifecycleNotification(NENotificationName.popGroupChatVC)
    client.leaveTeam(teamId: teamId)
  }

  private func postTeamLifecycleNotification(_ name: Notification.Name) {
    NotificationCenter.default.post(
      name: name,
      object: nil,
      userInfo: ["teamId": teamId]
    )
  }

  private func completeRemoteTeamLifecycleExit() {
    // Preserve a local operation's completion so it can publish the pop event.
    // A dissolution can be reported as teamDismissed followed by teamLeft.
    // Once its confirmation is visible, only the explicit confirmation owns
    // the route exit; otherwise the second callback removes the alert.
    guard !state.isSubmittingDestructiveAction,
          !state.didLeaveTeam,
          !state.isRemoteTeamDismissedAlertPresented else {
      return
    }
    invalidateRequestsAfterTeamExit()
    state.pendingDestructiveAction = nil
    state.isInviting = false
    state.route = nil
    state.toast = nil
    state.didLeaveTeam = true
  }

  private func presentRemoteTeamDismissedAlert() {
    guard !state.isSubmittingDestructiveAction,
          !state.didLeaveTeam,
          !state.isRemoteTeamDismissedAlertPresented else {
      return
    }
    invalidateRequestsAfterTeamExit()
    state.pendingDestructiveAction = nil
    state.isInviting = false
    state.route = nil
    state.toast = nil
    state.isRemoteTeamDismissedAlertPresented = true
  }

  private func invalidateRequestsAfterTeamExit() {
    loadGeneration = UUID()
    settingRefreshGeneration = UUID()
    toggleGeneration.removeAll()
    destructiveGeneration = UUID()
    inviteSelectionGeneration = UUID()
    inviteGeneration = UUID()
    memberPreviewGeneration = UUID()
    isLoadingMemberPreview = false
  }

  private func bindTeamEvents() {
    trace("bindTeamEvents begin teamId=\(teamId)")
    listenerToken = teamRepo.addTeamEventListener(
      NETeamEvent(
        syncFinished: { [weak self] in
          Task { @MainActor in
            guard let self, !self.state.didLeaveTeam else {
              return
            }
            self.eventCurrentRoleOverride = nil
            self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
          }
        },
        teamDismissed: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.presentRemoteTeamDismissedAlert()
          }
        },
        teamLeft: { [weak self] team, _ in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.completeRemoteTeamLifecycleExit()
          }
        },
        teamInfoUpdated: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.reloadSettingSnapshotAfterEvent()
          }
        },
        teamMemberJoined: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
          }
        },
        teamMemberKicked: { [weak self] _, members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
          }
        },
        teamMemberLeft: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
          }
        },
        teamMemberInfoUpdated: { [weak self] members in
          Task { @MainActor in
            guard let self else {
              return
            }
            let teamMembers = members.filter { $0.teamId == self.teamId }
            guard !teamMembers.isEmpty else {
              return
            }
            self.applyCurrentRoleIfNeeded(
              self.teamRepo.swiftUICurrentMemberRole(in: teamMembers, teamId: self.teamId)
            )
            self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
          }
        }
      )
    )
    trace("bindTeamEvents end teamId=\(teamId) token=\(listenerToken != nil)")
  }

  private func bindEventsIfNeeded() {
    guard !didBindEvents else {
      trace("bindEventsIfNeeded skip teamId=\(teamId)")
      return
    }
    trace("bindEventsIfNeeded begin teamId=\(teamId)")
    didBindEvents = true
    bindTeamEvents()
    bindSettingEvents()
    trace("bindEventsIfNeeded end teamId=\(teamId)")
  }

  private func bindSettingEvents() {
    trace("bindSettingEvents begin teamId=\(teamId)")
    settingListenerBag = teamRepo.addSwiftUITeamSettingListener(teamId: teamId) { [weak self] in
      debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel settingListenerChanged selfAlive=\(self != nil) main=\(Thread.isMainThread)")
      Task { @MainActor in
        self?.refreshSettingSnapshotSilently()
      }
    }

    profileListenerToken = teamRepo.addSwiftUITeamMemberProfileListener { [weak self] changedAccountIds in
      debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel profileListenerChanged selfAlive=\(self != nil) changedCount=\(changedAccountIds.count) main=\(Thread.isMainThread)")
      Task { @MainActor in
        guard let self,
              self.isLoadedMemberProfileChange(changedAccountIds) else {
          return
        }
        self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
      }
    }
    trace("bindSettingEvents end teamId=\(teamId) bag=\(settingListenerBag != nil) profileToken=\(profileListenerToken != nil)")
  }

  private func apply(_ snapshot: NETeamSwiftUISettingSnapshot) {
    trace(
      "apply teamId=\(teamId) snapshotTeamId=\(snapshot.teamId) sectionsBefore=\(state.sections.count) memberCount=\(snapshot.memberCount) preview=\(snapshot.memberPreview.count)"
    )
    state.snapshot = snapshot
    state.sections = makeSections(snapshot)
    state.phase = .loaded
    trace("apply end teamId=\(teamId) sections=\(state.sections.count) phase=\(Self.phaseTraceName(state.phase))")
  }

  private func applyCurrentRoleIfNeeded(_ role: NETeamSwiftUIMemberRole?) {
    guard let role,
          var snapshot = state.snapshot else {
      return
    }
    guard snapshot.currentRole != role else {
      return
    }
    eventCurrentRoleOverride = role
    snapshot.currentRole = role
    apply(snapshot)
  }

  private func handleLoadResult(snapshot: NETeamSwiftUISettingSnapshot?,
                                error: NSError?,
                                generation: UUID) {
    trace(
      "load handleResult begin teamId=\(teamId) generation=\(generation) currentGeneration=\(loadGeneration) snapshot=\(snapshot != nil) hasError=\(error != nil) main=\(Thread.isMainThread)"
    )
    guard loadGeneration == generation else {
      trace("load completionIgnored teamId=\(teamId) generation=\(generation)")
      return
    }
    if let error {
      let message = message(for: error)
      trace("load failed teamId=\(teamId) generation=\(generation) message=\(message)")
      state.phase = .failed(message)
      state.toast = NETeamToastState(message: message, style: .error)
      return
    }
    guard let snapshot else {
      let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.emptyTeam, value: "No team info")
      trace("load emptySnapshot teamId=\(teamId) generation=\(generation)")
      state.phase = .failed(message)
      state.toast = NETeamToastState(message: message, style: .warning)
      return
    }
    trace(
      "load applySnapshot teamId=\(teamId) generation=\(generation) memberCount=\(snapshot.memberCount) preview=\(snapshot.memberPreview.count) pinned=\(snapshot.isConversationPinned)"
    )
    applyLoadedSnapshot(snapshot)
  }

  private func refreshSettingSnapshotSilently(refreshMemberPreview: Bool = false) {
    guard !state.didLeaveTeam, state.snapshot != nil else {
      return
    }

    let generation = UUID()
    settingRefreshGeneration = generation
    teamRepo.loadSwiftUISettingSnapshot(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.settingRefreshGeneration == generation else {
          return
        }
        guard let snapshot, error == nil else {
          return
        }
        self.applyLoadedSnapshot(snapshot, refreshMemberPreview: refreshMemberPreview)
      }
    }
  }

  private func applyLoadedSnapshot(_ snapshot: NETeamSwiftUISettingSnapshot,
                                   refreshMemberPreview: Bool = false) {
    var nextSnapshot = snapshot
    if let eventCurrentRoleOverride {
      nextSnapshot.currentRole = eventCurrentRoleOverride
      if snapshot.currentRole == eventCurrentRoleOverride {
        self.eventCurrentRoleOverride = nil
      }
    }
    apply(nextSnapshot)
    loadMemberPreviewIfNeeded(for: nextSnapshot, force: refreshMemberPreview)
  }

  private func applyInviteMembershipSnapshot(_ memberSnapshot: NETeamSwiftUIMemberListSnapshot) {
    guard var snapshot = state.snapshot,
          snapshot.teamId == memberSnapshot.teamId else {
      return
    }
    snapshot.memberCount = memberSnapshot.members.count
    snapshot.memberPreview = Array(memberSnapshot.members.prefix(8))
    snapshot.memberLimit = memberSnapshot.memberLimit
    snapshot.remainingInviteCount = memberSnapshot.remainingInviteCount
    snapshot.existingAccountIds = memberSnapshot.existingAccountIds
    snapshot.canInviteMembers = memberSnapshot.canInviteMembers
    snapshot.allowsAIUserInvite = memberSnapshot.allowsAIUserInvite
    apply(snapshot)
  }

  private func loadMemberPreviewIfNeeded(for snapshot: NETeamSwiftUISettingSnapshot,
                                         force: Bool = false) {
    guard !state.didLeaveTeam,
          (force || snapshot.memberPreview.isEmpty),
          snapshot.memberCount > 0,
          (force || !isLoadingMemberPreview) else {
      return
    }

    let generation = UUID()
    memberPreviewGeneration = generation
    isLoadingMemberPreview = true
    trace(
      "memberPreview request teamId=\(teamId) generation=\(generation) memberCount=\(snapshot.memberCount)"
    )

    teamRepo.loadSwiftUISettingMemberPreview(
      teamId: teamId,
      teamType: teamType,
      forceRefresh: force
    ) { [weak self] members, error in
      debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel memberPreview callback selfAlive=\(self != nil) count=\(members.count) hasError=\(error != nil) main=\(Thread.isMainThread)")
      Task { @MainActor in
        guard let self,
              self.memberPreviewGeneration == generation else {
          return
        }
        self.isLoadingMemberPreview = false
        if let error {
          self.trace("memberPreview failed teamId=\(self.teamId) generation=\(generation) errorCode=\(error.code)")
          return
        }
        guard !members.isEmpty,
              var currentSnapshot = self.state.snapshot,
              currentSnapshot.teamId == snapshot.teamId else {
          self.trace("memberPreview empty teamId=\(self.teamId) generation=\(generation) count=\(members.count)")
          return
        }
        guard currentSnapshot.memberPreview != members else {
          self.trace("memberPreview unchanged teamId=\(self.teamId) generation=\(generation) count=\(members.count)")
          return
        }
        currentSnapshot.memberPreview = members
        if currentSnapshot.existingAccountIds.isEmpty {
          currentSnapshot.existingAccountIds = members.map(\.accountId)
        }
        self.trace("memberPreview apply teamId=\(self.teamId) generation=\(generation) count=\(members.count)")
        self.apply(currentSnapshot)
      }
    }
  }

  private func reloadSettingSnapshotAfterEvent() {
    guard !state.didLeaveTeam else {
      return
    }
    if state.snapshot == nil {
      load()
    } else {
      refreshSettingSnapshotSilently()
    }
  }

  private func isLoadedMemberProfileChange(_ accountIds: [String]) -> Bool {
    guard let snapshot = state.snapshot else {
      return false
    }
    let changed = Set(accountIds)
    return snapshot.memberPreview.contains { changed.contains($0.accountId) }
  }

  private func makeSections(_ snapshot: NETeamSwiftUISettingSnapshot) -> [TeamSettingSectionState] {
    let context = settingContext(for: snapshot)
    var infoRows = [TeamSettingRowState]()

    var settingRows = [TeamSettingRowState]()

    if snapshot.showsPinMessagesEntry {
      settingRows.append(
        TeamSettingRowState(
          id: "pinMessages",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.mark, value: "Pin"),
          kind: .hostAction(.pinMessages(conversationId: snapshot.conversationId))
        )
      )
    }

    settingRows.append(
      TeamSettingRowState(
        id: "historySearch",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.historicalRecord, value: "Search chat history"),
        kind: .hostAction(.historySearch(conversationId: snapshot.conversationId))
      )
    )

    settingRows.append(contentsOf: [
      TeamSettingRowState(
        id: "messageMute",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.messageRemind, value: "Open message remind"),
        isOn: !snapshot.isMessageMuted,
        kind: .toggle(.messageMute)
      ),
      TeamSettingRowState(
        id: "conversationPinned",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.sessionSetTop, value: "Sticky on Top"),
        isOn: snapshot.isConversationPinned,
        kind: .toggle(.conversationPinned)
      ),
    ])

    var manageRows = [TeamSettingRowState]()

    if snapshot.showsChatBannedSetting {
      manageRows.append(
        TeamSettingRowState(
          id: "chatBanned",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNoSpeak, value: "Mute"),
          isOn: snapshot.isChatBanned,
          kind: .toggle(.chatBanned)
        )
      )
    }

    if !snapshot.kind.isDiscuss, snapshot.currentRole.canManageMembers {
      manageRows.append(
        TeamSettingRowState(
          id: "manager",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.manageTeam, value: "Manage Group"),
          kind: .navigation(.manager(teamId: snapshot.teamId, teamType: teamType))
        )
      )
    }

    if snapshot.showsTeamNick {
      settingRows.append(
        TeamSettingRowState(
          id: "teamNick",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNick, value: "My Alias in Group"),
          value: snapshot.currentTeamNick,
          kind: .navigation(.editNick(teamId: snapshot.teamId, teamType: teamType))
        )
      )
    }

    var actionRows = [
      TeamSettingRowState(
        id: "leaveOrDismiss",
        title: leaveActionTitle(for: snapshot),
        kind: .destructive(.leaveOrDismiss)
      ),
    ]

    for action in config.settingCustomActionsProvider?(context) ?? [] {
      let row = TeamSettingRowState(customAction: action)
      switch action.placement {
      case .info:
        infoRows.append(row)
      case .settings:
        settingRows.append(row)
      case .actions:
        actionRows.append(row)
      }
    }

    return [
      TeamSettingSectionState(id: "info", rows: infoRows.filter { config.shouldShowSettingRow($0, context) }),
      TeamSettingSectionState(id: "settings", rows: settingRows.filter { config.shouldShowSettingRow($0, context) }),
      TeamSettingSectionState(id: "management", rows: manageRows.filter { config.shouldShowSettingRow($0, context) }),
      TeamSettingSectionState(id: "actions", rows: actionRows.filter { config.shouldShowSettingRow($0, context) }),
    ].filter { !$0.rows.isEmpty }
  }

  private func settingContext(for snapshot: NETeamSwiftUISettingSnapshot) -> NETeamSettingContext {
    NETeamSettingContext(snapshot: snapshot, style: style, teamType: teamType)
  }

  private func setMessageMute(_ isReminderEnabled: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }

    let previous = snapshot.isMessageMuted
    snapshot.isMessageMuted = !isReminderEnabled
    apply(snapshot)

    let generation = UUID()
    toggleGeneration[.messageMute] = generation
    teamRepo.setSwiftUITeamMessageMuted(teamId: teamId, teamType: teamType, isMuted: !isReminderEnabled) { [weak self] error in
      Task { @MainActor in
        guard let self,
              self.toggleGeneration[.messageMute] == generation else {
          return
        }
        self.toggleGeneration[.messageMute] = nil
        if let error {
          if var rollback = self.state.snapshot {
            rollback.isMessageMuted = previous
            self.apply(rollback)
          }
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func setConversationPinned(_ isOn: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }

    let previous = snapshot.isConversationPinned
    snapshot.isConversationPinned = isOn
    apply(snapshot)

    let generation = UUID()
    toggleGeneration[.conversationPinned] = generation
    teamRepo.setSwiftUITeamConversationPinned(teamId: teamId, isPinned: isOn) { [weak self] error in
      Task { @MainActor in
        guard let self,
              self.toggleGeneration[.conversationPinned] == generation else {
          return
        }
        self.toggleGeneration[.conversationPinned] = nil
        if let error {
          if var rollback = self.state.snapshot {
            rollback.isConversationPinned = previous
            self.apply(rollback)
          }
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func setChatBanned(_ isOn: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }

    let previous = snapshot.isChatBanned
    snapshot.isChatBanned = isOn
    apply(snapshot)

    let generation = UUID()
    toggleGeneration[.chatBanned] = generation
    teamRepo.setSwiftUITeamChatBanned(teamId: teamId, teamType: teamType, isBanned: isOn) { [weak self] error in
      Task { @MainActor in
        guard let self,
              self.toggleGeneration[.chatBanned] == generation else {
          return
        }
        self.toggleGeneration[.chatBanned] = nil
        if let error {
          if var rollback = self.state.snapshot {
            rollback.isChatBanned = previous
            self.apply(rollback)
          }
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func leaveActionTitle(for snapshot: NETeamSwiftUISettingSnapshot) -> String {
    if snapshot.kind.isDiscuss {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.leaveDiscuss, value: "Leave Temp Group")
    }
    if snapshot.currentRole == .owner {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.dismissTeam, value: "Disband Group")
    }
    return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.leaveTeam, value: "left group")
  }

  private func perform(_ action: TeamSettingHostAction) {
    switch action {
    case let .pinMessages(conversationId):
      client.openPinMessages(conversationId: conversationId)
    case let .historySearch(conversationId):
      client.openHistorySearch(conversationId: conversationId)
    }
  }

  private func performCustomAction(_ action: NETeamSettingCustomAction) {
    guard let snapshot = state.snapshot else {
      unavailableToast()
      return
    }
    let handled = config.settingCustomActionHandler?(action, settingContext(for: snapshot)) ?? false
    if !handled {
      unavailableToast()
    }
  }

  private func inviteMembers(_ accountIds: [String],
                             existingAccountIds: [String]? = nil,
                             remainingInviteCount: Int? = nil) {
    guard let snapshot = state.snapshot else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }
    let existingAccountIds = Set(existingAccountIds ?? snapshot.existingAccountIds)
    var seen = Set<String>()
    let inviteeAccountIds = accountIds.compactMap { accountId -> String? in
      let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty,
            !existingAccountIds.contains(value),
            !seen.contains(value) else {
        return nil
      }
      seen.insert(value)
      return value
    }

    guard !inviteeAccountIds.isEmpty else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.memberEmptyTip, value: "Select Member"),
        style: .warning
      )
      return
    }
    let availableInviteCount = remainingInviteCount ?? snapshot.remainingInviteCount
    guard inviteeAccountIds.count <= availableInviteCount else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberLimitExceeded, value: "Team member limit exceeded"),
        style: .warning
      )
      return
    }

    let generation = UUID()
    inviteGeneration = generation
    state.isInviting = true
    teamRepo.inviteSwiftUITeamMembers(teamId: teamId, teamType: teamType, accountIds: inviteeAccountIds) { [weak self] _, error in
      Task { @MainActor in
        guard let self, self.inviteGeneration == generation else {
          return
        }
        self.state.isInviting = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          // Bypass the member cache once after an invitation. The setting snapshot
          // can arrive before the SDK member cache receives its join event.
          self.memberPreviewGeneration = UUID()
          self.isLoadingMemberPreview = false
          self.refreshSettingSnapshotSilently(refreshMemberPreview: true)
        }
      }
    }
  }

  private func unavailableToast() {
    state.toast = NETeamToastState(
      message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed"),
      style: .warning
    )
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NETeamNetworkGuard.allowsNetworkOperation else {
      state.toast = NETeamToastState(message: NETeamErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }

  private func message(for error: NSError) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }

  private func trace(_ message: @autoclosure () -> String) {
    debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingViewModel \(message())")
  }

  private static func phaseTraceName(_ phase: NETeamAsyncPhase) -> String {
    switch phase {
    case .idle:
      return "idle"
    case .loading:
      return "loading"
    case .loaded:
      return "loaded"
    case .failed:
      return "failed"
    }
  }
}
