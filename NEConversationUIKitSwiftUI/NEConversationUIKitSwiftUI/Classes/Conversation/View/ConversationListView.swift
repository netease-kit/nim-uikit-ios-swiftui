// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import SwiftUI
import UIKit

public struct ConversationListView: View {
  @StateObject private var viewModel: ConversationListViewModel
  @State private var searchText = ""
  @State private var isSearchPresented = false
  @State private var openSwipeRowID: String?
  @StateObject private var scrollRuntime = ConversationListScrollRuntimeState()
  private let token: ConversationThemeToken

  @MainActor
  public init(viewModel: ConversationListViewModel,
              token: ConversationThemeToken? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token ?? viewModel.config.themeToken
  }

  public var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 0) {
        if viewModel.config.showTitleBar {
          ConversationHeaderView(
            title: viewModel.config.title ?? NEConversationUIKitSwiftUIBundle.localized("appName", value: "CommsEase IM"),
            config: viewModel.config,
            token: token,
            onSearch: {
              openSearch()
            },
            onAdd: {
              viewModel.toggleActionMenu()
            }
          )
        }

        bodyTopContent

        ConversationAIUserStripView(
          aiUsers: viewModel.state.aiUsers,
          token: token,
          onSelect: viewModel.selectAIUser
        )

        content
      }
      .background(token.pageBackground)

      if viewModel.state.isActionMenuPresented {
        Color.black.opacity(0.001)
          .ignoresSafeArea()
          .onTapGesture {
            viewModel.dismissActionMenu()
          }

        ConversationActionMenuView(
          token: token,
          showScanQREntry: viewModel.config.showScanQREntry
        ) { action in
          viewModel.performAction(action)
        }
        .padding(.top, viewModel.config.showTitleBar ? 44 : 8)
        .padding(.trailing, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .zIndex(2)
      }
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: $isSearchPresented) {
      ConversationSearchView(
        viewModel: ConversationSearchViewModel(),
        token: token,
        onSelect: { route in
          isSearchPresented = false
          // Match UIKit's pop-then-push order. Enqueuing the team chat in the
          // same navigation transaction can otherwise leave its destination
          // without a live host and render a blank page.
          DispatchQueue.main.async {
            openChatRoute(route)
          }
        }
      )
      .neCommonRequestsTabBarHidden()
    }
    .onAppear {
      scrollRuntime.restoreCapturedPosition()
      viewModel.onAppear()
    }
    .onDisappear {
      scrollRuntime.capturePositionIfNeeded()
      viewModel.onDisappear()
    }
    .onChange(of: searchText) { text in
      viewModel.setSearchText(text)
    }
    .onChange(of: viewModel.state.pendingRoute) { route in
      guard let route else {
        return
      }
      openChatRoute(route)
      viewModel.consumePendingRoute()
    }
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 52,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  @ViewBuilder
  private var bodyTopContent: some View {
    if shouldShowInlineSearchEntry {
      searchField
    }

    if let customView = viewModel.config.bodyTopContentProvider?(
      ConversationBodyTopContentContext(
        mode: viewModel.mode,
        styleMode: token.styleMode,
        state: viewModel.state
      )
    ) {
      customView
    }

    if viewModel.state.networkBroken {
      ConversationNetworkBannerView(token: token)
    }
  }

  private var searchField: some View {
    Button {
      openSearch()
    } label: {
      HStack(spacing: 8) {
        Image(token.styleMode == .fun ? "fun_search" : "nav_search",
              bundle: NECommonUIKitSwiftUIBundle.bundle)
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(width: token.styleMode == .fun ? 16 : 20,
                 height: token.styleMode == .fun ? 16 : 20)
        Text(NEConversationUIKitSwiftUIBundle.localized("search", value: "Search"))
          .font(.system(size: token.styleMode == .fun ? 16 : 14))
          .foregroundColor(token.secondaryTextColor)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: token.styleMode == .fun ? 36 : 34)
      .background(searchFieldBackground, in: RoundedRectangle(cornerRadius: token.styleMode == .fun ? 4 : 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, token.styleMode == .fun ? 8 : 16)
    .padding(.top, token.styleMode == .fun ? 12 : 8)
    .padding(.bottom, token.styleMode == .fun ? 12 : 8)
    .neCommonTheme(NEConversationCommonPresentation.searchTheme(for: token))
  }

  private var shouldShowInlineSearchEntry: Bool {
    token.styleMode == .fun
  }

  private var searchFieldBackground: Color {
    token.styleMode == .fun ? .white : token.searchBackground
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEConversationUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(
        state: NECommonErrorState(
          textKey: "network_error",
          fallbackText: message,
          severity: .warning,
          retryable: true
        ),
        retry: {
          viewModel.loadInitial()
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
    case .loaded:
      if viewModel.state.shouldShowEmpty {
        NECommonEmptyStateView(
          state: NECommonEmptyState(
            titleKey: "session_empty",
            fallbackTitle: NEConversationUIKitSwiftUIBundle.localized("session_empty", value: "No Session"),
            imageKind: .user
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
      } else {
        list
      }
    }
  }

  private var list: some View {
    let rows = viewModel.state.filteredRows
    return ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(rows) { row in
          ConversationSwipeRow(
            row: row,
            token: token,
            openRowID: $openSwipeRowID,
            onSelect: {
              scrollRuntime.capturePosition()
              viewModel.select(row)
            },
            onDelete: {
              viewModel.delete(row)
            },
            onToggleStickTop: {
              viewModel.toggleStickTop(row)
            }
          )
          .id(row.id)
          .onAppear {
            loadMoreIfNeeded(for: row)
          }
        }

        if viewModel.state.isLoadingMore {
          NECommonInlineLoadingView(title: nil)
            .frame(height: 44)
            .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
        }

        Color.clear
          .frame(height: 12)
      }
      .frame(height: listContentHeight(rowCount: rows.count), alignment: .top)
      .background {
        ConversationListScrollViewProbe(runtimeState: scrollRuntime)
      }
    }
    .scrollDismissesKeyboard(.immediately)
    .background(token.pageBackground)
  }

  private func loadMoreIfNeeded(for row: ConversationRowState) {
    guard row.id == viewModel.state.rows.last?.id else {
      return
    }
    viewModel.loadMoreIfNeeded(currentRow: row)
  }

  private func listContentHeight(rowCount: Int) -> CGFloat {
    CGFloat(rowCount) * token.rowHeight +
      (viewModel.state.isLoadingMore ? 44 : 0) + 12
  }

  private func openChatRoute(_ route: ConversationRouteContext) {
    let context = ChatSessionContext(
      kind: route.isRobot ? .botSubSession : route.kind,
      conversationId: route.conversationId,
      title: route.title,
      sessionId: route.targetId,
      sessionName: route.title
    )
    if route.isRobot {
      NEChatUIKitSwiftUIClient.shared.router.enqueue(.botSubSessionList(context))
    } else if route.kind == .team {
      NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(context))
    } else {
      NEChatUIKitSwiftUIClient.shared.router.enqueue(.p2pChat(context))
    }
  }

  private func openSearch() {
    if ConversationSwiftUIConfigCenter.shared.current().searchHandler != nil {
      viewModel.openSearch()
    } else {
      viewModel.clearSearch()
      searchText = ""
      isSearchPresented = true
    }
  }
}

@MainActor
private final class ConversationListScrollRuntimeState: NSObject, ObservableObject {
  private struct Snapshot {
    var contentOffsetY: CGFloat
  }

  weak var scrollView: UIScrollView?
  private var snapshot: Snapshot?
  private var hasCapturedPositionForPresentation = false
  private var isRestorationPending = false
  private var restorationGeneration = 0
  private var baselineRestorationGeneration: Int?
  private weak var baselineRestorationScrollView: UIScrollView?
  private var scheduledRestorationGeneration: Int?
  private weak var scheduledRestorationScrollView: UIScrollView?
  private weak var observedScrollView: UIScrollView?
  private var contentOffsetObservation: NSKeyValueObservation?
  private var boundsObservation: NSKeyValueObservation?
  private var contentSizeObservation: NSKeyValueObservation?
  private var isApplyingOffset = false
  private var isReturnOffsetGuardEnabled = false

  func attach(_ scrollView: UIScrollView?) {
    observeScrollView(scrollView)
    self.scrollView = scrollView
    guard isRestorationPending else {
      return
    }
    if isReturnOffsetGuardEnabled {
      restoreBaselineIfPossible(generation: restorationGeneration)
    }
    scheduleSingleRestore(generation: restorationGeneration)
  }

  func capturePosition() {
    guard let scrollView else {
      return
    }
    snapshot = Snapshot(contentOffsetY: scrollView.contentOffset.y)
    hasCapturedPositionForPresentation = true
    isRestorationPending = true
    restorationGeneration += 1
    baselineRestorationGeneration = nil
    baselineRestorationScrollView = nil
    scheduledRestorationGeneration = nil
    scheduledRestorationScrollView = nil
    isReturnOffsetGuardEnabled = true
  }

  func capturePositionIfNeeded() {
    guard !hasCapturedPositionForPresentation else {
      return
    }
    capturePosition()
  }

  func restoreCapturedPosition() {
    guard snapshot != nil, hasCapturedPositionForPresentation else {
      return
    }
    isRestorationPending = true
    restorationGeneration += 1
    baselineRestorationGeneration = nil
    baselineRestorationScrollView = nil
    scheduledRestorationGeneration = nil
    scheduledRestorationScrollView = nil
    isReturnOffsetGuardEnabled = false
    scheduleSingleRestore(generation: restorationGeneration)
  }

  private func observeScrollView(_ scrollView: UIScrollView?) {
    guard observedScrollView !== scrollView else {
      return
    }
    observedScrollView?.panGestureRecognizer.removeTarget(
      self,
      action: #selector(scrollViewPanGestureChanged(_:))
    )
    contentOffsetObservation = nil
    boundsObservation = nil
    contentSizeObservation = nil
    observedScrollView = scrollView
    guard let scrollView else {
      return
    }
    scrollView.panGestureRecognizer.addTarget(
      self,
      action: #selector(scrollViewPanGestureChanged(_:))
    )
    contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
      guard let scrollView else {
        return
      }
      MainActor.assumeIsolated {
        self?.scrollOffsetDidChange(scrollView)
      }
    }
    boundsObservation = scrollView.observe(\.bounds, options: [.new]) { [weak self, weak scrollView] _, _ in
      guard let scrollView else {
        return
      }
      MainActor.assumeIsolated {
        self?.scrollBoundsDidChange(scrollView)
      }
    }
    contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak scrollView] _, _ in
      guard let scrollView else {
        return
      }
      MainActor.assumeIsolated {
        self?.scrollContentSizeDidChange(scrollView)
      }
    }
  }

  private func scrollOffsetDidChange(_ scrollView: UIScrollView) {
    guard isReturnOffsetGuardEnabled,
          isRestorationPending,
          !isApplyingOffset,
          self.scrollView === scrollView,
          let snapshot,
          !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    applyOffset(snapshot.contentOffsetY, to: scrollView)
  }

  private func scrollBoundsDidChange(_ scrollView: UIScrollView) {
    guard isReturnOffsetGuardEnabled,
          isRestorationPending,
          !isApplyingOffset,
          self.scrollView === scrollView,
          let snapshot,
          !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    applyOffset(snapshot.contentOffsetY, to: scrollView)
  }

  private func scrollContentSizeDidChange(_ scrollView: UIScrollView) {
    guard isReturnOffsetGuardEnabled,
          isRestorationPending,
          !isApplyingOffset,
          self.scrollView === scrollView,
          let snapshot,
          !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    applyOffset(snapshot.contentOffsetY, to: scrollView)
  }

  private func restoreBaselineIfPossible(generation: Int) {
    guard isRestorationPending,
          restorationGeneration == generation,
          baselineRestorationGeneration != generation || baselineRestorationScrollView !== scrollView,
          let snapshot,
          let scrollView,
          !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    baselineRestorationGeneration = generation
    baselineRestorationScrollView = scrollView
    scrollView.superview?.layoutIfNeeded()
    scrollView.layoutIfNeeded()
    applyOffset(snapshot.contentOffsetY, to: scrollView)
  }

  private func restoreTransitionBaselineIfPossible(generation: Int) {
    guard isRestorationPending,
          restorationGeneration == generation,
          let snapshot,
          let scrollView,
          !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    scrollView.superview?.layoutIfNeeded()
    scrollView.layoutIfNeeded()
    applyOffset(snapshot.contentOffsetY, to: scrollView)
  }

  @discardableResult
  private func applyOffset(_ proposedOffsetY: CGFloat, to scrollView: UIScrollView) -> Bool {
    let minimumOffsetY = -scrollView.adjustedContentInset.top
    let maximumOffsetY = max(
      minimumOffsetY,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
    )
    guard proposedOffsetY <= maximumOffsetY + 0.5 else {
      return false
    }
    let targetOffsetY = min(maximumOffsetY, max(minimumOffsetY, proposedOffsetY))
    guard abs(scrollView.contentOffset.y - targetOffsetY) > 0.5 else {
      return true
    }
    isApplyingOffset = true
    defer {
      isApplyingOffset = false
    }
    UIView.performWithoutAnimation {
      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY),
        animated: false
      )
      scrollView.layer.removeAllAnimations()
    }
    return true
  }

  private func finishRestoration() {
    isReturnOffsetGuardEnabled = false
    snapshot = nil
    hasCapturedPositionForPresentation = false
    isRestorationPending = false
    baselineRestorationGeneration = nil
    baselineRestorationScrollView = nil
    scheduledRestorationGeneration = nil
    scheduledRestorationScrollView = nil
  }

  private func enableReturnOffsetGuard(generation: Int) {
    guard isRestorationPending,
          restorationGeneration == generation else {
      return
    }
    isReturnOffsetGuardEnabled = true
    restoreTransitionBaselineIfPossible(generation: generation)
  }

  func scrollInteractionDidBegin() {
    guard isRestorationPending else {
      return
    }
    finishRestoration()
  }

  @objc private func scrollViewPanGestureChanged(_ gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.state == .began else {
      return
    }
    scrollInteractionDidBegin()
  }

  private func scheduleSingleRestore(generation: Int) {
    guard isRestorationPending,
          restorationGeneration == generation,
          scheduledRestorationGeneration != generation || scheduledRestorationScrollView !== scrollView,
          let scrollView else {
      return
    }
    scheduledRestorationGeneration = generation
    scheduledRestorationScrollView = scrollView

    if !registerNavigationTransitionCompletion(for: scrollView, generation: generation) {
      enableReturnOffsetGuard(generation: generation)
      scheduleRestoreAfterLayoutCommit(generation: generation, transitionWasCancelled: false)
    }
  }

  private func scheduleRestoreAfterLayoutCommit(generation: Int,
                                                transitionWasCancelled: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.restoreOffsetIfNeeded(
        generation: generation,
        transitionWasCancelled: transitionWasCancelled
      )
    }
  }

  private func restoreOffsetIfNeeded(generation: Int,
                                     transitionWasCancelled: Bool) {
    guard isRestorationPending,
          restorationGeneration == generation else {
      return
    }
    guard !transitionWasCancelled else {
      isReturnOffsetGuardEnabled = false
      isRestorationPending = false
      scheduledRestorationGeneration = nil
      scheduledRestorationScrollView = nil
      return
    }
    guard let snapshot, let scrollView else {
      return
    }

    scrollView.superview?.layoutIfNeeded()
    scrollView.layoutIfNeeded()
    guard !scrollView.isTracking,
          !scrollView.isDragging,
          !scrollView.isDecelerating else {
      return
    }
    if abs(scrollView.contentOffset.y - snapshot.contentOffsetY) > 0.5 {
      applyOffset(snapshot.contentOffsetY, to: scrollView)
    }
  }

  private func registerNavigationTransitionCompletion(for scrollView: UIScrollView,
                                                      generation: Int) -> Bool {
    guard let rootViewController = scrollView.window?.rootViewController else {
      return false
    }
    var candidates = [rootViewController]
    while let candidate = candidates.popLast() {
      candidates.append(contentsOf: candidate.children)
      if let presentedViewController = candidate.presentedViewController {
        candidates.append(presentedViewController)
      }
      guard candidate.isViewLoaded,
            scrollView.isDescendant(of: candidate.view),
            let transitionCoordinator = candidate.transitionCoordinator ??
            candidate.navigationController?.transitionCoordinator else {
        continue
      }
      let isInteractive = transitionCoordinator.isInteractive
      let didRegisterCompletion = transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
        self?.scheduleRestoreAfterLayoutCommit(
          generation: generation,
          transitionWasCancelled: context.isCancelled
        )
      }
      if didRegisterCompletion {
        if isInteractive {
          transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
            guard !context.isCancelled else {
              self?.isReturnOffsetGuardEnabled = false
              return
            }
            self?.enableReturnOffsetGuard(generation: generation)
          }
        } else {
          enableReturnOffsetGuard(generation: generation)
        }
        return true
      }
    }
    return false
  }
}

