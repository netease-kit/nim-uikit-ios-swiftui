// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public protocol ChatUserVisibleError: Error {
  var userVisibleMessage: String { get }
}

public struct ChatMediaPreviewRequest: Equatable {
  public var preview: ChatMediaPreviewState
  public var message: MessageRowState
  public var context: ChatSessionContext

  public init(preview: ChatMediaPreviewState,
              message: MessageRowState,
              context: ChatSessionContext) {
    self.preview = preview
    self.message = message
    self.context = context
  }
}

public struct ChatFileInteractionRequest: Equatable {
  public var preview: ChatFilePreviewState
  public var message: MessageRowState
  public var context: ChatSessionContext

  public init(preview: ChatFilePreviewState,
              message: MessageRowState,
              context: ChatSessionContext) {
    self.preview = preview
    self.message = message
    self.context = context
  }
}

public struct ChatAudioPlaybackRequest: Equatable {
  public var messageId: String
  public var audio: MessageAudioState
  public var context: ChatSessionContext

  public init(messageId: String,
              audio: MessageAudioState,
              context: ChatSessionContext) {
    self.messageId = messageId
    self.audio = audio
    self.context = context
  }
}

public struct ChatAudioRecordRequest: Equatable {
  public var context: ChatSessionContext

  public init(context: ChatSessionContext) {
    self.context = context
  }
}

public struct ChatAudioRecordResult: Equatable {
  public var payload: ChatOutgoingMessagePayload?
  public var toast: ChatToastState?

  public init(payload: ChatOutgoingMessagePayload? = nil,
              toast: ChatToastState? = nil) {
    self.payload = payload
    self.toast = toast
  }
}

public enum ChatAudioPlaybackResult: Equatable {
  case playing
  case stopped
}

public struct ChatLocationInteractionRequest: Equatable {
  public var location: MessageLocationState
  public var message: MessageRowState
  public var context: ChatSessionContext

  public init(location: MessageLocationState,
              message: MessageRowState,
              context: ChatSessionContext) {
    self.location = location
    self.message = message
    self.context = context
  }
}

public struct ChatCallInteractionRequest: Equatable {
  public var call: MessageCallState
  public var message: MessageRowState?
  public var context: ChatSessionContext

  public init(call: MessageCallState,
              message: MessageRowState? = nil,
              context: ChatSessionContext) {
    self.call = call
    self.message = message
    self.context = context
  }
}

public struct ChatClipboardRequest: Equatable {
  public var text: String
  public var message: MessageRowState
  public var context: ChatSessionContext

  public init(text: String,
              message: MessageRowState,
              context: ChatSessionContext) {
    self.text = text
    self.message = message
    self.context = context
  }
}

public enum ChatURLInteractionSource: String, Equatable {
  case messageText
  case richText
  case voiceToText
  case aiStreamText
  case textPreview
  case multiForwardPreview
  case inlineReply
}

public enum ChatURLInteractionKind: String, Equatable {
  case web
  case phone
  case mail
  case other

  public init(url: URL) {
    switch url.scheme?.lowercased() {
    case "tel":
      self = .phone
    case "mailto":
      self = .mail
    case "http", "https":
      self = .web
    default:
      self = .other
    }
  }
}

public struct ChatURLInteractionRequest: Equatable {
  public var url: URL
  public var displayText: String
  public var source: ChatURLInteractionSource
  public var kind: ChatURLInteractionKind
  public var message: MessageRowState?
  public var preview: ChatTextPreviewState?
  public var context: ChatSessionContext

  public init(url: URL,
              displayText: String,
              source: ChatURLInteractionSource,
              message: MessageRowState? = nil,
              preview: ChatTextPreviewState? = nil,
              context: ChatSessionContext) {
    self.url = url
    self.displayText = displayText
    self.source = source
    kind = ChatURLInteractionKind(url: url)
    self.message = message
    self.preview = preview
    self.context = context
  }
}

