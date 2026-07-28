import Foundation
import ImageIO

private struct KeyboardDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private func requireExactKeys(
    from decoder: Decoder,
    expected: Set<String>,
    optional: Set<String> = []
) throws {
    let container = try decoder.container(
        keyedBy: KeyboardDynamicCodingKey.self
    )
    var actual = Set(container.allKeys.map(\.stringValue))
    // Additive server fields stay opt-in: an older keyboard build never sees
    // them, and a newer one accepts them without loosening the exact-shape
    // guarantee for everything else.
    actual.subtract(optional)
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription:
                    "Unexpected keys: \(actual.symmetricDifference(expected))"
            )
        )
    }
}

enum KeyboardAssistContractVersion: String, Codable, Equatable {
    case v1 = "keyboard-assist-v1"
    case v2 = "keyboard-assist-v2"
}

enum KeyboardSpeakerOverride: String, Codable, Equatable {
    case none
    case leftIsMe = "left_is_me"
    case rightIsMe = "right_is_me"
}

struct KeyboardAssistVoice: Codable, Equatable {
    let primary: KeyboardVoiceName?
    let secondary: KeyboardVoiceName?

    enum CodingKeys: CodingKey {
        case primary
        case secondary
    }

    init(primary: KeyboardVoiceName?, secondary: KeyboardVoiceName?) {
        self.primary = primary
        self.secondary = secondary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.primary), container.contains(.secondary) else {
            let missingKey: CodingKeys =
                container.contains(.primary) ? .secondary : .primary
            throw DecodingError.keyNotFound(
                missingKey,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Nullable voice keys are required"
                )
            )
        }
        primary = try container.decodeIfPresent(
            KeyboardVoiceName.self,
            forKey: .primary
        )
        secondary = try container.decodeIfPresent(
            KeyboardVoiceName.self,
            forKey: .secondary
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encode(secondary, forKey: .secondary)
    }
}

struct KeyboardAssistImage: Codable, Equatable {
    let mediaType: String
    let data: String
}

/// What this keyboard offered on the previous turn in this same chat.
///
/// It never introduces facts. `offeredTexts` exists so the next batch does not
/// repeat lines the user has already seen, and so the server can recognise its
/// own candidates being read back out of a screenshot. `insertedText` marks the
/// one line the user actually sent, which is therefore a legitimate part of the
/// conversation rather than a leak.
struct KeyboardAssistPriorTurn: Codable, Equatable {
    let offeredTexts: [String]
    let insertedText: String?

    enum CodingKeys: String, CodingKey {
        case offeredTexts
        case insertedText
    }

    init(offeredTexts: [String], insertedText: String?) {
        self.offeredTexts = offeredTexts
        self.insertedText = insertedText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offeredTexts = try container.decode(
            [String].self,
            forKey: .offeredTexts
        )
        insertedText = try container.decodeIfPresent(
            String.self,
            forKey: .insertedText
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offeredTexts, forKey: .offeredTexts)
        // The server requires both keys to be present, so nil must travel as an
        // explicit null rather than an omitted field.
        try container.encode(insertedText, forKey: .insertedText)
    }

    var isValid: Bool {
        guard (1...KeyboardSharedConfig.maximumPriorOfferedTexts)
            .contains(offeredTexts.count),
            Set(offeredTexts).count == offeredTexts.count,
            offeredTexts.allSatisfy(Self.isBounded)
        else {
            return false
        }
        guard let insertedText else { return true }
        return Self.isBounded(insertedText) &&
            offeredTexts.contains(insertedText)
    }

    private static func isBounded(_ value: String) -> Bool {
        let count = value.unicodeScalars.count
        return value.trimmingCharacters(in: .whitespacesAndNewlines) == value &&
            count >= 1 &&
            count <= KeyboardSharedConfig.maximumPriorTextLength
    }
}

