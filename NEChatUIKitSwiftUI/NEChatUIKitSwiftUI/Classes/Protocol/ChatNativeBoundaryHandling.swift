// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum ChatNativeBoundaryResult {
  case send(ChatOutgoingMessagePayload)
  case sendMultiple([ChatOutgoingMessagePayload])
  case route(NEChatSwiftUIRoute)
  case toast(ChatToastState)
  case none
}

public enum ChatNativeBoundaryDisposition: Equatable {
  case internalRoute(NEChatSwiftUIRoute)
  case appBoundaryRequired(reason: String)
  case deferred(reason: String)
}

public enum ChatNativeBoundaryCapability: String, CaseIterable, Identifiable, Equatable {
  case appSceneEvents
  case notificationEvents
  case apnsRemoteNotification
  case pushKitEvents
  case sdkBootstrapOptions
  case mediaPickerProvider
  case cameraCapture
  case avatarSelection
  case fileImportProvider
  case fileCardPreview
  case mediaPreview
  case audioRecording
  case audioPlayback
  case mapMessageDisplay
  case qrFallback
  case qrLiveScan
  case permissionRequest
  case urlOpen

  public var id: String {
    rawValue
  }
}

public enum ChatNativeBoundaryCapabilityDisposition: String, Equatable {
  case swiftUIOwned
  case appBoundaryRequired
  case deferred
}

public enum ChatNativeBoundaryOwner: String, Equatable {
  case chatModule
  case swiftUIAppHost
  case neChatKit
  case futureScope
}

public enum ChatNativeBoundaryLifecycle: String, Equatable {
  case bootstrap
  case appScene
  case userAction
  case messageInteraction
  case backgroundEvent
  case route
  case deferred
}

public struct ChatNativeBoundaryCapabilityPolicy: Equatable, Identifiable {
  public var capability: ChatNativeBoundaryCapability
  public var owner: ChatNativeBoundaryOwner
  public var lifecycle: ChatNativeBoundaryLifecycle
  public var disposition: ChatNativeBoundaryCapabilityDisposition
  public var swiftUIOption: String
  public var failureFallback: String
  public var manualQACase: String
  public var sourceScanRule: String

  public init(capability: ChatNativeBoundaryCapability,
              owner: ChatNativeBoundaryOwner,
              lifecycle: ChatNativeBoundaryLifecycle,
              disposition: ChatNativeBoundaryCapabilityDisposition,
              swiftUIOption: String,
              failureFallback: String,
              manualQACase: String,
              sourceScanRule: String) {
    self.capability = capability
    self.owner = owner
    self.lifecycle = lifecycle
    self.disposition = disposition
    self.swiftUIOption = swiftUIOption
    self.failureFallback = failureFallback
    self.manualQACase = manualQACase
    self.sourceScanRule = sourceScanRule
  }

  public var id: String {
    capability.rawValue
  }
}

public struct ChatNativeBoundaryPolicy {
  public var dispositionProvider: (ChatMoreAction, ChatSessionContext) -> ChatNativeBoundaryDisposition

  public init(dispositionProvider: @escaping (ChatMoreAction, ChatSessionContext) -> ChatNativeBoundaryDisposition) {
    self.dispositionProvider = dispositionProvider
  }

  public func disposition(for action: ChatMoreAction,
                          context: ChatSessionContext) -> ChatNativeBoundaryDisposition {
    dispositionProvider(action, context)
  }

  public static let firstPhase = ChatNativeBoundaryPolicy { action, context in
    switch action {
    case .photo, .takePicture, .file, .location:
      return .appBoundaryRequired(reason: "requires_swiftui_native_boundary_handler")
    case .rtc:
      return .appBoundaryRequired(reason: "rtc_call_requires_app_host")
    case .translate:
      return .deferred(reason: "translate_more_action_is_handled_by_chat_view_model")
    }
  }

