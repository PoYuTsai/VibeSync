import XCTest

final class KeyboardContextEnvelopeTests: XCTestCase {
    func testValidEnvelopePassesValidation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = KeyboardContextTestFixture.makeEnvelope(now: now)

        XCTAssertNoThrow(
            try envelope.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        )
    }

    func testOwnerExpiryConsentAndDuplicatePartnerFailClosed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = KeyboardContextTestFixture.makeEnvelope(now: now)

        XCTAssertThrowsError(
            try envelope.validate(
                expectedOwnerUserID: "user-b",
                now: now,
                encodedByteCount: 2_048
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .ownerMismatch) }

        var expired = envelope
        expired.expiresAt = now.addingTimeInterval(-1)
        XCTAssertThrowsError(
            try expired.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .expired) }

        var wrongConsent = envelope
        wrongConsent.consent.version = "old"
        XCTAssertThrowsError(
            try wrongConsent.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .consentMismatch) }

        var duplicate = envelope
        duplicate.partners.append(envelope.partners[0])
        XCTAssertThrowsError(
            try duplicate.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .duplicatePartnerID) }
    }

    func testOversizedEnvelopeAndCustomNoteFailClosed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var envelope = KeyboardContextTestFixture.makeEnvelope(now: now)

        XCTAssertThrowsError(
            try envelope.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: KeyboardSharedConfig.maximumContextPlaintextBytes + 1
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .plaintextTooLarge) }

        envelope.partners[0].facts[0].text = String(repeating: "字", count: 301)
        XCTAssertThrowsError(
            try envelope.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        ) { XCTAssertEqual($0 as? KeyboardContextValidationError, .factTooLong) }
    }

    func testPartnerVoiceWireMatchesDartWithoutSourceTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = KeyboardContextTestFixture.makeEnvelope(now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let partners = try XCTUnwrap(root["partners"] as? [[String: Any]])
        let voice = try XCTUnwrap(
            partners.first?["effectiveVoice"] as? [String: Any]
        )

        XCTAssertEqual(Set(voice.keys), Set(["primary", "secondary"]))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(
            try decoder.decode(KeyboardContextEnvelope.self, from: data)
        )
    }

    func testDisabledPartnerSharingCannotCarryPartnerContext() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var envelope = KeyboardContextTestFixture.makeEnvelope(now: now)
        envelope.consent.partnerContextSharingEnabled = false

        XCTAssertThrowsError(
            try envelope.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        ) {
            XCTAssertEqual(
                $0 as? KeyboardContextValidationError,
                .partnerSharingDisabled
            )
        }

        envelope.partners = []
        XCTAssertNoThrow(
            try envelope.validate(
                expectedOwnerUserID: "user-a",
                now: now,
                encodedByteCount: 2_048
            )
        )
    }
}

enum KeyboardContextTestFixture {
    static func makeEnvelope(now: Date) -> KeyboardContextEnvelope {
        KeyboardContextEnvelope(
            schemaVersion: 1,
            ownerUserId: "user-a",
            revision: String(repeating: "a", count: 64),
            generatedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(23 * 60 * 60),
            consent: KeyboardContextConsent(
                version: KeyboardSharedConfig.keyboardScreenshotConsentVersion,
                acceptedAt: now.addingTimeInterval(-120),
                latestScreenshotDetectionEnabled: true,
                partnerContextSharingEnabled: true
            ),
            globalVoice: KeyboardVoice(
                primary: .steady,
                secondary: nil,
                sourceUpdatedAt: now.addingTimeInterval(-300)
            ),
            partners: [
                KeyboardPartnerContext(
                    partnerId: "partner-1",
                    displayName: "Candy",
                    confirmedAliases: ["Candy L."],
                    contextStatus: .available,
                    facts: [
                        KeyboardContextFact(
                            kind: .userNote,
                            text: "喜歡爬山",
                            updatedAt: now.addingTimeInterval(-600)
                        ),
                    ],
                    outcomeStats: KeyboardOutcomeStats(
                        sampleSize: 6,
                        engaged: 3,
                        cold: 1,
                        noReply: 1,
                        negative: 0
                    ),
                    effectiveVoice: KeyboardPartnerVoice(
                        primary: .playful,
                        secondary: .steady
                    ),
                    contextRevision: String(repeating: "b", count: 64),
                    sourceUpdatedAt: now.addingTimeInterval(-300)
                ),
            ]
        )
    }
}
