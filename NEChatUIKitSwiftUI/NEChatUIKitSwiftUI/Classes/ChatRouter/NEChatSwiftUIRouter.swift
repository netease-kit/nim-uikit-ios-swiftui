// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct NEChatSwiftUIRouteRequest: Identifiable, Equatable {
  public var id: String
  public var route: NEChatSwiftUIRoute
  public var sourceURL: String?
  public var createdAt: TimeInterval

  public init(id: String = UUID().uuidString,
              route: NEChatSwiftUIRoute,
              sourceURL: String? = nil,
              createdAt: TimeInterval = Date().timeIntervalSince1970) {
    self.id = id
    self.route = route
    self.sourceURL = sourceURL
    self.createdAt = createdAt
  }
}

public enum NEChatSwiftUIRouteResult: Equatable {
  case handled
  case cancelled
  case failed(String)
  case value(String)
}

public struct NEChatSwiftUIRouteDiagnostic: Identifiable, Equatable {
  public var id: String
  public var routeId: String?
  public var sourceURL: String?
  public var reason: String
  public var createdAt: TimeInterval

  public init(id: String = UUID().uuidString,
              routeId: String? = nil,
              sourceURL: String? = nil,
              reason: String,
              createdAt: TimeInterval = Date().timeIntervalSince1970) {
    self.id = id
    self.routeId = routeId
    self.sourceURL = sourceURL
    self.reason = reason
    self.createdAt = createdAt
  }
}

public final class NEChatSwiftUIRouter {
  public var onRoute: ((NEChatSwiftUIRoute) -> Void)?
  public var onRouteRequest: ((NEChatSwiftUIRouteRequest) -> Void)?
  public var onDiagnostic: ((NEChatSwiftUIRouteDiagnostic) -> Void)?
  public private(set) var isLegacyRouteRegistered = false
  public private(set) var pendingRequests = [NEChatSwiftUIRouteRequest]()
  public private(set) var diagnostics = [NEChatSwiftUIRouteDiagnostic]()

  private var completions = [String: (NEChatSwiftUIRouteResult) -> Void]()

  public init(onRoute: ((NEChatSwiftUIRoute) -> Void)? = nil,
              onRouteRequest: ((NEChatSwiftUIRouteRequest) -> Void)? = nil,
              onDiagnostic: ((NEChatSwiftUIRouteDiagnostic) -> Void)? = nil) {
    self.onRoute = onRoute
    self.onRouteRequest = onRouteRequest
    self.onDiagnostic = onDiagnostic
  }

  public func handle(_ route: NEChatSwiftUIRoute) {
    onRoute?(route)
  }

  @discardableResult
  public func enqueue(_ route: NEChatSwiftUIRoute,
                      sourceURL: String? = nil,
                      completion: ((NEChatSwiftUIRouteResult) -> Void)? = nil) -> NEChatSwiftUIRouteRequest {
    let request = NEChatSwiftUIRouteRequest(route: route, sourceURL: sourceURL)
    pendingRequests.append(request)
    completions[request.id] = completion
    onRoute?(route)
    onRouteRequest?(request)
    recordDiagnosticIfNeeded(for: request)
    return request
  }

  @discardableResult
  public func handle(url: String, parameters: [String: Any]? = nil) -> NEChatSwiftUIRoute {
    let route = NEChatSwiftUIRoutePayloadAdapter.route(for: url, parameters: parameters)
    handle(route)
    if case let .unsupported(_, reason) = route {
      recordDiagnostic(routeId: route.id, sourceURL: url, reason: reason)
    }
    return route
  }

  @discardableResult
  public func enqueue(url: String,
                      parameters: [String: Any]? = nil,
                      completion: ((NEChatSwiftUIRouteResult) -> Void)? = nil) -> NEChatSwiftUIRouteRequest {
    let route = NEChatSwiftUIRoutePayloadAdapter.route(for: url, parameters: parameters)
    return enqueue(route, sourceURL: url, completion: completion)
  }

  public func complete(_ requestId: String,
                       result: NEChatSwiftUIRouteResult = .handled) {
    let sourceURL = pendingRequests.first { $0.id == requestId }?.sourceURL
    pendingRequests.removeAll { $0.id == requestId }
    let completion = completions.removeValue(forKey: requestId)
    completion?(result)
    if case let .failed(reason) = result {
      recordDiagnostic(routeId: requestId, sourceURL: sourceURL, reason: reason)
    }
  }

  public func cancel(_ requestId: String) {
    complete(requestId, result: .cancelled)
  }

  public func clearPending(result: NEChatSwiftUIRouteResult = .cancelled) {
    let requestIds = pendingRequests.map(\.id)
    pendingRequests.removeAll()
    requestIds.forEach { requestId in
      let completion = completions.removeValue(forKey: requestId)
      completion?(result)
      if case let .failed(reason) = result {
        recordDiagnostic(routeId: requestId, sourceURL: nil, reason: reason)
      }
    }
  }

  public func clearDiagnostics() {
    diagnostics.removeAll()
  }

  @discardableResult
  public func registerLegacyRoutes() -> Bool {
    guard !isLegacyRouteRegistered else {
      return false
    }

    isLegacyRouteRegistered = true
    NEChatSwiftUIRoutePayloadAdapter.supportedPatterns.forEach { pattern in
      Router.shared.register(pattern) { [weak self] params in
        self?.enqueue(url: pattern, parameters: params)
      }
    }
    return true
  }

  private func recordDiagnosticIfNeeded(for request: NEChatSwiftUIRouteRequest) {
    if case let .unsupported(url, reason) = request.route {
      recordDiagnostic(
        routeId: request.id,
        sourceURL: request.sourceURL ?? url,
        reason: reason
      )
    }
  }

  private func recordDiagnostic(routeId: String?,
                                sourceURL: String?,
                                reason: String) {
    let diagnostic = NEChatSwiftUIRouteDiagnostic(
      routeId: routeId,
      sourceURL: sourceURL,
      reason: reason
    )
    diagnostics.append(diagnostic)
    NEChatSwiftUILogger.log("route diagnostic reason=\(reason), url=\(sourceURL ?? "")")
    onDiagnostic?(diagnostic)
  }
}
