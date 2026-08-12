// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVFoundation
import AVKit
import Combine
import CoreLocation
import CoreMotion
import CoreTransferable
import Foundation
import ImageIO
import MapKit
import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import Photos
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZLPhotoBrowser

@MainActor
final class ExampleChatNativeBoundaryService: ObservableObject {
    static let shared = ExampleChatNativeBoundaryService()

    @Published var pendingPhotoPicker: ExampleChatMediaPickerRequest?
    @Published var pendingFileImporter: ExampleChatFilePickerRequest?
    @Published var pendingCameraSourceChoice: ExampleChatCameraSourceChoiceRequest?
    @Published var pendingFileSourceChoice: ExampleChatFileSourceChoiceRequest?
    @Published var pendingCameraCapture: ExampleChatCameraCaptureRequest?
    @Published var pendingVideoPreview: ExampleChatVideoPreviewRequest?
    @Published var pendingFilePreview: ExampleChatFilePreviewRequest?
    @Published var pendingURLAction: ExampleURLAction?
    @Published var pendingAvatarSourceChoice: ExampleAvatarSourceChoiceRequest?
    @Published var pendingAvatarPicker: ExampleChatAvatarSelectionRequest?
    @Published var pendingTeamAvatarPicker: ExampleTeamAvatarSelectionRequest?
    @Published var pendingCallSourceChoice: ExampleChatCallSourceChoiceRequest?
    @Published var pendingLocationPicker: ExampleChatLocationPickerRequest?

    private let audioRecorder = ExampleChatAudioRecorder()
    private let audioPlayer = ExampleChatAudioPlayer()
    private var mediaPickerCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var filePickerCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var sourceChoiceCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var cameraCaptureCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var videoPreviewCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var filePreviewCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var callCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var locationPickerCompletions = [String: (Result<ChatNativeBoundaryResult, Error>) -> Void]()
    private var avatarSelectionCompletions = [String: (Result<ChatAvatarSelectionResult, Error>) -> Void]()
    private var teamAvatarSelectionCompletions = [String: (Result<TeamAvatarSelectionResult, Error>) -> Void]()
    private weak var urlActionAlertController: UIAlertController?
    private var urlActionPresentationGeneration = 0

    private init() {}

    var nativeBoundaryHandler: ChatNativeBoundaryHandling {
        ChatNativeBoundaryHandler { [weak self] action, context, completion in
            Task { @MainActor in
                self?.handleMoreAction(action, context: context, completion: completion)
            }
        }
    }

    var mediaPreviewHandler: ChatMediaPreviewHandling {
        ChatMediaPreviewHandler { [weak self] request, completion in
            Task { @MainActor in
                self?.handleMediaPreview(request, completion: completion)
            }
        }
    }

    var audioRecordingHandler: ChatAudioRecordingHandling {
        ChatAudioRecordingHandler(
            begin: { [weak self] request, progress, completion in
                Task { @MainActor in
                    self?.audioRecorder.beginRecording(request, progress: progress, completion: completion)
                }
            },
            finish: { [weak self] request, completion in
                Task { @MainActor in
                    self?.audioRecorder.finishRecording(request, completion: completion)
                }
            },
            cancel: { [weak self] request, completion in
                Task { @MainActor in
                    self?.audioRecorder.cancelRecording(request, completion: completion)
                }
            }
        )
    }

    var audioPlaybackHandler: ChatAudioPlaybackHandling {
        ChatAudioPlaybackHandler(
            play: { [weak self] request, completion in
                Task { @MainActor in
                    self?.audioPlayer.playAudio(request, completion: completion)
                }
            },
            stop: { [weak self] request, completion in
                Task { @MainActor in
                    self?.audioPlayer.stopAudio(request, completion: completion)
                }
            },
            setAudioRoute: { [weak self] useSpeaker in
                Task { @MainActor in
                    self?.audioPlayer.setAudioRoute(useSpeaker: useSpeaker)
                }
            }
        )
    }

    var clipboardHandler: ChatClipboardHandling {
        ChatClipboardHandler { request, completion in
            Task { @MainActor in
                UIPasteboard.general.string = request.text
                completion(.success(.toast(ChatToastState(
                    message: NEChatUIKitSwiftUIBundle.localized("chat_copied", value: "Copied"),
                    style: .success
                ))))
            }
        }
    }

    var aiRobotConfigClipboardHandler: AIRobotConfigClipboardHandling {
        AIRobotConfigClipboardHandler { request, completion in
            Task { @MainActor in
                UIPasteboard.general.string = request.configString
                completion(.success(ChatToastState(
                    message: NEChatUIKitSwiftUIBundle.localized("ai_robot_config_copy_success", value: "Config copied"),
                    style: .success
                )))
            }
        }
    }

    var urlInteractionHandler: ChatURLInteractionHandling {
        ChatURLInteractionHandler { [weak self] request, completion in
            Task { @MainActor in
                switch request.kind {
                case .mail:
                    self?.presentURLAction(ExampleURLAction(
                        url: request.url,
                        kind: .mail,
                        displayText: request.displayText,
                        completion: completion
                    ))
                case .phone:
                    self?.presentURLAction(ExampleURLAction(
                        url: request.url,
                        kind: .phone,
                        displayText: request.displayText,
                        completion: completion
                    ))
                default:
                    guard UIApplication.shared.canOpenURL(request.url) else {
                        completion(.success(.toast(ChatToastState(
                            message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                            style: .warning
                        ))))
                        return
                    }
                    ExampleWebRouteCenter.shared.open(
                        title: request.displayText.isEmpty ? request.url.absoluteString : request.displayText,
                        url: request.url
                    )
                    completion(.success(.none))
                }
            }
        }
    }

    var fileInteractionHandler: ChatFileInteractionHandling {
        ChatFileInteractionHandler { [weak self] request, completion in
            Task { @MainActor in
                guard let self else {
                    completion(.success(.route(.filePreview(request.preview))))
                    return
                }
                guard let localPath = request.preview.file.existingLocalPath else {
                    completion(.success(.route(.filePreview(request.preview))))
                    return
                }
                let url = URL(fileURLWithPath: localPath)
                if Self.isVideoFile(
                    url: url,
                    fileName: request.preview.file.name,
                    fileExtension: request.preview.file.fileExtension
                ) {
                    let previewRequest = ExampleChatVideoPreviewRequest(
                        url: url,
                        title: request.preview.file.name,
                        duration: nil
                    )
                    self.videoPreviewCompletions[previewRequest.id] = completion
                    self.pendingVideoPreview = previewRequest
                    return
                }
                let previewRequest = ExampleChatFilePreviewRequest(url: url)
                self.filePreviewCompletions[previewRequest.id] = completion
                self.pendingFilePreview = previewRequest
            }
        }
    }

    var locationInteractionHandler: ChatLocationInteractionHandling {
        ChatLocationInteractionHandler { request, completion in
            completion(.success(.route(.locationDetail(request.location))))
        }
    }

    var callInteractionHandler: ChatCallInteractionHandling {
        ChatCallInteractionHandler { [weak self] request, completion in
            Task { @MainActor in
                self?.handleCallInteraction(request, completion: completion)
            }
        }
    }

