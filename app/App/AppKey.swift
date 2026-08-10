// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

/// AppKey 配置
///
/// 发布前请将 app/App/AppKey.private.swift.example 复制为 AppKey.private.swift 并填入真实密钥。
/// AppKey.private.swift 已在 .gitignore 中排除，不会被提交到仓库。
public enum AppKey {
  #if canImport(AppKeyPrivate)
    public static let appKey = AppKeyPrivate.appKey
    public static let overseasAppkey = AppKeyPrivate.overseasAppkey
    public static let gaodeMapAppkey = AppKeyPrivate.gaodeMapAppkey
    public static let apnsCername = AppKeyPrivate.apnsCername
    public static let pkCerName = AppKeyPrivate.pkCerName
  #else
    public static let appKey = ""
    public static let overseasAppkey = ""
    public static let gaodeMapAppkey = ""
    public static let apnsCername = ""
    public static let pkCerName = ""
  #endif

  #if DEBUG
    public static let isDebug = true
  #else
    public static let isDebug = false
  #endif
}
