// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonStateContainer<Value: Equatable, Content: View, IdleContent: View>: View {
  private let state: NECommonAsyncState<Value>
  private let empty: NECommonEmptyState?
  private let retry: (() -> Void)?
  private let idleContent: () -> IdleContent
  private let content: (Value) -> Content

  public init(state: NECommonAsyncState<Value>,
              empty: NECommonEmptyState? = nil,
              retry: (() -> Void)? = nil,
              @ViewBuilder idleContent: @escaping () -> IdleContent,
              @ViewBuilder content: @escaping (Value) -> Content) {
    self.state = state
    self.empty = empty
    self.retry = retry
    self.idleContent = idleContent
    self.content = content
  }

  public var body: some View {
    switch state {
    case .idle:
      idleContent()
    case .loading:
      NECommonLoadingView()
    case let .success(value):
      if let empty, isKnownEmpty(value) {
        NECommonEmptyStateView(state: empty)
      } else {
        content(value)
      }
    case let .failure(error):
      NECommonErrorStateView(state: error, retry: retry)
    }
  }

  private func isKnownEmpty(_ value: Value) -> Bool {
    if let collection = value as? any Collection {
      return collection.isEmpty
    }
    return false
  }
}

public extension NECommonStateContainer where IdleContent == EmptyView {
  init(state: NECommonAsyncState<Value>,
       empty: NECommonEmptyState? = nil,
       retry: (() -> Void)? = nil,
       @ViewBuilder content: @escaping (Value) -> Content) {
    self.init(state: state,
              empty: empty,
              retry: retry,
              idleContent: { EmptyView() },
              content: content)
  }
}
