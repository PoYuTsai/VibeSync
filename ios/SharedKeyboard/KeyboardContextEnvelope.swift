import Foundation

enum KeyboardVoiceName: String, Codable, CaseIterable, Equatable {
    case steady
    case direct
    case humorous
    case gentle
    case playful
}

struct KeyboardVoice: Codable, Equatable {
    var primary: KeyboardVoiceName?
    var secondary: KeyboardVoiceName?
    var sourceUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case sourceUpdatedAt
    }

    init(
        primary: KeyboardVoiceName?,
        secondary: KeyboardVoiceName?,
        sourceUpdatedAt: Date
    ) {
        self.primary = primary
        self.secondary = secondary
        self.sourceUpdatedAt = sourceUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.primary), container.contains(.secondary) else {
            throw DecodingError.keyNotFound(
                container.contains(.primary) ? .secondary : .primary,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Voice nullable fields are required"
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
        sourceUpdatedAt = try container.decode(Date.self, forKey: .sourceUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encode(secondary, forKey: .secondary)
        try container.encode(sourceUpdatedAt, forKey: .sourceUpdatedAt)
    }
}

/// Partner voice intentionally has no timestamp on the wire. The partner
/// context already carries `sourceUpdatedAt`, matching the Dart snapshot
/// contract and keeping nullable voice fields explicit.
struct KeyboardPartnerVoice: Codable, Equatable {
    var primary: KeyboardVoiceName?
    var secondary: KeyboardVoiceName?

    enum CodingKeys: String, CodingKey {
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
            throw DecodingError.keyNotFound(
                container.contains(.primary) ? .secondary : .primary,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Partner voice nullable fields are required"
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

struct KeyboardContextConsent: Codable, Equatable {
    var version: String
    var acceptedAt: Date
    var latestScreenshotDetectionEnabled: Bool
    var partnerContextSharingEnabled: Bool
}

enum KeyboardPartnerContextStatus: String, Codable, Equatable {
    case available
    case dataQualityFlagged = "data_quality_flagged"
}

enum KeyboardContextFactKind: String, Codable, Equatable {
    case userNote = "user_note"
}

struct KeyboardContextFact: Codable, Equatable {
    var kind: KeyboardContextFactKind
    var text: String
    var updatedAt: Date
}

struct KeyboardOutcomeStats: Codable, Equatable {
    var sampleSize: Int
    var engaged: Int
    var cold: Int
    var noReply: Int
    var negative: Int
}

struct KeyboardPartnerContext: Codable, Equatable {
    var partnerId: String
    var displayName: String
    var confirmedAliases: [String]
    var contextStatus: KeyboardPartnerContextStatus
    var facts: [KeyboardContextFact]
    var outcomeStats: KeyboardOutcomeStats?
    var effectiveVoice: KeyboardPartnerVoice?
    var contextRevision: String
    var sourceUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case partnerId
        case displayName
        case confirmedAliases
        case contextStatus
        case facts
        case outcomeStats
        case effectiveVoice
        case contextRevision
        case sourceUpdatedAt
    }

    init(
        partnerId: String,
        displayName: String,
        confirmedAliases: [String],
        contextStatus: KeyboardPartnerContextStatus,
        facts: [KeyboardContextFact],
        outcomeStats: KeyboardOutcomeStats?,
        effectiveVoice: KeyboardPartnerVoice?,
        contextRevision: String,
        sourceUpdatedAt: Date
    ) {
        self.partnerId = partnerId
        self.displayName = displayName
        self.confirmedAliases = confirmedAliases
        self.contextStatus = contextStatus
        self.facts = facts
        self.outcomeStats = outcomeStats
        self.effectiveVoice = effectiveVoice
        self.contextRevision = contextRevision
        self.sourceUpdatedAt = sourceUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [
            CodingKeys.outcomeStats,
            CodingKeys.effectiveVoice,
        ] where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Nullable context fields are required"
                )
            )
        }
        partnerId = try container.decode(String.self, forKey: .partnerId)
        displayName = try container.decode(String.self, forKey: .displayName)
        confirmedAliases = try container.decode(
            [String].self,
            forKey: .confirmedAliases
        )
        contextStatus = try container.decode(
            KeyboardPartnerContextStatus.self,
            forKey: .contextStatus
        )
        facts = try container.decode([KeyboardContextFact].self, forKey: .facts)
        outcomeStats = try container.decodeIfPresent(
            KeyboardOutcomeStats.self,
            forKey: .outcomeStats
        )
        effectiveVoice = try container.decodeIfPresent(
            KeyboardPartnerVoice.self,
            forKey: .effectiveVoice
        )
        contextRevision = try container.decode(
            String.self,
            forKey: .contextRevision
        )
        sourceUpdatedAt = try container.decode(Date.self, forKey: .sourceUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partnerId, forKey: .partnerId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(confirmedAliases, forKey: .confirmedAliases)
        try container.encode(contextStatus, forKey: .contextStatus)
        try container.encode(facts, forKey: .facts)
        try container.encode(outcomeStats, forKey: .outcomeStats)
        try container.encode(effectiveVoice, forKey: .effectiveVoice)
        try container.encode(contextRevision, forKey: .contextRevision)
        try container.encode(sourceUpdatedAt, forKey: .sourceUpdatedAt)
    }
}

struct KeyboardContextEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserId: String
    var revision: String
    var generatedAt: Date
    var expiresAt: Date
    var consent: KeyboardContextConsent
    var globalVoice: KeyboardVoice
    var partners: [KeyboardPartnerContext]
}

