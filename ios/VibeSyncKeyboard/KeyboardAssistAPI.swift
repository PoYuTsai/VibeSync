import Foundation

enum KeyboardAssistJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = KeyboardISO8601.encodingStrategy
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = KeyboardISO8601.decodingStrategy
        return decoder
    }()
}

protocol KeyboardAssistCancellable {
    func cancel()
}

extension URLSessionTask: KeyboardAssistCancellable {}

protocol KeyboardURLSessioning {
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (
            Data?,
            URLResponse?,
            Error?
        ) -> Void
    ) -> URLSessionDataTask
}

extension URLSession: KeyboardURLSessioning {}

enum KeyboardAssistAPIError: Error, Equatable {
    case unauthorized
    case capabilityUnavailable
    case quotaExhausted
    case modelRateLimited(retryAfterMs: Int?)
    case requestPending(retryAfterMs: Int?)
    case replayMismatch
    case requestNotFound
    case requestExpiredNoCharge
    case unsupportedConversation
    case invalidRequest
    case invalidResponse
    case transportUncertain
    case pendingReplayUnavailable
    case noPendingReplay
    case server(
        code: String,
        disposition: KeyboardAssistRetryDisposition,
        retryAfterMs: Int?
    )
}

struct KeyboardAssistRecoveredPending: Equatable {
    let metadata: KeyboardAssistPendingMetadata
    let response: KeyboardAssistResponse
}

