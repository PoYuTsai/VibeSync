import CryptoKit
import XCTest

final class KeyboardRequestBindingTests: XCTestCase {
    func testEverySecurityDimensionMustStillMatchAtInsertion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let binding = KeyboardRequestBinding.fixture(createdAt: now.addingTimeInterval(-30))
        let valid = KeyboardInsertionContext(
            operationID: binding.operationID,
            requestID: binding.requestID,
            ownerUserID: binding.ownerUserID,
            documentIdentifier: binding.documentIdentifier,
            assetIdentifier: binding.assetIdentifier,
            screenshotHash: binding.screenshotHash,
            partnerID: binding.partnerID,
            contextRevision: binding.contextRevision,
            now: now
        )

        XCTAssertNoThrow(
            try binding.validateForInsertion(
                context: valid,
                presentedAt: now.addingTimeInterval(-10)
            )
        )

        let invalidContexts: [(KeyboardInsertionContext, KeyboardBindingError)] = [
            (valid.replacing(operationID: UUID()), .operationChanged),
            (valid.replacing(requestID: UUID()), .requestChanged),
            (valid.replacing(ownerUserID: "user-b"), .ownerChanged),
            (valid.replacing(documentIdentifier: UUID()), .documentChanged),
            (valid.replacing(screenshotHash: "other"), .screenshotChanged),
            (valid.replacing(assetIdentifier: "other-asset"), .assetChanged),
            (valid.replacing(partnerID: "partner-2"), .partnerChanged),
            (valid.replacing(contextRevision: "other"), .contextChanged),
        ]
        for (context, expected) in invalidContexts {
            XCTAssertThrowsError(
                try binding.validateForInsertion(
                    context: context,
                    presentedAt: now.addingTimeInterval(-10)
                )
            ) { XCTAssertEqual($0 as? KeyboardBindingError, expected) }
        }

        XCTAssertThrowsError(
            try binding.validateForInsertion(
                context: valid,
                presentedAt: now.addingTimeInterval(
                    -KeyboardSharedConfig.resultsPresentationTTL - 1
                )
            )
        ) { XCTAssertEqual($0 as? KeyboardBindingError, .presentationExpired) }
    }

    func testSendAuthorizationBindsConsentOwnerPreviewAndImage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = Data("image-bytes".utf8)
        let request = KeyboardAssistV1Request(
            requestId: UUID(),
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: image.base64EncodedString()
            ),
            speakerOverride: .none,
            voice: KeyboardAssistVoice(primary: nil, secondary: nil)
        )
        let auth = KeyboardAuthSession(
            accessToken: "token",
            userId: "user-a",
            expiresAt: now.addingTimeInterval(600)
        )
        let binding = KeyboardRequestBinding(
            operationID: UUID(),
            requestID: request.requestId,
            ownerUserID: auth.userId,
            documentIdentifier: UUID(),
            assetIdentifier: "asset-1",
            screenshotHash: SHA256.hash(data: image)
                .map { String(format: "%02x", $0) }
                .joined(),
            partnerID: nil,
            contextRevision: nil,
            createdAt: now
        )
        let capability = KeyboardAssistCapabilityReceipt(
            contractVersion: .v1,
            ownerUserId: auth.userId,
            enabled: true,
            pipelineVersion: "compiler-judge-v1",
            receivedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        let valid = KeyboardAssistSendAuthorization(
            binding: binding,
            capability: capability,
            hasScreenshotAIConsent: true,
            consentVersion:
                KeyboardSharedConfig.keyboardScreenshotConsentVersion,
            previewConfirmedAt: now
        )

        XCTAssertNoThrow(
            try valid.validate(request: request, auth: auth, now: now)
        )
        XCTAssertThrowsError(
            try KeyboardAssistSendAuthorization(
                binding: binding,
                capability: capability,
                hasScreenshotAIConsent: false,
                consentVersion:
                    KeyboardSharedConfig.keyboardScreenshotConsentVersion,
                previewConfirmedAt: now
            ).validate(request: request, auth: auth, now: now)
        )
        XCTAssertThrowsError(
            try KeyboardAssistSendAuthorization(
                binding: binding,
                capability: capability,
                hasScreenshotAIConsent: true,
                consentVersion:
                    KeyboardSharedConfig.keyboardScreenshotConsentVersion,
                previewConfirmedAt: now.addingTimeInterval(
                    -KeyboardSharedConfig.resultsPresentationTTL - 1
                )
            ).validate(request: request, auth: auth, now: now)
        )
    }
}

extension KeyboardRequestBinding {
    static func fixture(
        operationID: UUID = UUID(),
        requestID: UUID = UUID(),
        createdAt: Date = Date()
    ) -> KeyboardRequestBinding {
        KeyboardRequestBinding(
            operationID: operationID,
            requestID: requestID,
            ownerUserID: "user-a",
            documentIdentifier: UUID(),
            assetIdentifier: "asset-1",
            screenshotHash: String(repeating: "a", count: 64),
            partnerID: "partner-1",
            contextRevision: String(repeating: "b", count: 64),
            createdAt: createdAt
        )
    }
}

private extension KeyboardInsertionContext {
    func replacing(
        operationID: UUID? = nil,
        requestID: UUID? = nil,
        ownerUserID: String? = nil,
        documentIdentifier: UUID? = nil,
        assetIdentifier: String? = nil,
        screenshotHash: String? = nil,
        partnerID: String? = nil,
        contextRevision: String? = nil
    ) -> KeyboardInsertionContext {
        KeyboardInsertionContext(
            operationID: operationID ?? self.operationID,
            requestID: requestID ?? self.requestID,
            ownerUserID: ownerUserID ?? self.ownerUserID,
            documentIdentifier: documentIdentifier ?? self.documentIdentifier,
            assetIdentifier: assetIdentifier ?? self.assetIdentifier,
            screenshotHash: screenshotHash ?? self.screenshotHash,
            partnerID: partnerID ?? self.partnerID,
            contextRevision: contextRevision ?? self.contextRevision,
            now: now
        )
    }
}
