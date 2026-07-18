import CryptoKit
import Foundation
import Security

enum KeyboardReplyStyle: String, CaseIterable {
    case extend, resonate, tease, humor, coldRead

    var title: String {
        switch self {
        case .extend: return "🔄 延展"
        case .resonate: return "💬 共鳴"
        case .tease: return "😏 調情"
        case .humor: return "🎭 幽默"
        case .coldRead: return "🔮 冷讀"
        }
    }
}

enum KeyboardAPIError: Error {
    case unauthorized
    case quotaExceeded
    case modelRateLimited(String)
    case fullAccessRequired
    case requestIdentityUnavailable
    case requestPending
    case requestConflict
    case invalidResponse
    case server(String)
    case network
}

struct KeyboardReplySuccess {
    let reply: String
    let requestId: String
}

private struct PendingKeyboardReply: Codable {
    let requestId: String
    let fingerprint: String
    let userId: String
    let createdAt: Date
}

private final class PendingKeyboardReplyStore {
    private static let accessGroup = "TTQHTVG8CC.group.com.poyutsai.vibesync"
    // Share flutter_secure_storage's service so Runner logout/delete-account
    // can purge auth and pending metadata in one Keychain deleteAll operation.
    private static let service = SharedAuth.service
    private static let accountPrefix = "pending_"
    private static let maxPendingCount = 16
    // The server retains replay rows for 24 hours. A 23-hour client window
    // leaves clock-skew and cleanup margin so a stale UUID cannot cross the
    // server retention boundary and become a second charge.
    private static let ttl: TimeInterval = 23 * 60 * 60
    private static let clockSkewAllowance: TimeInterval = 5 * 60

    func requestId(message: String, style: KeyboardReplyStyle, userId: String) throws -> String {
        let fingerprint = Self.fingerprint(message: message, style: style, userId: userId)
        let validEntries = cleanupExpiredEntries()
        let currentUserEntries = validEntries.filter { $0.userId == userId }
        if let pending = currentUserEntries.first(where: { $0.fingerprint == fingerprint }) {
            return pending.requestId
        }

        if currentUserEntries.count >= Self.maxPendingCount {
            // Never evict an unresolved identity: it may already own a charged
            // server result. Fail closed until an entry succeeds or expires.
            throw KeyboardAPIError.requestIdentityUnavailable
        }

        let pending = PendingKeyboardReply(
            requestId: UUID().uuidString.lowercased(),
            fingerprint: fingerprint,
            userId: userId,
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(pending)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: Self.accountPrefix + fingerprint,
            kSecAttrService: Self.service,
            kSecAttrAccessGroup: Self.accessGroup,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrGeneric: Data(pending.requestId.utf8),
            kSecValueData: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return pending.requestId }
        if status == errSecDuplicateItem,
           let existing = read(fingerprint: fingerprint),
           isWithinReplayWindow(existing) {
            return existing.requestId
        }
        throw KeyboardAPIError.requestIdentityUnavailable
    }

    func clear(requestId: String) {
        for pending in allEntries() where pending.requestId == requestId {
            delete(fingerprint: pending.fingerprint, requestId: pending.requestId)
        }
    }

    private func cleanupExpiredEntries() -> [PendingKeyboardReply] {
        var valid: [PendingKeyboardReply] = []
        for pending in allEntries() {
            if isWithinReplayWindow(pending) {
                valid.append(pending)
            } else {
                // Match both fingerprint and request ID. A stale cleanup reader
                // must never delete a fresh winner inserted by another process.
                delete(fingerprint: pending.fingerprint, requestId: pending.requestId)
            }
        }
        return valid
    }

    private func isWithinReplayWindow(_ pending: PendingKeyboardReply) -> Bool {
        let age = Date().timeIntervalSince(pending.createdAt)
        return age >= -Self.clockSkewAllowance && age <= Self.ttl
    }

