// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum CommonPreviewFixtures {
  public struct Item: Equatable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
      self.id = id
      self.title = title
    }
  }

  public struct Route: NECommonRouteValue {
    public var id: String

    public init(id: String) {
      self.id = id
    }
  }

  public static let error = NECommonErrorState(
    textKey: "common_error",
    fallbackText: "Operation failed",
    severity: .error,
    retryable: true
  )

  public static let empty = NECommonEmptyState(
    titleKey: "common_empty",
    fallbackTitle: "No content",
    messageKey: "common_empty_desc",
    fallbackMessage: "Nothing to show yet.",
    actionTitleKey: "common_retry",
    fallbackActionTitle: "Retry"
  )

  public static let asyncState = NECommonAsyncState<Item>.success(
    Item(id: "common-item", title: "Common Item")
  )

  public static let asyncPhase = NECommonAsyncPhase.failed(error)

  public static let pageState = NECommonPageState(
    hasMore: true,
    isLoadingMore: true,
    cursor: "cursor-preview"
  )

  public static let listState = NECommonListState(
    items: [
      Item(id: "item-1", title: "First"),
      Item(id: "item-2", title: "Second"),
    ],
    phase: .refreshing,
    page: pageState,
    empty: empty,
    error: error
  )

  public static let mutationState = NECommonMutationState(
    isMutating: true,
    error: error,
    rollbackIntent: "rollback-preview"
  )

  public static let selectionState = NECommonSelectionState<String>(
    selectedIDs: Set(["item-1", "item-2"]),
    limit: 3
  )

  public static let segmentedOptions = [
    NECommonSegmentedOption(id: "all", title: "All"),
    NECommonSegmentedOption(id: "media", title: "Media"),
    NECommonSegmentedOption(id: "disabled", title: "Disabled", isEnabled: false),
  ]

  public static let toast = NECommonToastState(
    textKey: "common_success",
    fallbackText: "Saved",
    level: .success,
    duration: 1.5
  )

  public static let blockingLoading = NECommonBlockingLoadingState(
    id: "commonBlockingLoadingPreview",
    textKey: "common_loading",
    fallbackText: "Loading",
    showsScrim: true,
    blocksInteraction: true
  )

  public static let dialog = NECommonDialogState(
    id: "dialog-preview",
    title: "Delete item?",
    message: "This action cannot be undone.",
    actions: [
      NECommonDialogAction(
        id: "delete",
        title: "Delete",
        systemImageName: "trash",
        role: .destructive
      ),
      NECommonDialogAction(
        id: "cancel",
        title: "Cancel",
        systemImageName: "xmark",
        role: .cancel
      ),
    ]
  )

  public static let navigationAction = NECommonNavigationAction(
    id: "common-route",
    title: "Open",
    systemImage: "chevron.right"
  )

  public static let route = Route(id: "route-preview")

  public static let permissionState = NECommonPermissionState(
    capability: .unavailable(reason: "host-service-missing"),
    isGranted: false
  )

  public static let boundaryResult = NECommonBoundaryResult.failure(error)

  public static let keyboardState = NECommonKeyboardState(
    height: 320,
    isVisible: true
  )

  public static let mediaValue = NECommonMediaValue(
    id: "media-preview",
    url: URL(string: "https://example.com/image.png"),
    name: "image.png",
    mimeType: "image/png",
    kind: .image
  )

  public static let fileValue = NECommonFileValue(
    id: "file-preview",
    url: URL(string: "https://example.com/report.pdf"),
    name: "report.pdf",
    mimeType: "application/pdf",
    sizeBytes: 4096
  )

  public static let audioValue = NECommonAudioValue(
    id: "audio-preview",
    url: URL(string: "https://example.com/audio.m4a"),
    name: "audio.m4a",
    mimeType: "audio/mp4",
    duration: 12.5,
    sizeBytes: 2048
  )

  public static let locationValue = NECommonLocationValue(
    latitude: 30.27,
    longitude: 120.15,
    title: "Hangzhou",
    address: "West Lake"
  )

  public static let mediaResult = NECommonValueServiceResult.success(mediaValue)
  public static let fileResult = NECommonValueServiceResult.success(fileValue)
  public static let audioResult = NECommonValueServiceResult.success(audioValue)
  public static let locationResult = NECommonValueServiceResult.success(locationValue)
}