public protocol ChatMediaPreviewHandling {
  func handleMediaPreview(_ request: ChatMediaPreviewRequest,
                          completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public protocol ChatFileInteractionHandling {
  func handleFileInteraction(_ request: ChatFileInteractionRequest,
                             completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public protocol ChatAudioPlaybackHandling {
  func playAudio(_ request: ChatAudioPlaybackRequest,
                 completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void)
  func stopAudio(_ request: ChatAudioPlaybackRequest,
                 completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void)
  func setAudioRoute(useSpeaker: Bool)
}

public extension ChatAudioPlaybackHandling {
  func setAudioRoute(useSpeaker _: Bool) {}
}

public protocol ChatAudioRecordingHandling {
  func beginRecording(_ request: ChatAudioRecordRequest,
                      progress: @escaping (ChatVoiceRecordingProgressState) -> Void,
                      completion: @escaping (Result<Void, Error>) -> Void)
  func finishRecording(_ request: ChatAudioRecordRequest,
                       completion: @escaping (Result<ChatAudioRecordResult, Error>) -> Void)
  func cancelRecording(_ request: ChatAudioRecordRequest,
                       completion: @escaping (Result<Void, Error>) -> Void)
}

public protocol ChatLocationInteractionHandling {
  func handleLocationInteraction(_ request: ChatLocationInteractionRequest,
                                 completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public protocol ChatCallInteractionHandling {
  func handleCallInteraction(_ request: ChatCallInteractionRequest,
                             completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public protocol ChatClipboardHandling {
  func copyText(_ request: ChatClipboardRequest,
                completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public protocol ChatURLInteractionHandling {
  func handleURLInteraction(_ request: ChatURLInteractionRequest,
                            completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
}

public struct ChatMediaPreviewHandler: ChatMediaPreviewHandling {
  private let handler: (ChatMediaPreviewRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatMediaPreviewRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handleMediaPreview(_ request: ChatMediaPreviewRequest,
                                 completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct ChatClipboardHandler: ChatClipboardHandling {
  private let handler: (ChatClipboardRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatClipboardRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func copyText(_ request: ChatClipboardRequest,
                       completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct ChatURLInteractionHandler: ChatURLInteractionHandling {
  private let handler: (ChatURLInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatURLInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handleURLInteraction(_ request: ChatURLInteractionRequest,
                                   completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct ChatFileInteractionHandler: ChatFileInteractionHandling {
  private let handler: (ChatFileInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatFileInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handleFileInteraction(_ request: ChatFileInteractionRequest,
                                    completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct ChatAudioPlaybackHandler: ChatAudioPlaybackHandling {
  private let playHandler: (ChatAudioPlaybackRequest, @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) -> Void
  private let stopHandler: (ChatAudioPlaybackRequest, @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) -> Void
  private let audioRouteHandler: (Bool) -> Void

  public init(play: @escaping (ChatAudioPlaybackRequest, @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) -> Void,
              stop: @escaping (ChatAudioPlaybackRequest, @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) -> Void,
              setAudioRoute: @escaping (Bool) -> Void = { _ in }) {
    playHandler = play
    stopHandler = stop
    audioRouteHandler = setAudioRoute
  }

  public func playAudio(_ request: ChatAudioPlaybackRequest,
                        completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) {
    playHandler(request, completion)
  }

  public func stopAudio(_ request: ChatAudioPlaybackRequest,
                        completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void) {
    stopHandler(request, completion)
  }

  public func setAudioRoute(useSpeaker: Bool) {
    audioRouteHandler(useSpeaker)
  }
}

public struct ChatAudioRecordingHandler: ChatAudioRecordingHandling {
  private let beginHandler: (ChatAudioRecordRequest, @escaping (ChatVoiceRecordingProgressState) -> Void, @escaping (Result<Void, Error>) -> Void) -> Void
  private let finishHandler: (ChatAudioRecordRequest, @escaping (Result<ChatAudioRecordResult, Error>) -> Void) -> Void
  private let cancelHandler: (ChatAudioRecordRequest, @escaping (Result<Void, Error>) -> Void) -> Void

  public init(begin: @escaping (ChatAudioRecordRequest, @escaping (ChatVoiceRecordingProgressState) -> Void, @escaping (Result<Void, Error>) -> Void) -> Void,
              finish: @escaping (ChatAudioRecordRequest, @escaping (Result<ChatAudioRecordResult, Error>) -> Void) -> Void,
              cancel: @escaping (ChatAudioRecordRequest, @escaping (Result<Void, Error>) -> Void) -> Void) {
    beginHandler = begin
    finishHandler = finish
    cancelHandler = cancel
  }

  public func beginRecording(_ request: ChatAudioRecordRequest,
                             progress: @escaping (ChatVoiceRecordingProgressState) -> Void,
                             completion: @escaping (Result<Void, Error>) -> Void) {
    beginHandler(request, progress, completion)
  }

  public func finishRecording(_ request: ChatAudioRecordRequest,
                              completion: @escaping (Result<ChatAudioRecordResult, Error>) -> Void) {
    finishHandler(request, completion)
  }

  public func cancelRecording(_ request: ChatAudioRecordRequest,
                              completion: @escaping (Result<Void, Error>) -> Void) {
    cancelHandler(request, completion)
  }
}

public struct ChatLocationInteractionHandler: ChatLocationInteractionHandling {
  private let handler: (ChatLocationInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatLocationInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handleLocationInteraction(_ request: ChatLocationInteractionRequest,
                                        completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}

public struct ChatCallInteractionHandler: ChatCallInteractionHandling {
  private let handler: (ChatCallInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatCallInteractionRequest, @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func handleCallInteraction(_ request: ChatCallInteractionRequest,
                                    completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void) {
    handler(request, completion)
  }
}
