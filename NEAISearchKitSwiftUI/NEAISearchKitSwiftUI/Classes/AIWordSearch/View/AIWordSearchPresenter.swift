// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public extension View {
  func aiWordSearchPresenter(client: NEAISearchSwiftUIClient = .shared) -> some View {
    modifier(AIWordSearchPresenter(client: client))
  }
}

private struct AIWordSearchPresenter: ViewModifier {
  @ObservedObject var client: NEAISearchSwiftUIClient

  func body(content: Content) -> some View {
    content
      .overlay {
        if let route = client.activeRoute {
          ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
              .ignoresSafeArea()
              .onTapGesture {
                client.dismissActiveRoute()
              }

            AIWordSearchView(route: route) {
              client.dismissActiveRoute()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          .ignoresSafeArea(edges: .bottom)
        }
      }
      .overlay(alignment: .top) {
        if let toast = client.toastMessage {
          AIWordSearchPresenterToastView(message: toast)
            .padding(.top, 56)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
              DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                client.consumeToast()
              }
            }
        }
      }
      .animation(.easeInOut(duration: 0.25), value: client.activeRoute?.id)
      .animation(.easeInOut(duration: 0.2), value: client.toastMessage)
  }
}

private struct AIWordSearchPresenterToastView: View {
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
