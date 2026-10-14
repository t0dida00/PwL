import SwiftUI
import UIKit

/// Round avatar: the user's photo, or their initial on a gradient.
struct AvatarView: View {
    let data: Data?
    let name: String
    var size: CGFloat = 56
    var color: Color = Theme.rose

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: size > 60 ? 4 : 2))
        .shadow(color: Theme.plum.opacity(0.18), radius: 6, y: 3)
        .accessibilityLabel("\(name)'s avatar")
    }
}

enum AvatarImage {
    /// Square-crops and shrinks a picked photo to a small JPEG suitable for storing inline.
    static func prepare(_ data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return square.jpegData(compressionQuality: 0.75)
    }
}

/// "Online now", "5 min ago", "Yesterday"…
enum LastSeenFormat {
    /// Facebook-style presence: "Online now" or "Active 5m ago".
    static func presence(_ user: UserAccount?, now: Date = .now) -> String {
        guard let user else { return "–" }
        if user.isOnline(at: now) { return "Online now" }
        guard let last = user.lastOnline else { return "Offline" }
        return "Active \(compactAgo(last, now: now))"
    }

    /// "just now", "5m ago", "3h ago", "2d ago", "4w ago".
    static func compactAgo(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes)m ago"
        case ..<(60 * 24): return "\(minutes / 60)h ago"
        case ..<(60 * 24 * 7): return "\(minutes / (60 * 24))d ago"
        default: return "\(minutes / (60 * 24 * 7))w ago"
        }
    }

    static func text(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "–" }
        if now.timeIntervalSince(date) < 5 * 60 { return "Online now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
