import Foundation
import Security

struct KeyboardAuthSession {
    let accessToken: String
    let userId: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date().addingTimeInterval(15) }
}

enum SharedAuth {
    static let accessGroup = "TTQHTVG8CC.group.com.poyutsai.vibesync"
    static let service = "flutter_secure_storage_service"
    static let accessTokenKey = "vibesync_keyboard_access_token"
    static let userIdKey = "vibesync_keyboard_user_id"
    static let expiresAtKey = "vibesync_keyboard_expires_at"
    static let quotaExceededKey = "vibesync_keyboard_quota_exceeded"

    static func currentSession() -> KeyboardAuthSession? {
        guard
            let accessToken = read(accessTokenKey), !accessToken.isEmpty,
            let userId = read(userIdKey), !userId.isEmpty,
            let expiresAtRaw = read(expiresAtKey),
            let expiresAtSeconds = TimeInterval(expiresAtRaw)
        else { return nil }

        let session = KeyboardAuthSession(
            accessToken: accessToken,
            userId: userId,
            expiresAt: Date(timeIntervalSince1970: expiresAtSeconds)
        )
        return session.isExpired ? nil : session
    }

    static func markQuotaExceeded() {
        let value = Data("1".utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: quotaExceededKey,
            kSecAttrService: service,
            kSecAttrAccessGroup: accessGroup,
        ]
        let update: [CFString: Any] = [kSecValueData: value]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var insert = query
        insert[kSecValueData] = value
        insert[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func read(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecAttrAccessGroup: accessGroup,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