enum KeyboardContextValidationError: Error, Equatable {
    case unsupportedSchema
    case ownerMismatch
    case invalidRevision
    case generatedInFuture
    case consentAcceptedInFuture
    case invalidExpiry
    case expired
    case consentMismatch
    case screenshotDetectionDisabled
    case partnerSharingDisabled
    case invalidVoice
    case tooManyPartners
    case duplicatePartnerID
    case invalidPartner
    case tooManyAliases
    case factTooLong
    case flaggedContextLeaked
    case invalidOutcomeStats
    case plaintextTooLarge
}

extension KeyboardContextEnvelope {
    func validate(
        expectedOwnerUserID: String,
        now: Date,
        encodedByteCount: Int
    ) throws {
        guard schemaVersion == 1 else {
            throw KeyboardContextValidationError.unsupportedSchema
        }
        guard ownerUserId == expectedOwnerUserID else {
            throw KeyboardContextValidationError.ownerMismatch
        }
        guard Self.isSafeRevision(revision) else {
            throw KeyboardContextValidationError.invalidRevision
        }
        guard generatedAt <= now.addingTimeInterval(
            KeyboardSharedConfig.futureClockSkewAllowance
        ) else {
            throw KeyboardContextValidationError.generatedInFuture
        }
        guard consent.acceptedAt <= now.addingTimeInterval(
            KeyboardSharedConfig.futureClockSkewAllowance
        ) else {
            throw KeyboardContextValidationError.consentAcceptedInFuture
        }
        guard expiresAt > generatedAt,
              expiresAt.timeIntervalSince(generatedAt) <= 24 * 60 * 60 + 1
        else {
            throw KeyboardContextValidationError.invalidExpiry
        }
        guard expiresAt > now else {
            throw KeyboardContextValidationError.expired
        }
        guard consent.version ==
                KeyboardSharedConfig.keyboardScreenshotConsentVersion
        else {
            throw KeyboardContextValidationError.consentMismatch
        }
        guard consent.latestScreenshotDetectionEnabled else {
            throw KeyboardContextValidationError.screenshotDetectionDisabled
        }
        guard consent.partnerContextSharingEnabled || partners.isEmpty else {
            throw KeyboardContextValidationError.partnerSharingDisabled
        }
        try Self.validateVoice(
            primary: globalVoice.primary,
            secondary: globalVoice.secondary
        )
        guard partners.count <= KeyboardSharedConfig.maximumPartners else {
            throw KeyboardContextValidationError.tooManyPartners
        }
        guard Set(partners.map(\.partnerId)).count == partners.count else {
            throw KeyboardContextValidationError.duplicatePartnerID
        }
        guard encodedByteCount <=
                KeyboardSharedConfig.maximumContextPlaintextBytes
        else {
            throw KeyboardContextValidationError.plaintextTooLarge
        }

        for partner in partners {
            guard !partner.partnerId.isEmpty,
                  !partner.displayName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  Self.isSafeRevision(partner.contextRevision)
            else {
                throw KeyboardContextValidationError.invalidPartner
            }
            guard partner.confirmedAliases.count <=
                    KeyboardSharedConfig.maximumAliasesPerPartner
            else {
                throw KeyboardContextValidationError.tooManyAliases
            }
            for fact in partner.facts {
                guard fact.text.count <=
                        KeyboardSharedConfig.maximumCustomNoteGraphemes
                else {
                    throw KeyboardContextValidationError.factTooLong
                }
            }
            if partner.contextStatus == .dataQualityFlagged,
               !partner.facts.isEmpty ||
                partner.outcomeStats != nil ||
                partner.effectiveVoice != nil
            {
                throw KeyboardContextValidationError.flaggedContextLeaked
            }
            if let voice = partner.effectiveVoice {
                try Self.validateVoice(
                    primary: voice.primary,
                    secondary: voice.secondary
                )
            }
            if let stats = partner.outcomeStats {
                let values = [
                    stats.sampleSize,
                    stats.engaged,
                    stats.cold,
                    stats.noReply,
                    stats.negative,
                ]
                guard values.allSatisfy({ $0 >= 0 }),
                      stats.engaged + stats.cold +
                        stats.noReply + stats.negative <= stats.sampleSize
                else {
                    throw KeyboardContextValidationError.invalidOutcomeStats
                }
            }
        }
    }

    private static func validateVoice(
        primary: KeyboardVoiceName?,
        secondary: KeyboardVoiceName?
    ) throws {
        guard secondary == nil ||
                (primary != nil && primary != secondary)
        else {
            throw KeyboardContextValidationError.invalidVoice
        }
    }

    private static func isSafeRevision(_ revision: String) -> Bool {
        revision.count == 64 &&
            revision.unicodeScalars.allSatisfy {
                (48...57).contains(Int($0.value)) ||
                    (97...102).contains(Int($0.value))
            }
    }
}
