import AppKit
import CoreImage
import UniformTypeIdentifiers
import Vision

/// On-device image tools behind Smart Drop, all from Apple's Vision framework:
/// nothing is uploaded anywhere.
enum ImageTools {
    /// Where made images are saved, so they can be dragged and pasted as files.
    static var outputFolder: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Halo/Made", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Lifts the subjects (people, pets, objects) out of the photo onto a transparent background.
    static func removeBackground(from image: NSImage) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                            croppedToInstancesExtent: true)
                let ciImage = CIImage(cvPixelBuffer: buffer)
                let context = CIContext()
                guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
                return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
            } catch {
                return nil
            }
        }.value
    }

    /// All the text in the image, line by line, in reading order.
    static func recognizeText(in image: NSImage) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }.value
    }

    /// The text or link in a QR code (or a barcode), read on-device with Vision.
    static func readQRCode(in image: NSImage) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let request = VNDetectBarcodesRequest()
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                return request.results?.first?.payloadStringValue
            } catch {
                return nil
            }
        }.value
    }

    enum Format {
        case png, jpeg

        var type: NSBitmapImageRep.FileType { self == .png ? .png : .jpeg }
        var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    /// Writes the image in a format and returns the file.
    static func save(_ image: NSImage, as format: Format, named name: String) -> URL? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.9] : [:]
        guard let data = bitmap.representation(using: format.type, properties: properties) else { return nil }
        let base = (name as NSString).deletingPathExtension
        var url = outputFolder.appendingPathComponent("\(base).\(format.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = outputFolder.appendingPathComponent("\(base) \(counter).\(format.fileExtension)")
            counter += 1
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// Puts an image on the pasteboard as the picture and as its file, ready for ⌘V.
    static func copy(image: NSImage, file: URL?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            if let png = bitmap.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
            item.setData(tiff, forType: .tiff)
        }
        if let file { item.setString(file.absoluteString, forType: .fileURL) }
        pasteboard.writeObjects([item])
    }

    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        service.perform(withItems: urls)
    }
}