    var avatarSelectionHandler: ChatAvatarSelectionHandling {
        ChatAvatarSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let avatarRequest = ExampleChatAvatarSelectionRequest(request: request)
                self?.avatarSelectionCompletions[avatarRequest.id] = completion
                self?.pendingAvatarSourceChoice = ExampleAvatarSourceChoiceRequest(target: .chatAvatar(avatarRequest))
            }
        }
    }

    var teamAvatarSelectionHandler: TeamAvatarSelectionHandling {
        TeamAvatarSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let avatarRequest = ExampleTeamAvatarSelectionRequest(request: request)
                self?.teamAvatarSelectionCompletions[avatarRequest.id] = completion
                self?.pendingAvatarSourceChoice = ExampleAvatarSourceChoiceRequest(target: .teamAvatar(avatarRequest))
            }
        }
    }

    func saveImageToPhotoLibrary(_ item: ChatMediaItem) async throws {
        let url = item.kind == .image ? item.media.imageDownloadURL : item.media.videoURL
        guard let url else {
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
        let localURL: URL
        if url.isFileURL {
            localURL = url
        } else {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                throw ExampleChatNativeBoundaryError.imageDownloadFailed
            }
            localURL = temporaryURL
        }
        switch item.kind {
        case .image:
            try await Self.saveImageFileToPhotoLibrary(localURL)
        case .video:
            try await Self.saveVideoFileToPhotoLibrary(localURL)
        }
    }

    private func handleMoreAction(_ action: ChatMoreAction,
                                  context: ChatSessionContext,
                                  completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
    {
        switch action {
        case .photo:
            let request = ExampleChatMediaPickerRequest(source: .photoLibrary)
            mediaPickerCompletions[request.id] = completion
            pendingPhotoPicker = request
        case .takePicture:
            let request = ExampleChatCameraSourceChoiceRequest()
            sourceChoiceCompletions[request.id] = completion
            pendingCameraSourceChoice = request
        case .file:
            let request = ExampleChatFileSourceChoiceRequest()
            sourceChoiceCompletions[request.id] = completion
            pendingFileSourceChoice = request
        case .rtc:
            let request = ExampleChatCallSourceChoiceRequest(context: context)
            callCompletions[request.id] = completion
            pendingCallSourceChoice = request
        case .location:
            let request = ExampleChatLocationPickerRequest()
            locationPickerCompletions[request.id] = completion
            pendingLocationPicker = request
        default:
            completion(.success(.toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .info
            ))))
        }
    }

    private func handleCallInteraction(_ request: ChatCallInteractionRequest,
                                       completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
    {
        let callType = request.call.type == 1 ? 1 : 2
        guard let result = routeCall(type: callType, context: request.context) else {
            completion(.success(.toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ))))
            return
        }
        completion(.success(result))
    }

    func selectCameraSource(_ mode: ExampleChatCameraCaptureMode) {
        guard let request = pendingCameraSourceChoice,
              let completion = sourceChoiceCompletions.removeValue(forKey: request.id)
        else {
            pendingCameraSourceChoice = nil
            return
        }
        pendingCameraSourceChoice = nil
        Task {
            guard await Self.requestCameraAccess() else {
                Self.showCameraSettingsPrompt()
                completion(.success(.toast(ChatToastState(
                    message: ExampleChatNativeBoundaryError.cameraPermissionDenied.userVisibleMessage,
                    style: .warning
                ))))
                return
            }
            let captureRequest = ExampleChatCameraCaptureRequest(mode: mode)
            cameraCaptureCompletions[captureRequest.id] = completion
            pendingCameraCapture = captureRequest
        }
    }

    func cancelCameraSourceChoice() {
        guard let request = pendingCameraSourceChoice else {
            return
        }
        pendingCameraSourceChoice = nil
        sourceChoiceCompletions.removeValue(forKey: request.id)?(.success(.none))
    }

    func selectFileSource(_ source: ExampleChatFileSource) {
        guard let request = pendingFileSourceChoice,
              let completion = sourceChoiceCompletions.removeValue(forKey: request.id)
        else {
            pendingFileSourceChoice = nil
            return
        }
        pendingFileSourceChoice = nil
        switch source {
        case .iCloud:
            let fileRequest = ExampleChatFilePickerRequest()
            filePickerCompletions[fileRequest.id] = completion
            pendingFileImporter = fileRequest
        case .album:
            let mediaRequest = ExampleChatMediaPickerRequest(source: .fileAlbum)
            mediaPickerCompletions[mediaRequest.id] = completion
            pendingPhotoPicker = mediaRequest
        }
    }

    func cancelFileSourceChoice() {
        guard let request = pendingFileSourceChoice else {
            return
        }
        pendingFileSourceChoice = nil
        sourceChoiceCompletions.removeValue(forKey: request.id)?(.success(.none))
    }

    func selectAvatarSource(_ source: ExampleAvatarSource) {
        guard let request = pendingAvatarSourceChoice else {
            return
        }
        pendingAvatarSourceChoice = nil

        switch (source, request.target) {
        case let (.camera, .chatAvatar(avatarRequest)):
            prepareAvatarCameraCapture(
                target: .chatAvatar(avatarRequest),
                onDenied: { [weak self] in
                    self?.completeAvatarSelection(avatarRequest, result: .success(nil))
                }
            )
        case let (.camera, .teamAvatar(avatarRequest)):
            guard DemoNetworkPresentation.allowsNetworkOperation else {
                completeTeamAvatarSelection(
                    avatarRequest,
                    result: .failure(ExampleChatNativeBoundaryError.userVisibleMessage(DemoNetworkPresentation.networkMessage()))
                )
                return
            }
            prepareAvatarCameraCapture(
                target: .teamAvatar(avatarRequest),
                onDenied: { [weak self] in
                    self?.completeTeamAvatarSelection(avatarRequest, result: .success(nil))
                }
            )
        case let (.album, .chatAvatar(avatarRequest)):
            pendingAvatarPicker = avatarRequest
        case let (.album, .teamAvatar(avatarRequest)):
            guard DemoNetworkPresentation.allowsNetworkOperation else {
                completeTeamAvatarSelection(
                    avatarRequest,
                    result: .failure(ExampleChatNativeBoundaryError.userVisibleMessage(DemoNetworkPresentation.networkMessage()))
                )
                return
            }
            pendingTeamAvatarPicker = avatarRequest
        }
    }

    private func prepareAvatarCameraCapture(target: ExampleCameraCaptureTarget,
                                            onDenied: @escaping () -> Void) {
        Task {
            guard await Self.requestCameraAccess() else {
                Self.showCameraSettingsPrompt()
                onDenied()
                return
            }
            pendingCameraCapture = ExampleChatCameraCaptureRequest(
                mode: .photo,
                target: target
            )
        }
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private static func showCameraSettingsPrompt() {
        let error = ExampleChatNativeBoundaryError.cameraPermissionDenied
        NotificationCenter.default.post(
            name: .appSettingsPrompt,
            object: AppSettingsPrompt(
                title: localizable("camera_permission_title"),
                message: error.userVisibleMessage
            )
        )
    }

    func cancelAvatarSourceChoice() {
        guard let request = pendingAvatarSourceChoice else {
            return
        }
        pendingAvatarSourceChoice = nil

        switch request.target {
        case let .chatAvatar(avatarRequest):
            completeAvatarSelection(avatarRequest, result: .success(nil))
        case let .teamAvatar(avatarRequest):
            completeTeamAvatarSelection(avatarRequest, result: .success(nil))
        }
    }

    func selectCallSource(_ callType: Int) {
        guard let request = pendingCallSourceChoice,
              let completion = callCompletions.removeValue(forKey: request.id)
        else {
            pendingCallSourceChoice = nil
            return
        }
        pendingCallSourceChoice = nil

        guard let result = routeCall(type: callType, context: request.context) else {
            completion(.success(.toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ))))
            return
        }
        completion(.success(result))
    }

    func cancelCallSourceChoice() {
        guard let request = pendingCallSourceChoice else {
            return
        }
        pendingCallSourceChoice = nil
        callCompletions.removeValue(forKey: request.id)?(.success(.none))
    }

    func completeLocationPicker(_ request: ExampleChatLocationPickerRequest,
                                selection: ExampleChatLocationSelection?) {
        let completion = locationPickerCompletions.removeValue(forKey: request.id)
        pendingLocationPicker = nil
        guard let selection else {
            completion?(.success(.none))
            return
        }
        completion?(.success(.send(.location(
            latitude: selection.coordinate.latitude,
            longitude: selection.coordinate.longitude,
            title: selection.title,
            address: selection.address
        ))))
    }

    private func routeCall(type: Int, context: ChatSessionContext) -> ChatNativeBoundaryResult? {
        guard let sessionId = Self.sessionId(from: context), !sessionId.isEmpty else {
            return .toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ))
        }

        if !IMKitConfigCenter.shared.enableOnlyFriendCall,
           !NEFriendUserCache.shared.isFriend(sessionId) {
            return .toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("disable_stranger_call", value: "Not a contact, call failed."),
                style: .warning
            ))
        }

        var param = [String: Any]()
        param["remoteUserAccid"] = sessionId
        param["currentUserAccid"] = IMKitClient.instance.account()
        param["remoteShowName"] = Self.displayName(for: sessionId)
        param["type"] = NSNumber(integerLiteral: type)
        if let avatar = NEFriendUserCache.shared.getFriendInfo(sessionId)?.user?.avatar,
           !avatar.isEmpty {
            param["remoteAvatar"] = avatar
        }

        var didRoute = false
        Router.shared.use(CallViewRouter, parameters: param) { _, state, _ in
            didRoute = state == .success
        }
        guard didRoute else {
            return .toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ))
        }
        return ChatNativeBoundaryResult.none
    }

    private static func sessionId(from context: ChatSessionContext) -> String? {
        if let sessionId = context.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionId.isEmpty {
            return sessionId
        }
        return V2NIMConversationIdUtil.conversationTargetId(context.conversationId)
    }

    private static func displayName(for accountId: String) -> String {
        let showName = NEAIUserManager.shared.getShowName(accountId) ??
            NEFriendUserCache.shared.getShowName(accountId, true)
        return showName.isEmpty ? accountId : showName
    }

    private func handleMediaPreview(_ request: ChatMediaPreviewRequest,
                                    completion: @escaping (Result<ChatNativeBoundaryResult, Error>) -> Void)
    {
        completion(.success(.route(.mediaPreview(request.preview))))
    }

    private static func isVideoFile(url: URL, fileName: String, fileExtension: String?) -> Bool {
        let videoExtensions: Set<String> = [
            "mp4", "avi", "wmv", "mpeg", "m4v", "mov",
            "asf", "flv", "f4v", "rmvb", "rm", "3gp"
        ]
        return [url.pathExtension, (fileName as NSString).pathExtension, fileExtension]
            .compactMap { $0?
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
                .lowercased()
            }
            .contains { videoExtensions.contains($0) }
    }

    func completeMediaPicker(_ request: ExampleChatMediaPickerRequest,
                             result: Result<[ChatOutgoingMessagePayload], Error>)
    {
        let completion = mediaPickerCompletions.removeValue(forKey: request.id)
        pendingPhotoPicker = nil
        switch result {
        case let .success(payloads):
            if payloads.isEmpty {
                completion?(.success(.none))
            } else if payloads.count == 1, let payload = payloads.first {
                completion?(.success(.send(payload)))
            } else {
                completion?(.success(.sendMultiple(payloads)))
            }
        case let .failure(error):
            completion?(.failure(error))
        }
    }

    func completeAvatarSelection(_ request: ExampleChatAvatarSelectionRequest,
                                 result: Result<String?, Error>)
    {
        let completion = avatarSelectionCompletions.removeValue(forKey: request.id)
        pendingAvatarPicker = nil
        switch result {
        case let .success(urlString):
            completion?(.success(urlString.flatMap(URL.init(string:)).map(ChatAvatarSelectionResult.selected) ?? .cancelled))
        case let .failure(error):
            completion?(.failure(error))
        }
    }

    func completeTeamAvatarSelection(_ request: ExampleTeamAvatarSelectionRequest,
                                     result: Result<String?, Error>)
    {
        let completion = teamAvatarSelectionCompletions.removeValue(forKey: request.id)
        pendingTeamAvatarPicker = nil
        switch result {
        case let .success(url):
            completion?(.success(url.map { .selected(url: $0) } ?? .cancelled))
        case let .failure(error):
            completion?(.failure(error))
        }
    }

    func completeFilePicker(_ request: ExampleChatFilePickerRequest,
                            result: Result<ChatOutgoingMessagePayload?, Error>)
    {
        let completion = filePickerCompletions.removeValue(forKey: request.id)
        pendingFileImporter = nil
        switch result {
        case let .success(payload):
            completion?(.success(payload.map(ChatNativeBoundaryResult.send) ?? .none))
        case let .failure(error):
            completion?(.failure(error))
        }
    }

    func completeCameraCapture(_ request: ExampleChatCameraCaptureRequest,
                               result: Result<ChatOutgoingMessagePayload?, Error>)
    {
        pendingCameraCapture = nil

        switch request.target {
        case .chatMessage:
            let completion = cameraCaptureCompletions.removeValue(forKey: request.id)
            switch result {
            case let .success(payload):
                completion?(.success(payload.map(ChatNativeBoundaryResult.send) ?? .none))
            case let .failure(error):
                // Permission denial is an actionable, non-fatal camera result.
                // Returning a boundary failure makes the chat route render its
                // error page and leaves subsequent camera taps unusable.
                let message = DemoNetworkPresentation.chatMessage(
                    for: error,
                    fallbackKey: "chat_camera_unavailable",
                    fallbackValue: "Camera is unavailable"
                )
                completion?(.success(.toast(ChatToastState(message: message, style: .warning))))
            }
        case let .chatAvatar(avatarRequest):
            switch result {
            case let .success(payload):
                guard let path = payload?.capturedImagePath else {
                    completeAvatarSelection(avatarRequest, result: .success(nil))
                    return
                }
                let fileURL = URL(fileURLWithPath: path)
                Task {
                    let uploadResult: Result<String?, Error>
                    do {
                        uploadResult = try await ExampleChatPayloadBuilder.uploadedAvatarURL(
                            from: fileURL,
                            compressionQuality: ExampleChatPayloadBuilder.avatarCompressionQuality(
                                for: avatarRequest.request.source
                            )
                        )
                    } catch {
                        uploadResult = .failure(error)
                    }
                    await MainActor.run {
                        self.completeAvatarSelection(avatarRequest, result: uploadResult)
                    }
                }
            case let .failure(error):
                completeAvatarSelection(avatarRequest, result: .failure(error))
            }
        case let .teamAvatar(avatarRequest):
            switch result {
            case let .success(payload):
                guard let path = payload?.capturedImagePath else {
                    completeTeamAvatarSelection(avatarRequest, result: .success(nil))
                    return
                }
                guard DemoNetworkPresentation.allowsNetworkOperation else {
                    completeTeamAvatarSelection(
                        avatarRequest,
                        result: .failure(ExampleChatNativeBoundaryError.userVisibleMessage(DemoNetworkPresentation.networkMessage()))
                    )
                    return
                }
                let fileURL = URL(fileURLWithPath: path)
                Task {
                    let uploadResult: Result<String?, Error>
                    do {
                        uploadResult = try await ExampleChatPayloadBuilder.uploadedAvatarURL(
                            from: fileURL,
                            compressionQuality: 0.6
                        )
                    } catch {
                        uploadResult = .failure(error)
                    }
                    await MainActor.run {
                        self.completeTeamAvatarSelection(avatarRequest, result: uploadResult)
                    }
                }
            case let .failure(error):
                completeTeamAvatarSelection(avatarRequest, result: .failure(error))
            }
        }
    }

    func completeVideoPreview(_ request: ExampleChatVideoPreviewRequest) {
        pendingVideoPreview = nil
        videoPreviewCompletions.removeValue(forKey: request.id)?(.success(.none))
    }

    func completeFilePreview(_ request: ExampleChatFilePreviewRequest) {
        pendingFilePreview = nil
        filePreviewCompletions.removeValue(forKey: request.id)?(.success(.none))
    }

    func confirmURLAction(_ action: ExampleURLAction) {
        pendingURLAction = nil
        urlActionAlertController = nil
        guard UIApplication.shared.canOpenURL(action.url) else {
            action.completion(.success(.toast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ))))
            return
        }
        UIApplication.shared.open(action.url)
        action.completion(.success(.none))
    }

    func copyURLAction(_ action: ExampleURLAction) {
        pendingURLAction = nil
        urlActionAlertController = nil
        UIPasteboard.general.string = action.address
        action.completion(.success(.toast(ChatToastState(
            message: NECommonUIKitSwiftUIBundle.localized("copy_success", fallback: "Copied!"),
            style: .success
        ))))
    }

    func cancelURLAction(_ action: ExampleURLAction) {
        pendingURLAction = nil
        urlActionAlertController = nil
        action.completion(.success(.none))
    }

    private func presentURLAction(_ action: ExampleURLAction) {
        if let pending = pendingURLAction, pending.id != action.id {
            cancelURLAction(pending)
        }
        pendingURLAction = action
        urlActionPresentationGeneration += 1
        presentURLActionIfPossible(
            actionID: action.id,
            generation: urlActionPresentationGeneration,
            remainingAttempts: 12
        )
    }

    private func presentURLActionIfPossible(actionID: UUID,
                                            generation: Int,
                                            remainingAttempts: Int) {
        guard generation == urlActionPresentationGeneration,
              pendingURLAction?.id == actionID,
              urlActionAlertController == nil else {
            return
        }
        guard let presenter = Self.topViewController(),
              presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingDismissed else {
            retryURLActionPresentation(
                actionID: actionID,
                generation: generation,
                remainingAttempts: remainingAttempts
            )
            return
        }
        guard let action = pendingURLAction else {
            return
        }

        let alert = UIAlertController(
            title: urlActionDialogTitle(for: action),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: action.kind == .mail
                ? NECommonUIKitSwiftUIBundle.localized("detect_mailto_send", fallback: "Send via default email account")
                : NECommonUIKitSwiftUIBundle.localized("detect_tel_call", fallback: "Call"),
            style: .default
        ) { [weak self] _ in
            self?.confirmURLAction(action)
        })
        alert.addAction(UIAlertAction(
            title: urlActionCopyTitle(for: action),
            style: .default
        ) { [weak self] _ in
            self?.copyURLAction(action)
        })
        alert.addAction(UIAlertAction(
            title: NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"),
            style: .cancel
        ) { [weak self] _ in
            self?.cancelURLAction(action)
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        urlActionAlertController = alert
        presenter.present(alert, animated: true)
    }

    private func retryURLActionPresentation(actionID: UUID,
                                            generation: Int,
                                            remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            guard generation == urlActionPresentationGeneration,
                  let action = pendingURLAction,
                  action.id == actionID else {
                return
            }
            cancelURLAction(action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.presentURLActionIfPossible(
                actionID: actionID,
                generation: generation,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private func urlActionDialogTitle(for action: ExampleURLAction) -> String {
        switch action.kind {
        case .mail:
            let format = NECommonUIKitSwiftUIBundle.localized(
                "detect_mailto_title",
                fallback: "Send message to\"%@\""
            )
            return String(format: format, action.address)
        case .phone:
            let format = NECommonUIKitSwiftUIBundle.localized(
                "detect_tel_title",
                fallback: "\"%@\" may be a phone number, You can:"
            )
            return String(format: format, action.address)
        default:
            return action.address
        }
    }

    private func urlActionCopyTitle(for action: ExampleURLAction) -> String {
        switch action.kind {
        case .mail:
            return NECommonUIKitSwiftUIBundle.localized("detect_mailto_copy", fallback: "Copy Email")
        case .phone:
            return NECommonUIKitSwiftUIBundle.localized("detect_tel_copy", fallback: "Copy Number")
        default:
            return NECommonUIKitSwiftUIBundle.localized("copy", fallback: "Copy")
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? scenes
            .flatMap(\.windows)
            .first(where: { !$0.isHidden && $0.alpha > 0 })
        return topViewController(from: window?.rootViewController)
    }

    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else {
            return nil
        }
        if let presented = controller.presentedViewController,
           !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let visibleChild = controller.children.last(where: { child in
            child.viewIfLoaded?.window != nil
        }) {
            return topViewController(from: visibleChild)
        }
        return controller
    }

    private static func saveImageFileToPhotoLibrary(_ url: URL) async throws {
        guard let data = try? Data(contentsOf: url),
              ExampleChatImageMetadata.size(from: data) != nil else {
            throw ExampleChatNativeBoundaryError.invalidImageData
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw ExampleChatNativeBoundaryError.photoPermissionDenied
            }
        default:
            throw ExampleChatNativeBoundaryError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExampleChatNativeBoundaryError.unsupportedMedia)
                }
            }
        }
    }

    private static func saveVideoFileToPhotoLibrary(_ url: URL) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw ExampleChatNativeBoundaryError.photoPermissionDenied
            }
        default:
            throw ExampleChatNativeBoundaryError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExampleChatNativeBoundaryError.unsupportedMedia)
                }
            }
        }
    }
}

