// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NEChatUIKitSwiftUI

enum DemoNetworkPresentation {
    static var allowsNetworkOperation: Bool {
        NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false
    }

    static func networkMessage() -> String {
        localizable("network_error")
    }

    static func message(for error: Error, fallbackKey: String? = nil) -> String {
        if let userVisibleError = error as? ChatUserVisibleError {
            return userVisibleError.userVisibleMessage
        }
        let nsError = error as NSError
        NEALog.errorLog("DemoNetworkPresentation", desc: nsError.localizedDescription)
        switch nsError.code {
        case protocolSendFailed, protocolTimeout:
            return networkMessage()
        default:
            if let fallbackKey {
                return localizable(fallbackKey)
            }
            return localizable("failed_operation")
        }
    }

    static func chatMessage(for error: Error,
                            fallbackKey: String = "failed_operation",
                            fallbackValue: String = "Operation failed") -> String {
        if let userVisibleError = error as? ChatUserVisibleError {
            return userVisibleError.userVisibleMessage
        }
        let nsError = error as NSError
        NEALog.errorLog("DemoNetworkPresentation", desc: nsError.localizedDescription)
        switch nsError.code {
        case protocolSendFailed, protocolTimeout:
            return NEChatUIKitSwiftUIBundle.localized("network_error", value: "No Network")
        case noPermissionCode, noPermissionOperationCode:
            return NEChatUIKitSwiftUIBundle.localized("no_permission_tip", value: "No Permission")
        case fileUploadFailed:
            return NEChatUIKitSwiftUIBundle.localized("file_upload_failed", value: "File upload failed")
        default:
            return NEChatUIKitSwiftUIBundle.localized(fallbackKey, value: fallbackValue)
        }
    }
}