  public static let firstPhaseCapabilities: [ChatNativeBoundaryCapabilityPolicy] = [
    ChatNativeBoundaryCapabilityPolicy(
      capability: .sdkBootstrapOptions,
      owner: .swiftUIAppHost,
      lifecycle: .bootstrap,
      disposition: .appBoundaryRequired,
      swiftUIOption: "SwiftUI app bootstrap calls NEChatKit setup and injects ChatSwiftUIConfig before opening ChatView.",
      failureFallback: "Keep chat routes queued and expose a route diagnostic until NEChatKit bootstrap succeeds.",
      manualQACase: "Cold launch, logout-login, style switch and failed setup should not duplicate Chat listeners or routes.",
      sourceScanRule: "Chat views and view models must not perform SDK bootstrap directly."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .appSceneEvents,
      owner: .swiftUIAppHost,
      lifecycle: .appScene,
      disposition: .appBoundaryRequired,
      swiftUIOption: "SwiftUI app scene phase and app delegate adapters emit value events to the root state.",
      failureFallback: "ChatSessionViewModel keeps listener cleanup in onDisappear and deinit as the local fallback.",
      manualQACase: "Enter background and foreground with an active P2P and team chat, then verify no duplicated events.",
      sourceScanRule: "Chat module must not observe process-wide app lifecycle notifications directly."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .notificationEvents,
      owner: .swiftUIAppHost,
      lifecycle: .backgroundEvent,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Notification authorization, foreground presentation and tap handling stay in the SwiftUI app host.",
      failureFallback: "Malformed or unsupported payloads are converted to router diagnostics and dropped without crashing.",
      manualQACase: "Tap a message notification before and after login; route should wait for root readiness.",
      sourceScanRule: "Chat module only consumes NEChatSwiftUIRouter queue requests for notification navigation."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .apnsRemoteNotification,
      owner: .swiftUIAppHost,
      lifecycle: .backgroundEvent,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Remote notification payload parsing is converted to a typed chat route request by the app host.",
      failureFallback: "Unsupported payloads record diagnostics and leave the current route unchanged.",
      manualQACase: "APNS payload for P2P, team and missing conversation id should route or fail with diagnostics.",
      sourceScanRule: "Chat module must not parse platform notification payload dictionaries as UI state."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .pushKitEvents,
      owner: .swiftUIAppHost,
      lifecycle: .backgroundEvent,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Optional VoIP push events are owned by the app host and may enqueue chat or call routes.",
      failureFallback: "If the host does not enable VoIP push, Chat keeps RTC entry deferred and shows the boundary toast.",
      manualQACase: "When VoIP is enabled, verify chat route enqueue and logout cleanup; when disabled, verify no Chat crash.",
      sourceScanRule: "Chat module must not own VoIP delegates or call UI setup."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .mediaPickerProvider,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "PhotosPicker returns image or video ChatOutgoingMessagePayload values through ChatNativeBoundaryHandling.",
      failureFallback: "Cancel, permission denial or missing handler shows a non-fatal toast and sends no message.",
      manualQACase: "Pick image, pick video, cancel, denied permission and upload failure should keep the input usable.",
      sourceScanRule: "Photo action must stay behind ChatNativeBoundaryHandling and payload values."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .cameraCapture,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Camera capture is an app-level native service that returns media payloads; exact camera parity is deferred.",
      failureFallback: "Without a host service the camera action routes to .moreAction and shows the boundary-required toast.",
      manualQACase: "Camera unavailable, denied permission and host cancellation should not create pending messages.",
      sourceScanRule: "Chat module must not contain camera capture or preview UI."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .avatarSelection,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Avatar pick and crop are provided by Contact or Mine SwiftUI modules as value results.",
      failureFallback: "Keep the current avatar and show a host-provided error or cancellation toast.",
      manualQACase: "AI robot avatar edit and profile avatar edit should cancel, fail and retry without stale Chat state.",
      sourceScanRule: "Chat module must not upload avatar resources directly."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .fileImportProvider,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "fileImporter returns file ChatOutgoingMessagePayload values through ChatNativeBoundaryHandling.",
      failureFallback: "Cancel, security-scoped access failure or missing handler shows a toast and sends no message.",
      manualQACase: "Pick a small file, large file, unsupported file and cancel from the picker.",
      sourceScanRule: "File action must stay behind ChatNativeBoundaryHandling and payload values."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .fileCardPreview,
      owner: .swiftUIAppHost,
      lifecycle: .messageInteraction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "quickLookPreview, ShareLink or URL open can be injected by ChatFileInteractionHandling.",
      failureFallback: "ChatFilePreviewView shows the file card and metadata when no host preview service is available.",
      manualQACase: "Tap cached file, missing file, share, save and unsupported extension.",
      sourceScanRule: "File preview must be value-service based and keep platform preview UI outside Chat."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .mediaPreview,
      owner: .chatModule,
      lifecycle: .messageInteraction,
      disposition: .swiftUIOwned,
      swiftUIOption: "Pure SwiftUI media preview route with SwiftUI image zoom and AVKit video playback; save and share stay behind value services.",
      failureFallback: "Missing media URL renders the unavailable state and avoids infinite loading.",
      manualQACase: "Open image, open video, missing URL, pinch, pan and double-tap image preview.",
      sourceScanRule: "Media preview must remain SwiftUI-owned for image display and video playback; app media-service fallback copy must not be reintroduced."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .audioRecording,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Audio recording service returns ChatAudioRecordResult with an audio payload.",
      failureFallback: "Missing service, permission denial or recorder failure shows the recording failure toast.",
      manualQACase: "Press, slide to cancel, short recording, permission denied and interruption.",
      sourceScanRule: "Recorder implementation must stay outside Chat and return value progress."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .audioPlayback,
      owner: .swiftUIAppHost,
      lifecycle: .messageInteraction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Audio playback service returns playing or stopped state through ChatAudioPlaybackHandling.",
      failureFallback: "Missing playback service shows a toast and keeps the message row stable.",
      manualQACase: "Play, stop, leave chat while playing, missing file and concurrent audio taps.",
      sourceScanRule: "Audio playback must not be implemented with platform UI inside Chat."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .mapMessageDisplay,
      owner: .chatModule,
      lifecycle: .messageInteraction,
      disposition: .swiftUIOwned,
      swiftUIOption: "SwiftUI renders the static location card and the same unavailable fallback page as IMUIKitExample when its map module is not included.",
      failureFallback: "Show the no-map-plugin card state and keep the message operation menu available.",
      manualQACase: "Open a location card without the map module, then long-press it and verify the operation menu remains available.",
      sourceScanRule: "Map selection, POI search and navigation remain out of first-phase Chat."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .qrFallback,
      owner: .chatModule,
      lifecycle: .route,
      disposition: .swiftUIOwned,
      swiftUIOption: "SwiftUI QR fallback shows code, config text, bind route and share actions where available.",
      failureFallback: "Missing or expired code shows the existing AI robot QR failure toast.",
      manualQACase: "Open AI robot bind route with valid, expired and missing QR data.",
      sourceScanRule: "QR fallback must be display-only in Chat."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .qrLiveScan,
      owner: .futureScope,
      lifecycle: .deferred,
      disposition: .deferred,
      swiftUIOption: "Live scan is deferred until an app-level scanner service is approved.",
      failureFallback: "Use manual bind, code display or app-host selection route instead of live scan.",
      manualQACase: "Tap scan entry and verify it degrades to the manual fallback without camera UI in Chat.",
      sourceScanRule: "Chat module must not contain scanner or live camera UI."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .permissionRequest,
      owner: .swiftUIAppHost,
      lifecycle: .userAction,
      disposition: .appBoundaryRequired,
      swiftUIOption: "Permission prompts are owned by the app host and reported back as value errors or payloads.",
      failureFallback: "Denied or restricted permissions show a stable toast and leave pending send state untouched.",
      manualQACase: "Denied photo, camera, microphone, notification and file access permissions.",
      sourceScanRule: "Chat module must not open system settings or permission prompts directly."
    ),
    ChatNativeBoundaryCapabilityPolicy(
      capability: .urlOpen,
      owner: .swiftUIAppHost,
      lifecycle: .route,
      disposition: .appBoundaryRequired,
      swiftUIOption: "SwiftUI app host URL interaction service or host router opens external links and unsupported files.",
      failureFallback: "Unsupported URLs become route diagnostics or in-chat unsupported fallback views.",
      manualQACase: "Open http link, unsupported scheme, file URL and blocked external URL.",
      sourceScanRule: "Chat module must route URL opening through value routes or host services."
    ),
  ]