struct ExampleChatMediaPickerRequest: Identifiable, Equatable {
    enum Source: Equatable {
        case photoLibrary
        case fileAlbum
    }

    let id = UUID().uuidString
    var source: Source
}

struct ExampleChatFilePickerRequest: Identifiable, Equatable {
    let id = UUID().uuidString
}

struct ExampleChatCameraSourceChoiceRequest: Identifiable, Equatable {
    let id = UUID().uuidString
}

struct ExampleChatFileSourceChoiceRequest: Identifiable, Equatable {
    let id = UUID().uuidString
}

struct ExampleChatCallSourceChoiceRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var context: ChatSessionContext
}

struct ExampleAvatarSourceChoiceRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var target: ExampleAvatarSelectionTarget
}

enum ExampleChatCameraCaptureMode: String, Equatable {
    case photo
    case video
}

enum ExampleChatFileSource: Equatable {
    case iCloud
    case album
}

enum ExampleAvatarSource: Equatable {
    case camera
    case album
}

enum ExampleAvatarSelectionTarget: Equatable {
    case chatAvatar(ExampleChatAvatarSelectionRequest)
    case teamAvatar(ExampleTeamAvatarSelectionRequest)
}

enum ExampleCameraCaptureTarget: Equatable {
    case chatMessage
    case chatAvatar(ExampleChatAvatarSelectionRequest)
    case teamAvatar(ExampleTeamAvatarSelectionRequest)
}

struct ExampleChatCameraCaptureRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var mode: ExampleChatCameraCaptureMode
    var target: ExampleCameraCaptureTarget = .chatMessage
}

struct ExampleChatVideoPreviewRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var url: URL
    var title: String?
    var duration: TimeInterval?
}

struct ExampleURLAction: Identifiable {
    let id = UUID()
    let url: URL
    let kind: ChatURLInteractionKind
    let displayText: String
    let completion: (Result<ChatNativeBoundaryResult, Error>) -> Void

    var address: String {
        switch kind {
        case .mail:
            return url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        case .phone:
            return url.absoluteString.replacingOccurrences(of: "tel:", with: "")
        default:
            return url.absoluteString
        }
    }
}

struct ExampleChatFilePreviewRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var url: URL
}

struct ExampleChatLocationPickerRequest: Identifiable, Equatable {
    let id = UUID().uuidString
}

struct ExampleChatLocationSelection: Identifiable, Equatable {
    let id = UUID().uuidString
    var coordinate: CLLocationCoordinate2D
    var title: String
    var address: String

    static func == (lhs: ExampleChatLocationSelection,
                    rhs: ExampleChatLocationSelection) -> Bool {
        lhs.id == rhs.id &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title &&
            lhs.address == rhs.address
    }
}

struct ExampleChatAvatarSelectionRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var request: ChatAvatarSelectionRequest
}

struct ExampleTeamAvatarSelectionRequest: Identifiable, Equatable {
    let id = UUID().uuidString
    var request: TeamAvatarSelectionRequest
}

enum ExampleChatNativeBoundaryError: LocalizedError, ChatUserVisibleError, TeamUserVisibleError {
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraAndMicrophonePermissionDenied
    case missingSelection
    case unsupportedMedia
    case fileAccessFailed
    case audioPermissionDenied
    case audioTooShort
    case recorderUnavailable
    case playerUnavailable
    case imageDownloadFailed
    case invalidImageData
    case photoPermissionDenied
    case userVisibleMessage(String)

    var errorDescription: String? {
        userVisibleMessage
    }

    var userVisibleMessage: String {
        switch self {
        case .cameraUnavailable:
            return NEChatUIKitSwiftUIBundle.localized("chat_camera_unavailable", value: "Camera is unavailable")
        case .cameraPermissionDenied:
            return NEChatUIKitSwiftUIBundle.localized("chat_camera_permission_required", value: "Please allow camera access in Settings.")
        case .cameraAndMicrophonePermissionDenied:
            return NEChatUIKitSwiftUIBundle.localized("chat_camera_microphone_permission_required", value: "Please allow camera and microphone access in Settings.")
        case .missingSelection:
            return NEChatUIKitSwiftUIBundle.localized("chat_media_missing_selection", value: "No media selected")
        case .unsupportedMedia:
            return NEChatUIKitSwiftUIBundle.localized("chat_media_unsupported", value: "Unsupported media type")
        case .fileAccessFailed:
            return NEChatUIKitSwiftUIBundle.localized("chat_file_access_failed", value: "File access failed")
        case .audioPermissionDenied:
            return NEChatUIKitSwiftUIBundle.localized("chat_microphone_permission_required", value: "Please allow microphone access in Settings.")
        case .audioTooShort:
            return NEChatUIKitSwiftUIBundle.localized("chat_audio_too_short", value: "Recording is too short")
        case .recorderUnavailable:
            return NEChatUIKitSwiftUIBundle.localized("chat_audio_recorder_unavailable", value: "Recorder is unavailable")
        case .playerUnavailable:
            return NEChatUIKitSwiftUIBundle.localized("chat_audio_player_unavailable", value: "Player is unavailable")
        case .imageDownloadFailed, .invalidImageData:
            return NEChatUIKitSwiftUIBundle.localized("chat_image_save_failed", value: "Failed to save image")
        case .photoPermissionDenied:
            return NEChatUIKitSwiftUIBundle.localized("chat_photo_permission_required", value: "Please allow photo access in Settings.")
        case let .userVisibleMessage(message):
            return message
        }
    }
}

private extension ChatOutgoingMessagePayload {
    var capturedImagePath: String? {
        switch self {
        case let .image(path, _, _, _):
            return path
        default:
            return nil
        }
    }
}

private enum ExampleZLPhotoPickerTarget: Identifiable {
    case media(ExampleChatMediaPickerRequest)
    case chatAvatar(ExampleChatAvatarSelectionRequest)
    case teamAvatar(ExampleTeamAvatarSelectionRequest)

    var id: String {
        switch self {
        case let .media(request):
            return request.id
        case let .chatAvatar(request):
            return request.id
        case let .teamAvatar(request):
            return request.id
        }
    }
}

private struct ExampleZLPhotoPickerPresentation: Identifiable {
    var target: ExampleZLPhotoPickerTarget
    var picker: ZLPhotoPicker

    var id: String {
        target.id
    }
}

private struct ExampleZLPhotoPickerView: UIViewControllerRepresentable {
    var picker: ZLPhotoPicker

