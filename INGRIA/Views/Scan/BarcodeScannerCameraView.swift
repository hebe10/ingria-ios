import SwiftUI
@preconcurrency import AVFoundation

struct BarcodeScannerCameraView: UIViewRepresentable {
    @Binding var torchOn: Bool
    let onCodeScanned: (String) -> Void
    let onStateChange: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.configure(preview: view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.setTorch(enabled: torchOn)
    }

    func makeCoordinator() -> BarcodeScannerCoordinator {
        BarcodeScannerCoordinator(onCodeScanned: onCodeScanned, onStateChange: onStateChange)
    }
}

final class BarcodeScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ingria.barcode.scanner", qos: .userInitiated)
    private let onCodeScanned: (String) -> Void
    private let onStateChange: (String) -> Void
    private var lastCode: String?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var camera: AVCaptureDevice?

    init(onCodeScanned: @escaping (String) -> Void, onStateChange: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onStateChange = onStateChange
        super.init()
    }

    func configure(preview: CameraPreviewView) {
        preview.videoPreviewLayer.session = session
        preview.videoPreviewLayer.videoGravity = .resizeAspectFill

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.start()
                    } else {
                        self.onStateChange("Camera permission was denied. Enter the barcode manually.")
                    }
                }
            }
        case .denied, .restricted:
            onStateChange("Camera permission is off. Enable camera access or enter barcode manually.")
        @unknown default:
            onStateChange("Camera is unavailable. Enter barcode manually.")
        }
    }

    private func start() {
        guard let camera = Self.bestBarcodeCamera() else {
            onStateChange("No camera found. Enter barcode manually.")
            return
        }

        do {
            try configureCamera(camera)
            self.camera = camera
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureMetadataOutput()

            guard session.canAddInput(input), session.canAddOutput(output) else {
                onStateChange("Scanner could not start. Enter barcode manually.")
                return
            }

            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: queue)
            output.metadataObjectTypes = Self.supportedBarcodeTypes(from: output)
            // Keep scanning wide for real shopping use: barcodes are often off-center,
            // tilted, or partly outside the visual frame. Hardware metadata scanning is
            // much cheaper than running Vision on every camera frame.
            output.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            metadataOutput = output
            session.commitConfiguration()

            let session = session
            queue.async {
                session.startRunning()
            }

            onStateChange("Align barcode inside the frame.")
        } catch {
            onStateChange("Camera could not start. Enter barcode manually.")
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              emit(code) else { return }
    }

    @discardableResult
    private func emit(_ rawCode: String) -> Bool {
        let code = BarcodeValueNormalizer.normalize(rawCode)
        guard code.count >= 8, code != lastCode else { return false }
        lastCode = code
        DispatchQueue.main.async {
            self.onStateChange("Barcode found. Fetching ingredients...")
            self.onCodeScanned(code)
        }
        return true
    }

    private static func supportedBarcodeTypes(from output: AVCaptureMetadataOutput) -> [AVMetadataObject.ObjectType] {
        let preferred: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .code93, .qr]
        return preferred.filter { output.availableMetadataObjectTypes.contains($0) }
    }

    private static func bestBarcodeCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configureCamera(_ camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isFocusPointOfInterestSupported {
            camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera.isExposurePointOfInterestSupported {
            camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            camera.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if camera.isSmoothAutoFocusSupported {
            camera.isSmoothAutoFocusEnabled = false
        }
        if camera.isLowLightBoostSupported {
            camera.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        if camera.isSubjectAreaChangeMonitoringEnabled == false {
            camera.isSubjectAreaChangeMonitoringEnabled = true
        }
        let zoom = min(max(camera.minAvailableVideoZoomFactor, 1.12), camera.maxAvailableVideoZoomFactor)
        camera.videoZoomFactor = zoom
        camera.unlockForConfiguration()
    }

    func setTorch(enabled: Bool) {
        guard let camera, camera.hasTorch, camera.isTorchModeSupported(enabled ? .on : .off) else { return }
        do {
            try camera.lockForConfiguration()
            if enabled {
                try camera.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, 0.45))
            } else {
                camera.torchMode = .off
            }
            camera.unlockForConfiguration()
        } catch {
            onStateChange("Torch is unavailable. Continue scanning or enter barcode manually.")
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
