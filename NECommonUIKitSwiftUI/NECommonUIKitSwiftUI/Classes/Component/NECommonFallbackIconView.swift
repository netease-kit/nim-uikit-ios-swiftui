// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

struct NECommonFallbackIconView: View {
  var name: String

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let rect = CGRect(
        x: (proxy.size.width - side) / 2,
        y: (proxy.size.height - side) / 2,
        width: side,
        height: side
      )

      Path { path in
        drawIcon(named: name, in: rect, path: &path)
      }
      .stroke(style: StrokeStyle(lineWidth: max(1.4, side * 0.09), lineCap: .round, lineJoin: .round))
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private func drawIcon(named name: String,
                        in rect: CGRect,
                        path: inout Path) {
    let key = name.lowercased()
    if key.contains("magnifyingglass") || key.contains("search") {
      drawSearch(in: rect, path: &path)
    } else if key.contains("chevron.right") || key.contains("arrow.forward") {
      drawChevron(in: rect, direction: .right, path: &path)
    } else if key.contains("chevron.left") || key.contains("back") {
      drawChevron(in: rect, direction: .left, path: &path)
    } else if key.contains("chevron.up") {
      drawChevron(in: rect, direction: .up, path: &path)
    } else if key.contains("chevron.down") || key.contains("arrow.down") {
      drawChevron(in: rect, direction: .down, path: &path)
    } else if key.contains("xmark") || key.contains("close") || key.contains("clear") {
      if key.contains("circle") {
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
      }
      drawX(in: rect, path: &path)
    } else if key.contains("checkmark") || key.contains("select") {
      if key.contains("circle") {
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
      }
      drawCheck(in: rect, path: &path)
    } else if key.contains("plus") || key.contains("add") {
      if key.contains("circle") {
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
      }
      drawPlus(in: rect, path: &path)
    } else if key.contains("ellipsis") || key.contains("more") {
      drawEllipsis(in: rect, path: &path)
    } else if key.contains("trash") || key.contains("delete") {
      drawTrash(in: rect, path: &path)
    } else {
      drawPlaceholder(in: rect, path: &path)
    }
  }

  private enum Direction {
    case left
    case right
    case up
    case down
  }

  private func drawChevron(in rect: CGRect, direction: Direction, path: inout Path) {
    let minX = rect.minX
    let maxX = rect.maxX
    let minY = rect.minY
    let maxY = rect.maxY
    let midX = rect.midX
    let midY = rect.midY
    switch direction {
    case .right:
      path.move(to: CGPoint(x: minX + rect.width * 0.35, y: minY + rect.height * 0.25))
      path.addLine(to: CGPoint(x: maxX - rect.width * 0.30, y: midY))
      path.addLine(to: CGPoint(x: minX + rect.width * 0.35, y: maxY - rect.height * 0.25))
    case .left:
      path.move(to: CGPoint(x: maxX - rect.width * 0.35, y: minY + rect.height * 0.25))
      path.addLine(to: CGPoint(x: minX + rect.width * 0.30, y: midY))
      path.addLine(to: CGPoint(x: maxX - rect.width * 0.35, y: maxY - rect.height * 0.25))
    case .up:
      path.move(to: CGPoint(x: minX + rect.width * 0.25, y: maxY - rect.height * 0.35))
      path.addLine(to: CGPoint(x: midX, y: minY + rect.height * 0.30))
      path.addLine(to: CGPoint(x: maxX - rect.width * 0.25, y: maxY - rect.height * 0.35))
    case .down:
      path.move(to: CGPoint(x: minX + rect.width * 0.25, y: minY + rect.height * 0.35))
      path.addLine(to: CGPoint(x: midX, y: maxY - rect.height * 0.30))
      path.addLine(to: CGPoint(x: maxX - rect.width * 0.25, y: minY + rect.height * 0.35))
    }
  }

  private func drawSearch(in rect: CGRect, path: inout Path) {
    path.addEllipse(in: CGRect(
      x: rect.minX + rect.width * 0.18,
      y: rect.minY + rect.height * 0.16,
      width: rect.width * 0.48,
      height: rect.height * 0.48
    ))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.61, y: rect.minY + rect.height * 0.61))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.16))
  }

  private func drawX(in rect: CGRect, path: inout Path) {
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.30))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.maxY - rect.height * 0.30))
    path.move(to: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.minY + rect.height * 0.30))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY - rect.height * 0.30))
  }

  private func drawCheck(in rect: CGRect, path: inout Path) {
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.maxY - rect.height * 0.28))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.minY + rect.height * 0.26))
  }

  private func drawPlus(in rect: CGRect, path: inout Path) {
    path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.24))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.midY))
  }

  private func drawEllipsis(in rect: CGRect, path: inout Path) {
    let radius = rect.width * 0.045
    for point in [0.32, 0.50, 0.68] {
      path.addEllipse(in: CGRect(
        x: rect.minX + rect.width * point - radius,
        y: rect.midY - radius,
        width: radius * 2,
        height: radius * 2
      ))
    }
  }

  private func drawTrash(in rect: CGRect, path: inout Path) {
    path.addRoundedRect(
      in: CGRect(x: rect.minX + rect.width * 0.28,
                 y: rect.minY + rect.height * 0.36,
                 width: rect.width * 0.44,
                 height: rect.height * 0.44),
      cornerSize: CGSize(width: rect.width * 0.05, height: rect.height * 0.05)
    )
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.30))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.30))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.22))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.40, y: rect.minY + rect.height * 0.22))
  }

  private func drawPlaceholder(in rect: CGRect, path: inout Path) {
    path.addRoundedRect(
      in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18),
      cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12)
    )
  }
}