    func makeUIViewController(context: Context) -> UIViewController {
        picker.showPhotoLibraryForSwiftUI()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ExampleChatMediaPickerModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService

    @State private var activeFileRequest: ExampleChatFilePickerRequest?
    @State private var activePhotoRequest: ExampleChatMediaPickerRequest?
    @State private var activeAvatarRequest: ExampleChatAvatarSelectionRequest?
    @State private var activeTeamAvatarRequest: ExampleTeamAvatarSelectionRequest?
    @State private var activeZLPhotoPickerPresentation: ExampleZLPhotoPickerPresentation?
    @State private var isResolvingPhotoSelection = false
    @State private var isResolvingAvatarSelection = false
    @State private var isResolvingTeamAvatarSelection = false
    @State private var isResolvingFileSelection = false
    @State private var activeZLPhotoPicker: ZLPhotoPicker?
    @State private var selectedChatVideoAssetIds = Set<String>()

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                item: $activeZLPhotoPickerPresentation,
                onDismiss: handleZLPhotoPickerDismiss
            ) { presentation in
                ExampleZLPhotoPickerView(picker: presentation.picker)
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                "",
                isPresented: cameraSourceChoiceBinding,
                titleVisibility: .hidden
            ) {
                Button(NECommonUIKitSwiftUIBundle.localized("take_picture", fallback: "Photo")) {
                    service.selectCameraSource(.photo)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("camera", fallback: "Video")) {
                    service.selectCameraSource(.video)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"), role: .cancel) {
                    service.cancelCameraSourceChoice()
                }
            }
            .confirmationDialog(
                "",
                isPresented: fileSourceChoiceBinding,
                titleVisibility: .hidden
            ) {
                Button(NECommonUIKitSwiftUIBundle.localized("select_from_icloud", fallback: "iCloud")) {
                    service.selectFileSource(.iCloud)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("select_from_album", fallback: "Album")) {
                    service.selectFileSource(.album)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"), role: .cancel) {
                    service.cancelFileSourceChoice()
                }
            }
            .confirmationDialog(
                "",
                isPresented: avatarSourceChoiceBinding,
                titleVisibility: .hidden
            ) {
                Button(NECommonUIKitSwiftUIBundle.localized("take_picture", fallback: "Photo")) {
                    service.selectAvatarSource(.camera)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("select_from_album", fallback: "Album")) {
                    service.selectAvatarSource(.album)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"), role: .cancel) {
                    service.cancelAvatarSourceChoice()
                }
            }
            .confirmationDialog(
                "",
                isPresented: callSourceChoiceBinding,
                titleVisibility: .hidden
            ) {
                Button(NEChatUIKitSwiftUIBundle.localized("video_call", value: "Video Call")) {
                    service.selectCallSource(2)
                }
                Button(NEChatUIKitSwiftUIBundle.localized("audio_call", value: "Voice Call")) {
                    service.selectCallSource(1)
                }
                Button(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"), role: .cancel) {
                    service.cancelCallSourceChoice()
                }
            }
            .onChange(of: service.pendingFileImporter) { request in
                activeFileRequest = request
            }
            .fileImporter(
                isPresented: fileImporterBinding,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                guard let request = activeFileRequest else {
                    return
                }
                isResolvingFileSelection = true
                Task {
                    let payloadResult = await ExampleChatPayloadBuilder.filePayload(from: result)
                    await MainActor.run {
                        isResolvingFileSelection = false
                        activeFileRequest = nil
                        service.completeFilePicker(request, result: payloadResult)
                    }
                }
            }
            .onChange(of: service.pendingPhotoPicker) { request in
                guard let request else {
                    resetZLPhotoSelectionCallbacks()
                    activePhotoRequest = nil
                    activeZLPhotoPickerPresentation = nil
                    isResolvingPhotoSelection = false
                    activeZLPhotoPicker = nil
                    return
                }
                preparePhotoPicker(for: request)
            }
            .onChange(of: service.pendingAvatarPicker) { request in
                guard let request else {
                    activeAvatarRequest = nil
                    return
                }
                prepareAvatarPicker(for: request)
            }
            .onChange(of: service.pendingTeamAvatarPicker) { request in
                guard let request else {
                    activeTeamAvatarRequest = nil
                    return
                }
                prepareTeamAvatarPicker(for: request)
            }
    }

    private var cameraSourceChoiceBinding: Binding<Bool> {
        Binding(
            get: { service.pendingCameraSourceChoice != nil },
            set: { isPresented in
                if !isPresented {
                    service.cancelCameraSourceChoice()
                }
            }
        )
    }

    private var fileSourceChoiceBinding: Binding<Bool> {
        Binding(
            get: { service.pendingFileSourceChoice != nil },
            set: { isPresented in
                if !isPresented {
                    service.cancelFileSourceChoice()
                }
            }
        )
    }

    private var avatarSourceChoiceBinding: Binding<Bool> {
        Binding(
            get: { service.pendingAvatarSourceChoice != nil },
            set: { isPresented in
                if !isPresented {
                    service.cancelAvatarSourceChoice()
                }
            }
        )
    }

    private var callSourceChoiceBinding: Binding<Bool> {
        Binding(
            get: { service.pendingCallSourceChoice != nil },
            set: { isPresented in
                if !isPresented {
                    service.cancelCallSourceChoice()
                }
            }
        )
    }

    private var fileImporterBinding: Binding<Bool> {
        Binding(
            get: { activeFileRequest != nil },
            set: { isPresented in
                guard !isPresented,
                      let request = activeFileRequest else {
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if activeFileRequest == request,
                       !isResolvingFileSelection
                    {
                        activeFileRequest = nil
                        service.completeFilePicker(request, result: .success(nil))
                    }
                }
            }
        )
    }

    private func preparePhotoPicker(for request: ExampleChatMediaPickerRequest) {
        requestPhotoLibraryAccess { granted in
            guard service.pendingPhotoPicker == request else {
                return
            }
            if granted {
                presentZLPhotoPicker(for: request)
            } else {
                activePhotoRequest = nil
                service.completeMediaPicker(request, result: .failure(ExampleChatNativeBoundaryError.photoPermissionDenied))
            }
        }
    }

    private func presentZLPhotoPicker(for request: ExampleChatMediaPickerRequest) {
        configureZLPhotoBrowser(for: request)
        let picker = ZLPhotoPicker()
        activeZLPhotoPicker = picker
        activePhotoRequest = request

        picker.cancelBlock = {
            Task { @MainActor in
                guard service.pendingPhotoPicker == request else {
                    return
                }
                resetZLPhotoPickerState()
                service.completeMediaPicker(request, result: .success([]))
            }
        }
        picker.selectImageBlock = { results, isOriginal in
            Task { @MainActor in
                guard service.pendingPhotoPicker == request else {
                    return
                }
                isResolvingPhotoSelection = true
                let result = await ExampleChatPayloadBuilder.payloads(
                    from: results,
                    source: request.source,
                    isOriginal: isOriginal
                )
                guard service.pendingPhotoPicker == request else {
                    return
                }
                resetZLPhotoPickerState()
                service.completeMediaPicker(request, result: result)
            }
        }
        activeZLPhotoPickerPresentation = ExampleZLPhotoPickerPresentation(
            target: .media(request),
            picker: picker
        )
    }

    private func configureZLPhotoBrowser(for request: ExampleChatMediaPickerRequest) {
        resetZLPhotoSelectionCallbacks()
        let config = ZLPhotoConfiguration.default()
        switch request.source {
        case .photoLibrary:
            config.allowSelectImage = true
            config.allowSelectVideo = true
            config.allowSelectLivePhoto = true
            config.allowTakePhotoInLibrary = false
            config.allowMixSelect = false
            config.editAfterSelectThumbnailImage = false
            config.maxSelectCount = chatImageCountLimit
            config.showSelectBtnWhenSingleSelect = true
            config.maxSelectVideoDataSize = ChatSwiftUIConfigCenter.shared.current().fileSizeLimitMB * 1024
            config.canSelectAsset = { asset in
                guard !selectedChatVideoAssetIds.isEmpty else { return true }
                return selectedChatVideoAssetIds.contains(asset.localIdentifier)
            }
            config.didSelectAsset = { asset in
                guard asset.mediaType == .video else { return }
                selectedChatVideoAssetIds.insert(asset.localIdentifier)
                config.maxSelectCount = chatVideoCountLimit
            }
            config.didDeselectAsset = { asset in
                guard asset.mediaType == .video else { return }
                selectedChatVideoAssetIds.remove(asset.localIdentifier)
                if selectedChatVideoAssetIds.isEmpty {
                    config.maxSelectCount = chatImageCountLimit
                }
            }
        case .fileAlbum:
            config.allowSelectImage = true
            config.allowSelectVideo = true
            config.allowSelectLivePhoto = true
            config.allowTakePhotoInLibrary = false
            config.allowMixSelect = false
            config.editAfterSelectThumbnailImage = false
            config.maxSelectCount = 1
            config.maxSelectVideoDataSize = ChatSwiftUIConfigCenter.shared.current().fileSizeLimitMB * 1024
        }
    }

    private func handleZLPhotoPickerDismiss() {
        if let request = activePhotoRequest {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard activePhotoRequest == request,
                      service.pendingPhotoPicker == request,
                      !isResolvingPhotoSelection else {
                    return
                }
                resetZLPhotoPickerState()
                service.completeMediaPicker(request, result: .success([]))
            }
            return
        }

        if let request = activeAvatarRequest {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard activeAvatarRequest == request,
                      service.pendingAvatarPicker == request,
                      !isResolvingAvatarSelection else {
                    return
                }
                resetZLPhotoPickerState()
                service.completeAvatarSelection(request, result: .success(nil))
            }
            return
        }

        if let request = activeTeamAvatarRequest {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard activeTeamAvatarRequest == request,
                      service.pendingTeamAvatarPicker == request,
                      !isResolvingTeamAvatarSelection else {
                    return
                }
                resetZLPhotoPickerState()
                service.completeTeamAvatarSelection(request, result: .success(nil))
            }
        }
    }

    private func resetZLPhotoPickerState() {
        resetZLPhotoSelectionCallbacks()
        isResolvingPhotoSelection = false
        isResolvingAvatarSelection = false
        isResolvingTeamAvatarSelection = false
        activePhotoRequest = nil
        activeAvatarRequest = nil
        activeTeamAvatarRequest = nil
        activeZLPhotoPickerPresentation = nil
        activeZLPhotoPicker = nil
    }

    private func resetZLPhotoSelectionCallbacks() {
        selectedChatVideoAssetIds.removeAll()
        let config = ZLPhotoConfiguration.default()
        config.maxSelectCount = chatImageCountLimit
        config.showSelectBtnWhenSingleSelect = false
        config.canSelectAsset = nil
        config.didSelectAsset = nil
        config.didDeselectAsset = nil
    }

    private func prepareAvatarPicker(for request: ExampleChatAvatarSelectionRequest) {
        requestPhotoLibraryAccess { granted in
            guard service.pendingAvatarPicker == request else {
                return
            }
            if granted {
                activeAvatarRequest = request
                presentZLAvatarPicker(for: request)
            } else {
                activeAvatarRequest = nil
                service.completeAvatarSelection(request, result: .failure(ExampleChatNativeBoundaryError.photoPermissionDenied))
            }
        }
    }

    private func prepareTeamAvatarPicker(for request: ExampleTeamAvatarSelectionRequest) {
        requestPhotoLibraryAccess { granted in
            guard service.pendingTeamAvatarPicker == request else {
                return
            }
            if granted {
                activeTeamAvatarRequest = request
                presentZLTeamAvatarPicker(for: request)
            } else {
                activeTeamAvatarRequest = nil
                service.completeTeamAvatarSelection(request, result: .failure(ExampleChatNativeBoundaryError.photoPermissionDenied))
            }
        }
    }

    private func presentZLAvatarPicker(for request: ExampleChatAvatarSelectionRequest) {
        configureZLAvatarPhotoBrowser()
        let picker = ZLPhotoPicker()
        activeZLPhotoPicker = picker
        picker.cancelBlock = {
            Task { @MainActor in
                guard activeAvatarRequest == request else { return }
                resetZLPhotoPickerState()
                service.completeAvatarSelection(request, result: .success(nil))
            }
        }
        picker.selectImageBlock = { results, _ in
            Task { @MainActor in
                guard activeAvatarRequest == request else { return }
                isResolvingAvatarSelection = true
                let result = await ExampleChatPayloadBuilder.uploadedAvatarURL(
                    from: results.first?.image,
                    compressionQuality: ExampleChatPayloadBuilder.avatarCompressionQuality(
                        for: request.request.source
                    )
                )
                guard activeAvatarRequest == request else { return }
                resetZLPhotoPickerState()
                service.completeAvatarSelection(request, result: result)
            }
        }
        activeZLPhotoPickerPresentation = ExampleZLPhotoPickerPresentation(
            target: .chatAvatar(request),
            picker: picker
        )
    }

    private func presentZLTeamAvatarPicker(for request: ExampleTeamAvatarSelectionRequest) {
        configureZLAvatarPhotoBrowser()
        let picker = ZLPhotoPicker()
        activeZLPhotoPicker = picker
        picker.cancelBlock = {
            Task { @MainActor in
                guard activeTeamAvatarRequest == request else { return }
                resetZLPhotoPickerState()
                service.completeTeamAvatarSelection(request, result: .success(nil))
            }
        }
        picker.selectImageBlock = { results, _ in
            Task { @MainActor in
                guard activeTeamAvatarRequest == request else { return }
                guard DemoNetworkPresentation.allowsNetworkOperation else {
                    resetZLPhotoPickerState()
                    service.completeTeamAvatarSelection(
                        request,
                        result: .failure(ExampleChatNativeBoundaryError.userVisibleMessage(DemoNetworkPresentation.networkMessage()))
                    )
                    return
                }
                isResolvingTeamAvatarSelection = true
                let result = await ExampleChatPayloadBuilder.uploadedAvatarURL(
                    from: results.first?.image,
                    compressionQuality: 0.6
                )
                guard activeTeamAvatarRequest == request else { return }
                resetZLPhotoPickerState()
                service.completeTeamAvatarSelection(request, result: result)
            }
        }
        activeZLPhotoPickerPresentation = ExampleZLPhotoPickerPresentation(
            target: .teamAvatar(request),
            picker: picker
        )
    }

    private func configureZLAvatarPhotoBrowser() {
        resetZLPhotoSelectionCallbacks()
        let config = ZLPhotoConfiguration.default()
        config.allowSelectImage = true
        config.allowSelectVideo = false
        config.allowSelectLivePhoto = true
        config.allowTakePhotoInLibrary = false
        config.allowMixSelect = false
        config.allowEditImage = true
        config.editAfterSelectThumbnailImage = true
        config.maxSelectCount = 1
    }

    private func requestPhotoLibraryAccess(_ completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { granted in
            Task { @MainActor in
                if !granted {
                    Self.showSettingsPrompt(
                        title: localizable("photo_permission_title"),
                        message: NEChatUIKitSwiftUIBundle.localized("chat_photo_permission_required", value: "Please allow photo access in Settings.")
                    )
                }
                completion(granted)
            }
        }
        if #available(iOS 14, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .authorized, .limited:
                finish(true)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    finish(status == .authorized || status == .limited)
                }
            default:
                finish(false)
            }
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                finish(true)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    finish(status == .authorized)
                }
            default:
                finish(false)
            }
        }
    }

    private static func showSettingsPrompt(title: String, message: String) {
        let prompt = AppSettingsPrompt(title: title, message: message)
        NotificationCenter.default.post(name: .appSettingsPrompt, object: prompt)
    }
}

struct ExampleChatLocationPickerModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $service.pendingLocationPicker) { request in
                ExampleChatLocationPickerView(
                    onCancel: {
                        service.completeLocationPicker(request, selection: nil)
                    },
                    onSend: { selection in
                        service.completeLocationPicker(request, selection: selection)
                    }
                )
                .interactiveDismissDisabled()
            }
    }
}

private struct ExampleChatLocationPickerView: View {
    @StateObject private var model = ExampleChatLocationPickerModel()
    @FocusState private var isSearchFocused: Bool

