import Foundation
import Security

struct ClaudeCredentials: Codable {
    struct OAuth: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Double?
        var subscriptionType: String?
        var rateLimitTier: String?
        var scopes: [String]?
    }
    var claudeAiOauth: OAuth
}

enum ClaudeKeychain {
    private static let service = "Claude Code-credentials"

    static func read() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return try JSONDecoder().decode(ClaudeCredentials.self, from: data)
        }
        return try readViaCLI()
    }

    static func write(_ credentials: ClaudeCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            try writeViaCLI(data)
        }
    }

    private static func readViaCLI() throws -> ClaudeCredentials {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProviderError.missingCredentials("Claude credentials not found in Keychain")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let trimmed = data.drop(while: { $0 == 0x0A || $0 == 0x20 })
        return try JSONDecoder().decode(ClaudeCredentials.self, from: Data(trimmed))
    }

    private static func writeViaCLI(_ data: Data) throws {
        guard let json = String(data: data, encoding: .utf8) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password", "-U",
            "-a", NSUserName(),
            "-s", service,
            "-w", json,
        ]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
