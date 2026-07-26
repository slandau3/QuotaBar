import Foundation

func parseISO8601(_ string: String?) -> Date? {
    guard let string else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    return URLSession(configuration: config)
}

// MARK: - Claude

private struct ClaudeUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let usedPercent: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case usedPercent = "used_percent"
            case resetsAt = "resets_at"
        }

        var percent: Double? {
            if let u = utilization { return u <= 1.0 ? u * 100 : u }
            return usedPercent
        }
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

private struct ClaudeRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

func fetchClaude() async -> ServiceUsage {
    var usage = ServiceUsage(service: .claude)
    do {
        var creds = try ClaudeKeychain.read()
        usage.planLabel = creds.claudeAiOauth.subscriptionType?.capitalized

        let nowMs = Date().timeIntervalSince1970 * 1000
        if let expiresAt = creds.claudeAiOauth.expiresAt, expiresAt < nowMs + 60_000 {
            creds = try await refreshClaudeToken(creds)
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(creds.claudeAiOauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await makeSession().data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 || status == 403 {
                usage.error = "Re-auth needed — run `claude` once"
            } else {
                usage.error = "HTTP \(status)"
            }
            return usage
        }

        let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        var windows: [UsageWindow] = []
        if let w = decoded.fiveHour, let pct = w.percent {
            windows.append(UsageWindow(name: "5-hour", usedPercent: pct, resetsAt: parseISO8601(w.resetsAt), detail: nil))
        }
        if let w = decoded.sevenDay, let pct = w.percent {
            windows.append(UsageWindow(name: "Weekly", usedPercent: pct, resetsAt: parseISO8601(w.resetsAt), detail: nil))
        }
        if let w = decoded.sevenDaySonnet, let pct = w.percent {
            windows.append(UsageWindow(name: "Sonnet 7d", usedPercent: pct, resetsAt: parseISO8601(w.resetsAt), detail: nil))
        }
        if let w = decoded.sevenDayOpus, let pct = w.percent {
            windows.append(UsageWindow(name: "Opus 7d", usedPercent: pct, resetsAt: parseISO8601(w.resetsAt), detail: nil))
        }
        if windows.isEmpty {
            usage.error = "No usage windows in response"
        } else {
            usage.windows = windows
        }
    } catch let error as ProviderError {
        usage.error = error.errorDescription
    } catch is DecodingError {
        usage.error = "Re-auth needed — run `claude` once"
    } catch {
        usage.error = error.localizedDescription
    }
    return usage
}

private func refreshClaudeToken(_ creds: ClaudeCredentials) async throws -> ClaudeCredentials {
    guard let refreshToken = creds.claudeAiOauth.refreshToken else {
        throw ProviderError.missingCredentials("Re-auth needed — run `claude` once")
    }
    var refreshed = creds
    var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    ])

    let (data, response) = try await makeSession().data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        throw ProviderError.httpError(status, "Re-auth needed — run `claude` once")
    }

    let decoded = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: data)
    refreshed.claudeAiOauth.accessToken = decoded.accessToken
    if let newRefresh = decoded.refreshToken {
        refreshed.claudeAiOauth.refreshToken = newRefresh
    }
    if let expiresIn = decoded.expiresIn {
        refreshed.claudeAiOauth.expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
    }
    try? ClaudeKeychain.write(refreshed)
    return refreshed
}

// MARK: - ChatGPT (Codex CLI auth)

private struct CodexAuth: Decodable {
    struct Tokens: Decodable {
        let accessToken: String
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }
    let tokens: Tokens
}

private struct CodexUsageResponse: Decodable {
    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: TimeInterval?
    }
    struct RateLimit: Decodable {
        let limitReached: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }
    let planType: String?
    let rateLimit: RateLimit?
}

func fetchChatGPT() async -> ServiceUsage {
    var usage = ServiceUsage(service: .chatgpt)
    do {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        let auth = try JSONDecoder().decode(CodexAuth.self, from: Data(contentsOf: authURL))

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(auth.tokens.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = auth.tokens.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await makeSession().data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            usage.error = (status == 401 || status == 403)
                ? "Re-auth needed — run `codex` once"
                : "HTTP \(status)"
            return usage
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(CodexUsageResponse.self, from: data)
        usage.planLabel = decoded.planType?.capitalized

        var windows: [UsageWindow] = []
        for window in [decoded.rateLimit?.primaryWindow, decoded.rateLimit?.secondaryWindow] {
            guard let window else { continue }
            let seconds = window.limitWindowSeconds ?? 18_000
            let resetDate: Date? = window.resetAt.map { Date(timeIntervalSince1970: $0) }
                ?? window.resetAfterSeconds.map { Date().addingTimeInterval(TimeInterval($0)) }
            windows.append(UsageWindow(
                name: windowLabel(forSeconds: seconds),
                usedPercent: window.usedPercent,
                resetsAt: resetDate,
                detail: nil
            ))
        }
        if windows.isEmpty {
            usage.error = "No active usage windows"
        } else {
            usage.windows = windows
        }
    } catch let error as ProviderError {
        usage.error = error.errorDescription
    } catch {
        usage.error = error.localizedDescription
    }
    return usage
}

// MARK: - Kimi K3 (opencode auth)

private struct KimiUsageResponse: Decodable {
    struct Detail: Decodable {
        let limit: String
        let used: String
        let remaining: String?
        let resetTime: String?
    }
    struct LimitEntry: Decodable {
        struct Window: Decodable {
            let duration: Int
            let timeUnit: String
        }
        let window: Window
        let detail: Detail
    }
    let usage: Detail
    let limits: [LimitEntry]?
}

func fetchKimi() async -> ServiceUsage {
    var usage = ServiceUsage(service: .kimi)
    do {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
        let authJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: authURL)) as? [String: Any]
        guard let entry = authJSON?["kimi-for-coding"] as? [String: Any],
              let key = entry["key"] as? String else {
            usage.error = "Kimi key not found — run `opencode auth login`"
            return usage
        }

        var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await makeSession().data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            usage.error = (status == 401 || status == 403)
                ? "Key rejected — run `opencode auth login`"
                : "HTTP \(status)"
            return usage
        }

        let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: data)

        var windows: [UsageWindow] = []
        for entry in decoded.limits ?? [] {
            let seconds = entry.window.timeUnit == "TIME_UNIT_MINUTE"
                ? entry.window.duration * 60
                : entry.window.duration
            guard let limit = Double(entry.detail.limit), let used = Double(entry.detail.used), limit > 0 else { continue }
            windows.append(UsageWindow(
                name: windowLabel(forSeconds: seconds),
                usedPercent: used / limit * 100,
                resetsAt: parseISO8601(entry.detail.resetTime),
                detail: "\(entry.detail.used)/\(entry.detail.limit)"
            ))
        }
        if let limit = Double(decoded.usage.limit), let used = Double(decoded.usage.used), limit > 0 {
            windows.append(UsageWindow(
                name: "Weekly",
                usedPercent: used / limit * 100,
                resetsAt: parseISO8601(decoded.usage.resetTime),
                detail: "\(decoded.usage.used)/\(decoded.usage.limit)"
            ))
        }
        if windows.isEmpty {
            usage.error = "No usage windows in response"
        } else {
            usage.windows = windows
        }
    } catch let error as ProviderError {
        usage.error = error.errorDescription
    } catch {
        usage.error = error.localizedDescription
    }
    return usage
}
