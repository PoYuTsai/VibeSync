import CryptoKit
import XCTest

final class KeyboardAPIContractTests: XCTestCase {
    func testV1RequestEncodesRequiredNullableVoiceKeysAndNoContext() throws {
        let request = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        let data = try KeyboardAssistJSON.encoder.encode(request)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let voice = try XCTUnwrap(json["voice"] as? [String: Any])

        XCTAssertEqual(
            Set(json.keys),
            [
                "contractVersion",
                "requestId",
                "image",
                "speakerOverride",
                "voice",
            ]
        )
        XCTAssertTrue(voice.keys.contains("primary"))
        XCTAssertTrue(voice.keys.contains("secondary"))
        XCTAssertTrue(voice["primary"] is NSNull)
        XCTAssertTrue(voice["secondary"] is NSNull)
        XCTAssertNil(json["messages"])
        XCTAssertNil(json["partnerId"])
        XCTAssertNil(json["conversationSummary"])
    }

    func testV1RequestRejectsContradictoryVoiceAndSpoofedMime() {
        let sameVoice = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(
                primary: .steady,
                secondary: .steady
            )
        )
        XCTAssertThrowsError(try sameVoice.validate())

        let spoofed = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/png",
                data: Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        XCTAssertThrowsError(try spoofed.validate())
    }

    func testV1RequestAllowsUnsetVoiceButRejectsTruncatedImage() {
        let valid = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/png",
                data:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        XCTAssertNoThrow(try valid.validate())

        let truncated = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: Data([0xff, 0xd8, 0xff, 0xd9])
                    .base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        XCTAssertThrowsError(try truncated.validate())
    }

    func testReadyResponseRequiresThreeUniqueBoundedOptions() throws {
        let response = KeyboardAssistReadyResponse.fixture(requestID: UUID())
        XCTAssertNoThrow(try response.validate())

        let invalid = KeyboardAssistReadyResponse(
            contractVersion: .v1,
            requestId: UUID(),
            source: response.source,
            turnState: response.turnState,
            cue: response.cue,
            uncertainty: nil,
            options: Array(response.options.prefix(2))
        )
        XCTAssertThrowsError(try invalid.validate())
    }

    func testMissingNullableResponseKeysAreNotTreatedAsNull() throws {
        let ready = KeyboardAssistResponse.ready(
            KeyboardAssistReadyResponse.fixture(requestID: UUID())
        )
        let readyData = try KeyboardAssistJSON.encoder.encode(ready)
        var readyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: readyData)
                as? [String: Any]
        )
        readyJSON.removeValue(forKey: "uncertainty")
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: readyJSON)
            )
        )
        readyJSON["uncertainty"] = NSNull()
        XCTAssertNoThrow(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: readyJSON)
            )
        )

        let confirmation = KeyboardAssistResponse.needsSpeakerConfirmation(
            KeyboardAssistSpeakerConfirmationResponse(
                contractVersion: .v1,
                requestId: UUID(),
                suggestedMySide: .right,
                sideConfidence: .low
            )
        )
        let confirmationData = try KeyboardAssistJSON.encoder.encode(
            confirmation
        )
        var confirmationJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: confirmationData)
                as? [String: Any]
        )
        confirmationJSON.removeValue(forKey: "suggestedMySide")
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(
                    withJSONObject: confirmationJSON
                )
            )
        )
        confirmationJSON["suggestedMySide"] = NSNull()
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(
                    withJSONObject: confirmationJSON
                )
            )
        )
    }

    func testReadyResponseRejectsV2ScopeAndUntrimmedText() {
        let fixture = KeyboardAssistReadyResponse.fixture(requestID: UUID())
        let v2 = KeyboardAssistReadyResponse(
            contractVersion: .v2,
            requestId: fixture.requestId,
            source: fixture.source,
            turnState: fixture.turnState,
            cue: fixture.cue,
            uncertainty: fixture.uncertainty,
            options: fixture.options
        )
        XCTAssertThrowsError(try v2.validate())

        let linked = KeyboardAssistReadyResponse(
            contractVersion: .v1,
            requestId: fixture.requestId,
            source: KeyboardAssistSource(
                scope: .linkedPartner,
                messageCount: 3,
                confidence: .high,
                sideConfidence: .high,
                partnerId: "partner-1",
                contextRevision: String(repeating: "a", count: 64),
                contextUpdatedAt: Date()
            ),
            turnState: fixture.turnState,
            cue: fixture.cue,
            uncertainty: fixture.uncertainty,
            options: fixture.options
        )
        XCTAssertThrowsError(try linked.validate())

        let untrimmed = KeyboardAssistReadyResponse(
            contractVersion: .v1,
            requestId: fixture.requestId,
            source: fixture.source,
            turnState: fixture.turnState,
            cue: " \(fixture.cue)",
            uncertainty: fixture.uncertainty,
            options: fixture.options
        )
        XCTAssertThrowsError(try untrimmed.validate())
    }

    func testReadyDecoderRejectsUnknownTopSourceAndOptionKeys() throws {
        let response = KeyboardAssistResponse.ready(
            KeyboardAssistReadyResponse.fixture(requestID: UUID())
        )
        let data = try KeyboardAssistJSON.encoder.encode(response)
        let original = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        var top = original
        top["transcript"] = "must not cross the boundary"
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: top)
            )
        )

        var source = original
        var sourceBody = try XCTUnwrap(
            source["source"] as? [String: Any]
        )
        sourceBody["partnerId"] = "partner-1"
        source["source"] = sourceBody
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: source)
            )
        )

        var option = original
        var options = try XCTUnwrap(
            option["options"] as? [[String: Any]]
        )
        options[0]["score"] = 0.99
        option["options"] = options
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: option)
            )
        )
    }

    func testSpeakerConfirmationRequiresConcreteSideAndLowConfidence() throws {
        let response = KeyboardAssistResponse.needsSpeakerConfirmation(
            KeyboardAssistSpeakerConfirmationResponse(
                contractVersion: .v1,
                requestId: UUID(),
                suggestedMySide: .left,
                sideConfidence: .low
            )
        )
        let encoded = try KeyboardAssistJSON.encoder.encode(response)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json["sideConfidence"] = "medium"
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: json)
            )
        )
        json["sideConfidence"] = "low"
        json["suggestedMySide"] = NSNull()
        XCTAssertThrowsError(
            try KeyboardAssistJSON.decoder.decode(
                KeyboardAssistResponse.self,
                from: JSONSerialization.data(withJSONObject: json)
            )
        )
    }

    func testSubmitRejectsInvalidRequestBeforeCreatingNetworkTask() {
        let session = CountingKeyboardURLSession()
        let api = KeyboardAssistAPI(session: session)
        let invalid = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/png",
                data: Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        let completed = expectation(description: "invalid request")

        let task = api.submit(
            invalid,
            session: KeyboardAuthSession(
                accessToken: "token",
                userId: "user-a",
                expiresAt: Date().addingTimeInterval(-300)
            ),
            authorization: sendAuthorization(
                request: invalid,
                ownerUserId: "user-a"
            )
        ) { result in
            guard case .failure(.invalidRequest) = result else {
                return XCTFail("Expected local contract rejection")
            }
            completed.fulfill()
        }

        XCTAssertNil(task)
        wait(for: [completed], timeout: 0.2)
        XCTAssertEqual(session.dataTaskCount, 0)
    }

    func testCapabilityResponseBecomesOwnerBoundFiveMinuteReceipt() throws {
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let auth = KeyboardAuthSession(
            accessToken: "token",
            userId: "owner-a",
            expiresAt: receivedAt.addingTimeInterval(600)
        )
        let data = try JSONSerialization.data(withJSONObject: [
            "contractVersion": "keyboard-assist-v1",
            "enabled": true,
            "pipelineVersion": "compiler-judge-v1",
        ])

        let result = KeyboardAssistAPI.decodeCapabilityResponse(
            data,
            auth: auth,
            receivedAt: receivedAt
        )

        guard case .success(let receipt) = result else {
            return XCTFail("Expected a valid authenticated capability")
        }
        XCTAssertEqual(receipt.ownerUserId, "owner-a")
        XCTAssertEqual(
            receipt.expiresAt,
            receivedAt.addingTimeInterval(5 * 60)
        )
        XCTAssertTrue(
            receipt.isUsable(
                ownerUserId: "owner-a",
                now: receivedAt.addingTimeInterval(60)
            )
        )
        XCTAssertFalse(
            receipt.isUsable(
                ownerUserId: "owner-b",
                now: receivedAt.addingTimeInterval(60)
            )
        )
    }

    func testCapabilityResponseRejectsExtraFieldsAndUnsafePipeline() throws {
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let auth = KeyboardAuthSession(
            accessToken: "token",
            userId: "owner-a",
            expiresAt: receivedAt.addingTimeInterval(600)
        )
        for body in [
            [
                "contractVersion": "keyboard-assist-v1",
                "enabled": true,
                "pipelineVersion": "compiler-judge-v1",
                "allowlist": ["owner-a"],
            ] as [String: Any],
            [
                "contractVersion": "keyboard-assist-v1",
                "enabled": true,
                "pipelineVersion": "../unsafe",
            ] as [String: Any],
        ] {
            let result = KeyboardAssistAPI.decodeCapabilityResponse(
                try JSONSerialization.data(withJSONObject: body),
                auth: auth,
                receivedAt: receivedAt
            )
            guard case .failure(.invalidResponse) = result else {
                return XCTFail("Capability wire shape must fail closed")
            }
        }
    }

    func testSubmitRejectsWrongOwnerCapabilityBeforeNetwork() {
        let session = CountingKeyboardURLSession()
        let now = Date()
        let api = KeyboardAssistAPI(session: session, now: { now })
        let request = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/png",
                data:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        let finished = expectation(description: "capability unavailable")

        let task = api.submit(
            request,
            session: KeyboardAuthSession(
                accessToken: "token",
                userId: "owner-a",
                expiresAt: now.addingTimeInterval(600)
            ),
            authorization: sendAuthorization(
                request: request,
                ownerUserId: "owner-b",
                now: now
            )
        ) { result in
            guard case .failure(.capabilityUnavailable) = result else {
                return XCTFail("Expected owner-bound capability rejection")
            }
            finished.fulfill()
        }

        XCTAssertNil(task)
        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(session.dataTaskCount, 0)
    }

    func testUndecodableSuccessRequiresLookupWithSameRequestIdentity() {
        let result = KeyboardAssistAPI.decodeSuccessResponse(
            Data("{\"status\":\"ready\"}".utf8)
        )

        guard case .failure(.transportUncertain) = result else {
            return XCTFail("A settled but undecodable 2xx must use GET lookup")
        }
    }
}

