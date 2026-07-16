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
    case invalidResponse
    case server(String)
    case network
}

final class KeyboardAPI {
    private let endpoint = URL(string: "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/keyboard-reply")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg"

    func generate(
        message: String,
        style: KeyboardReplyStyle,
        session: KeyboardAuthSession,
        completion: @escaping (Result<String, KeyboardAPIError>) -> Void
    ) {
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
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<String, KeyboardAPIError>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }
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
                finish(.success(reply))
            case 401:
                finish(.failure(.unauthorized))
            case 429:
                if json?["code"] as? String == "MODEL_RATE_LIMITED" {
                    finish(.failure(.modelRateLimited(json?["message"] as? String ?? "操作太頻繁，請稍後再試。")))
                } else {
                    finish(.failure(.quotaExceeded))
                }
            default:
                finish(.failure(.server(json?["error"] as? String ?? "generation_failed")))
            }
        }.resume()
    }
}