    private func read(fingerprint: String) -> PendingKeyboardReply? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: Self.accountPrefix + fingerprint,
            kSecAttrService: Self.service,
            kSecAttrAccessGroup: Self.accessGroup,
            kSecReturnData: true,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let row = result as? [String: Any],
              let data = row[kSecValueData as String] as? Data,
              let requestIdData = row[kSecAttrGeneric as String] as? Data,
              let pending = try? JSONDecoder().decode(PendingKeyboardReply.self, from: data),
              requestIdData == Data(pending.requestId.utf8),
              pending.fingerprint == fingerprint else { return nil }
        return pending
    }

    private func allEntries() -> [PendingKeyboardReply] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccessGroup: Self.accessGroup,
            kSecReturnData: true,
            kSecReturnAttributes: true,
            kSecReturnPersistentRef: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]] else { return [] }
        var entries: [PendingKeyboardReply] = []
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.accountPrefix) else { continue }
            guard
                  let data = row[kSecValueData as String] as? Data,
                  let requestIdData = row[kSecAttrGeneric as String] as? Data,
                  let pending = try? JSONDecoder().decode(PendingKeyboardReply.self, from: data),
                  requestIdData == Data(pending.requestId.utf8),
                  !pending.userId.isEmpty,
                  account == Self.accountPrefix + pending.fingerprint else {
                // Remove only this malformed legacy item's persistent identity;
                // a concurrent replacement has a different persistent ref.
                if let persistentRef = row[kSecValuePersistentRef as String] as? Data {
                    delete(persistentRef: persistentRef)
                }
                continue
            }
            entries.append(pending)
        }
        return entries
    }

    private func delete(fingerprint: String, requestId: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: Self.accountPrefix + fingerprint,
            kSecAttrService: Self.service,
            kSecAttrAccessGroup: Self.accessGroup,
            kSecAttrGeneric: Data(requestId.utf8),
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func delete(persistentRef: Data) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: persistentRef,
        ] as CFDictionary)
    }

    private static func fingerprint(
        message: String,
        style: KeyboardReplyStyle,
        userId: String
    ) -> String {
        let data = Data("\(userId)\u{0}\(style.rawValue)\u{0}\(message)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class KeyboardAPI {
    private let endpoint = URL(string: "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/keyboard-reply")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg"
    private let pendingStore = PendingKeyboardReplyStore()

    func generate(
        message: String,
        style: KeyboardReplyStyle,
        session: KeyboardAuthSession,
        completion: @escaping (Result<KeyboardReplySuccess, KeyboardAPIError>) -> Void
    ) {
        let finish: (Result<KeyboardReplySuccess, KeyboardAPIError>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        let requestId: String
        do {
            requestId = try pendingStore.requestId(
                message: message,
                style: style,
                userId: session.userId
            )
        } catch {
            finish(.failure(.requestIdentityUnavailable))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Server has a 24s request-entry deadline: at most 20s for generation
        // plus a 4s settlement reserve. Keep this 30s client fence outside the
        // server path but inside the database's 45s ownership lease.
        request.timeoutInterval = 30
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "message": message,
            "style": style.rawValue,
            "requestId": requestId,
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil { finish(.failure(.network)); return }
            guard let http = response as? HTTPURLResponse else {
                finish(.failure(.invalidResponse)); return
            }
            let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
            switch http.statusCode {
            case 200:
                guard let reply = json?["reply"] as? String, !reply.isEmpty else {
                    finish(.failure(.invalidResponse)); return
                }
                finish(.success(KeyboardReplySuccess(reply: reply, requestId: requestId)))
            case 401:
                // Keep the same identity across an app-driven token refresh.
                finish(.failure(.unauthorized))
            case 409:
                if json?["code"] as? String == "KEYBOARD_REPLY_REQUEST_PENDING" {
                    finish(.failure(.requestPending))
                } else if json?["code"] as? String == "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH" {
                    self.pendingStore.clear(requestId: requestId)
                    finish(.failure(.requestConflict))
                } else {
                    finish(.failure(.server(json?["error"] as? String ?? "request_conflict_unknown")))
                }
            case 429:
                if json?["code"] as? String == "MODEL_RATE_LIMITED" {
                    if json?["safeToClear"] as? Bool == true {
                        self.pendingStore.clear(requestId: requestId)
                    }
                    finish(.failure(.modelRateLimited(json?["message"] as? String ?? "操作太頻繁，請稍後再試。")))
                } else if json?["code"] as? String == "QUOTA_EXCEEDED" {
                    if json?["safeToClear"] as? Bool == true {
                        self.pendingStore.clear(requestId: requestId)
                    }
                    finish(.failure(.quotaExceeded))
                } else {
                    // Unknown 429 remains ambiguous and retains the identity.
                    finish(.failure(.server(json?["error"] as? String ?? "rate_limit_unknown")))
                }
            case 408, 425:
                // The server may still be completing this identity.
                finish(.failure(.server(json?["error"] as? String ?? "request_pending")))
            case 400..<500:
                self.pendingStore.clear(requestId: requestId)
                finish(.failure(.server(json?["error"] as? String ?? "request_rejected")))
            default:
                // 5xx and ambiguous transport failures retain the same id.
                finish(.failure(.server(json?["error"] as? String ?? "generation_failed")))
            }
        }.resume()
    }

    func markPresented(requestId: String) {
        pendingStore.clear(requestId: requestId)
    }
}