struct KeyboardAssistV1Request: Codable, Equatable {
    let contractVersion: KeyboardAssistContractVersion
    let requestId: UUID
    let image: KeyboardAssistImage
    let speakerOverride: KeyboardSpeakerOverride
    let voice: KeyboardAssistVoice
    let priorTurn: KeyboardAssistPriorTurn?

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestId
        case image
        case speakerOverride
        case voice
        case priorTurn
    }

    init(
        requestId: UUID,
        image: KeyboardAssistImage,
        speakerOverride: KeyboardSpeakerOverride,
        voice: KeyboardAssistVoice,
        priorTurn: KeyboardAssistPriorTurn? = nil
    ) {
        contractVersion = .v1
        self.requestId = requestId
        self.image = image
        self.speakerOverride = speakerOverride
        self.voice = voice
        self.priorTurn = priorTurn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decode(
            KeyboardAssistContractVersion.self,
            forKey: .contractVersion
        )
        requestId = try container.decode(UUID.self, forKey: .requestId)
        image = try container.decode(
            KeyboardAssistImage.self,
            forKey: .image
        )
        speakerOverride = try container.decode(
            KeyboardSpeakerOverride.self,
            forKey: .speakerOverride
        )
        voice = try container.decode(
            KeyboardAssistVoice.self,
            forKey: .voice
        )
        priorTurn = try container.decodeIfPresent(
            KeyboardAssistPriorTurn.self,
            forKey: .priorTurn
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(image, forKey: .image)
        try container.encode(speakerOverride, forKey: .speakerOverride)
        try container.encode(voice, forKey: .voice)
        // Additive field: an absent prior turn is omitted entirely so the wire
        // shape stays identical to the original v1 request.
        try container.encodeIfPresent(priorTurn, forKey: .priorTurn)
    }

    func validate() throws {
        guard voice.secondary == nil ||
                (voice.primary != nil && voice.primary != voice.secondary)
        else {
            throw KeyboardAssistContractError.invalidRequest
        }
        if let priorTurn, !priorTurn.isValid {
            throw KeyboardAssistContractError.invalidRequest
        }
        guard let decoded = Data(base64Encoded: image.data),
              !decoded.isEmpty,
              decoded.count <= KeyboardSharedConfig.maximumImageBytes
        else {
            throw KeyboardAssistContractError.invalidRequest
        }
        let validFormat: Bool
        switch image.mediaType {
        case "image/jpeg":
            validFormat = decoded.starts(with: [0xff, 0xd8, 0xff])
        case "image/png":
            validFormat = decoded.starts(
                with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            )
        case "image/webp":
            validFormat =
                decoded.count >= 12 &&
                Array(decoded.prefix(4)) == Array("RIFF".utf8) &&
                Array(decoded.dropFirst(8).prefix(4)) ==
                    Array("WEBP".utf8)
        default:
            validFormat = false
        }
        guard validFormat else {
            throw KeyboardAssistContractError.invalidRequest
        }
        guard let source = CGImageSourceCreateWithData(
            decoded as CFData,
            nil
        ),
            CGImageSourceGetCount(source) == 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.intValue > 0,
            height.intValue > 0,
            width.intValue <=
                KeyboardSharedConfig.maximumImageDimension,
            height.intValue <=
                KeyboardSharedConfig.maximumImageDimension,
            width.intValue * height.intValue <=
                KeyboardSharedConfig.maximumImagePixels
        else {
            throw KeyboardAssistContractError.invalidRequest
        }
    }
}

enum KeyboardAssistStatus: String, Codable, Equatable {
    case ready
    case needsSpeakerConfirmation = "needs_speaker_confirmation"
    case partnerMismatchConfirmation = "partner_mismatch_confirmation"
}

enum KeyboardAssistConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
}

enum KeyboardAssistTurnState: String, Codable, Equatable {
    case replyDue = "reply_due"
    case optionalFollowUp = "optional_follow_up"
}

enum KeyboardAssistSourceScope: String, Codable, Equatable {
    case screenshotOnly = "screenshot_only"
    case screenshotPlusGlobalVoice = "screenshot_plus_global_voice"
    case linkedPartner = "linked_partner"
}