    var onCancel: () -> Void
    var onSend: (ExampleChatLocationSelection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            searchBar
            map
            resultList
        }
        .background(Color(hex: 0xF5F6F7).ignoresSafeArea())
        .onAppear { model.start() }
        .onReceive(model.$region.dropFirst().debounce(for: .milliseconds(450), scheduler: RunLoop.main)) { region in
            model.regionDidSettle(region)
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text(NEChatUIKitSwiftUIBundle.localized("chat_more_location", value: "Location"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: 0x222222))

            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: 0x222222))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    if let selection = model.selectedLocation {
                        onSend(selection)
                    }
                } label: {
                    Text(NEChatUIKitSwiftUIBundle.localized("send", value: "Send"))
                        .font(.system(size: 16))
                        .foregroundColor(model.selectedLocation == nil ? Color(hex: 0xA6ADB4) : Color(hex: 0x337EFF))
                        .frame(minWidth: 52, minHeight: 44)
                }
                .disabled(model.selectedLocation == nil)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
        .background(Color.white)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0xA6ADB4))
            TextField(
                NEChatUIKitSwiftUIBundle.localized("search_place", value: "Search Location"),
                text: $model.query
            )
            .focused($isSearchFocused)
            .submitLabel(.search)
            .onSubmit { model.searchImmediately() }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: 0xA6ADB4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(hex: 0xF2F4F5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    private var map: some View {
        Map(
            coordinateRegion: $model.region,
            interactionModes: [.pan, .zoom],
            showsUserLocation: true,
            annotationItems: model.mapSelection
        ) { selection in
            MapMarker(coordinate: selection.coordinate, tint: .red)
        }
        .frame(height: 260)
        .overlay(alignment: .bottomTrailing) {
            Button {
                model.returnToCurrentLocation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0x337EFF))
                    .frame(width: 42, height: 42)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .overlay {
            if model.authorizationDenied {
                VStack(spacing: 12) {
                    Text(NEChatUIKitSwiftUIBundle.localized(
                        "location_not_auth",
                        value: "Location access is disabled. Enable it in Settings."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x333333))
                    .multilineTextAlignment(.center)

                    Button(localizable("setting")) {
                        model.openSettings()
                    }
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x337EFF))
                }
                .padding(20)
                .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
                .padding(24)
            }
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.isSearching {
                    ProgressView()
                        .padding(.vertical, 24)
                } else if model.visibleLocations.isEmpty {
                    Text(NEChatUIKitSwiftUIBundle.localized("search_result_empty", value: "Not Found"))
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x999999))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    ForEach(model.visibleLocations) { location in
                        Button {
                            isSearchFocused = false
                            model.select(location)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: model.isSelected(location) ? "checkmark.circle.fill" : "mappin.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(model.isSelected(location) ? Color(hex: 0x337EFF) : Color(hex: 0x777777))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.title)
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: 0x222222))
                                        .lineLimit(1)
                                    Text(location.address)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: 0x888888))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.white)
                        .overlay(alignment: .bottom) {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .background(Color.white)
    }
}

@MainActor
private final class ExampleChatLocationPickerModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @Published private(set) var selectedLocation: ExampleChatLocationSelection?
    @Published private(set) var nearbyLocations = [ExampleChatLocationSelection]()
    @Published private(set) var searchLocations = [ExampleChatLocationSelection]()
    @Published private(set) var isSearching = false
    @Published private(set) var authorizationDenied = false

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var currentCoordinate: CLLocationCoordinate2D?
    private var searchTask: Task<Void, Never>?
    private var regionTask: Task<Void, Never>?

    var visibleLocations: [ExampleChatLocationSelection] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nearbyLocations
            : searchLocations
    }

    var mapSelection: [ExampleChatLocationSelection] {
        selectedLocation.map { [$0] } ?? []
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationDenied = false
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        @unknown default:
            authorizationDenied = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        start()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentCoordinate = location.coordinate
        authorizationDenied = false
        focus(on: location.coordinate)
        resolveAndLoadNearby(location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            authorizationDenied = true
        }
    }

    func returnToCurrentLocation() {
        if let currentCoordinate {
            focus(on: currentCoordinate)
            resolveAndLoadNearby(currentCoordinate)
        } else {
            start()
        }
    }

    func regionDidSettle(_ settledRegion: MKCoordinateRegion) {
        guard !isSameCoordinate(selectedLocation?.coordinate, settledRegion.center) else { return }
        regionTask?.cancel()
        regionTask = Task { [weak self] in
            guard let self else { return }
            await self.resolveAndLoadNearby(settledRegion.center)
        }
    }

    func select(_ location: ExampleChatLocationSelection) {
        selectedLocation = location
        query = ""
        searchLocations = []
        focus(on: location.coordinate)
    }

    func isSelected(_ location: ExampleChatLocationSelection) -> Bool {
        selectedLocation?.id == location.id
    }

    func searchImmediately() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.performSearch()
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            searchLocations = []
            isSearching = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    private func performSearch() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = region
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled,
                  keyword == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchLocations = response.mapItems.map(Self.selection(from:))
        } catch {
            if !Task.isCancelled {
                searchLocations = []
            }
        }
        isSearching = false
    }

    private func resolveAndLoadNearby(_ coordinate: CLLocationCoordinate2D) {
        regionTask?.cancel()
        regionTask = Task { [weak self] in
            guard let self else { return }
            async let resolved = self.reverseGeocodedSelection(coordinate)
            async let nearby = self.nearbySelections(coordinate)
            let (resolvedSelection, nearbySelections) = await (resolved, nearby)
            guard !Task.isCancelled else { return }
            if let resolvedSelection {
                self.selectedLocation = resolvedSelection
            }
            self.nearbyLocations = [resolvedSelection].compactMap { $0 } + nearbySelections.filter {
                !self.isSameCoordinate($0.coordinate, resolvedSelection?.coordinate)
            }
        }
    }

    private func reverseGeocodedSelection(_ coordinate: CLLocationCoordinate2D) async -> ExampleChatLocationSelection? {
        do {
            let placemark = try await geocoder.reverseGeocodeLocation(CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )).first
            let title = placemark?.name ?? NEChatUIKitSwiftUIBundle.localized("current_location", value: "Current location")
            let address = [placemark?.locality, placemark?.subLocality, placemark?.thoroughfare]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return ExampleChatLocationSelection(
                coordinate: coordinate,
                title: title,
                address: address.isEmpty ? title : address
            )
        } catch {
            return ExampleChatLocationSelection(
                coordinate: coordinate,
                title: NEChatUIKitSwiftUIBundle.localized("current_location", value: "Current location"),
                address: String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
            )
        }
    }

    private func nearbySelections(_ coordinate: CLLocationCoordinate2D) async -> [ExampleChatLocationSelection] {
        let nearbyRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: nearbyRegion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(20).map(Self.selection(from:))
        } catch {
            return []
        }
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }

    private func isSameCoordinate(_ lhs: CLLocationCoordinate2D?,
                                  _ rhs: CLLocationCoordinate2D?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.latitude - rhs.latitude) < 0.000_01 &&
            abs(lhs.longitude - rhs.longitude) < 0.000_01
    }

    private static func selection(from item: MKMapItem) -> ExampleChatLocationSelection {
        let coordinate = item.placemark.coordinate
        let title = item.name ?? item.placemark.name ?? String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        let address = item.placemark.title ?? title
        return ExampleChatLocationSelection(
            coordinate: coordinate,
            title: title,
            address: address
        )
    }
}

struct ExampleChatCameraCaptureModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $service.pendingCameraCapture) { request in
                ExampleChatCameraCaptureView(request: request) { result in
                    service.completeCameraCapture(request, result: result)
                }
            }
    }
}

struct ExampleChatCameraCaptureView: View {
    var request: ExampleChatCameraCaptureRequest
    var onComplete: (Result<ChatOutgoingMessagePayload?, Error>) -> Void

    @StateObject private var camera = ExampleChatCameraCaptureController()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let pendingCapture = camera.pendingCapture {
                    capturedPreview(
                        pendingCapture,
                        videoPlaceholderImage: camera.pendingVideoPreviewImage,
                        size: geometry.size
                    )
                } else if camera.isReady || camera.isPreparingCapture {
                    ExampleChatCameraPreviewView(
                        session: camera.captureSession,
                        videoOrientation: camera.previewVideoOrientation
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text(camera.errorMessage ?? NEChatUIKitSwiftUIBundle.localized("chat_camera_starting", value: "Starting camera"))
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.86))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                cameraControlOverlay
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .zIndex(10)
            }
        }
        .onAppear {
            camera.start(mode: request.mode, completion: onComplete)
        }
        .onDisappear {
            camera.stopSession()
        }
    }

    private var cameraControlOverlay: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                Spacer(minLength: 0)

                if camera.pendingCapture != nil {
                    captureConfirmationControls
                        .padding(.horizontal, 28)
                        .padding(.bottom, 38)
                } else if camera.isPreparingCapture {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 74, height: 74)
                        .padding(.bottom, 34)
                } else {
                    if request.mode == .video, camera.isRecording {
                        Text(camera.elapsedText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, 18)
                    }

                    Button {
                        camera.performPrimaryAction()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 74, height: 74)
                            if request.mode == .video, camera.isRecording {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.red)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(request.mode == .video ? Color.red : Color.white)
                                    .frame(width: 58, height: 58)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!camera.isReady)
                    .opacity(camera.isReady ? 1 : 0.45)
                    .accessibilityLabel(request.mode == .video
                        ? NEChatUIKitSwiftUIBundle.localized("chat_camera_record_video", value: "Record video")
                        : NEChatUIKitSwiftUIBundle.localized("chat_camera_take_photo", value: "Take photo"))
                    .padding(.bottom, 34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            cameraCloseButton
                .padding(.leading, 16)
                .padding(.top, 58)
                .zIndex(2)
        }
    }

    @ViewBuilder
    private func capturedPreview(_ payload: ChatOutgoingMessagePayload,
                                 videoPlaceholderImage: UIImage?,
                                 size: CGSize) -> some View {
        switch payload {
        case let .image(path, _, _, _):
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        case let .video(filePath, _, _, _, _):
            ExampleCapturedVideoPreview(
                url: URL(fileURLWithPath: filePath),
                placeholderImage: videoPlaceholderImage
            )
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
        default:
            Color.black.ignoresSafeArea()
        }
    }

    private var captureConfirmationControls: some View {
        HStack(spacing: 20) {
            Button {
                camera.retake()
            } label: {
                Text(localizable("chat_camera_retake"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.black.opacity(0.56), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                camera.usePendingCapture()
            } label: {
                Text(request.mode == .video
                    ? localizable("chat_camera_use_video")
                    : localizable("chat_camera_use_photo"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var cameraCloseButton: some View {
        Button {
            camera.cancel()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black.opacity(0.82))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.92), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("back", value: "Back"))
    }

}

private struct ExampleCapturedVideoPreview: View {
    let url: URL
    let placeholderImage: UIImage?
    @State private var player: AVPlayer
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var isPlayerReadyForDisplay = false

    init(url: URL, placeholderImage: UIImage?) {
        self.url = url
        self.placeholderImage = placeholderImage
        _player = State(initialValue: AVPlayer(playerItem: AVPlayerItem(url: url)))
    }

    var body: some View {
        ZStack {
            Color.black

            ExampleCapturedVideoPlayerView(
                player: player,
                onReadyForDisplay: {
                    isPlayerReadyForDisplay = true
                }
            )

            if !isPlayerReadyForDisplay {
                if let placeholderImage {
                    Image(uiImage: placeholderImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func startPlayback() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        isPlayerReadyForDisplay = false
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                guard finished else { return }
                player?.playImmediately(atRate: 1)
            }
        }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else { return }
            player.playImmediately(atRate: 1)
        }
    }

    private func stopPlayback() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        player.pause()
    }
}

private struct ExampleCapturedVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: () -> Void

    func makeUIView(context _: Context) -> ExampleCapturedVideoPlayerUIView {
        let view = ExampleCapturedVideoPlayerUIView()
        view.setPlayer(player, onReadyForDisplay: onReadyForDisplay)
        return view
    }

    func updateUIView(_ uiView: ExampleCapturedVideoPlayerUIView, context _: Context) {
        uiView.setPlayer(player, onReadyForDisplay: onReadyForDisplay)
    }

    static func dismantleUIView(_ uiView: ExampleCapturedVideoPlayerUIView, coordinator _: ()) {
        uiView.resetPlayer()
    }
}

private final class ExampleCapturedVideoPlayerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var readyForDisplayObservation: NSKeyValueObservation?
    private var onReadyForDisplay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayer(_ player: AVPlayer, onReadyForDisplay: @escaping () -> Void) {
        self.onReadyForDisplay = onReadyForDisplay
        guard playerLayer.player !== player else {
            notifyIfReadyForDisplay()
            return
        }
        readyForDisplayObservation?.invalidate()
        playerLayer.player = player
        readyForDisplayObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.notifyIfReadyForDisplay()
            }
        }
    }

    func resetPlayer() {
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        onReadyForDisplay = nil
        playerLayer.player = nil
    }

    private func notifyIfReadyForDisplay() {
        guard playerLayer.isReadyForDisplay else { return }
        onReadyForDisplay?()
    }
}

struct ExampleChatVideoPreviewModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $service.pendingVideoPreview) { request in
                ExampleChatVideoPreviewView(request: request) {
                    service.completeVideoPreview(request)
                }
            }
    }
}

struct ExampleChatFilePreviewModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService

    private var previewURLBinding: Binding<URL?> {
        Binding(
            get: { service.pendingFilePreview?.url },
            set: { url in
                guard url == nil,
                      let request = service.pendingFilePreview else {
                    return
                }
                service.completeFilePreview(request)
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .quickLookPreview(previewURLBinding)
    }
}

struct ExampleChatURLActionModifier: ViewModifier {
    @ObservedObject var service: ExampleChatNativeBoundaryService
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                urlActionDialogTitle,
                isPresented: Binding(
                    get: { isEnabled && service.pendingURLAction != nil },
                    set: { presented in
                        if !presented, let action = service.pendingURLAction {
                            service.cancelURLAction(action)
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let action = service.pendingURLAction {
                    Button(action.kind == .mail
                           ? NECommonUIKitSwiftUIBundle.localized("detect_mailto_send", fallback: "Send via default email account")
                           : NECommonUIKitSwiftUIBundle.localized("detect_tel_call", fallback: "Call")) {
                        service.confirmURLAction(action)
                    }
                    Button(urlActionCopyTitle(for: action)) {
                        service.copyURLAction(action)
                    }
                    Button(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"), role: .cancel) {
                        service.cancelURLAction(action)
                    }
                }
            }
    }

    private var urlActionDialogTitle: String {
        guard let action = service.pendingURLAction else {
            return ""
        }
        switch action.kind {
        case .mail:
            let format = NECommonUIKitSwiftUIBundle.localized("detect_mailto_title", fallback: "Send message to\"%@\"")
            return String(format: format, action.address)
        case .phone:
            let format = NECommonUIKitSwiftUIBundle.localized("detect_tel_title", fallback: "\"%@\" may be a phone number, You can:")
            return String(format: format, action.address)
        default:
            return action.address
        }
    }

    private func urlActionCopyTitle(for action: ExampleURLAction) -> String {
        switch action.kind {
        case .mail:
            return NECommonUIKitSwiftUIBundle.localized("detect_mailto_copy", fallback: "Copy Email")
        case .phone:
            return NECommonUIKitSwiftUIBundle.localized("detect_tel_copy", fallback: "Copy Number")
        default:
            return NECommonUIKitSwiftUIBundle.localized("copy", fallback: "Copy")
        }
    }
}

struct ExampleChatVideoPreviewView: View {
    var request: ExampleChatVideoPreviewRequest
    var onClose: () -> Void

    @State private var player: AVPlayer?
    @State private var playerStatusTask: Task<Void, Never>?
    @State private var playerTimeControlTask: Task<Void, Never>?
    @State private var loadingFallbackTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isLoading: Bool

    init(request: ExampleChatVideoPreviewRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        _isLoading = State(initialValue: false)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if isLoading {
                ProgressView()
                    .tint(.white)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("back", value: "Back"))

                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func startPlayback() {
        guard player == nil else {
            isLoading = false
            errorMessage = nil
            player?.play()
            return
        }

        guard playableURLExists else {
            isLoading = false
            errorMessage = videoUnavailableText
            return
        }

        isLoading = false
        errorMessage = nil
        let item = AVPlayerItem(url: request.url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playerStatusTask = Task { @MainActor in
            for await status in item.publisher(for: \.status, options: [.initial, .new]).values {
                handlePlayerItemStatus(status, item: item, player: player)
            }
        }
        playerTimeControlTask = Task { @MainActor in
            for await status in player.publisher(for: \.timeControlStatus, options: [.initial, .new]).values {
                if status == .playing || isPlaybackLikelyStarted(player) {
                    isLoading = false
                    errorMessage = nil
                }
            }
        }
        loadingFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else {
                return
            }
            if isPlaybackLikelyStarted(player) {
                isLoading = false
                errorMessage = nil
                return
            }
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard !Task.isCancelled else {
                return
            }
            handlePlayerItemStatus(item.status, item: item, player: player)
            if request.url.isFileURL, item.status == .unknown, isLoading {
                isLoading = false
                errorMessage = videoUnavailableText
            }
        }
        player.play()
        if isImmediatelyPlayableLocalFile {
            isLoading = false
        }
    }

    private func handlePlayerItemStatus(_ status: AVPlayerItem.Status,
                                        item: AVPlayerItem,
                                        player: AVPlayer) {
        switch status {
        case .readyToPlay:
            isLoading = false
            errorMessage = nil
            player.play()
        case .failed:
            isLoading = false
            if let error = item.error {
                NEALog.errorLog("ExampleVideoPlayer", desc: error.localizedDescription)
            }
            errorMessage = videoUnavailableText
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func isPlaybackLikelyStarted(_ player: AVPlayer) -> Bool {
        player.timeControlStatus == .playing ||
            player.rate > 0 ||
            player.currentTime().seconds > 0
    }

    private func stopPlayback() {
        playerStatusTask?.cancel()
        playerStatusTask = nil
        playerTimeControlTask?.cancel()
        playerTimeControlTask = nil
        loadingFallbackTask?.cancel()
        loadingFallbackTask = nil
        player?.pause()
        player = nil
    }

    private var playableURLExists: Bool {
        Self.playableURLExists(request.url)
    }

    private var isImmediatelyPlayableLocalFile: Bool {
        Self.isImmediatelyPlayableLocalFile(request.url)
    }

    private static func playableURLExists(_ url: URL) -> Bool {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0
            else {
                return false
            }
        }
        return true
    }

    private static func isImmediatelyPlayableLocalFile(_ url: URL) -> Bool {
        url.isFileURL && playableURLExists(url)
    }

    private var videoUnavailableText: String {
        NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable")
    }
}

enum ExampleChatPayloadBuilder {
    static func payload(from item: PhotosPickerItem) async -> Result<ChatOutgoingMessagePayload?, Error> {
        do {
            if let video = try await item.loadTransferable(type: VideoTransfer.self) {
                return try .success(videoPayload(from: video.url))
            }
            if let movieData = try await item.loadTransferable(type: MovieDataTransfer.self) {
                let url = try writeData(movieData.data, fileName: movieData.fileName)
                return try .success(videoPayload(from: url, suggestedName: movieData.fileName))
            }
            if let data = try await item.loadTransferable(type: Data.self) {
                return try .success(imagePayload(data: data, suggestedName: item.itemIdentifier))
            }
            return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
        } catch {
            return .failure(error)
        }
    }

    static func filePayload(from item: PhotosPickerItem) async -> Result<ChatOutgoingMessagePayload?, Error> {
        do {
            if let video = try await item.loadTransferable(type: VideoTransfer.self) {
                let fileName = normalizedFileName(video.url.lastPathComponent, fallbackExtension: "mov")
                let url = try copyFileToTemporaryDirectory(video.url, fileName: fileName)
                return .success(.file(filePath: url.path, displayName: fileName))
            }
            if let movieData = try await item.loadTransferable(type: MovieDataTransfer.self) {
                let fileName = normalizedFileName(movieData.fileName, fallbackExtension: "mov")
                let url = try writeData(movieData.data, fileName: fileName)
                return .success(.file(filePath: url.path, displayName: fileName))
            }
            if let data = try await item.loadTransferable(type: Data.self) {
                let fileName = normalizedFileName(item.itemIdentifier, fallbackExtension: "jpg")
                let url = try writeData(data, fileName: fileName)
                return .success(.file(filePath: url.path, displayName: fileName))
            }
            return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
        } catch {
            return .failure(error)
        }
    }

    static func payload(from result: ZLResultModel?,
                        source: ExampleChatMediaPickerRequest.Source,
                        isOriginal: Bool = false) async -> Result<ChatOutgoingMessagePayload?, Error>
    {
        do {
            guard let result else {
                return .success(nil)
            }
            switch source {
            case .photoLibrary:
                switch result.asset.mediaType {
                case .image:
                    if isOriginal, !result.isEdited {
                        let url = try await originalImageURL(from: result.asset)
                        return try .success(imagePayload(
                            fileURL: url,
                            asset: result.asset,
                            suggestedName: mediaFileName(for: result.asset, fallback: url.lastPathComponent)
                        ))
                    }
                    return try .success(imagePayload(from: result))
                case .video:
                    let url = try await videoURL(from: result.asset)
                    return try .success(videoPayload(from: url, suggestedName: mediaFileName(for: result.asset, fallback: "video.mov")))
                default:
                    return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
                }
            case .fileAlbum:
                let url = try await fileURL(from: result)
                let fileName = mediaFileName(for: result.asset, fallback: url.lastPathComponent.isEmpty ? "media" : url.lastPathComponent)
                let copiedURL = try copyFileToTemporaryDirectory(url, fileName: fileName)
                return .success(.file(filePath: copiedURL.path, displayName: fileName))
            }
        } catch {
            return .failure(error)
        }
    }

    static func payloads(from results: [ZLResultModel],
                         source: ExampleChatMediaPickerRequest.Source,
                         isOriginal: Bool = false) async -> Result<[ChatOutgoingMessagePayload], Error>
    {
        guard !results.isEmpty else {
            return .success([])
        }
        if source == .photoLibrary {
            let imageCount = results.filter { $0.asset.mediaType == .image }.count
            let videoCount = results.filter { $0.asset.mediaType == .video }.count
            if imageCount > chatImageCountLimit {
                return .failure(ExampleChatNativeBoundaryError.userVisibleMessage(String(
                    format: NECommonUIKitSwiftUIBundle.localized("image_count_over_limit", fallback: "image more than %d limit"),
                    chatImageCountLimit
                )))
            }
            if videoCount > chatVideoCountLimit {
                return .failure(ExampleChatNativeBoundaryError.userVisibleMessage(String(
                    format: NECommonUIKitSwiftUIBundle.localized("video_count_over_limit", fallback: "video more than %d limit"),
                    chatVideoCountLimit
                )))
            }
        }

        var payloads = [ChatOutgoingMessagePayload]()
        for result in results {
            switch await payload(from: result, source: source, isOriginal: isOriginal) {
            case let .success(payload):
                if let payload {
                    payloads.append(payload)
                }
            case let .failure(error):
                return .failure(error)
            }
        }
        return .success(payloads)
    }

    static func imagePayload(data: Data,
                             suggestedName: String? = nil) throws -> ChatOutgoingMessagePayload
    {
        guard let size = ExampleChatImageMetadata.size(from: data) else {
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
        let fileName = normalizedFileName(suggestedName, fallbackExtension: "jpg")
        let url = try writeData(data, fileName: fileName)
        return .image(
            path: url.path,
            name: fileName,
            width: Int32(max(0, size.width)),
            height: Int32(max(0, size.height))
        )
    }

    static func normalizedCameraImageData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
        guard image.imageOrientation != .up else {
            return data
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalizedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let normalizedData = normalizedImage.pngData() else {
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
        return normalizedData
    }

    static func imagePayload(from result: ZLResultModel) throws -> ChatOutgoingMessagePayload {
        let encoded = processedImageData(from: result.image)
        guard let data = encoded.data else {
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
        let displayName = mediaFileName(for: result.asset, fallback: "image")
        let temporaryName = "\(URL(fileURLWithPath: displayName).deletingPathExtension().lastPathComponent).\(encoded.fileExtension)"
        let url = try writeData(data, fileName: temporaryName)
        return .image(
            path: url.path,
            name: displayName,
            width: Int32(max(0, result.image.size.width)),
            height: Int32(max(0, result.image.size.height))
        )
    }

    private static func processedImageData(from image: UIImage) -> (data: Data?, fileExtension: String) {
        if imageHasAlpha(image) {
            return (image.pngData(), "png")
        }
        return (image.jpegData(compressionQuality: 0.82), "jpg")
    }

    private static func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else {
            return true
        }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    static func imagePayload(fileURL: URL,
                             asset: PHAsset,
                             suggestedName: String) throws -> ChatOutgoingMessagePayload
    {
        let fileName = normalizedFileName(suggestedName, fallbackExtension: "jpg")
        let url = try copyFileToTemporaryDirectory(fileURL, fileName: fileName)
        return .image(
            path: url.path,
            name: fileName,
            width: Int32(max(0, asset.pixelWidth)),
            height: Int32(max(0, asset.pixelHeight))
        )
    }

    static func videoPayload(from sourceURL: URL,
                             suggestedName: String? = nil) throws -> ChatOutgoingMessagePayload
    {
        let fileName = normalizedFileName(suggestedName ?? sourceURL.lastPathComponent, fallbackExtension: "mov")
        let url = try copyFileToTemporaryDirectory(sourceURL, fileName: fileName)
        let asset = AVURLAsset(url: url)
        let size = videoSize(from: asset)
        let duration = asset.duration.seconds.isFinite ? Int32(max(0, asset.duration.seconds * 1000)) : 0
        return .video(
            filePath: url.path,
            name: fileName,
            width: Int32(max(0, size.width)),
            height: Int32(max(0, size.height)),
            duration: duration
        )
    }

    static func filePayload(from result: Result<[URL], Error>) async -> Result<ChatOutgoingMessagePayload?, Error> {
        do {
            guard let sourceURL = try result.get().first else {
                return .success(nil)
            }
            let fileName = displayName(for: sourceURL, fallbackName: "file")
            let url = try copyFileToTemporaryDirectory(sourceURL, fileName: fileName)
            return .success(.file(filePath: url.path, displayName: fileName))
        } catch {
            return .failure(error)
        }
    }

    static func avatarURL(from item: PhotosPickerItem) async -> Result<URL?, Error> {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  ExampleChatImageMetadata.size(from: data) != nil
            else {
                return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
            }
            let fileName = normalizedFileName(item.itemIdentifier, fallbackExtension: "jpg")
            return try .success(writeData(data, fileName: fileName))
        } catch {
            return .failure(error)
        }
    }

    static func uploadedAvatarURL(from item: PhotosPickerItem,
                                  compressionQuality: CGFloat) async -> Result<String?, Error> {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressedData = image.jpegData(compressionQuality: compressionQuality)
            else {
                return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
            }
            let fileName = normalizedFileName(item.itemIdentifier, fallbackExtension: "jpg")
            let fileURL = try writeData(compressedData, fileName: fileName)
            return try await uploadFile(fileURL)
        } catch {
            return .failure(error)
        }
    }

    static func uploadedAvatarURL(from image: UIImage?,
                                  compressionQuality: CGFloat) async -> Result<String?, Error> {
        do {
            guard let image,
                  let compressedData = image.jpegData(compressionQuality: compressionQuality)
            else {
                return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
            }
            let fileURL = try writeData(compressedData, fileName: "avatar.jpg")
            return try await uploadFile(fileURL)
        } catch {
            return .failure(error)
        }
    }

    static func uploadedAvatarURL(from fileURL: URL,
                                  compressionQuality: CGFloat) async throws -> Result<String?, Error> {
        let data = try Data(contentsOf: fileURL)
        guard let image = UIImage(data: data),
              let compressedData = image.jpegData(compressionQuality: compressionQuality)
        else {
            return .failure(ExampleChatNativeBoundaryError.unsupportedMedia)
        }
        let compressedURL = try writeData(compressedData, fileName: "avatar.jpg")
        return try await uploadFile(compressedURL)
    }

    static func avatarCompressionQuality(for source: ChatAvatarSelectionSource) -> CGFloat {
        source == .profileEdit ? 0.6 : 0.8
    }

    private static func writeData(_ data: Data, fileName: String) throws -> URL {
        let destinationURL = temporaryDirectory().appendingPathComponent(uniqueFileName(fileName))
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private static func copyFileToTemporaryDirectory(_ sourceURL: URL,
                                                     fileName: String) throws -> URL
    {
        let destinationURL = temporaryDirectory().appendingPathComponent(uniqueFileName(fileName))
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }
        if let copyError {
            throw copyError
        }
        if let coordinatorError {
            throw coordinatorError
        }
        return destinationURL
    }

    static func uploadFile(_ fileURL: URL) async throws -> Result<String?, Error> {
        let task = ResourceRepo.shared.createUploadFileTask(fileURL.path, V2NIMStorageSceneConfig.default_IM().sceneName)
        return try await withCheckedThrowingContinuation { continuation in
            ResourceRepo.shared.uploadFile(task, nil) { urlString, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(urlString))
                }
            }
        }
    }

    private static func temporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("IMUIKitSwiftUIExampleChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func uniqueFileName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let normalizedBase = baseName.isEmpty ? "media" : baseName
        if ext.isEmpty {
            return "\(UUID().uuidString)-\(normalizedBase)"
        }
        return "\(UUID().uuidString)-\(normalizedBase).\(ext)"
    }

    private static func displayName(for fileURL: URL, fallbackName: String) -> String {
        let localizedName = FileManager.default.displayName(atPath: fileURL.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !localizedName.isEmpty, localizedName != "/" {
            return localizedName
        }
        let lastPathComponent = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? fallbackName : lastPathComponent
    }

    private static func normalizedFileName(_ fileName: String?, fallbackExtension: String) -> String {
        guard let fileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "media.\(fallbackExtension)"
        }
        let url = URL(fileURLWithPath: fileName)
        guard url.pathExtension.isEmpty else {
            return url.lastPathComponent
        }
        return "\(url.lastPathComponent).\(fallbackExtension)"
    }

    private static func fileURL(from result: ZLResultModel) async throws -> URL {
        switch result.asset.mediaType {
        case .image:
            guard let data = result.image.pngData() else {
                throw ExampleChatNativeBoundaryError.unsupportedMedia
            }
            return try writeData(data, fileName: mediaFileName(for: result.asset, fallback: "image.png"))
        case .video:
            return try await videoURL(from: result.asset)
        default:
            throw ExampleChatNativeBoundaryError.unsupportedMedia
        }
    }

    private static func videoURL(from asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avURLAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: ExampleChatNativeBoundaryError.unsupportedMedia)
                    return
                }
                continuation.resume(returning: avURLAsset.url)
            }
        }
    }

    private static func originalImageURL(from asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            options.canHandleAdjustmentData = { _ in true }
            asset.requestContentEditingInput(with: options) { input, _ in
                guard let url = input?.fullSizeImageURL else {
                    continuation.resume(throwing: ExampleChatNativeBoundaryError.unsupportedMedia)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private static func mediaFileName(for asset: PHAsset, fallback: String) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename ?? fallback
    }

    private static func videoSize(from asset: AVURLAsset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else {
            return .zero
        }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }
}

private enum ExampleChatImageMetadata {
    static func size(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        let needsSwap = orientation.map { [5, 6, 7, 8].contains($0) } ?? false
        if needsSwap {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }
}

private struct VideoTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copiedURL = try ExampleChatPayloadBuilder.copyTransferredVideo(received.file)
            return VideoTransfer(url: copiedURL)
        }
    }
}

