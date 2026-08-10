// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public protocol NECommonPermissionService {
  func currentPermissionState(for key: String) async -> NECommonPermissionState
  func requestPermission(for key: String) async -> NECommonPermissionState
}

public struct NECommonKeyboardState: Equatable {
  public var height: Double
  public var isVisible: Bool

  public init(height: Double = 0, isVisible: Bool = false) {
    self.height = height
    self.isVisible = isVisible
  }
}

public protocol NECommonKeyboardStateProviding {
  var currentKeyboardState: NECommonKeyboardState { get }
}

public protocol NECommonClipboardService {
  func copyText(_ text: String) async -> NECommonBoundaryResult
}

public struct NECommonUnavailableClipboardService: NECommonClipboardService {
  public init() {}

  public func copyText(_ text: String) async -> NECommonBoundaryResult {
    .unavailable("Clipboard service is not configured.")
  }
}

public final class NECommonClipboardServiceCenter {
  public static let shared = NECommonClipboardServiceCenter()

  private let lock = NSLock()
  private var service: NECommonClipboardService

  private init(service: NECommonClipboardService = NECommonUnavailableClipboardService()) {
    self.service = service
  }

  public func configure(_ service: NECommonClipboardService) {
    lock.lock()
    self.service = service
    lock.unlock()
  }

  public func current() -> NECommonClipboardService {
    lock.lock()
    defer { lock.unlock() }
    return service
  }
}

public protocol NECommonURLOpeningService {
  func open(_ url: URL) async -> NECommonBoundaryResult
}

public enum NECommonValueServiceResult<Value: Equatable>: Equatable {
  case success(Value)
  case cancelled
  case failure(NECommonErrorState)
  case unavailable(String)
}

public struct NECommonMediaValue: Equatable, Identifiable {
  public var id: String
  public var url: URL?
  public var name: String?
  public var mimeType: String?
  public var kind: NECommonMediaKind

  public init(id: String = UUID().uuidString,
              url: URL? = nil,
              name: String? = nil,
              mimeType: String? = nil,
              kind: NECommonMediaKind = .unknown) {
    self.id = id
    self.url = url
    self.name = name
    self.mimeType = mimeType
    self.kind = kind
  }
}

public enum NECommonMediaKind: String, Equatable {
  case image
  case video
  case unknown
}

public struct NECommonFileValue: Equatable, Identifiable {
  public var id: String
  public var url: URL?
  public var name: String?
  public var mimeType: String?
  public var sizeBytes: Int64?

  public init(id: String = UUID().uuidString,
              url: URL? = nil,
              name: String? = nil,
              mimeType: String? = nil,
              sizeBytes: Int64? = nil) {
    self.id = id
    self.url = url
    self.name = name
    self.mimeType = mimeType
    self.sizeBytes = sizeBytes
  }
}

public struct NECommonAudioValue: Equatable, Identifiable {
  public var id: String
  public var url: URL?
  public var name: String?
  public var mimeType: String?
  public var duration: TimeInterval?
  public var sizeBytes: Int64?

  public init(id: String = UUID().uuidString,
              url: URL? = nil,
              name: String? = nil,
              mimeType: String? = nil,
              duration: TimeInterval? = nil,
              sizeBytes: Int64? = nil) {
    self.id = id
    self.url = url
    self.name = name
    self.mimeType = mimeType
    self.duration = duration
    self.sizeBytes = sizeBytes
  }
}

public struct NECommonLocationValue: Equatable {
  public var latitude: Double
  public var longitude: Double
  public var title: String?
  public var address: String?

  public init(latitude: Double,
              longitude: Double,
              title: String? = nil,
              address: String? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.title = title
    self.address = address
  }
}

public protocol NECommonMediaValueService {
  var capability: NECommonCapabilityState { get }
  func requestMediaValue() async -> NECommonValueServiceResult<NECommonMediaValue>
}

public protocol NECommonFileValueService {
  var capability: NECommonCapabilityState { get }
  func requestFileValue() async -> NECommonValueServiceResult<NECommonFileValue>
}

public protocol NECommonAudioValueService {
  var capability: NECommonCapabilityState { get }
  func requestAudioValue() async -> NECommonValueServiceResult<NECommonAudioValue>
}

public protocol NECommonMapValueService {
  var capability: NECommonCapabilityState { get }
  func requestLocationValue() async -> NECommonValueServiceResult<NECommonLocationValue>
  func openLocationValue(_ value: NECommonLocationValue) async -> NECommonBoundaryResult
}