enum KeyboardAssistStrategy:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Hashable
{
    case extend
    case flirt
    case humor
    // Retired taxonomy. Kept decodable so a build that predates a server-side
    // rename still renders its panel instead of failing the whole response.
    case keepPace = "keep_pace"
    case buildConnection = "build_connection"
    case moveForward = "move_forward"
    case clarify
    case deescalate
}

struct KeyboardAssistSource: Codable, Equatable {
    let scope: KeyboardAssistSourceScope
    let messageCount: Int
    let confidence: KeyboardAssistConfidence
    let sideConfidence: KeyboardAssistConfidence
    let partnerId: String?
    let contextRevision: String?
    let contextUpdatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case scope
        case messageCount
        case confidence
        case sideConfidence
        case partnerId
        case contextRevision
        case contextUpdatedAt
    }

    init(
        scope: KeyboardAssistSourceScope,
        messageCount: Int,
        confidence: KeyboardAssistConfidence,
        sideConfidence: KeyboardAssistConfidence,
        partnerId: String?,
        contextRevision: String?,
        contextUpdatedAt: Date?
    ) {
        self.scope = scope
        self.messageCount = messageCount
        self.confidence = confidence
        self.sideConfidence = sideConfidence
        self.partnerId = partnerId
        self.contextRevision = contextRevision
        self.contextUpdatedAt = contextUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(
            keyedBy: KeyboardDynamicCodingKey.self
        )
        let keys = Set(dynamic.allKeys.map(\.stringValue))
        let v1Keys = Set([
            "scope",
            "messageCount",
            "confidence",
            "sideConfidence",
        ])
        let v2Keys = v1Keys.union([
            "partnerId",
            "contextRevision",
            "contextUpdatedAt",
        ])
        guard keys == v1Keys || keys == v2Keys else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unexpected source keys"
                )
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(
            KeyboardAssistSourceScope.self,
            forKey: .scope
        )
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        confidence = try container.decode(
            KeyboardAssistConfidence.self,
            forKey: .confidence
        )
        sideConfidence = try container.decode(
            KeyboardAssistConfidence.self,
            forKey: .sideConfidence
        )
        partnerId = try container.decodeIfPresent(
            String.self,
            forKey: .partnerId
        )
        contextRevision = try container.decodeIfPresent(
            String.self,
            forKey: .contextRevision
        )
        contextUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .contextUpdatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scope, forKey: .scope)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(sideConfidence, forKey: .sideConfidence)
        if partnerId != nil ||
            contextRevision != nil ||
            contextUpdatedAt != nil
        {
            try container.encode(partnerId, forKey: .partnerId)
            try container.encode(
                contextRevision,
                forKey: .contextRevision
            )
            try container.encode(
                contextUpdatedAt,
                forKey: .contextUpdatedAt
            )
        }
    }
}

struct KeyboardAssistOption: Codable, Equatable {
    let strategy: KeyboardAssistStrategy
    let text: String
    let why: String
    let effect: String

    var candidateID: String { strategy.rawValue }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case text
        case why
        case effect
    }

    init(
        strategy: KeyboardAssistStrategy,
        text: String,
        why: String,
        effect: String
    ) {
        self.strategy = strategy
        self.text = text
        self.why = why
        self.effect = effect
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            expected: Set(["strategy", "text", "why", "effect"])
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strategy = try container.decode(
            KeyboardAssistStrategy.self,
            forKey: .strategy
        )
        text = try container.decode(String.self, forKey: .text)
        why = try container.decode(String.self, forKey: .why)
        effect = try container.decode(String.self, forKey: .effect)
    }
}

