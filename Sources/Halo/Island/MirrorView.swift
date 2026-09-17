import AVFoundation
import SwiftUI

/// A live, mirrored view from the FaceTime camera — a quick look before a call.
/// The camera runs only while this page is on screen.
struct MirrorView: NSViewRepresentable {
    func makeNSView(context: Context) -> MirrorPreview {
        MirrorPreview()
    }

    func updateNSView(_ nsView: MirrorPreview, context: Context) {}

    static func dismantleNSView(_ nsView: MirrorPreview, coordinator: ()) {
        nsView.stop()
    }
}

final class MirrorPreview: NSView {
    private let session = AVCaptureSession()
    private let preview: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "com.niranjan.Halo.mirror")

    override init(frame: CGRect) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        start()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configure() }
            }
        default:
            break
        }
    }

    private func configure() {
        let session = self.session
        let preview = self.preview
        queue.async {
            guard session.inputs.isEmpty,
                  let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            session.commitConfiguration()
            DispatchQueue.main.async {
                if let connection = preview.connection, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            session.startRunning()
        }
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }
}
