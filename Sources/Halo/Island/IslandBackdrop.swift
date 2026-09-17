import AppKit
import QuartzCore
import SwiftUI

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The island's body, drawn and animated with Core Animation.
///
/// SwiftUI animations are stepped on the app's main thread, so anything else the
/// app does mid-animation shows up as a stutter. Here the outline is a mask path
/// animated with `CASpringAnimation`, which the window server runs by itself at the
/// display's full frame rate — the same way iPhone's island moves. The SwiftUI
/// content, Liquid Glass and black fill all sit at their final size underneath and
/// are simply revealed by the moving outline.
@MainActor
final class IslandBackdrop {
    struct State: Equatable {
        /// The island, in the window's top-left coordinates.
        var rect: CGRect
        var topRadius: CGFloat
        var bottomRadius: CGFloat
        /// The split-off circle; nil when there is none.
        var bubble: CGRect?
        var isCard: Bool
        var usesGlass: Bool
        var isVisible: Bool
        var notchHeight: CGFloat
    }

    let root = FlippedView()
    private let clip = FlippedView()
    private let solidHost = FlippedView()
    private let solid = CALayer()
    private let gradientHost = FlippedView()
    private let gradient = CAGradientLayer()
    private var glass: NSView?
    private let outline = CAShapeLayer()
    private let shadow = CALayer()
    private var current: State?

    init(content: NSView) {
        for view in [root, clip, solidHost, gradientHost] {
            view.wantsLayer = true
            view.autoresizingMask = [.width, .height]
        }
        root.layer?.masksToBounds = false

        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0
        shadow.shadowRadius = 16
        shadow.shadowOffset = CGSize(width: 0, height: 8)
        root.layer?.addSublayer(shadow)

        root.addSubview(clip)

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.tintColor = NSColor.black.withAlphaComponent(0.34)
            glassView.alphaValue = 0
            clip.addSubview(glassView)
            glass = glassView
        }

        solid.backgroundColor = NSColor.black.cgColor
        solidHost.layer?.addSublayer(solid)
        clip.addSubview(solidHost)

        gradient.opacity = 0
        gradientHost.layer?.addSublayer(gradient)
        clip.addSubview(gradientHost)

        content.autoresizingMask = [.width, .height]
        clip.addSubview(content)

        outline.fillColor = NSColor.black.cgColor
        clip.layer?.mask = outline
    }

    // MARK: Updates

    func apply(_ state: State) {
        let bounds = root.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.frame = bounds
        shadow.frame = bounds
        gradientHost.frame = bounds
        solid.frame = bounds
        CATransaction.commit()

        guard let previous = current else {
            current = state
            set(state, animated: false, from: nil)
            return
        }
        guard previous != state else { return }
        current = state
        set(state, animated: true, from: previous)
    }

    private func set(_ state: State, animated: Bool, from previous: State?) {
        let islandPath = Self.path(rect: state.rect, top: state.topRadius, bottom: state.bottomRadius)
        let fullPath = CGMutablePath()
        fullPath.addPath(islandPath)
        // A split-off circle, or a speck hidden inside the island, so every path has the
        // same shape of elements and Core Animation can morph between any two.
        let bubble = state.bubble ?? CGRect(x: state.rect.midX - 0.5, y: state.rect.minY + 1, width: 1, height: 1)
        fullPath.addEllipse(in: bubble)

        let showsCard = state.isCard && state.usesGlass && glass != nil
        let opening = previous.map { state.rect.height > $0.rect.height + 0.5 || state.rect.width > $0.rect.width + 0.5 } ?? true
        let resizesOnly = previous.map { $0.isCard == state.isCard && abs($0.rect.height - state.rect.height) < 12 } ?? false

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if animated {
            // iPhone's island: a lively spring opening, a calm one closing, and a quick
            // tight one for small changes like the press squeeze.
            // Card to card (moving between pages) reshapes calmly, without a bounce.
            let betweenCards = previous?.isCard == true && state.isCard
            let spring: (duration: Double, bounce: Double) =
                betweenCards ? (0.36, 0.04) : (resizesOnly ? (0.32, 0.14) : (opening ? (0.5, 0.2) : (0.4, 0.06)))
            animate(outline, "path", to: fullPath, spring: spring)
            animate(shadow, "shadowPath", to: islandPath, spring: spring)
        }
        outline.path = fullPath
        shadow.shadowPath = islandPath

        // The looks that don't move with the outline sit at the card's final frame and fade.
        if showsCard {
            glass?.frame = state.rect
            gradientHost.frame = root.bounds
            gradient.frame = state.rect
            // Solid black only where the island meets the notch, then clear glass.
            gradient.colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                               NSColor.black.withAlphaComponent(0.12).cgColor,
                               NSColor.black.withAlphaComponent(0.12).cgColor]
            let height = max(state.rect.height, 1)
            gradient.locations = [0, NSNumber(value: min(0.4, state.notchHeight / height)),
                                  NSNumber(value: min(0.6, (state.notchHeight + 26) / height)), 1]
        }
        let fade = animated ? (opening ? 0.16 : 0.22) : 0
        fadeLayer(solid, to: showsCard ? 0 : 1, duration: fade)
        fadeLayer(gradient, to: showsCard ? 1 : 0, duration: fade)
        fadeLayer(shadow, to: state.isCard ? 0.45 : 0, duration: fade, keyPath: "shadowOpacity")
        if let glass { fadeView(glass, to: showsCard ? 1 : 0, duration: fade) }
        fadeView(clip, to: state.isVisible ? 1 : 0, duration: animated ? 0.2 : 0)

        CATransaction.commit()
    }

    private func animate(_ layer: CALayer, _ keyPath: String, to value: CGPath, spring: (duration: Double, bounce: Double)) {
        // Start from what is on screen right now, so a change mid-animation carries on smoothly.
        let from: Any? = keyPath == "path"
            ? (layer.presentation() as? CAShapeLayer)?.path ?? (layer as? CAShapeLayer)?.path
            : layer.presentation()?.shadowPath ?? layer.shadowPath
        let animation = CASpringAnimation(perceptualDuration: spring.duration, bounce: spring.bounce)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = value
        animation.duration = animation.settlingDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: keyPath)
    }

    private func fadeLayer(_ layer: CALayer?, to value: Float, duration: Double, keyPath: String = "opacity") {
        guard let layer else { return }
        let currentValue = (layer.presentation()?.value(forKeyPath: keyPath) as? Float)
            ?? (layer.value(forKeyPath: keyPath) as? Float) ?? value
        if keyPath == "opacity" { layer.opacity = value } else { layer.shadowOpacity = value }
        guard duration > 0, abs(currentValue - value) > 0.001 else {
            layer.removeAnimation(forKey: keyPath)
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = currentValue
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: keyPath)
    }

    /// Views own their layer's opacity, so fade through alphaValue and animate the layer to match.
    private func fadeView(_ view: NSView, to value: CGFloat, duration: Double) {
        let from = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
        view.alphaValue = value
        guard duration > 0, abs(CGFloat(from) - value) > 0.001, let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = Float(value)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "fade")
    }

    /// The island outline in top-left coordinates, from the same shape SwiftUI uses.
    private static func path(rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let size = CGSize(width: max(rect.width, 2), height: max(rect.height, 2))
        let shape = IslandShape(neckWidth: size.width, topRadius: top, bottomRadius: bottom)
        let local = shape.path(in: CGRect(origin: .zero, size: size)).cgPath
        let path = CGMutablePath()
        path.addPath(local, transform: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path
    }
}