struct KeyboardAssistReadyResponse: Codable, Equatable {
    let contractVersion: KeyboardAssistContractVersion
    let requestId: UUID
    let source: KeyboardAssistSource
    let turnState: KeyboardAssistTurnState
    let cue: String
    let uncertainty: String?
    let options: [KeyboardAssistOption]
    /// The second batch behind "換一批". The compiler already produced six
    /// candidates, so serving both batches from one call means swapping costs
    /// no extra request and therefore no second charge.
    let alternates: [KeyboardAssistOption]

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestId
        case status
        case source
        case turnState
        case cue
        case uncertainty
        case options
        case alternates
    }

    init(
        contractVersion: KeyboardAssistContractVersion,
        requestId: UUID,
        source: KeyboardAssistSource,
        turnState: KeyboardAssistTurnState,
        cue: String,
        uncertainty: String?,
        options: [KeyboardAssistOption],
        alternates: [KeyboardAssistOption] = []
    ) {
        self.contractVersion = contractVersion
        self.requestId = requestId
        self.source = source
        self.turnState = turnState
        self.cue = cue
        self.uncertainty = uncertainty
        self.options = options
        self.alternates = alternates
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            expected: Set([
                "contractVersion",
                "requestId",
                "status",
                "source",
                "turnState",
                "cue",
                "uncertainty",
                "options",
            ]),
            optional: Set(["alternates"])
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.uncertainty) else {
            throw DecodingError.keyNotFound(
                CodingKeys.uncertainty,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Nullable uncertainty key is required"
                )
            )
        }
        let status = try container.decode(
            KeyboardAssistStatus.self,
            forKey: .status
        )
        guard status == .ready else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Expected ready response"
            )
        }
        contractVersion = try container.decode(
            KeyboardAssistContractVersion.self,
            forKey: .contractVersion
        )
        requestId = try container.decode(UUID.self, forKey: .requestId)
        source = try container.decode(KeyboardAssistSource.self, forKey: .source)
        turnState = try container.decode(
            KeyboardAssistTurnState.self,
            forKey: .turnState
        )
        cue = try container.decode(String.self, forKey: .cue)
        uncertainty = try container.decodeIfPresent(
            String.self,
            forKey: .uncertainty
        )
        options = try container.decode(
            [KeyboardAssistOption].self,
            forKey: .options
        )
        alternates = try container.decodeIfPresent(
            [KeyboardAssistOption].self,
            forKey: .alternates
        ) ?? []
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(KeyboardAssistStatus.ready, forKey: .status)
        try container.encode(source, forKey: .source)
        try container.encode(turnState, forKey: .turnState)
        try container.encode(cue, forKey: .cue)
        try container.encode(uncertainty, forKey: .uncertainty)
        try container.encode(options, forKey: .options)
        if !alternates.isEmpty {
            try container.encode(alternates, forKey: .alternates)
        }
    }

    func validate() throws {
        guard contractVersion == .v1,
              (
                source.scope == .screenshotOnly ||
                    source.scope == .screenshotPlusGlobalVoice
              ),
              (1...100).contains(source.messageCount),
              source.partnerId == nil,
              source.contextRevision == nil,
              source.contextUpdatedAt == nil,
              Self.hasBoundedTrimmedText(cue, range: 1...120),
              (
                uncertainty.map {
                    Self.hasBoundedTrimmedText($0, range: 1...120)
                } ?? true
              ),
              Self.isBatchOfThree(options),
              // Absent when the server predates the second batch; present
              // means it is held to exactly the same bar as the first.
              alternates.isEmpty || Self.isBatchOfThree(alternates),
              Set(alternates.map(\.text))
                  .isDisjoint(with: Set(options.map(\.text)))
        else {
            throw KeyboardAssistContractError.invalidReadyResponse
        }
    }

    private static func isBatchOfThree(
        _ batch: [KeyboardAssistOption]
    ) -> Bool {
        batch.count == 3 &&
            Set(batch.map(\.strategy)).count == 3 &&
            batch.allSatisfy {
                hasBoundedTrimmedText($0.text, range: 1...100) &&
                    hasBoundedTrimmedText($0.why, range: 1...80) &&
                    hasBoundedTrimmedText($0.effect, range: 1...60)
            }
    }

    private static func hasBoundedTrimmedText(
        _ text: String,
        range: ClosedRange<Int>
    ) -> Bool {
        text == text.trimmingCharacters(in: .whitespacesAndNewlines) &&
            range.contains(text.unicodeScalars.count)
    }
}