protocol KeyboardAssistTransporting {
    @discardableResult
    func fetchCapability(
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func submit(
        _ request: KeyboardAssistV1Request,
        session: KeyboardAuthSession,
        authorization: KeyboardAssistSendAuthorization,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func lookup(
        requestID: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable?
}

protocol KeyboardAssistPendingPresentationClearing: AnyObject {
    func clearPendingAfterPresentation(
        requestID: UUID,
        session: KeyboardAuthSession
    ) throws
}

protocol KeyboardAssistPendingRecovering: AnyObject {
    @discardableResult
    func recoverPending(
        requestID: UUID,
        documentIdentifier: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func recoverLatestPending(
        documentIdentifier: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable?
}

final class KeyboardAssistAPI:
    KeyboardAssistTransporting,
    KeyboardAssistPendingRecovering,
    KeyboardAssistPendingPresentationClearing
{
    private let endpoint: URL
    private let anonKey: String
    private let session: KeyboardURLSessioning
    private let pendingReplayStore: KeyboardAssistPendingReplayStoring
    private let now: () -> Date

    init(
        endpoint: URL = URL(
            string:
                "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/keyboard-assist"
        )!,
        anonKey: String =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg",
        session: KeyboardURLSessioning = URLSession.shared,
        pendingReplayStore: KeyboardAssistPendingReplayStoring =
            KeyboardAssistPendingReplayStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.endpoint = endpoint
        self.anonKey = anonKey
        self.session = session
        self.pendingReplayStore = pendingReplayStore
        self.now = now
    }

    @discardableResult
    func fetchCapability(
        session auth: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        guard !auth.isExpired else {
            complete(.failure(.unauthorized), with: completion)
            return nil
        }
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "capability", value: "1"),
        ]
        guard let url = components.url else {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        var request = authenticatedRequest(url: url, auth: auth)
        request.httpMethod = "GET"
        return startCapability(
            request,
            auth: auth,
            completion: completion
        )
    }

    @discardableResult
    func submit(
        _ payload: KeyboardAssistV1Request,
        session auth: KeyboardAuthSession,
        authorization: KeyboardAssistSendAuthorization,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        do {
            try payload.validate()
        } catch {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        guard !auth.isExpired else {
            complete(.failure(.unauthorized), with: completion)
            return nil
        }
        let submittedAt = now()
        do {
            try authorization.validate(
                request: payload,
                auth: auth,
                now: submittedAt
            )
        } catch KeyboardSendAuthorizationError.capabilityUnavailable {
            complete(.failure(.capabilityUnavailable), with: completion)
            return nil
        } catch {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        let body: Data
        do {
            body = try KeyboardAssistJSON.encoder.encode(payload)
        } catch {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        do {
            try pendingReplayStore.persist(
                KeyboardAssistPendingMetadata(
                    request: payload,
                    authorization: authorization,
                    createdAt: submittedAt
                ),
                now: submittedAt
            )
        } catch KeyboardAssistPendingReplayError.conflict {
            complete(.failure(.replayMismatch), with: completion)
            return nil
        } catch {
            complete(
                .failure(.pendingReplayUnavailable),
                with: completion
            )
            return nil
        }

        var request = authenticatedRequest(auth: auth)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return start(
            request,
            requestID: payload.requestId,
            ownerUserId: auth.userId,
            completion: completion
        )
    }

    @discardableResult
    private func startCapability(
        _ request: URLRequest,
        auth: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable {
        let task = session.dataTask(with: request) {
            data,
            response,
            error in
            if error != nil {
                self.complete(
                    .failure(.transportUncertain),
                    with: completion
                )
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.complete(
                    .failure(.invalidResponse),
                    with: completion
                )
                return
            }
            if (200..<300).contains(http.statusCode) {
                self.complete(
                    Self.decodeCapabilityResponse(
                        data,
                        auth: auth,
                        receivedAt: self.now()
                    ),
                    with: completion
                )
                return
            }
            let detail = data.flatMap {
                try? KeyboardAssistJSON.decoder.decode(
                    KeyboardAssistErrorEnvelope.self,
                    from: $0
                ).error
            }
            self.complete(
                .failure(
                    Self.mapError(
                        statusCode: http.statusCode,
                        detail: detail
                    )
                ),
                with: completion
            )
        }
        task.resume()
        return task
    }

    @discardableResult
    func lookup(
        requestID: UUID,
        session auth: KeyboardAuthSession,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        guard !auth.isExpired else {
            complete(.failure(.unauthorized), with: completion)
            return nil
        }
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        components.queryItems = [
            URLQueryItem(
                name: "requestId",
                value: requestID.uuidString.lowercased()
            ),
        ]
        guard let url = components.url else {
            complete(.failure(.invalidRequest), with: completion)
            return nil
        }
        var request = authenticatedRequest(url: url, auth: auth)
        request.httpMethod = "GET"
        return start(
            request,
            requestID: requestID,
            ownerUserId: auth.userId,
            completion: completion
        )
    }

    @discardableResult
    func recoverPending(
        requestID: UUID,
        documentIdentifier: UUID,
        session auth: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        guard !auth.isExpired else {
            complete(.failure(.unauthorized), with: completion)
            return nil
        }
        let metadata: KeyboardAssistPendingMetadata
        do {
            guard let matching = try pendingReplayStore.matching(
                requestId: requestID,
                ownerUserId: auth.userId,
                documentIdentifier: documentIdentifier,
                now: now()
            ) else {
                complete(.failure(.noPendingReplay), with: completion)
                return nil
            }
            metadata = matching
        } catch {
            complete(
                .failure(.pendingReplayUnavailable),
                with: completion
            )
            return nil
        }
        return recover(
            metadata: metadata,
            session: auth,
            completion: completion
        )
    }

    @discardableResult
    func recoverLatestPending(
        documentIdentifier: UUID,
        session auth: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        guard !auth.isExpired else {
            complete(.failure(.unauthorized), with: completion)
            return nil
        }
        let metadata: KeyboardAssistPendingMetadata
        do {
            guard let latest = try pendingReplayStore.latest(
                ownerUserId: auth.userId,
                documentIdentifier: documentIdentifier,
                now: now()
            ) else {
                complete(.failure(.noPendingReplay), with: completion)
                return nil
            }
            metadata = latest
        } catch {
            complete(
                .failure(.pendingReplayUnavailable),
                with: completion
            )
            return nil
        }
        return recover(
            metadata: metadata,
            session: auth,
            completion: completion
        )
    }

    @discardableResult
    private func recover(
        metadata: KeyboardAssistPendingMetadata,
        session auth: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        lookup(
            requestID: metadata.requestId,
            session: auth
        ) { result in
            switch result {
            case .success(let response)
                where Self.response(
                    response,
                    matches: metadata.requestId
                ):
                completion(
                    .success(
                        KeyboardAssistRecoveredPending(
                            metadata: metadata,
                            response: response
                        )
                    )
                )
            case .success:
                try? self.pendingReplayStore.clear(
                    requestId: metadata.requestId,
                    ownerUserId: auth.userId,
                    now: self.now()
                )
                completion(.failure(.invalidResponse))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func clearPendingAfterPresentation(
        requestID: UUID,
        session auth: KeyboardAuthSession
    ) throws {
        guard !auth.isExpired else {
            throw KeyboardAssistAPIError.unauthorized
        }
        do {
            try pendingReplayStore.clear(
                requestId: requestID,
                ownerUserId: auth.userId,
                now: now()
            )
        } catch {
            throw KeyboardAssistAPIError.pendingReplayUnavailable
        }
    }

    private func authenticatedRequest(
        url: URL? = nil,
        auth: KeyboardAuthSession
    ) -> URLRequest {
        var request = URLRequest(url: url ?? endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // The Edge request has an absolute 40-second fence. Keep the client
        // outside it so valid compiler + judge + settlement work can finish.
        request.timeoutInterval = 45
        request.setValue(
            "Bearer \(auth.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        return request
    }

    @discardableResult
    private func start(
        _ request: URLRequest,
        requestID: UUID,
        ownerUserId: String,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable {
        let task = session.dataTask(with: request) {
            data,
            response,
            error in
            if error != nil {
                self.finishRequest(
                    .failure(.transportUncertain),
                    requestID: requestID,
                    ownerUserId: ownerUserId,
                    with: completion
                )
                return
            }
            guard let http = response as? HTTPURLResponse else {
                // Without a trustworthy HTTP status, the POST may have
                // reached settlement. Preserve its request identity and
                // recover through the image-free GET endpoint.
                self.finishRequest(
                    .failure(.transportUncertain),
                    requestID: requestID,
                    ownerUserId: ownerUserId,
                    with: completion
                )
                return
            }
            if (200..<300).contains(http.statusCode) {
                let decoded = Self.decodeSuccessResponse(data)
                let validated: Result<
                    KeyboardAssistResponse,
                    KeyboardAssistAPIError
                >
                if case .success(let response) = decoded,
                   !Self.response(response, matches: requestID)
                {
                    validated = .failure(.invalidResponse)
                } else {
                    validated = decoded
                }
                self.finishRequest(
                    validated,
                    requestID: requestID,
                    ownerUserId: ownerUserId,
                    with: completion
                )
                return
            }
            let detail = data.flatMap {
                try? KeyboardAssistJSON.decoder.decode(
                    KeyboardAssistErrorEnvelope.self,
                    from: $0
                ).error
            }
            self.finishRequest(
                .failure(
                    Self.mapError(
                        statusCode: http.statusCode,
                        detail: detail
                    )
                ),
                requestID: requestID,
                ownerUserId: ownerUserId,
                with: completion
            )
        }
        task.resume()
        return task
    }

    private func finishRequest(
        _ result: Result<
            KeyboardAssistResponse,
            KeyboardAssistAPIError
        >,
        requestID: UUID,
        ownerUserId: String,
        with completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) {
        if Self.shouldClearPending(after: result) {
            try? pendingReplayStore.clear(
                requestId: requestID,
                ownerUserId: ownerUserId,
                now: now()
            )
        }
        complete(result, with: completion)
    }

    static func shouldClearPending(
        after result: Result<
            KeyboardAssistResponse,
            KeyboardAssistAPIError
        >
    ) -> Bool {
        guard case .failure(let error) = result else {
            // A settled result is retained until the UI confirms it was
            // presented; a restart can recover it with an image-free GET.
            return false
        }
        switch error {
        case .replayMismatch,
             .requestNotFound,
             .requestExpiredNoCharge,
             .unsupportedConversation,
             .invalidRequest,
             .invalidResponse:
            return true
        case .server(_, let disposition, _):
            return disposition == .newRequestAfterUserChange ||
                disposition == .terminalClear
        case .unauthorized,
             .capabilityUnavailable,
             .quotaExhausted,
             .modelRateLimited,
             .requestPending,
             .transportUncertain,
             .pendingReplayUnavailable,
             .noPendingReplay:
            return false
        }
    }

    private static func response(
        _ response: KeyboardAssistResponse,
        matches requestID: UUID
    ) -> Bool {
        switch response {
        case .ready(let ready):
            return ready.requestId == requestID
        case .needsSpeakerConfirmation(let confirmation):
            return confirmation.requestId == requestID
        case .partnerMismatchConfirmation(let mismatch):
            return mismatch.requestId == requestID
        }
    }

    static func decodeSuccessResponse(
        _ data: Data?
    ) -> Result<KeyboardAssistResponse, KeyboardAssistAPIError> {
        guard let data,
              let decoded = try? KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: data
              )
        else {
            // A 2xx means the server may already have atomically settled and
            // charged this request. Keep the identity and force the caller
            // through image-free status lookup instead of generating again.
            return .failure(.transportUncertain)
        }
        return .success(decoded)
    }

    static func decodeCapabilityResponse(
        _ data: Data?,
        auth: KeyboardAuthSession,
        receivedAt: Date
    ) -> Result<
        KeyboardAssistCapabilityReceipt,
        KeyboardAssistAPIError
    > {
        struct WireResponse: Decodable {
            let contractVersion: KeyboardAssistContractVersion
            let enabled: Bool
            let pipelineVersion: String
        }

        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == Set([
                "contractVersion",
                "enabled",
                "pipelineVersion",
              ]),
              let wire = try? KeyboardAssistJSON.decoder.decode(
                WireResponse.self,
                from: data
              ),
              wire.contractVersion == .v1,
              KeyboardAssistCapabilityReceipt.isSafePipelineVersion(
                wire.pipelineVersion
              ),
              !auth.userId.isEmpty
        else {
            return .failure(.invalidResponse)
        }

        let expiresAt = min(
            receivedAt.addingTimeInterval(
                KeyboardSharedConfig.capabilityReceiptMaximumLifetime
            ),
            auth.expiresAt
        )
        guard expiresAt > receivedAt else {
            return .failure(.unauthorized)
        }
        return .success(
            KeyboardAssistCapabilityReceipt(
                contractVersion: wire.contractVersion,
                ownerUserId: auth.userId,
                enabled: wire.enabled,
                pipelineVersion: wire.pipelineVersion,
                receivedAt: receivedAt,
                expiresAt: expiresAt
            )
        )
    }

    private func complete<Value>(
        _ result: Result<Value, KeyboardAssistAPIError>,
        with completion: @escaping (
            Result<Value, KeyboardAssistAPIError>
        ) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private static func mapError(
        statusCode: Int,
        detail: KeyboardAssistErrorDetail?
    ) -> KeyboardAssistAPIError {
        switch (statusCode, detail?.code) {
        case (401, _), (_, "unauthorized"):
            return .unauthorized
        case (429, "quota_exhausted"):
            return .quotaExhausted
        case (429, "model_rate_limited"):
            return .modelRateLimited(retryAfterMs: detail?.retryAfterMs)
        case (425, _), (_, "request_pending"):
            return .requestPending(retryAfterMs: detail?.retryAfterMs)
        case (409, "request_replay_mismatch"):
            return .replayMismatch
        case (404, _), (_, "request_not_found"):
            return .requestNotFound
        case (410, _), (_, "request_expired_no_charge"):
            return .requestExpiredNoCharge
        case (422, _), (_, "unsupported_conversation"):
            return .unsupportedConversation
        case (400, _), (_, "invalid_request"),
             (413, _), (_, "image_too_large"),
             (415, _), (_, "unsupported_image"):
            return .invalidRequest
        default:
            if let detail {
                return .server(
                    code: detail.code,
                    disposition: detail.retryDisposition,
                    retryAfterMs: detail.retryAfterMs
                )
            }
            return .server(
                code: "http_\(statusCode)",
                disposition: .lookupSameRequest,
                retryAfterMs: nil
            )
        }
    }
}
