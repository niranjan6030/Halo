import SwiftUI

/// Halo Intelligence's card: the Siri-style orb while it's thinking, then the
/// on-device answer, with a small confirmation chip when it also did something.
struct HaloIntelligenceView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var intelligence: HaloIntelligenceController

    init(model: IslandModel) {
        self.model = model
        self.intelligence = model.intelligence
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notchSize.height - 2)

            HStack(alignment: .top, spacing: 14) {
                SiriOrb(size: 40, listening: intelligence.phase == .thinking)
                    .opacity(intelligence.phase == .failed ? 0.35 : 1)
                    .appearing()

                VStack(alignment: .leading, spacing: 6) {
                    if !intelligence.question.isEmpty {
                        Text(intelligence.question)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Group {
                        switch intelligence.phase {
                        case .idle:
                            Text("Ask me anything — it stays on this Mac.")
                                .foregroundStyle(.white.opacity(0.55))
                        case .thinking:
                            Text(intelligence.answerText.isEmpty ? "Thinking…" : intelligence.answerText)
                                .foregroundStyle(.white.opacity(0.85))
                        case .answered:
                            Text(intelligence.answerText)
                                .foregroundStyle(.white.opacity(0.95))
                        case .failed:
                            Text(intelligence.answerText)
                                .foregroundStyle(Color.orange.opacity(0.9))
                        }
                    }
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.smooth(duration: 0.25), value: intelligence.answerText)

                    if let label = intelligence.actionLabel, let symbol = intelligence.actionSymbol {
                        Label(label, systemImage: symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .popIn()
                    }
                }
                .appearing(delay: 0.05)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)

            Spacer(minLength: 0)

            HStack {
                Text("Ask Halo again  ⌥Space")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
                if intelligence.phase == .thinking {
                    ProgressView().controlSize(.mini).tint(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }
}
