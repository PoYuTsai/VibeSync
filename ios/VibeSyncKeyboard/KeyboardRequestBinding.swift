import CryptoKit
import Foundation

struct KeyboardRequestBinding: Equatable {
    let operationID: UUID
    let requestID: UUID
    let ownerUserID: String
    let documentIdentifier: UUID
    let assetIdentifier: String
    let screenshotHash: String
    let partnerID: String?
    let contextRevision: String?
    let createdAt: Date
}

struct KeyboardInsertionContext: Equatable {
    let operationID: UUID
    let requestID: UUID
    let ownerUserID: String
    let documentIdentifier: UUID
    let assetIdentifier: String
    let screenshotHash: String
    let partnerID: String?
    let contextRevision: String?
    let now: Date
}

struct KeyboardAssistSendAuthorization: Equatable {
    let binding: KeyboardRequestBinding
    let capability: KeyboardAssistCapabilityReceipt
    let hasScreenshotAIConsent: Bool
    let consentVersion: String
    let previewConfirmedAt: Date

    func validate(
        request: KeyboardAssistV1Request,
        auth: KeyboardAuthSession,
        now: Date
    ) throws {
        guard capability.isUsable(
            ownerUserId: auth.userId,
            now: now
        ) else {
            throw KeyboardSendAuthorizationError.capabilityUnavailable
        }
        guard hasScreenshotAIConsent,
              consentVersion ==
                KeyboardSharedConfig.keyboardScreenshotConsentVersion
        else {
            throw KeyboardSendAuthorizationError.consentRequired
        }
        guard binding.ownerUserID == auth.userId else {
            throw KeyboardSendAuthorizationError.ownerChanged
        }
        guard binding.requestID == request.requestId else {
            throw KeyboardSendAuthorizationError.requestChanged
        }
        guard !binding.assetIdentifier.isEmpty,
              let image = Data(base64Encoded: request.image.data)
        else {
            throw KeyboardSendAuthorizationError.imageChanged
        }
        let digest = SHA256.hash(data: image)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == binding.screenshotHash else {
            throw KeyboardSendAuthorizationError.imageChanged
        }
        let age = now.timeIntervalSince(previewConfirmedAt)
        guard age >= 0 else {
            throw KeyboardSendAuthorizationError.previewInFuture
        }
        guard age <= KeyboardSharedConfig.resultsPresentationTTL else {
            throw KeyboardSendAuthorizationError.previewExpired
        }
    }
}

enum KeyboardSendAuthorizationError: Error, Equatable {
    case capabilityUnavailable
    case consentRequired
    case ownerChanged
    case requestChanged
    case imageChanged
    case previewInFuture
    case previewExpired
}

enum KeyboardBindingError: Error, Equatable {
    case operationChanged
    case requestChanged
    case ownerChanged
    case documentChanged
    case assetChanged
    case screenshotChanged
    case partnerChanged
    case contextChanged
    case presentationInFuture
    case presentationExpired
}

extension KeyboardRequestBinding {
    func validateForInsertion(
        context: KeyboardInsertionContext,
        presentedAt: Date
    ) throws {
        guard operationID == context.operationID else {
            throw KeyboardBindingError.operationChanged
        }
        guard requestID == context.requestID else {
            throw KeyboardBindingError.requestChanged
        }
        guard ownerUserID == context.ownerUserID else {
            throw KeyboardBindingError.ownerChanged
        }
        guard documentIdentifier == context.documentIdentifier else {
            throw KeyboardBindingError.documentChanged
        }
        guard assetIdentifier == context.assetIdentifier else {
            throw KeyboardBindingError.assetChanged
        }
        guard screenshotHash == context.screenshotHash else {
            throw KeyboardBindingError.screenshotChanged
        }
        guard partnerID == context.partnerID else {
            throw KeyboardBindingError.partnerChanged
        }
        guard contextRevision == context.contextRevision else {
            throw KeyboardBindingError.contextChanged
        }
        let age = context.now.timeIntervalSince(presentedAt)
        guard age >= -KeyboardSharedConfig.futureClockSkewAllowance else {
            throw KeyboardBindingError.presentationInFuture
        }
        guard age <= KeyboardSharedConfig.resultsPresentationTTL else {
            throw KeyboardBindingError.presentationExpired
        }
    }
}

struct KeyboardResultsPresentation: Equatable {
    let binding: KeyboardRequestBinding
    let options: [KeyboardAssistOption]
    let presentedAt: Date
}
