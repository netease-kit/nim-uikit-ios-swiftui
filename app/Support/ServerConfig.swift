// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NIMSDK

struct DemoPrivateCloudConfigModel: Equatable {
    var configMap: [String: String] = [:]
    var customJson: String?
    var enableCustomConfig = false
    var accountId: String?
    var accountIdToken: String?

    var appKey: String {
        get { configMap[#keyPath(NIMSDKOption.appKey)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMSDKOption.appKey)) }
    }

    var module: String {
        get { configMap[#keyPath(NIMServerSetting.module)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.module)) }
    }

    var linkAddress: String {
        get { configMap[#keyPath(NIMServerSetting.linkAddress)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.linkAddress)) }
    }

    var lbsAddress: String {
        get { configMap[#keyPath(NIMServerSetting.lbsAddress)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.lbsAddress)) }
    }

    var nosLbsAddress: String {
        get { configMap[#keyPath(NIMServerSetting.nosLbsAddress)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.nosLbsAddress)) }
    }

    var nosUploadAddress: String {
        get { configMap[#keyPath(NIMServerSetting.nosUploadAddress)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.nosUploadAddress)) }
    }

    var nosDownloadAddress: String {
        get { configMap[#keyPath(NIMServerSetting.nosDownloadAddress)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.nosDownloadAddress)) }
    }

    var nosUploadHost: String {
        get { configMap[#keyPath(NIMServerSetting.nosUploadHost)] ?? "" }
        set { update(newValue, forKey: #keyPath(NIMServerSetting.nosUploadHost)) }
    }

    mutating func update(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            configMap.removeValue(forKey: key)
        } else {
            configMap[key] = value
        }
    }

    func dictionaryRepresentation() -> [String: Any] {
        var dictionary: [String: Any] = [
            "configMap": configMap,
            "enableCustomConfig": enableCustomConfig,
        ]
        if let customJson, !customJson.isEmpty {
            dictionary["customJson"] = customJson
        }
        if let accountId, !accountId.isEmpty {
            dictionary["accountId"] = accountId
        }
        if let accountIdToken, !accountIdToken.isEmpty {
            dictionary["accountIdToken"] = accountIdToken
        }
        return dictionary
    }

    static func model(from dictionary: [String: Any]) -> DemoPrivateCloudConfigModel {
        var model = DemoPrivateCloudConfigModel()
        if let configMap = dictionary["configMap"] as? [String: String] {
            model.configMap = configMap
        } else if let configMap = dictionary["configMap"] as? [String: Any] {
            model.configMap = configMap.compactMapValues { $0 as? String }
        }
        if let enable = dictionary["enableCustomConfig"] as? Bool {
            model.enableCustomConfig = enable
        } else if let enable = dictionary["enableCustomConfig"] as? NSNumber {
            model.enableCustomConfig = enable.boolValue
        }
        model.customJson = dictionary["customJson"] as? String
        model.accountId = dictionary["accountId"] as? String
        model.accountIdToken = (dictionary["accountIdToken"] as? String) ?? (dictionary["accountToken"] as? String)
        return model
    }
}

enum DemoPrivateCloudConfigStore {
    private static let filename = "sdk_config"
    private static var cachedModel: DemoPrivateCloudConfigModel?

    static func getConfig() -> DemoPrivateCloudConfigModel {
        if let cachedModel {
            return cachedModel
        }
        let model = loadObjectFromDisk() ?? legacyUserDefaultsModel()
        cachedModel = model
        return model
    }

    static func saveConfig(_ model: DemoPrivateCloudConfigModel) {
        cachedModel = model
        saveObjectToDisk(model)
    }

    static func clearCredentials() {
        var model = getConfig()
        model.accountId = nil
        model.accountIdToken = nil
        saveConfig(model)
    }

    static func clearConfig() {
        cachedModel = nil
        let defaults = UserDefaults.standard
        [
            "poc.private.enabled",
            "poc.private.appKey",
            "poc.private.module",
            "poc.private.link",
            "poc.private.lbs",
            "poc.private.json",
            "poc.accountId",
            "poc.accountIdToken",
        ].forEach(defaults.removeObject(forKey:))
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(filename))
    }

    private static func legacyUserDefaultsModel() -> DemoPrivateCloudConfigModel {
        let defaults = UserDefaults.standard
        var model = DemoPrivateCloudConfigModel()
        model.enableCustomConfig = defaults.bool(forKey: "poc.private.enabled")
        model.appKey = defaults.string(forKey: "poc.private.appKey") ?? ""
        model.module = defaults.string(forKey: "poc.private.module") ?? ""
        model.linkAddress = defaults.string(forKey: "poc.private.link") ?? ""
        model.lbsAddress = defaults.string(forKey: "poc.private.lbs") ?? ""
        model.customJson = defaults.string(forKey: "poc.private.json")
        model.accountId = defaults.string(forKey: "poc.accountId")
        model.accountIdToken = defaults.string(forKey: "poc.accountIdToken")
        return model
    }

    private static func saveObjectToDisk(_ object: DemoPrivateCloudConfigModel) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let archiveURL = documentsDirectory.appendingPathComponent(filename)
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: object.dictionaryRepresentation(),
                format: .binary,
                options: 0
            )
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            print("saveObjectToDisk error: \(error)")
        }
    }

    private static func loadObjectFromDisk() -> DemoPrivateCloudConfigModel? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let archiveURL = documentsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            return nil
        }
        do {
            let retrievedData = try Data(contentsOf: archiveURL)
            let propertyList = try PropertyListSerialization.propertyList(from: retrievedData, options: [], format: nil)
            if let dictionary = propertyList as? [String: Any],
               dictionary["configMap"] != nil || dictionary["customJson"] != nil || dictionary["enableCustomConfig"] != nil ||
               dictionary["accountId"] != nil || dictionary["accountToken"] != nil || dictionary["accountIdToken"] != nil {
                return DemoPrivateCloudConfigModel.model(from: dictionary)
            }
        } catch {
            print("loadObjectFromDisk error: \(error)")
        }
        try? FileManager.default.removeItem(at: archiveURL)
        return nil
    }
}

/// Server address and appkey configuration helper.
/// Mirrors IMUIKitExample ServerAddresses for domestic/overseas support.
enum ServerConfig {

    static func configServer() {
        let privateConfig = DemoPrivateCloudConfigStore.getConfig()
        if privateConfig.enableCustomConfig {
            configCustomServer(privateConfig)
            return
        }
        let isOverseas = UserDefaults.standard.bool(forKey: "is_overseas_node")
        if isOverseas {
            // Overseas server config - server addresses are configured via NIMServerSetting
            // when specific overseas functionality is needed.
        }
    }

    static func configCustomServer(_ model: DemoPrivateCloudConfigModel) {
        let serverAddresses = NIMServerSetting()
        if let custom = model.customJson, !custom.isEmpty, let data = custom.data(using: .utf8) {
            serverAddresses.update(fromConfigData: data)
        } else {
            if let value = model.configMap[#keyPath(NIMServerSetting.linkAddress)] {
                serverAddresses.linkAddress = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.lbsAddress)] {
                serverAddresses.lbsAddress = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.nosLbsAddress)] {
                serverAddresses.nosLbsAddress = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.nosUploadAddress)] {
                serverAddresses.nosUploadAddress = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.nosDownloadAddress)] {
                serverAddresses.nosDownloadAddress = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.nosUploadHost)] {
                serverAddresses.nosUploadHost = value
            }
            if let value = model.configMap[#keyPath(NIMServerSetting.module)] {
                serverAddresses.module = value
            }
        }
        NIMSDK.shared().serverSetting = serverAddresses
    }

    static func getAppkey() -> String {
        let privateConfig = DemoPrivateCloudConfigStore.getConfig()
        if privateConfig.enableCustomConfig {
            if let jsonAppKey = appKey(from: privateConfig.customJson) {
                return jsonAppKey
            }
            if !privateConfig.appKey.isEmpty {
                return privateConfig.appKey
            }
        }
        return AppKey.appKey
    }

    private static func appKey(from customJson: String?) -> String? {
        guard let customJson,
              let data = customJson.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let value = dictionary["appkey"] as? String
            ?? dictionary[#keyPath(NIMSDKOption.appKey)] as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Helpers

func localizable(_ key: String) -> String {
    if let language = UserDefaults.standard.string(forKey: "IMKitLanguage"),
       let path = Bundle.main.path(forResource: language, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

extension Notification.Name {
    static let logout = Notification.Name("logout")
    static let appToast = Notification.Name("appToast")
    static let appSettingsPrompt = Notification.Name("appSettingsPrompt")
}