struct KeyboardAssistSpeakerConfirmationResponse: Codable, Equatable {
    enum Side: String, Codable {
        case left
        case right
    }

    let contractVersion: KeyboardAssistContractVersion
    let requestId: UUID
    let suggestedMySide: Side
    let sideConfidence: KeyboardAssistConfidence

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestId
        case suggestedMySide
        case sideConfidence
    }

    init(
        contractVersion: KeyboardAssistContractVersion,
        requestId: UUID,
        suggestedMySide: Side,
        sideConfidence: KeyboardAssistConfidence
    ) {
        self.contractVersion = contractVersion
        self.requestId = requestId
        self.suggestedMySide = suggestedMySide
        self.sideConfidence = sideConfidence
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            expected: Set([
                "contractVersion",
                "requestId",
                "status",
                "suggestedMySide",
                "sideConfidence",
            ])
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decode(
            KeyboardAssistContractVersion.self,
            forKey: .contractVersion
        )
        requestId = try container.decode(UUID.self, forKey: .requestId)
        suggestedMySide = try container.decode(
            Side.self,
            forKey: .suggestedMySide
        )
        sideConfidence = try container.decode(
            KeyboardAssistConfidence.self,
            forKey: .sideConfidence
        )
        guard contractVersion == .v1, sideConfidence == .low else {
            throw DecodingError.dataCorruptedError(
                forKey: .sideConfidence,
                in: container,
                debugDescription:
                    "V1 speaker confirmation requires low confidence"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(suggestedMySide, forKey: .suggestedMySide)
        try container.encode(sideConfidence, forKey: .sideConfidence)
    }
}

struct KeyboardAssistPartnerMismatchResponse: Codable, Equatable {
    let contractVersion: KeyboardAssistContractVersion
    let requestId: UUID
}

enum KeyboardAssistResponse: Codable, Equatable {
    case ready(KeyboardAssistReadyResponse)
    case needsSpeakerConfirmation(
        KeyboardAssistSpeakerConfirmationResponse
    )
    case partnerMismatchConfirmation(
        KeyboardAssistPartnerMismatchResponse
    )

    private enum CodingKeys: String, CodingKey {
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(KeyboardAssistStatus.self, forKey: .status) {
        case .ready:
            self = .ready(try KeyboardAssistReadyResponse(from: decoder))
        case .needsSpeakerConfirmation:
            self = .needsSpeakerConfirmation(
                try KeyboardAssistSpeakerConfirmationResponse(from: decoder)
            )
        case .partnerMismatchConfirmation:
            self = .partnerMismatchConfirmation(
                try KeyboardAssistPartnerMismatchResponse(from: decoder)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .ready(let response):
            try response.encode(to: encoder)
        case .needsSpeakerConfirmation(let response):
            try response.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(
                KeyboardAssistStatus.needsSpeakerConfirmation,
                forKey: .status
            )
        case .partnerMismatchConfirmation(let response):
            try response.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(
                KeyboardAssistStatus.partnerMismatchConfirmation,
                forKey: .status
            )
        }
    }
}

enum KeyboardAssistRetryDisposition: String, Codable, Equatable {
    case lookupSameRequest = "lookup_same_request"
    case retrySamePayload = "retry_same_payload"
    case newRequestAfterUserChange = "new_request_after_user_change"
    case terminalClear = "terminal_clear"
}

struct KeyboardAssistErrorDetail: Codable, Equatable {
    let code: String
    let retryDisposition: KeyboardAssistRetryDisposition
    let retryAfterMs: Int?
}

struct KeyboardAssistErrorEnvelope: Codable, Equatable {
    let error: KeyboardAssistErrorDetail
}

enum KeyboardAssistContractError: Error {
    case invalidRequest
    case invalidReadyResponse
}
