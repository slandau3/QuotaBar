import Foundation
import SwiftUI

enum Service: String, Sendable, CaseIterable {
    case claude = "Claude"
    case chatgpt = "ChatGPT"
    case kimi = "Kimi K3"

    var color: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        switch self {
        case .claude: return NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .chatgpt: return NSColor(red: 0.06, green: 0.64, blue: 0.49, alpha: 1)
        case .kimi: return NSColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1)
        }
    }
}

struct UsageWindow: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
    let detail: String?
}

struct ServiceUsage: Sendable, Identifiable {
    var id: Service { service }
    let service: Service
    var planLabel: String?
    var windows: [UsageWindow] = []
    var error: String?
    var rateLimited = false
}

enum ProviderError: Error, LocalizedError {
    case missingCredentials(String)
    case httpError(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let msg): return msg
        case .httpError(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : msg
        case .decodingFailed(let msg): return msg
        }
    }
}

func windowLabel(forSeconds seconds: Int) -> String {
    if seconds <= 6 * 3600 { return "5-hour" }
    if seconds >= 7 * 86_400 { return "Weekly" }
    if seconds >= 86_400 { return "\(seconds / 86_400)-day" }
    return "\(seconds / 3600)h"
}

func resetText(for date: Date?, now: Date = Date()) -> String {
    guard let date else { return "" }
    let interval = date.timeIntervalSince(now)
    if interval <= 0 { return "resetting now" }
    let minutes = Int(interval / 60)
    if minutes < 60 { return "resets in \(minutes)m" }
    let hours = minutes / 60
    if hours < 48 { return "resets in \(hours)h \(minutes % 60)m" }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE h:mm a"
    return "resets \(formatter.string(from: date))"
}

func severityColorName(for percent: Double) -> String {
    if percent >= 80 { return "red" }
    if percent >= 50 { return "orange" }
    return "green"
}
