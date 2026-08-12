// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatOutgoingMessageFactory {
  private let chatRepo: ChatRepo

  public init(chatRepo: ChatRepo = .shared) {
    self.chatRepo = chatRepo
  }

  public func message(from payload: ChatOutgoingMessagePayload) throws -> V2NIMMessage {
    switch payload {
    case let .image(path, name, width, height):
      try Self.validateFilePath(path)
      return chatRepo.makeImageMessage(path: path, name: name, width: width, height: height)
    case let .audio(filePath, name, duration):
      try Self.validateFilePath(filePath)
      return chatRepo.makeAudioMessage(filePath: filePath, name: name, duration: duration)
    case let .video(filePath, name, width, height, duration):
      try Self.validateFilePath(filePath)
      return chatRepo.makeVideoMessage(filePath: filePath, name: name, width: width, height: height, duration: duration)
    case let .file(filePath, displayName):
      try Self.validateFilePath(filePath)
      return chatRepo.makeFileMessage(filePath: filePath, displayName: Self.normalizedFileDisplayName(displayName, filePath: filePath))
    case let .location(latitude, longitude, title, address):
      return chatRepo.makeLocationMessage(latitude: latitude, longitude: longitude, title: title, address: address)
    case let .call(text, type, channelId, status, durations):
      return chatRepo.makeCallMessage(text: text, type: type, channelId: channelId, status: status, durations: durations)
    case let .custom(text, rawAttachment):
      return chatRepo.makeCustomMessage(text: text, rawAttachment: rawAttachment)
    }
  }

  private static func validateFilePath(_ path: String) throws {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw error(code: -1, message: NEChatUIKitSwiftUIBundle.localized("chat_file_path_empty", value: "File path is empty"))
    }
  }

  private static func normalizedFileDisplayName(_ displayName: String?,
                                                filePath: String) -> String {
    let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
      return trimmedDisplayName
    }

    let fileName = URL(fileURLWithPath: filePath).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    return fileName.isEmpty
      ? NEChatUIKitSwiftUIBundle.localized("chat_message_file", value: "File")
      : fileName
  }

  private static func error(code: Int, message: String) -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

public enum ChatOutgoingMessagePayload: Equatable {
  case image(path: String, name: String?, width: Int32, height: Int32)
  case audio(filePath: String, name: String?, duration: Int32)
  case video(filePath: String, name: String?, width: Int32, height: Int32, duration: Int32)
  case file(filePath: String, displayName: String?)
  case location(latitude: Double, longitude: Double, title: String, address: String)
  case call(text: String, type: Int, channelId: String, status: Int, durations: [NEChatCallDurationInfo])
  case custom(text: String, rawAttachment: String)
}

public extension ChatOutgoingMessagePayload {
  var filePathForSizeLimit: String? {
    switch self {
    case let .image(path, _, _, _):
      return path
    case let .audio(filePath, _, _):
      return filePath
    case let .video(filePath, _, _, _, _):
      return filePath
    case let .file(filePath, _):
      return filePath
    case .location, .call, .custom:
      return nil
    }
  }
}
