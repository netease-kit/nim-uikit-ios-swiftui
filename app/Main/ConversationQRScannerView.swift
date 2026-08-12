// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVFoundation
import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NEConversationUIKitSwiftUI
import SwiftUI
import UIKit

struct ConversationQRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = ConversationQRScannerController()
    @State private var toast: ConversationQRScannerToast?
    @State private var didHandleResult = false

    var token: ConversationThemeToken

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ConversationQRCameraPreview(session: scanner.session)
                .ignoresSafeArea()

            if let message = scanner.statusMessage {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            ConversationQRScanBeam(color: beamColor, glowColor: beamGlowColor)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .demoHidesTabBar()
        .neCommonTransientOverlay(
            toast,
            placement: .top,
            topPadding: 52,
            onDismiss: { value in
                if toast?.id == value.id {
                    toast = nil
                }
            }
        ) { toast in
            Text(toast.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .onAppear {
            scanner.onScan = handleScanResult
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text(NEConversationUIKitSwiftUIBundle.localized("scan_qr", value: "Scan QR"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(NEConversationUIKitSwiftUIBundle.localized("cancel", value: "Cancel"))

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .background(Color.clear)
    }

    private var beamColor: Color {
        token.styleMode == .fun ? Color(hex: 0x22D39B) : Color(hex: 0x4686FF)
    }

    private var beamGlowColor: Color {
        token.styleMode == .fun ? Color(hex: 0x5DE9A6) : Color(hex: 0x56A8FF)
    }

    private func handleScanResult(_ result: String) {
        guard !didHandleResult else {
            return
        }
        didHandleResult = true

        let parsed = ConversationQRCodeParser.parse(result)
        if let message = parsed.errorMessage {
            showToastThenDismiss(message)
            return
        }

        guard parsed.qrCode != nil else {
            showToastThenDismiss(NEConversationUIKitSwiftUIBundle.localized("scan_qr_fail", value: "Scan failed, please try again"))
            return
        }

        dismiss()
        NEChatUIKitSwiftUIClient.shared.router.enqueue(
            .aiRobot(.init(kind: .bind, autoBindQrCode: result, sourceURL: ContactAIRobotBindRouter)),
            sourceURL: ContactAIRobotBindRouter
        )
    }

    private func showToastThenDismiss(_ message: String) {
        toast = ConversationQRScannerToast(message: message)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        }
    }
}

private final class ConversationQRScannerController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    var onScan: ((String) -> Void)?

    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.netease.imuikit.swiftui.example.qrscanner")
    private var didEmitResult = false
    private var isConfigured = false

    func start() {
        didEmitResult = false
        requestPermissionAndConfigure()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    private func requestPermissionAndConfigure() {
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureIfNeeded()
            case .notDetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        continuation.resume(returning: granted)
                    }
                }
                granted ? configureIfNeeded() : showNoPermission()
            default:
                showNoPermission()
            }
        }
    }

    private func showNoPermission() {
        Task { @MainActor in
            statusMessage = NEConversationUIKitSwiftUIBundle.localized("scan_qr_no_camera_permission", value: "Please enable camera permission in Settings")
        }
    }

    private func configureIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            if self.isConfigured {
                self.startRunning()
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                self.showFailure()
                return
            }
            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                self.showFailure()
                return
            }
            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            let supportedTypes: [AVMetadataObject.ObjectType] = [
                .qr, .ean13, .ean8, .code128, .code39, .code93, .aztec, .pdf417, .dataMatrix,
            ]
            output.metadataObjectTypes = supportedTypes.filter {
                output.availableMetadataObjectTypes.contains($0)
            }
            output.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)

            self.session.commitConfiguration()
            self.isConfigured = true
            self.startRunning()
        }
    }

    private func startRunning() {
        Task { @MainActor in
            statusMessage = nil
        }
        guard !session.isRunning else {
            return
        }
        session.startRunning()
    }

    private func showFailure() {
        Task { @MainActor in
            statusMessage = NEConversationUIKitSwiftUIBundle.localized("scan_qr_fail", value: "Scan failed, please try again")
        }
    }
}

extension ConversationQRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from _: AVCaptureConnection)
    {
        guard !didEmitResult,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty
        else {
            return
        }
        didEmitResult = true
        stop()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan?(value)
    }
}

private struct ConversationQRCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context _: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

private struct ConversationQRScanBeam: View {
    var color: Color
    var glowColor: Color
    @State private var offset: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            glowColor.opacity(0),
                            glowColor.opacity(0.34),
                            color.opacity(0.88),
                            glowColor.opacity(0.34),
                            glowColor.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 64)
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                        .shadow(color: glowColor.opacity(0.8), radius: 12, y: 0)
                }
                .offset(y: offset)
                .onAppear {
                    offset = proxy.safeAreaInsets.top + 44
                    withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        offset = UIScreen.main.bounds.height
                    }
                }
        }
        .clipped()
    }
}

private enum ConversationQRCodeParser {
    static func parse(_ rawValue: String) -> (qrCode: String?, errorMessage: String?) {
        guard let data = rawValue.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let qrCode = dict["qrCode"] as? String,
              !qrCode.isEmpty
        else {
            return (nil, nil)
        }

        if let expireAt = dict["expireAt"] as? TimeInterval,
           Date(timeIntervalSince1970: expireAt / 1000) < Date()
        {
            return (
                nil,
                NEConversationUIKitSwiftUIBundle.localized("qr_code_expired", value: "QR code has expired")
            )
        }

        return (qrCode, nil)
    }
}

private struct ConversationQRScannerToast: Identifiable, Equatable {
    var id = UUID().uuidString
    var message: String
}
