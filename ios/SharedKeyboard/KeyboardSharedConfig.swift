import Foundation

enum KeyboardSharedConfig {
    static let appGroupIdentifier = "group.com.poyutsai.vibesync"
    static let keychainAccessGroup = "TTQHTVG8CC.group.com.poyutsai.vibesync"
    static let keychainService = "flutter_secure_storage_service"

    static let keyboardScreenshotConsentVersion =
        "keyboard_screenshot_ai_202607_v2"
    static let keyboardScreenshotConsentReceipt =
        "keyboard_screenshot_consent_receipt_v1"
    static let screenshotAssistCapabilityReceipt =
        "keyboard_screenshot_assist_capability_receipt_v1"
    static let currentContextRevisionSignal =
        "keyboard_context_current_revision"
    static let keyboardAssistPendingAccountPrefix =
        "keyboard_assist_pending_"

    static let contextKeyAccount = "keyboard_context_aes_gcm_v1"
    static let contextPointerFilename = "keyboard-context.current"
    static let contextFilePrefix = "keyboard-context."
    static let contextFileSuffix = ".enc"

    static let maximumContextPlaintextBytes = 64 * 1_024
    static let maximumContextCiphertextBytes =
        maximumContextPlaintextBytes + 1_024
    static let maximumPartners = 20
    static let maximumAliasesPerPartner = 5
    static let maximumCustomNoteGraphemes = 300
    static let screenshotRecencyWindow: TimeInterval = 180
    static let capabilityReceiptMaximumLifetime: TimeInterval = 5 * 60
    static let futureClockSkewAllowance: TimeInterval = 5 * 60
    static let resultsPresentationTTL: TimeInterval = 2 * 60
    static let keyboardAssistPendingTTL: TimeInterval = 23 * 60 * 60
    static let maximumKeyboardAssistPendingCount = 8
    static let maximumImageBytes = 900 * 1_024
    static let maximumImageDimension = 8_192
    static let maximumImagePixels = 20_000_000
}

struct KeyboardAssistCapabilityReceipt: Codable, Equatable {
    let contractVersion: KeyboardAssistContractVersion
    let ownerUserId: String
    let enabled: Bool
    let pipelineVersion: String
    let receivedAt: Date
    let expiresAt: Date

    func isUsable(ownerUserId expectedOwner: String, now: Date) -> Bool {
        let normalizedOwner = expectedOwner.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let lifetime = expiresAt.timeIntervalSince(receivedAt)
        return enabled &&
            contractVersion == .v1 &&
            !normalizedOwner.isEmpty &&
            normalizedOwner == expectedOwner &&
            ownerUserId == normalizedOwner &&
            Self.isSafePipelineVersion(pipelineVersion) &&
            receivedAt <= now &&
            expiresAt > now &&
            lifetime > 0 &&
            lifetime <=
                KeyboardSharedConfig.capabilityReceiptMaximumLifetime
    }

    static func isSafePipelineVersion(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count),
              let first = value.utf8.first,
              Self.isASCIIAlphaNumeric(first)
        else {
            return false
        }
        return value.utf8.allSatisfy {
            Self.isASCIIAlphaNumeric($0) ||
                $0 == 46 ||
                $0 == 95 ||
                $0 == 45
        }
    }

    private static func isASCIIAlphaNumeric(_ value: UInt8) -> Bool {
        (48...57).contains(value) ||
            (65...90).contains(value) ||
            (97...122).contains(value)
    }
}

final class KeyboardAssistCapabilityStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    convenience init?() {
        guard let defaults = UserDefaults(
            suiteName: KeyboardSharedConfig.appGroupIdentifier
        ) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    func save(_ receipt: KeyboardAssistCapabilityReceipt) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = KeyboardISO8601.encodingStrategy
        let data = try encoder.encode(receipt)
        defaults.set(
            data,
            forKey:
                KeyboardSharedConfig.screenshotAssistCapabilityReceipt
        )
    }

    func usableReceipt(
        ownerUserId: String,
        now: Date
    ) -> KeyboardAssistCapabilityReceipt? {
        guard let data = defaults.data(
            forKey:
                KeyboardSharedConfig.screenshotAssistCapabilityReceipt
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = KeyboardISO8601.decodingStrategy
        guard let receipt = try? decoder.decode(
            KeyboardAssistCapabilityReceipt.self,
            from: data
        ),
            receipt.isUsable(ownerUserId: ownerUserId, now: now)
        else {
            clear()
            return nil
        }
        return receipt
    }

    func clear() {
        defaults.removeObject(
            forKey:
                KeyboardSharedConfig.screenshotAssistCapabilityReceipt
        )
    }
}

enum KeyboardISO8601 {
    static let encodingStrategy: JSONEncoder.DateEncodingStrategy = .custom {
        date,
        encoder in
        var container = encoder.singleValueContainer()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        try container.encode(formatter.string(from: date))
    }

    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom {
        decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        if let date = wholeSeconds.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO-8601 timestamp"
        )
    }
}