  public static func firstPhaseCapability(_ capability: ChatNativeBoundaryCapability) -> ChatNativeBoundaryCapabilityPolicy? {
    firstPhaseCapabilities.first { $0.capability == capability }
  }
}

public protocol ChatNativeBoundaryHandling {
  func handle(action: ChatMoreAction,
              context: ChatSessionContext,
              completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public struct ChatNativeBoundaryHandler: ChatNativeBoundaryHandling {
  private let handler: (ChatMoreAction, ChatSessionContext, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatMoreAction, ChatSessionContext, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handle(action: ChatMoreAction,
                     context: ChatSessionContext,
                     completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(action, context, completion)
  }
}

public enum ChatAvatarSelectionSource: String, Equatable {
  case aiRobotCreate
  case aiRobotEdit
  case profileEdit
}

public struct ChatAvatarSelectionRequest: Equatable {
  public var source: ChatAvatarSelectionSource
  public var currentAvatarURL: URL?
  public var displayName: String
  public var accountId: String?

  public init(source: ChatAvatarSelectionSource,
              currentAvatarURL: URL? = nil,
              displayName: String,
              accountId: String? = nil) {
    self.source = source
    self.currentAvatarURL = currentAvatarURL
    self.displayName = displayName
    self.accountId = accountId
  }
}

public enum ChatAvatarSelectionResult: Equatable {
  case selected(URL)
  case cancelled
}

public protocol ChatAvatarSelectionHandling {
  func selectAvatar(request: ChatAvatarSelectionRequest,
                    completion: @escaping (Result<ChatAvatarSelectionResult, Error>) -> Void)
}

public struct ChatAvatarSelectionHandler: ChatAvatarSelectionHandling {
  private let handler: (ChatAvatarSelectionRequest, @escaping (Result<ChatAvatarSelectionResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatAvatarSelectionRequest, @escaping (Result<ChatAvatarSelectionResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func selectAvatar(request: ChatAvatarSelectionRequest,
                           completion: @escaping (Result<ChatAvatarSelectionResult, Error>) -> Void) {
    handler(request, completion)
  }
}
