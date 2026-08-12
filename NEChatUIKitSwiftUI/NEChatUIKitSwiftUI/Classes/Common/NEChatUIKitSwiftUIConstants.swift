// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import CoreGraphics

public enum NEChatUIKitSwiftUIConstants {
  public static let moduleName = "NEChatUIKitSwiftUI"
  public static let telemetryComponentName = "ChatUIKitSwiftUI"
  public static let telemetryLanguage = "swiftui"
  public static let aiSearchPluginServiceName = "NEAISearchKit"
  public static let defaultHistoryPageSize = 100
  public static let inputMinHeight: CGFloat = 40
  public static let inputMinVisibleLines = 1
  public static let inputMaxVisibleLines = 4
  public static let inputTextLineHeight: CGFloat = 22
  public static let inputTextVerticalPadding: CGFloat = 16
  public static let inputIconSize = CGSize(width: 44, height: 40)
  public static let inputIconImageSize = CGSize(width: 28, height: 28)
  public static let locationCardSize = CGSize(width: 242, height: 140)
  public static let locationThumbnailHeight: CGFloat = 86
  public static let multiForwardCardSize = CGSize(width: 266, height: 130)
  public static let defaultMessageContentMaxWidth: CGFloat = 234
  public static let morePanelColumnCount = 4
  public static let revokeEditTimeGap: TimeInterval = 2

  public static let supportedAudioFileExtensions = ["mp3", "aac", "wav", "wma", "flac"]
  public static let supportedVideoFileExtensions = ["mp4", "avi", "wmv", "mpeg", "m4v", "mov", "asf", "flv", "f4v", "rmvb", "rm", "3gp"]
  public static let supportedImageFileExtensions = ["jpg", "jpeg", "png", "tiff", "heic", "gif"]
  public static let supportedDocumentFileExtensions = ["doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "txt", "pdf", "rtf", "html"]
  public static let supportedArchiveFileExtensions = ["zip", "tar", "rar", "7z"]
}
