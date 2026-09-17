import AppKit
import SwiftUI

/// What the island offers after an image is dropped on it: remove the background, copy
/// the text in it, read a QR code, convert it, or AirDrop it. Everything it makes goes
/// into the clipboard and onto the pasteboard, ready for ⌘V.
struct SmartDropView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 2)
            if let item = model.dropItem, case let .image(image, file) = item.content {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Checkerboard()
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                            .id(file)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    .frame(width: 98, height: 98)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if model.dropBusy {
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.45))
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .onDrag {
                        model.isDraggingOut = true
                        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
                    }
                    .help("Drag into any app")
                    .appearing(delay: 0.02)

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(model.dropStatus ?? "\(Int(image.size.width)) × \(Int(image.size.height)) · in your clipboard")
                                .font(.system(size: 11.5))
                                .foregroundStyle(model.dropStatus == nil ? .white.opacity(0.55) : .green)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                        HStack(spacing: 6) {
                            action("Remove Background", "wand.and.stars") { model.removeDroppedBackground() }
                            action("Copy Text", "text.viewfinder") { model.copyDroppedText() }
                        }
                        HStack(spacing: 6) {
                            action("Read QR Code", "qrcode.viewfinder") { model.readDroppedQRCode() }
                            action("PNG", "photo") { model.convertDropped(to: .png) }
                        }
                        HStack(spacing: 6) {
                            action("JPEG", "photo.fill") { model.convertDropped(to: .jpeg) }
                            action("AirDrop", "dot.radiowaves.up.forward") { ImageTools.airDrop([file]) }
                        }
                    }
                    .appearing(delay: 0.08)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .animation(.smooth(duration: 0.3), value: model.dropStatus)
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        IslandPill(title: title, systemImage: symbol, height: 30, expand: true, action: perform)
            .disabled(model.dropBusy)
    }
}

/// The grey-and-white squares that show where an image is transparent.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.32)))
            for row in 0..<Int(size.height / square) + 1 {
                for column in 0..<Int(size.width / square) + 1 where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)),
                                 with: .color(Color(white: 0.24)))
                }
            }
        }
    }
}