private func capabilityReceipt(
    ownerUserId: String,
    now: Date = Date()
) -> KeyboardAssistCapabilityReceipt {
    KeyboardAssistCapabilityReceipt(
        contractVersion: .v1,
        ownerUserId: ownerUserId,
        enabled: true,
        pipelineVersion: "compiler-judge-v1",
        receivedAt: now,
        expiresAt: now.addingTimeInterval(5 * 60)
    )
}

private func sendAuthorization(
    request: KeyboardAssistV1Request,
    ownerUserId: String,
    now: Date = Date()
) -> KeyboardAssistSendAuthorization {
    let image = Data(base64Encoded: request.image.data) ?? Data()
    let hash = SHA256.hash(data: image)
        .map { String(format: "%02x", $0) }
        .joined()
    return KeyboardAssistSendAuthorization(
        binding: KeyboardRequestBinding(
            operationID: UUID(),
            requestID: request.requestId,
            ownerUserID: ownerUserId,
            documentIdentifier: UUID(),
            assetIdentifier: "asset-1",
            screenshotHash: hash,
            partnerID: nil,
            contextRevision: nil,
            createdAt: now
        ),
        capability: capabilityReceipt(
            ownerUserId: ownerUserId,
            now: now
        ),
        hasScreenshotAIConsent: true,
        consentVersion:
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
        previewConfirmedAt: now
    )
}

private final class CountingKeyboardURLSession: KeyboardURLSessioning {
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
