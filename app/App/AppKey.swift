// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

/// AppKey 配置
/// 请在此处填写云信 AppKey 和推送证书名。
public struct AppKey {
    public static let accountId = "<#account#>"
    public static let token = "<#token#>"

    #if DEBUG
    public static let appKey = "<#请输入云信 AppKey#>"
    public static let apnsCername = "<#请输入云信 Apns 推送证书名#>"
    public static let pkCerName = "<#请输入云信 PushKit 推送证书名#>"
    #else
    public static let appKey = "<#请输入云信 AppKey#>"
    public static let apnsCername = "<#请输入云信 Apns 推送证书名#>"
    public static let pkCerName = "<#请输入云信 PushKit 推送证书名#>"
    #endif
}