private struct ConversationListScrollViewProbe: UIViewRepresentable {
  weak var runtimeState: ConversationListScrollRuntimeState?

  func makeUIView(context: Context) -> ConversationListScrollViewProbeView {
    let view = ConversationListScrollViewProbeView(frame: .zero)
    context.coordinator.runtimeState = runtimeState
    view.runtimeState = runtimeState
    view.resolveScrollView()
    return view
  }

  func updateUIView(_ uiView: ConversationListScrollViewProbeView, context: Context) {
    context.coordinator.runtimeState = runtimeState
    uiView.runtimeState = runtimeState
    uiView.resolveScrollView()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator {
    weak var runtimeState: ConversationListScrollRuntimeState?
  }
}

private final class ConversationListScrollViewProbeView: UIView {
  weak var runtimeState: ConversationListScrollRuntimeState?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    resolveScrollView()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    resolveScrollView()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    resolveScrollView()
  }

  func resolveScrollView() {
    var candidate = superview
    while let current = candidate {
      if let scrollView = current as? UIScrollView {
        runtimeState?.attach(scrollView)
        return
      }
      candidate = current.superview
    }
    runtimeState?.attach(nil)
  }
}

private struct ConversationSwipeRow: View {
  private static let actionWidth: CGFloat = 80

