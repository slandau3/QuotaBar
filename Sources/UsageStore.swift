import Foundation
import SwiftUI

@MainActor
@Observable
final class UsageStore {
    var services: [ServiceUsage] = []
    var lastUpdated: Date?
    var isRefreshing = false

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let claude = fetchClaude()
        async let chatgpt = fetchChatGPT()
        async let kimi = fetchKimi()

        services = await [claude, chatgpt, kimi]
        lastUpdated = Date()
    }

    func startAutoRefresh() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { break }
            await refresh()
        }
    }

    func ringPercent(for service: Service) -> Double? {
        guard let usage = services.first(where: { $0.service == service }) else { return nil }
        return usage.windows.first(where: { $0.name == "5-hour" })?.usedPercent
            ?? usage.windows.first?.usedPercent
    }
}
