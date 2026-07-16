import CryptoKit
import Foundation

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
    let createdAt: Date
}

private final class PendingKeyboardReplyStore {
    private static let appGroup = "group.com.poyutsai.vibesync"
    private static let ttl: TimeInterval = 24 * 60 * 60
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        fileURL = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appendingPathComponent("keyboard_reply_pending.json")
    }

    func requestId(message: String, style: KeyboardReplyStyle, userId: String) throws -> String {
        guard let fileURL else { throw KeyboardAPIError.requestIdentityUnavailable }
        let fingerprint = Self.fingerprint(message: message, style: style, userId: userId)
        if let pending = load(from: fileURL),
           Date().timeIntervalSince(pending.createdAt) <= Self.ttl,
           pending.fingerprint == fingerprint {
            return pending.requestId
        }

        let pending = PendingKeyboardReply(
            requestId: UUID().uuidString.lowercased(),
            fingerprint: fingerprint,
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(pending)
        try data.write(to: fileURL, options: .atomic)
        return pending.requestId
    }

    func clear(requestId: String) {
        guard let fileURL,
              let pending = load(from: fileURL),
              pending.requestId == requestId else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            // A corrupt/locked stale record must not pin the same replay forever.
            try? Data().write(to: fileURL, options: .atomic)
        }
    }

    private func load(from fileURL: URL) -> PendingKeyboardReply? {
        guard let data = try? Data(contentsOf: fileURL),
              let pending = try? JSONDecoder().decode(PendingKeyboardReply.self, from: data)
        else { return nil }
        return pending
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
        // Server may use one bounded format-repair call (2 × 8s). Keep the
        // client fence outside that window so a valid charged response is not
        // predictably discarded by the extension.
        request.timeoutInterval = 20
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
                self.pendingStore.clear(requestId: requestId)
                finish(.failure(.requestConflict))
            case 429:
                // Keep the durable id. A concurrent first request may have
                // committed at the quota boundary; retry preflight can replay it.
                if json?["code"] as? String == "MODEL_RATE_LIMITED" {
                    finish(.failure(.modelRateLimited(json?["message"] as? String ?? "操作太頻繁，請稍後再試。")))
                } else {
                    finish(.failure(.quotaExceeded))
                }
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