private struct MovieDataTransfer: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .movie) { movie in
            movie.data
        } importing: { received in
            MovieDataTransfer(data: received, fileName: "video.mov")
        }
    }
}

private struct ExampleChatCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation

    func makeUIView(context _: Context) -> ExampleChatCameraPreviewUIView {
        ExampleChatCameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: ExampleChatCameraPreviewUIView, context _: Context) {
        uiView.updateVideoOrientation(videoOrientation)
    }
}

private final class ExampleChatCameraPreviewUIView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    func updateVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported,
              connection.videoOrientation != orientation else {
            return
        }
        connection.videoOrientation = orientation
    }
}

private final class ExampleChatCameraCaptureController: NSObject, ObservableObject {
    @Published private(set) var pendingCapture: ChatOutgoingMessagePayload?
    @Published private(set) var pendingVideoPreviewImage: UIImage?
    @Published var isReady = false
    @Published var isRecording = false
    @Published private(set) var isPreparingCapture = false
    @Published var errorMessage: String?
    @Published var elapsedText = "0:00"
    @Published private(set) var previewVideoOrientation: AVCaptureVideoOrientation = .portrait

    fileprivate let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.netease.imuikit.swiftui.example.camera")
    private let mediaPreparationQueue = DispatchQueue(label: "com.netease.imuikit.swiftui.example.camera.media")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let motionManager = CMMotionManager()
    private var mode: ExampleChatCameraCaptureMode = .photo
    private var completion: ((Result<ChatOutgoingMessagePayload?, Error>) -> Void)?
    private var recordingStartDate: Date?
    private var elapsedTimer: Timer?
    private var didComplete = false
    private var activeVideoDevice: AVCaptureDevice?
    private var deviceOrientationObserver: NSObjectProtocol?
    private var lastValidDeviceOrientation: UIDeviceOrientation?

    func start(mode: ExampleChatCameraCaptureMode,
               completion: @escaping (Result<ChatOutgoingMessagePayload?, Error>) -> Void)
    {
        self.mode = mode
        self.completion = completion
        didComplete = false
        pendingCapture = nil
        pendingVideoPreviewImage = nil
        errorMessage = nil
        isReady = false
        isPreparingCapture = false
        startDeviceOrientationUpdates()
        requestPermissionsAndConfigure()
    }

    func performPrimaryAction() {
        switch mode {
        case .photo:
            capturePhoto()
        case .video:
            isRecording ? stopRecording() : startRecording()
        }
    }

    func cancel() {
        discardPendingCapture()
        complete(.success(nil))
    }

    func retake() {
        guard pendingCapture != nil, !didComplete else {
            return
        }
        discardPendingCapture()
        errorMessage = nil
        elapsedText = "0:00"
        isPreparingCapture = false
        isReady = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            guard !self.didComplete else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                guard self.pendingCapture == nil, !self.didComplete else {
                    return
                }
                self.isReady = true
            }
        }
    }

    func usePendingCapture() {
        guard let pendingCapture else {
            return
        }
        complete(.success(pendingCapture))
    }

    func stopSession() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        stopDeviceOrientationUpdates()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.activeVideoDevice = nil
        }
    }

    private func requestPermissionsAndConfigure() {
        Task {
            let cameraGranted = await Self.requestAccess(for: .video)
            guard cameraGranted else {
                await MainActor.run {
                    let error = ExampleChatNativeBoundaryError.cameraPermissionDenied
                    self.errorMessage = error.userVisibleMessage
                    Self.showSettingsPrompt(
                        title: localizable("camera_permission_title"),
                        message: error.userVisibleMessage
                    )
                    self.complete(.failure(error))
                }
                return
            }

            let audioGranted = mode == .video ? await Self.requestAccess(for: .audio) : true
            guard audioGranted else {
                await MainActor.run {
                    let error = ExampleChatNativeBoundaryError.cameraAndMicrophonePermissionDenied
                    self.errorMessage = error.userVisibleMessage
                    Self.showSettingsPrompt(
                        title: localizable("camera_permission_title"),
                        message: error.userVisibleMessage
                    )
                    self.complete(.failure(error))
                }
                return
            }
            sessionQueue.async { [weak self] in
                self?.configureSession()
            }
        }
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private static func showSettingsPrompt(title: String, message: String) {
        let prompt = AppSettingsPrompt(title: title, message: message)
        NotificationCenter.default.post(name: .appSettingsPrompt, object: prompt)
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = mode == .video ? .high : .photo
        removeExistingInputsAndOutputs()

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(videoInput)
        else {
            finishConfigureWithError(ExampleChatNativeBoundaryError.cameraUnavailable)
            return
        }
        captureSession.addInput(videoInput)
        activeVideoDevice = camera
        resetVideoZoom()

        if mode == .video,
           let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           captureSession.canAddInput(audioInput)
        {
            captureSession.addInput(audioInput)
        }

        switch mode {
        case .photo:
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.connection(with: .video)?.videoOrientation = .portrait
            }
        case .video:
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
                let connection = movieOutput.connection(with: .video)
                connection?.videoOrientation = .portrait
                connection?.preferredVideoStabilizationMode = .off
            }
        }

        applyPhotoVideoOrientation(.portrait)
        applyMovieVideoOrientation(.portrait)
        captureSession.commitConfiguration()
        captureSession.startRunning()
        DispatchQueue.main.async {
            self.isReady = true
        }
    }

    private func removeExistingInputsAndOutputs() {
        activeVideoDevice = nil
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
    }

    private func finishConfigureWithError(_ error: Error) {
        captureSession.commitConfiguration()
        DispatchQueue.main.async {
            self.errorMessage = DemoNetworkPresentation.chatMessage(
                for: error,
                fallbackKey: "chat_camera_unavailable",
                fallbackValue: "Camera is unavailable"
            )
            self.complete(.failure(error))
        }
    }

    private func capturePhoto() {
        guard isReady else {
            return
        }
        let photoOrientation = captureVideoOrientationForCurrentDevice()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyPhotoVideoOrientation(photoOrientation)
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func startRecording() {
        guard isReady else {
            return
        }
        let recordingOrientation = captureVideoOrientationForCurrentDevice()
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else {
                return
            }
            self.resetVideoZoom()
            self.applyMovieVideoOrientation(recordingOrientation)
            let connection = self.movieOutput.connection(with: .video)
            connection?.preferredVideoStabilizationMode = .off
            if let connection, connection.videoMaxScaleAndCropFactor >= 1 {
                connection.videoScaleAndCropFactor = 1
            }
            NEChatSwiftUILogger.log(
                "camera recording start physicalOrientation=\(self.lastValidDeviceOrientation?.rawValue.description ?? "unknown") movieOrientation=\(recordingOrientation.rawValue) previewOrientation=\(self.previewVideoOrientation.rawValue) zoom=\(self.activeVideoDevice?.videoZoomFactor.description ?? "nil") queue=session"
            )
            let url = ExampleChatPayloadBuilder.cameraTemporaryURL(fileExtension: "mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async {
                self.recordingStartDate = Date()
                self.isRecording = true
                self.startElapsedTimer()
            }
        }
    }

    private func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else {
                return
            }
            self.movieOutput.stopRecording()
        }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateElapsedText()
        }
    }

    private func updateElapsedText() {
        let elapsed = Int(Date().timeIntervalSince(recordingStartDate ?? Date()))
        elapsedText = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    private func applyPhotoVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoOrientationSupported else {
            return
        }
        connection.videoOrientation = orientation
    }

    private func applyMovieVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoOrientationSupported else {
            return
        }
        connection.videoOrientation = orientation
    }

    private func startDeviceOrientationUpdates() {
        guard deviceOrientationObserver == nil else {
            return
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateLastValidDeviceOrientation(UIDevice.current.orientation)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let gravity = motion?.gravity else {
                    return
                }
                self?.updateLastValidDeviceOrientation(from: gravity)
            }
        }
        deviceOrientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLastValidDeviceOrientation(UIDevice.current.orientation)
        }
    }

    private func stopDeviceOrientationUpdates() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopDeviceOrientationUpdates()
            }
            return
        }
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        if let deviceOrientationObserver {
            NotificationCenter.default.removeObserver(deviceOrientationObserver)
            self.deviceOrientationObserver = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private func updateLastValidDeviceOrientation(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            lastValidDeviceOrientation = orientation
        default:
            break
        }
    }

    private func updateLastValidDeviceOrientation(from gravity: CMAcceleration) {
        let horizontalMagnitude = abs(gravity.x)
        let verticalMagnitude = abs(gravity.y)
        guard max(horizontalMagnitude, verticalMagnitude) >= 0.5 else {
            return
        }
        if lastValidDeviceOrientation != nil,
           abs(horizontalMagnitude - verticalMagnitude) < 0.15 {
            return
        }
        if horizontalMagnitude > verticalMagnitude {
            lastValidDeviceOrientation = gravity.x >= 0 ? .landscapeRight : .landscapeLeft
        } else {
            lastValidDeviceOrientation = gravity.y >= 0 ? .portraitUpsideDown : .portrait
        }
    }

    private func captureVideoOrientationForCurrentDevice() -> AVCaptureVideoOrientation {
        updateLastValidDeviceOrientation(UIDevice.current.orientation)
        if let gravity = motionManager.deviceMotion?.gravity {
            updateLastValidDeviceOrientation(from: gravity)
        }
        switch lastValidDeviceOrientation ?? .portrait {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    private func resetVideoZoom() {
        guard let device = activeVideoDevice else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1
            device.unlockForConfiguration()
        } catch {
            NEChatSwiftUILogger.log("camera reset zoom failed error=\(error.localizedDescription)")
        }
    }

    private func complete(_ result: Result<ChatOutgoingMessagePayload?, Error>) {
        guard !didComplete else {
            return
        }
        didComplete = true
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        let completion = completion
        self.completion = nil
        stopSession()
        DispatchQueue.main.async {
            completion?(result)
        }
    }

    private func prepareCapturedVideoPayload(_ payload: ChatOutgoingMessagePayload,
                                             url: URL) {
        DispatchQueue.main.async {
            guard !self.didComplete else {
                Self.removeCapturedPayloadFile(payload)
                return
            }
            self.isReady = false
            self.isPreparingCapture = true
        }
        mediaPreparationQueue.async { [weak self] in
            let image = Self.videoPreviewImage(at: url)
            self?.presentCapturedPayload(payload, videoPreviewImage: image)
        }
    }

    private static func videoPreviewImage(at url: URL) -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        for time in [CMTime(value: 1, timescale: 30), .zero] {
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                return UIImage(cgImage: image)
            }
        }
        return nil
    }

    private func presentCapturedPayload(_ payload: ChatOutgoingMessagePayload,
                                        videoPreviewImage: UIImage? = nil) {
        DispatchQueue.main.async {
            guard !self.didComplete else {
                Self.removeCapturedPayloadFile(payload)
                return
            }
            self.pendingVideoPreviewImage = videoPreviewImage
            self.pendingCapture = payload
            self.isRecording = false
            self.isReady = false
            self.isPreparingCapture = false
            self.elapsedTimer?.invalidate()
            self.elapsedTimer = nil
            self.sessionQueue.async { [weak self] in
                guard let self, self.captureSession.isRunning else {
                    return
                }
                self.captureSession.stopRunning()
            }
        }
    }

    private func discardPendingCapture() {
        let discardedCapture = pendingCapture
        self.pendingCapture = nil
        pendingVideoPreviewImage = nil
        if let discardedCapture {
            mediaPreparationQueue.async {
                Self.removeCapturedPayloadFile(discardedCapture)
            }
        }
    }

    private static func removeCapturedPayloadFile(_ payload: ChatOutgoingMessagePayload) {
        let path: String?
        switch payload {
        case let .image(filePath, _, _, _):
            path = filePath
        case let .video(filePath, _, _, _, _):
            path = filePath
        default:
            path = nil
        }
        guard let path, !path.isEmpty else {
            return
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension ExampleChatCameraCaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?)
    {
        if let error {
            complete(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            complete(.failure(ExampleChatNativeBoundaryError.unsupportedMedia))
            return
        }
        do {
            let normalizedData = try ExampleChatPayloadBuilder.normalizedCameraImageData(data)
            let payload = try ExampleChatPayloadBuilder.imagePayload(
                data: normalizedData,
                suggestedName: "camera-photo.png"
            )
            presentCapturedPayload(payload)
        } catch {
            complete(.failure(error))
        }
    }
}

extension ExampleChatCameraCaptureController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from _: [AVCaptureConnection],
                    error: Error?)
    {
        DispatchQueue.main.async {
            self.isRecording = false
        }
        if let error {
            try? FileManager.default.removeItem(at: outputFileURL)
            complete(.failure(error))
            return
        }
        do {
            let payload = try ExampleChatPayloadBuilder.videoPayload(
                from: outputFileURL,
                suggestedName: "camera-video.mov"
            )
            try? FileManager.default.removeItem(at: outputFileURL)
            guard case let .video(filePath, _, _, _, _) = payload else {
                presentCapturedPayload(payload)
                return
            }
            prepareCapturedVideoPayload(
                payload,
                url: URL(fileURLWithPath: filePath)
            )
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            complete(.failure(error))
        }
    }
}

