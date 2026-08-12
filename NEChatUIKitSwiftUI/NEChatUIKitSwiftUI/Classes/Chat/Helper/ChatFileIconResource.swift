// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

enum ChatFileIconResource {
  static func imageName(for file: MessageFileState) -> String {
    imageName(for: file.name, fallbackExtension: file.fileExtension)
  }

  static func imageName(for fileName: String) -> String {
    imageName(for: fileName, fallbackExtension: nil)
  }

  private static func imageName(for fileName: String, fallbackExtension: String?) -> String {
    let ext = normalizedExtension(fileName: fileName, fallbackExtension: fallbackExtension)
    switch ext {
    case "doc", "docx": return "file_doc"
    case "xls", "xlsx", "csv": return "file_xls"
    case "ppt", "pptx": return "file_ppt"
    case "key", "keynote": return "file_keynote"
    case "pdf", "rtf": return "file_pdf"
    case "txt": return "file_txt"
    case "html": return "file_html"
    case "zip", "tar", "rar", "7z": return "file_zip"
    case "jpg", "jpeg", "png", "tiff", "heic", "gif": return "file_img"
    case "mp4", "avi", "wmv", "mpeg", "m4v", "mov", "asf", "flv", "f4v", "rmvb", "rm", "3gp": return "file_vedio"
    case "mp3", "aac", "wav", "flac", "wma": return "file_audio"
    default: return "file_unknown"
    }
  }

  private static func normalizedExtension(fileName: String, fallbackExtension: String?) -> String {
    let nameExtension = (fileName as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    if !nameExtension.isEmpty {
      return nameExtension.lowercased()
    }
    guard let fallbackExtension else {
      return ""
    }
    return fallbackExtension
      .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
      .lowercased()
  }
}