  let row: ConversationRowState
  let token: ConversationThemeToken
  @Binding var openRowID: String?
  let onSelect: () -> Void
  let onDelete: () -> Void
  let onToggleStickTop: () -> Void

  @State private var dragTranslation: CGFloat?

  private var isOpen: Bool {
    openRowID == row.id
  }

  private var totalActionWidth: CGFloat {
    Self.actionWidth * 2
  }

  private var contentOffset: CGFloat {
    let restingOffset = isOpen ? -totalActionWidth : 0
    return min(0, max(-totalActionWidth, restingOffset + (dragTranslation ?? 0)))
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      actionButtons
        .frame(width: totalActionWidth)
        .mask(alignment: .trailing) {
          Rectangle()
            .frame(width: max(-contentOffset, 0))
        }
        .allowsHitTesting(isOpen && dragTranslation == nil)
        .zIndex(1)

      ZStack {
        ConversationRowView(row: row, token: token)

        ConversationSwipeGestureSurface(
          horizontalDominanceRatio: 1.2,
          onTap: handleTap,
          onSwipeChanged: { translation in
            dragTranslation = translation
          },
          onSwipeEnded: { projectedTranslation in
            finishSwipe(projectedTranslation: projectedTranslation)
          },
          onSwipeCancelled: {
            dragTranslation = nil
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
        .offset(x: contentOffset)
        .contentShape(Rectangle())
        .zIndex(0)
    }
    .frame(maxWidth: .infinity)
    .frame(height: token.rowHeight)
    .clipped()
    .accessibilityAction(named: Text(stickTopTitle)) {
      performAction(onToggleStickTop)
    }
    .accessibilityAction(named: Text(deleteTitle)) {
      performAction(onDelete)
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 0) {
      actionButton(
        title: stickTopTitle,
        background: token.topActionColor,
        action: onToggleStickTop
      )

      actionButton(
        title: deleteTitle,
        background: token.destructiveColor,
        action: onDelete
      )
    }
    .accessibilityHidden(!isOpen)
  }

  private func actionButton(title: String,
                            background: Color,
                            action: @escaping () -> Void) -> some View {
    Button {
      performAction(action)
    } label: {
      Text(title)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .frame(width: Self.actionWidth, height: token.rowHeight)
        .background(background)
    }
    .buttonStyle(.plain)
  }

  private func handleTap() {
    if openRowID == nil {
      onSelect()
    } else {
      closeActions()
    }
  }

  private func finishSwipe(projectedTranslation: CGFloat) {
    let restingOffset = isOpen ? -totalActionWidth : 0
    let projectedOffset = restingOffset + projectedTranslation
    withAnimation(.easeOut(duration: 0.18)) {
      openRowID = projectedOffset < -totalActionWidth / 2 ? row.id : nil
      dragTranslation = nil
    }
  }

  private var stickTopTitle: String {
    row.isStickTop
      ? NEConversationUIKitSwiftUIBundle.localized("cancel_stickTop", value: "Remove from top")
      : NEConversationUIKitSwiftUIBundle.localized("stickTop", value: "Sticky on Top")
  }

  private var deleteTitle: String {
    NEConversationUIKitSwiftUIBundle.localized("delete", value: "Delete")
  }

  private func performAction(_ action: () -> Void) {
    openRowID = nil
    action()
  }

  private func closeActions() {
    withAnimation(.easeOut(duration: 0.18)) {
      openRowID = nil
    }
  }
}

private struct ConversationSwipeGestureSurface: UIViewRepresentable {
  let horizontalDominanceRatio: CGFloat
  let onTap: () -> Void
  let onSwipeChanged: (CGFloat) -> Void
  let onSwipeEnded: (CGFloat) -> Void
  let onSwipeCancelled: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear

    let tapGesture = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap(_:))
    )
    let panGesture = UIPanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handlePan(_:))
    )
    panGesture.maximumNumberOfTouches = 1
    panGesture.delegate = context.coordinator
    tapGesture.require(toFail: panGesture)
    view.addGestureRecognizer(tapGesture)
    view.addGestureRecognizer(panGesture)
    return view
  }

  func updateUIView(_: UIView, context: Context) {
    context.coordinator.surface = self
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(surface: self)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var surface: ConversationSwipeGestureSurface

    init(surface: ConversationSwipeGestureSurface) {
      self.surface = surface
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      guard gestureRecognizer.state == .ended else {
        return
      }
      surface.onTap()
    }

    @objc func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
      let translation = gestureRecognizer.translation(in: gestureRecognizer.view).x
      switch gestureRecognizer.state {
      case .changed:
        surface.onSwipeChanged(translation)
      case .ended:
        let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view).x
        surface.onSwipeEnded(translation + velocity * 0.2)
      case .cancelled, .failed:
        surface.onSwipeCancelled()
      default:
        break
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
        return true
      }
      let velocity = panGesture.velocity(in: panGesture.view)
      return abs(velocity.x) > abs(velocity.y) * surface.horizontalDominanceRatio
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      gestureRecognizer is UIPanGestureRecognizer &&
        otherGestureRecognizer.view is UIScrollView
    }
  }
}
