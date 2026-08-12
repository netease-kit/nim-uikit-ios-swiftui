// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum MediaZoomPageDirection {
  case previous
  case next
}

public struct MediaZoomModifier: ViewModifier {
  private let minScale: CGFloat
  private let maxScale: CGFloat
  private let doubleTapScale: CGFloat
  private let onPageRequest: (MediaZoomPageDirection) -> Bool

  @State private var committedScale: CGFloat = 1
  @State private var activeMagnification: CGFloat = 1
  @State private var committedOffset: CGSize = .zero
  @State private var activeDragOffset: CGSize = .zero

  public init(minScale: CGFloat = 1,
              maxScale: CGFloat = 4,
              doubleTapScale: CGFloat = 2.5,
              onPageRequest: @escaping (MediaZoomPageDirection) -> Bool = { _ in false }) {
    self.minScale = minScale
    self.maxScale = maxScale
    self.doubleTapScale = doubleTapScale
    self.onPageRequest = onPageRequest
  }

  public func body(content: Content) -> some View {
    GeometryReader { proxy in
      let scale = boundedScale(committedScale * activeMagnification)
      let proposedOffset = CGSize(
        width: committedOffset.width + activeDragOffset.width,
        height: committedOffset.height + activeDragOffset.height
      )
      let offset = displayedOffset(
        proposedOffset,
        scale: scale,
        container: proxy.size
      )

      let zoomedContent = content
        .frame(width: proxy.size.width, height: proxy.size.height)
        .scaleEffect(scale)
        .offset(offset)
        .contentShape(Rectangle())
        .clipped()
        .highPriorityGesture(magnificationGesture(in: proxy.size))
        .simultaneousGesture(doubleTapGesture(in: proxy.size))
        .highPriorityGesture(
          dragGesture(in: proxy.size, scale: scale),
          including: scale > normalizedMinScale ? .all : .none
        )

      zoomedContent
    }
  }

  private func magnificationGesture(in container: CGSize) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        activeMagnification = value
      }
      .onEnded { value in
        let nextScale = boundedScale(committedScale * value)
        withoutAnimation {
          committedScale = nextScale
          committedOffset = nextScale <= normalizedMinScale
            ? .zero
            : boundedOffset(committedOffset, scale: nextScale, container: container)
          activeMagnification = 1
        }
      }
  }

  private func dragGesture(in container: CGSize, scale: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        guard scale > normalizedMinScale else {
          activeDragOffset = .zero
          return
        }
        activeDragOffset = value.translation
      }
      .onEnded { value in
        guard scale > normalizedMinScale else {
          withoutAnimation {
            activeDragOffset = .zero
            committedOffset = .zero
          }
          return
        }

        let proposed = CGSize(
          width: committedOffset.width + value.translation.width,
          height: committedOffset.height + value.translation.height
        )
        if let direction = pageDirection(
          for: value,
          proposedOffset: proposed,
          scale: scale,
          container: container
        ), onPageRequest(direction) {
          withoutAnimation {
            activeDragOffset = .zero
            committedScale = normalizedMinScale
            committedOffset = .zero
          }
          return
        }
        // Commit the final finger position and clear the transient offset in
        // one non-animated transaction. @GestureState resets before SwiftUI's
        // animated commit on some devices, briefly exposing the old offset and
        // producing the visible reverse-direction shake.
        withoutAnimation {
          committedOffset = boundedOffset(proposed, scale: scale, container: container)
          activeDragOffset = .zero
        }
      }
  }

  private func doubleTapGesture(in container: CGSize) -> some Gesture {
    TapGesture(count: 2)
      .onEnded {
        let nextScale = committedScale > normalizedMinScale ? normalizedMinScale : normalizedDoubleTapScale
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
          committedScale = nextScale
          committedOffset = boundedOffset(committedOffset, scale: nextScale, container: container)
          if nextScale <= normalizedMinScale {
            committedOffset = .zero
          }
        }
      }
  }

  private var normalizedMinScale: CGFloat {
    max(1, minScale)
  }

  private var normalizedMaxScale: CGFloat {
    max(normalizedMinScale, maxScale)
  }

  private var normalizedDoubleTapScale: CGFloat {
    min(max(doubleTapScale, normalizedMinScale), normalizedMaxScale)
  }

  private func boundedScale(_ scale: CGFloat) -> CGFloat {
    min(max(scale, normalizedMinScale), normalizedMaxScale)
  }

  private func boundedOffset(_ offset: CGSize, scale: CGFloat, container: CGSize) -> CGSize {
    guard scale > normalizedMinScale else {
      return .zero
    }

    let maxX = max(0, container.width * (scale - 1) / 2)
    let maxY = max(0, container.height * (scale - 1) / 2)

    return CGSize(
      width: min(max(offset.width, -maxX), maxX),
      height: min(max(offset.height, -maxY), maxY)
    )
  }

  private func pageDirection(for value: DragGesture.Value,
                             proposedOffset: CGSize,
                             scale: CGFloat,
                             container: CGSize) -> MediaZoomPageDirection? {
    guard scale > normalizedMinScale else {
      return nil
    }
    let translation = value.translation
    guard abs(translation.width) > abs(translation.height) * 1.15 else {
      return nil
    }
    let maxX = max(0, container.width * (scale - 1) / 2)
    if proposedOffset.width < -maxX - Self.pageTransitionThreshold {
      return .next
    }
    if proposedOffset.width > maxX + Self.pageTransitionThreshold {
      return .previous
    }
    return nil
  }

  private static let pageTransitionThreshold: CGFloat = 44
  private static let edgeResistance: CGFloat = 0.28

  private func displayedOffset(_ offset: CGSize,
                               scale: CGFloat,
                               container: CGSize) -> CGSize {
    guard scale > normalizedMinScale else {
      return .zero
    }
    let maxX = max(0, container.width * (scale - 1) / 2)
    let maxY = max(0, container.height * (scale - 1) / 2)
    return CGSize(
      width: resisted(offset.width, limit: maxX),
      height: min(max(offset.height, -maxY), maxY)
    )
  }

  private func resisted(_ value: CGFloat, limit: CGFloat) -> CGFloat {
    if value > limit {
      return limit + (value - limit) * Self.edgeResistance
    }
    if value < -limit {
      return -limit + (value + limit) * Self.edgeResistance
    }
    return value
  }

  private func withoutAnimation(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)
  }
}

public extension View {
  func mediaZoomable(minScale: CGFloat = 1,
                     maxScale: CGFloat = 4,
                     doubleTapScale: CGFloat = 2.5,
                     onPageRequest: @escaping (MediaZoomPageDirection) -> Bool = { _ in false }) -> some View {
    modifier(MediaZoomModifier(
      minScale: minScale,
      maxScale: maxScale,
      doubleTapScale: doubleTapScale,
      onPageRequest: onPageRequest
    ))
  }
}
