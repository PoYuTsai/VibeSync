import CryptoKit
import XCTest

final class KeyboardAssistPendingReplayTests: XCTestCase {
    func testPersistsOnlyBoundedMetadataAndReadsExactOwner() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = InMemoryPendingStorage()
        let store = KeyboardAssistPendingReplayStore(storage: storage)
        let metadata = pendingMetadata(now: now)

        try store.persist(metadata, now: now)

        let record = try XCTUnwrap(storage.rows.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: record.data)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(json.keys),
            KeyboardAssistPendingMetadata.exactWireKeys
        )
        XCTAssertNil(json["image"])
        XCTAssertNil(json["imageData"])
        XCTAssertNil(json["base64"])
        XCTAssertNil(json["transcript"])
        XCTAssertEqual(
            try store.latest(
                ownerUserId: metadata.ownerUserId,
                documentIdentifier: metadata.documentIdentifier,
                now: now
            ),
            metadata
        )
        XCTAssertNil(
            try store.latest(
                ownerUserId: "owner-b",
                documentIdentifier: metadata.documentIdentifier,
                now: now
            )
        )
        XCTAssertNil(
            try store.latest(
                ownerUserId: metadata.ownerUserId,
                documentIdentifier: UUID(),
                now: now
            )
        )
        XCTAssertNil(
            try store.matching(
                requestId: metadata.requestId,
                ownerUserId: "owner-b",
                documentIdentifier: metadata.documentIdentifier,
                now: now
            )
        )
    }

    func testMalformedAndExpiredRowsAreDeletedAndCountIsBounded() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = InMemoryPendingStorage()
        let malformedID = UUID()
        try storage.insert(
            KeyboardAssistPendingRawRecord(
                account:
                    KeyboardSharedConfig.keyboardAssistPendingAccountPrefix +
                    malformedID.uuidString.lowercased(),
                data: Data("{}".utf8)
            )
        )
        let expired = pendingMetadata(
            createdAt: now.addingTimeInterval(
                -KeyboardSharedConfig.keyboardAssistPendingTTL - 1
            )
        )
        try storage.insert(
            rawPendingRecord(expired)
        )
        let store = KeyboardAssistPendingReplayStore(storage: storage)

        XCTAssertNil(
            try store.latest(
                ownerUserId: "owner-a",
                documentIdentifier: UUID(),
                now: now
            )
        )
        XCTAssertTrue(storage.rows.isEmpty)

        for offset in 0..<12 {
            let metadata = pendingMetadata(
                requestId: UUID(),
                createdAt: now.addingTimeInterval(TimeInterval(offset))
            )
            try store.persist(
                metadata,
                now: now.addingTimeInterval(TimeInterval(offset))
            )
        }
        XCTAssertEqual(
            storage.rows.count,
            KeyboardSharedConfig.maximumKeyboardAssistPendingCount
        )
    }

    func testSameRequestIsIdempotentButChangedIdentityFailsClosed() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = InMemoryPendingStorage()
        let store = KeyboardAssistPendingReplayStore(storage: storage)
        let first = pendingMetadata(now: now)
        let sameIdentityLater = pendingMetadata(
            requestId: first.requestId,
            documentIdentifier: first.documentIdentifier,
            createdAt: now.addingTimeInterval(5)
        )

        try store.persist(first, now: now)
        XCTAssertEqual(
            try store.persist(
                sameIdentityLater,
                now: now.addingTimeInterval(5)
            ),
            first
        )

        let conflicting = KeyboardAssistPendingMetadata(
            requestId: first.requestId,
            ownerUserId: first.ownerUserId,
            documentIdentifier: first.documentIdentifier,
            assetIdentifier: first.assetIdentifier,
            imageSHA256: String(repeating: "f", count: 64),
            speakerOverride: first.speakerOverride,
            voice: first.voice,
            partnerId: first.partnerId,
            contextRevision: first.contextRevision,
            createdAt: now.addingTimeInterval(6)
        )
        XCTAssertThrowsError(
            try store.persist(
                conflicting,
                now: now.addingTimeInterval(6)
            )
        ) {
            XCTAssertEqual(
                $0 as? KeyboardAssistPendingReplayError,
                .conflict
            )
        }
        XCTAssertEqual(storage.rows.count, 1)
    }

    func testSubmitCannotCreateNetworkTaskWhenMetadataWriteFails() {
        let session = PendingCountingURLSession()
        let now = Date()
        let request = validPendingRequest()
        let api = KeyboardAssistAPI(
            session: session,
            pendingReplayStore: FailingPendingReplayStore(),
            now: { now }
        )
        let completed = expectation(description: "pending write failed")

        let task = api.submit(
            request,
            session: KeyboardAuthSession(
                accessToken: "token",
                userId: "owner-a",
                expiresAt: now.addingTimeInterval(600)
            ),
            authorization: pendingSendAuthorization(
                request: request,
                ownerUserId: "owner-a",
                now: now
            )
        ) { result in
            guard case .failure(.pendingReplayUnavailable) = result else {
                return XCTFail("Expected local persistence failure")
            }
            completed.fulfill()
        }

        XCTAssertNil(task)
        wait(for: [completed], timeout: 0.2)
        XCTAssertEqual(session.dataTaskCount, 0)
    }

    func testRecoveryWithoutOwnerMatchingMetadataNeverCreatesTask() {
        let session = PendingCountingURLSession()
        let now = Date()
        let api = KeyboardAssistAPI(
            session: session,
            pendingReplayStore: KeyboardAssistPendingReplayStore(
                storage: InMemoryPendingStorage()
            ),
            now: { now }
        )
        let completed = expectation(description: "no replay")

        let task = api.recoverPending(
            requestID: UUID(),
            documentIdentifier: UUID(),
            session: KeyboardAuthSession(
                accessToken: "token",
                userId: "owner-a",
                expiresAt: now.addingTimeInterval(600)
            )
        ) { result in
            guard case .failure(.noPendingReplay) = result else {
                return XCTFail("Expected owner-bound no-pending result")
            }
            completed.fulfill()
        }

        XCTAssertNil(task)
        wait(for: [completed], timeout: 0.2)
        XCTAssertEqual(session.dataTaskCount, 0)
    }

    func testRecoveryNeverReadsAnotherDocumentPendingRequest() throws {
        let session = PendingCountingURLSession()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = InMemoryPendingStorage()
        let store = KeyboardAssistPendingReplayStore(storage: storage)
        let metadata = pendingMetadata(now: now)
        try store.persist(metadata, now: now)
        let api = KeyboardAssistAPI(
            session: session,
            pendingReplayStore: store,
            now: { now }
        )
        let completed = expectation(description: "document mismatch")

        let task = api.recoverLatestPending(
            documentIdentifier: UUID(),
            session: KeyboardAuthSession(
                accessToken: "token",
                userId: metadata.ownerUserId,
                expiresAt: now.addingTimeInterval(600)
            )
        ) { result in
            guard case .failure(.noPendingReplay) = result else {
                return XCTFail("Expected exact document-bound recovery")
            }
            completed.fulfill()
        }

        XCTAssertNil(task)
        wait(for: [completed], timeout: 0.2)
        XCTAssertEqual(session.dataTaskCount, 0)
    }

    func testSettledResultWaitsForPresentationButTerminalClears() {
        XCTAssertFalse(
            KeyboardAssistAPI.shouldClearPending(
                after: .success(
                    .ready(
                        KeyboardAssistReadyResponse.fixture(
                            requestID: UUID()
                        )
                    )
                )
            )
        )
        XCTAssertFalse(
            KeyboardAssistAPI.shouldClearPending(
                after: .failure(.transportUncertain)
            )
        )
        XCTAssertTrue(
            KeyboardAssistAPI.shouldClearPending(
                after: .failure(.requestExpiredNoCharge)
            )
        )
        XCTAssertTrue(
            KeyboardAssistAPI.shouldClearPending(
                after: .failure(
                    .server(
                        code: "terminal",
                        disposition: .terminalClear,
                        retryAfterMs: nil
                    )
                )
            )
        )
    }
}