private extension ExampleChatPayloadBuilder {
    static func copyTransferredVideo(_ sourceURL: URL) throws -> URL {
        try copyFileToTemporaryDirectory(sourceURL, fileName: sourceURL.lastPathComponent.isEmpty ? "video.mov" : sourceURL.lastPathComponent)
    }

    static func cameraTemporaryURL(fileExtension: String) -> URL {
        temporaryDirectory().appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
    }
}

private final class ExampleChatAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var progress: ((ChatVoiceRecordingProgressState) -> Void)?
    private var recordingURL: URL?
    private var wasInterruptedByAnotherAudioSession = false
    // Match IMUIKitExample: leave headroom for recorder timing drift so the
    // SDK voice-to-text request remains within its 60-second limit.
    private let maxDuration: TimeInterval = 59.6

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCallKitPresentation),
            name: Notification.Name("kCallKitShowNoti"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func beginRecording(_: ChatAudioRecordRequest,
                        progress: @escaping (ChatVoiceRecordingProgressState) -> Void,
                        completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.progress = progress
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted else {
                    self?.resetRecorderState(removeFile: true)
                    completion(.failure(ExampleChatNativeBoundaryError.audioPermissionDenied))
                    return
                }
                self?.startRecorder(completion: completion)
            }
        }
    }

    func finishRecording(_: ChatAudioRecordRequest,
                         completion: @escaping (Result<ChatAudioRecordResult, Error>) -> Void)
    {
        guard let recorder,
              let recordingURL
        else {
            resetRecorderState(removeFile: false)
            completion(.failure(ExampleChatNativeBoundaryError.recorderUnavailable))
            return
        }
        let duration = recorder.currentTime
        resetRecorderState(removeFile: false)
        guard duration > 1 else {
            try? FileManager.default.removeItem(at: recordingURL)
            completion(.success(ChatAudioRecordResult(toast: ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("record_too_short", value: "Message too short"),
                style: .warning
            ))))
            return
        }
        completion(.success(ChatAudioRecordResult(payload: .audio(
            filePath: recordingURL.path,
            name: recordingURL.lastPathComponent,
            duration: Int32(duration * 1000)
        ))))
    }

    func cancelRecording(_: ChatAudioRecordRequest,
                         completion: @escaping (Result<Void, Error>) -> Void)
    {
        resetRecorderState(
            removeFile: true,
            deactivateAudioSession: !wasInterruptedByAnotherAudioSession
        )
        wasInterruptedByAnotherAudioSession = false
        completion(.success(()))
    }

    private func startRecorder(completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            wasInterruptedByAnotherAudioSession = false
            resetRecorderState(removeFile: true)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("IMUIKitSwiftUIExampleChat-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: maxDuration) else {
                throw ExampleChatNativeBoundaryError.recorderUnavailable
            }
            self.recorder = recorder
            recordingURL = url
            startTimer()
            completion(.success(()))
        } catch {
            resetRecorderState(removeFile: true)
            completion(.failure(error))
        }
    }

    private func resetRecorderState(removeFile: Bool,
                                    deactivateAudioSession: Bool = true) {
        let url = recordingURL
        stopTimer()
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        if removeFile, let url {
            try? FileManager.default.removeItem(at: url)
        }
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emitProgress()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func emitProgress() {
        guard let recorder else {
            return
        }
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let level = pow(10, averagePower / 40)
        let duration = recorder.currentTime
        let didReachMaximumDuration = duration >= maxDuration - 0.15
        progress?(ChatVoiceRecordingProgressState(
            duration: duration,
            level: Double(max(0, min(1, level))),
            remainingTime: didReachMaximumDuration ? 0 : max(0, maxDuration - duration)
        ))
        if didReachMaximumDuration {
            stopTimer()
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard recorder != nil,
              let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
            return
        }
        // CallKit owns the audio session after the interruption begins. Stop and
        // discard only this recorder; deactivating the shared session here would
        // silence the incoming-call ringtone.
        wasInterruptedByAnotherAudioSession = true
        resetRecorderState(removeFile: true, deactivateAudioSession: false)
        NotificationCenter.default.post(name: .neChatMediaPlaybackShouldStop, object: nil)
    }

    @objc private func handleCallKitPresentation() {
        guard recorder != nil else {
            return
        }
        // The chat view handles this same notification asynchronously. Mark the
        // recorder first so that cancellation cannot deactivate CallKit's audio
        // session when this notification precedes the AVAudioSession interrupt.
        wasInterruptedByAnotherAudioSession = true
        resetRecorderState(removeFile: true, deactivateAudioSession: false)
    }
}

private final class ExampleChatAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: ((Result<ChatAudioPlaybackResult, Error>) -> Void)?
    private var usesSpeaker = SettingRepo.shared.getHandsetMode()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopProximityMonitoring()
    }

    func playAudio(_ request: ChatAudioPlaybackRequest,
                   completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void)
    {
        do {
            try stopCurrentPlayer()
            guard let url = request.audio.displayURL else {
                completion(.failure(ExampleChatNativeBoundaryError.playerUnavailable))
                return
            }
            usesSpeaker = SettingRepo.shared.getHandsetMode()
            try applyAudioRoute()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            self.completion = completion
            completion(.success(.playing))
        } catch {
            completion(.failure(error))
        }
    }

    func stopAudio(_: ChatAudioPlaybackRequest,
                   completion: @escaping (Result<ChatAudioPlaybackResult, Error>) -> Void)
    {
        do {
            try stopCurrentPlayer()
            completion(.success(.stopped))
        } catch {
            completion(.failure(error))
        }
    }

    func setAudioRoute(useSpeaker: Bool) {
        usesSpeaker = useSpeaker
        guard player?.isPlaying == true else {
            return
        }
        do {
            try applyAudioRoute()
        } catch {
            debugPrint("[ExampleChatAudioPlayer] route switch failed: \(error)")
        }
    }

    private func stopCurrentPlayer() throws {
        player?.stop()
        player = nil
        completion = nil
        stopProximityMonitoring()
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func applyAudioRoute() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        try session.setActive(true)
        try session.overrideOutputAudioPort(.none)
        let shouldUseSpeaker = usesSpeaker &&
            !UIDevice.current.proximityState &&
            !hasExternalAudioOutput(in: session)
        try session.overrideOutputAudioPort(shouldUseSpeaker ? .speaker : .none)
        try session.setPreferredOutputNumberOfChannels(1)
        usesSpeaker ? startProximityMonitoring() : stopProximityMonitoring()
    }

    private func hasExternalAudioOutput(in session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .builtInReceiver, .builtInSpeaker:
                return false
            default:
                return true
            }
        }
    }

    private func startProximityMonitoring() {
        guard !UIDevice.current.isProximityMonitoringEnabled else {
            return
        }
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProximityChange),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }

    private func stopProximityMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
        if UIDevice.current.isProximityMonitoringEnabled {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }

    @objc private func handleProximityChange() {
        guard usesSpeaker, player?.isPlaying == true else {
            return
        }
        do {
            try applyAudioRoute()
        } catch {
            debugPrint("[ExampleChatAudioPlayer] proximity route switch failed: \(error)")
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard player?.isPlaying == true,
              let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
              reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player?.isPlaying == true else {
                return
            }
            do {
                // Removing an external route leaves playAndRecord on the receiver.
                // Reapply the saved UIKit handset mode immediately instead of
                // waiting for the next proximity event to repair the route.
                try self.applyAudioRoute()
            } catch {
                debugPrint("[ExampleChatAudioPlayer] route change failed: \(error)")
            }
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began,
              player != nil else {
            return
        }
        let playbackCompletion = completion
        do {
            try stopCurrentPlayer()
            playbackCompletion?(.success(.stopped))
        } catch {
            playbackCompletion?(.failure(error))
        }
    }

    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        player = nil
        stopProximityMonitoring()
        completion?(.success(.stopped))
        completion = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        player = nil
        stopProximityMonitoring()
        completion?(.failure(error ?? ExampleChatNativeBoundaryError.playerUnavailable))
        completion = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private extension MessageAudioState {
    var displayURL: URL? {
        if let existing = existingLocalPath {
            return URL(fileURLWithPath: existing)
        }
        return url
    }
}

private extension MessageMediaState {
    var videoURL: URL? {
        if let existingLocalPath {
            return URL(fileURLWithPath: existingLocalPath)
        }
        return url
    }
}
