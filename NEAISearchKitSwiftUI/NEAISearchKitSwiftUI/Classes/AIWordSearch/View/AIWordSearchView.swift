// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct AIWordSearchView: View {
  @StateObject private var viewModel: AIWordSearchViewModel
  public var onDismiss: () -> Void

  public init(route: AIWordSearchRoute,
              onDismiss: @escaping () -> Void) {
    _viewModel = StateObject(wrappedValue: AIWordSearchViewModel(route: route))
    self.onDismiss = onDismiss
  }

  public var body: some View {
    VStack(spacing: 0) {
      titleBar
      if viewModel.state.isSupplementExpanded {
        supplementInput
          .padding(.horizontal, 20)
          .padding(.top, 16)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      resultList
    }
    .frame(maxWidth: .infinity)
    .frame(height: viewModel.state.isSupplementExpanded ? NEAISearchSwiftUIConstants.expandedPanelHeight : NEAISearchSwiftUIConstants.defaultPanelHeight)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.gray.opacity(0.45), lineWidth: 0.5)
    }
    .animation(.easeInOut(duration: 0.25), value: viewModel.state.isSupplementExpanded)
    .onAppear {
      viewModel.onAppear()
    }
    .onDisappear {
      viewModel.dismiss()
    }
    .overlay(alignment: .top) {
      if let toast = viewModel.state.toastMessage {
        AIWordSearchToastView(message: toast)
          .padding(.top, 58)
          .transition(.move(edge: .top).combined(with: .opacity))
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
              viewModel.consumeToast()
            }
          }
      }
    }
  }

  private var titleBar: some View {
    HStack(spacing: 8) {
      Button {
        dismiss()
      } label: {
        Text(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.cancel, value: "Cancel"))
          .font(.system(size: 16))
          .foregroundStyle(NEAISearchSwiftUIConstants.darkTextColor)
          .frame(minWidth: 48, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("id.cancel")

      Spacer(minLength: 8)

      HStack(spacing: 4) {
        if viewModel.state.isLoading {
          AISearchLoadingIndicator()
        }
        Text(viewModel.state.title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(NEAISearchSwiftUIConstants.titleTextColor)
          .lineLimit(1)
          .accessibilityIdentifier("id.title")
      }
      .frame(maxWidth: .infinity)

      Spacer(minLength: 8)

      if !viewModel.state.isSupplementExpanded {
        Button {
          viewModel.expandSupplement()
        } label: {
          HStack(spacing: 4) {
            NEAISearchSwiftUIBundle.image(named: NEAISearchSwiftUIConstants.expandIconName)
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
            Text(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.inputMoreButton, value: "Add More"))
              .font(.system(size: 16))
              .lineLimit(1)
          }
          .foregroundStyle(NEAISearchSwiftUIConstants.actionColor)
          .frame(minWidth: 92, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("id.moreButton")
      } else {
        Color.clear
          .frame(width: 92, height: 18)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 50)
    .background(Color.white)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(NEAISearchSwiftUIConstants.titleBarLineColor)
        .frame(height: 1)
    }
  }

  private var supplementInput: some View {
    AIWordSearchSupplementInputView(
      text: Binding(
        get: { viewModel.state.supplementText },
        set: { viewModel.updateSupplementText($0) }
      ),
      canSubmit: viewModel.state.canSubmitSupplement
    ) {
      viewModel.submitSupplement()
    }
  }

  private var resultList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(viewModel.state.results.enumerated()), id: \.element.id) { index, result in
          AIWordSearchResultRowView(
            result: result,
            showsSeparator: shouldShowSeparator(index: index)
          )
        }
      }
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.immediately)
  }

  private func shouldShowSeparator(index: Int) -> Bool {
    !(viewModel.state.results.count == 1 && !viewModel.state.isSupplementExpanded) &&
      index < viewModel.state.results.count
  }

  private func dismiss() {
    viewModel.dismiss()
    onDismiss()
  }
}

private struct AIWordSearchToastView: View {
  var message: String

  var body: some View {
    Text(message)
      .font(.system(size: 14))
      .foregroundStyle(Color.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.76), in: Capsule())
      .padding(.horizontal, 24)
  }
}