private final class InMemoryPendingStorage:
    KeyboardAssistPendingStorage
{
    fileprivate var rows: [KeyboardAssistPendingRawRecord] = []

    func records() throws -> [KeyboardAssistPendingRawRecord] {
        rows
    }

    func insert(_ record: KeyboardAssistPendingRawRecord) throws {
        guard !rows.contains(where: { $0.account == record.account }) else {
            throw KeyboardAssistPendingStorageError.duplicate
        }
        rows.append(record)
    }

    func delete(account: String) throws {
        rows.removeAll { $0.account == account }
    }
}

private final class FailingPendingReplayStore:
    KeyboardAssistPendingReplayStoring
{
    func persist(
        _ metadata: KeyboardAssistPendingMetadata,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata {
        throw KeyboardAssistPendingReplayError.unavailable
    }

    func latest(
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata? {
        throw KeyboardAssistPendingReplayError.unavailable
    }

    func matching(
        requestId: UUID,
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata? {
        throw KeyboardAssistPendingReplayError.unavailable
    }

    func clear(
        requestId: UUID,
        ownerUserId: String,
        now: Date
    ) throws {
        throw KeyboardAssistPendingReplayError.unavailable
    }
}

private final class PendingCountingURLSession: KeyboardURLSessioning {
    private(set) var dataTaskCount = 0

    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (
            Data?,
            URLResponse?,
            Error?
        ) -> Void
    ) -> URLSessionDataTask {
        dataTaskCount += 1
        return URLSession.shared.dataTask(with: request)
    }
}

private func pendingMetadata(
    requestId: UUID = UUID(),
    ownerUserId: String = "owner-a",
    documentIdentifier: UUID = UUID(),
    createdAt: Date? = nil,
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> KeyboardAssistPendingMetadata {
    KeyboardAssistPendingMetadata(
        requestId: requestId,
        ownerUserId: ownerUserId,
        documentIdentifier: documentIdentifier,
        assetIdentifier: "asset-1",
        imageSHA256: String(repeating: "a", count: 64),
        speakerOverride: .none,
        voice: KeyboardAssistVoice(primary: .steady, secondary: .playful),
        partnerId: "partner-1",
        contextRevision: String(repeating: "b", count: 64),
        createdAt: createdAt ?? now
    )
}

private func rawPendingRecord(
    _ metadata: KeyboardAssistPendingMetadata
) throws -> KeyboardAssistPendingRawRecord {
    KeyboardAssistPendingRawRecord(
        account:
            KeyboardSharedConfig.keyboardAssistPendingAccountPrefix +
            metadata.requestId.uuidString.lowercased(),
        data: try KeyboardAssistJSON.encoder.encode(metadata)
    )
}

private func validPendingRequest() -> KeyboardAssistV1Request {
    KeyboardAssistV1Request(
        requestId: UUID(),
        image: KeyboardAssistImage(
            mediaType: "image/png",
            data:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ),
        speakerOverride: .none,
        voice: KeyboardAssistVoice(primary: nil, secondary: nil)
    )
}

private func pendingSendAuthorization(
    request: KeyboardAssistV1Request,
    ownerUserId: String,
    now: Date
) -> KeyboardAssistSendAuthorization {
    let image = Data(base64Encoded: request.image.data) ?? Data()
    return KeyboardAssistSendAuthorization(
        binding: KeyboardRequestBinding(
            operationID: UUID(),
            requestID: request.requestId,
            ownerUserID: ownerUserId,
            documentIdentifier: UUID(),
            assetIdentifier: "asset-1",
            screenshotHash: SHA256.hash(data: image)
                .map { String(format: "%02x", $0) }
                .joined(),
            partnerID: nil,
            contextRevision: nil,
            createdAt: now
        ),
        capability: KeyboardAssistCapabilityReceipt(
            contractVersion: .v1,
            ownerUserId: ownerUserId,
            enabled: true,
            pipelineVersion: "compiler-judge-v1",
            receivedAt: now,
            expiresAt: now.addingTimeInterval(300)
        ),
        hasScreenshotAIConsent: true,
        consentVersion:
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
        previewConfirmedAt: now
    )
}
