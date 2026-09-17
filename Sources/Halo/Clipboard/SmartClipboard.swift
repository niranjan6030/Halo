import AppKit
import Foundation
import SwiftUI

/// One useful thing to do with a piece of copied text, worked out the same way Mail
/// and Notes underline a phone number or a date — Apple's own data detectors, entirely
/// on this Mac. Only the single best match is offered; one clear button beats a wall
/// of them.
enum SmartClipboardAction: Equatable {
    case call(String)
    case email(String)
    case map(String)
    case openLink(URL)

    var title: String {
        switch self {
        case let .call(number): return "Call \(number)"
        case let .email(address): return "Email \(address)"
        case .map: return "Open in Maps"
        case .openLink: return "Open Link"
        }
    }

    var symbol: String {
        switch self {
        case .call: return "phone.fill"
        case .email: return "envelope.fill"
        case .map: return "map.fill"
        case .openLink: return "safari.fill"
        }
    }

    func perform() {
        switch self {
        case let .call(number):
            let digits = number.filter { $0.isNumber || $0 == "+" }
            openURL("tel:\(digits)")
        case let .email(address):
            openURL("mailto:\(address)")
        case let .map(address):
            guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            openURL("maps://?address=\(encoded)")
        case let .openLink(url):
            NSWorkspace.shared.open(url)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let detector = try? NSDataDetector(
        types: [NSTextCheckingResult.CheckingType.link, .phoneNumber, .address].reduce(0) { $0 | $1.rawValue }
    )

    /// The clipboard already keeps private, password-manager-marked copies out of its
    /// history, so anything reaching this has already been treated as shareable.
    static func detect(in text: String) -> SmartClipboardAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A short line, not a whole paragraph that happens to mention a number.
        guard !trimmed.isEmpty, trimmed.count < 200, let detector else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range) else { return nil }

        switch match.resultType {
        case .phoneNumber:
            guard let number = match.phoneNumber else { return nil }
            return .call(number)
        case .link:
            guard let url = match.url else { return nil }
            if url.scheme == "mailto" {
                return .email(String(url.absoluteString.dropFirst("mailto:".count)))
            }
            guard url.scheme == "http" || url.scheme == "https" else { return nil }
            return .openLink(url)
        case .address:
            return .map((trimmed as NSString).substring(with: match.range))
        default:
            return nil
        }
    }
}

/// The button shown for it — plain, like Paste and Copy right below it, since a
/// prominent style barely shows up against this window's dark glass background.
struct SmartClipboardButton: View {
    let action: SmartClipboardAction

    var body: some View {
        Button {
            action.perform()
        } label: {
            Label(action.title, systemImage: action.symbol)
                .lineLimit(1)
        }
        .controlSize(.regular)
    }
}
