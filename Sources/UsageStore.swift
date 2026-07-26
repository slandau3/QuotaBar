import Foundation
import SwiftUI

@MainActor
@Observable
final class UsageStore {
    var services: [ServiceUsage] = []
    var lastUpdated: Date?
    var isRefreshing = false
    private var cooldownUntil: [Service: Date] = [:]
    private var lastFetchAt: [Service: Date] = [:]

    private func minInterval(for service: Service) -> TimeInterval {
        switch service {
        case .claude: return 600
        case .chatgpt, .kimi: return 300
        }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let claude = fetchIfNeeded(.claude, force: force)
        async let chatgpt = fetchIfNeeded(.chatgpt, force: force)
        async let kimi = fetchIfNeeded(.kimi, force: force)
        let results = await [claude, chatgpt, kimi].compactMap { $0 }

        services = Service.allCases.map { service in
            if let fresh = results.first(where: { $0.service == service }) {
                return fresh
            }
            return services.first(where: { $0.service == service })
                ?? ServiceUsage(service: service, error: "Rate limited — retrying soon")
        }
        lastUpdated = Date()
    }

    private func fetchIfNeeded(_ service: Service, force: Bool) async -> ServiceUsage? {
        let now = Date()
        if !force {
            if let last = lastFetchAt[service], now.timeIntervalSince(last) < minInterval(for: service) { return nil }
            if let until = cooldownUntil[service], until > now { return nil }
        }
        lastFetchAt[service] = now

        let usage: ServiceUsage
        switch service {
        case .claude: usage = await fetchClaude()
        case .chatgpt: usage = await fetchChatGPT()
        case .kimi: usage = await fetchKimi()
        }

        if usage.rateLimited {
            cooldownUntil[service] = Date().addingTimeInterval(15 * 60)
            if let previous = services.first(where: { $0.service == service }), !previous.windows.isEmpty {
                return previous
            }
        } else {
            cooldownUntil[service] = nil
        }
        return usage
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
