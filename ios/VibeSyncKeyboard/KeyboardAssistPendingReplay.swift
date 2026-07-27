import Foundation
import Security

enum KeyboardAssistPendingReplayError: Error, Equatable {
    case invalidMetadata
    case conflict
    case unavailable
}

struct KeyboardAssistPendingMetadata: Codable, Equatable {
    let requestId: UUID
    let ownerUserId: String
    let documentIdentifier: UUID
    let assetIdentifier: String
    let imageSHA256: String
    let speakerOverride: KeyboardSpeakerOverride
    let voice: KeyboardAssistVoice
    let partnerId: String?
    let contextRevision: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case requestId
        case ownerUserId
        case documentIdentifier
        case assetIdentifier
        case imageSHA256
        case speakerOverride
        case voice
        case partnerId
        case contextRevision
        case createdAt
    }

    init(
        request: KeyboardAssistV1Request,
        authorization: KeyboardAssistSendAuthorization,
        createdAt: Date
    ) {
        requestId = request.requestId
        ownerUserId = authorization.binding.ownerUserID
        documentIdentifier =
            authorization.binding.documentIdentifier
        assetIdentifier = authorization.binding.assetIdentifier
        imageSHA256 = authorization.binding.screenshotHash
        speakerOverride = request.speakerOverride
        voice = request.voice
        partnerId = authorization.binding.partnerID
        contextRevision = authorization.binding.contextRevision
        self.createdAt = createdAt
    }

    init(
        requestId: UUID,
        ownerUserId: String,
        documentIdentifier: UUID,
        assetIdentifier: String,
        imageSHA256: String,
        speakerOverride: KeyboardSpeakerOverride,
        voice: KeyboardAssistVoice,
        partnerId: String?,
        contextRevision: String?,
        createdAt: Date
    ) {
        self.requestId = requestId
        self.ownerUserId = ownerUserId
        self.documentIdentifier = documentIdentifier
        self.assetIdentifier = assetIdentifier
        self.imageSHA256 = imageSHA256
        self.speakerOverride = speakerOverride
        self.voice = voice
        self.partnerId = partnerId
        self.contextRevision = contextRevision
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard CodingKeys.allCases.allSatisfy(container.contains) else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
        requestId = try container.decode(UUID.self, forKey: .requestId)
        ownerUserId = try container.decode(
            String.self,
            forKey: .ownerUserId
        )
        documentIdentifier = try container.decode(
            UUID.self,
            forKey: .documentIdentifier
        )
        assetIdentifier = try container.decode(
            String.self,
            forKey: .assetIdentifier
        )
        imageSHA256 = try container.decode(
            String.self,
            forKey: .imageSHA256
        )
        speakerOverride = try container.decode(
            KeyboardSpeakerOverride.self,
            forKey: .speakerOverride
        )
        voice = try container.decode(
            KeyboardAssistVoice.self,
            forKey: .voice
        )
        partnerId = try container.decodeIfPresent(
            String.self,
            forKey: .partnerId
        )
        contextRevision = try container.decodeIfPresent(
            String.self,
            forKey: .contextRevision
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(ownerUserId, forKey: .ownerUserId)
        try container.encode(
            documentIdentifier,
            forKey: .documentIdentifier
        )
        try container.encode(assetIdentifier, forKey: .assetIdentifier)
        try container.encode(imageSHA256, forKey: .imageSHA256)
        try container.encode(speakerOverride, forKey: .speakerOverride)
        try container.encode(voice, forKey: .voice)
        try container.encode(partnerId, forKey: .partnerId)
        try container.encode(contextRevision, forKey: .contextRevision)
        try container.encode(createdAt, forKey: .createdAt)
    }

    func validate(now: Date, expectedOwnerUserId: String? = nil) throws {
        guard Self.isExactBoundedText(ownerUserId, maximumBytes: 256),
              Self.isExactBoundedText(
                assetIdentifier,
                maximumBytes: 1_024
              ),
              expectedOwnerUserId.map({ $0 == ownerUserId }) ?? true,
              Self.isLowercaseSHA256(imageSHA256),
              voice.secondary == nil ||
                (
                    voice.primary != nil &&
                    voice.primary != voice.secondary
                ),
              partnerId.map({
                  Self.isExactBoundedText($0, maximumBytes: 256)
              }) ?? true,
              contextRevision.map(Self.isLowercaseSHA256) ?? true,
              createdAt.timeIntervalSince1970.isFinite
        else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
        let age = now.timeIntervalSince(createdAt)
        guard age >= 0,
              age <= KeyboardSharedConfig.keyboardAssistPendingTTL
        else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
    }

    func hasSameRequestIdentity(
        as other: KeyboardAssistPendingMetadata
    ) -> Bool {
        requestId == other.requestId &&
            ownerUserId == other.ownerUserId &&
            documentIdentifier == other.documentIdentifier &&
            assetIdentifier == other.assetIdentifier &&
            imageSHA256 == other.imageSHA256 &&
            speakerOverride == other.speakerOverride &&
            voice == other.voice &&
            partnerId == other.partnerId &&
            contextRevision == other.contextRevision
    }

    static var exactWireKeys: Set<String> {
        Set(CodingKeys.allCases.map(\.stringValue))
    }

    private static func isExactBoundedText(
        _ value: String,
        maximumBytes: Int
    ) -> Bool {
        !value.isEmpty &&
            value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
            value.utf8.count <= maximumBytes
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 &&
            value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
    }
}

struct KeyboardAssistPendingRawRecord: Equatable {
    let account: String
    let data: Data
}

enum KeyboardAssistPendingStorageError: Error, Equatable {
    case duplicate
    case unavailable
}

protocol KeyboardAssistPendingStorage: AnyObject {
    func records() throws -> [KeyboardAssistPendingRawRecord]
    func insert(_ record: KeyboardAssistPendingRawRecord) throws
    func delete(account: String) throws
}

protocol KeyboardAssistPendingReplayStoring: AnyObject {
    @discardableResult
    func persist(
        _ metadata: KeyboardAssistPendingMetadata,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata

    func latest(
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata?

    func matching(
        requestId: UUID,
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata?

    func clear(
        requestId: UUID,
        ownerUserId: String,
        now: Date
    ) throws
}

final class KeyboardAssistPendingKeychainStorage:
    KeyboardAssistPendingStorage
{
    func records() throws -> [KeyboardAssistPendingRawRecord] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var rawResult: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &rawResult)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw KeyboardAssistPendingStorageError.unavailable
        }

        let rows: [[String: Any]]
        if let many = rawResult as? [[String: Any]] {
            rows = many
        } else if let one = rawResult as? [String: Any] {
            rows = [one]
        } else {
            throw KeyboardAssistPendingStorageError.unavailable
        }

        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String,
                  account.hasPrefix(
                    KeyboardSharedConfig.keyboardAssistPendingAccountPrefix
                  )
            else {
                return nil
            }
            return KeyboardAssistPendingRawRecord(
                account: account,
                data:
                    (row[kSecValueData as String] as? Data) ??
                    Foundation.Data()
            )
        }
    }

    func insert(_ record: KeyboardAssistPendingRawRecord) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: record.account,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
            kSecAttrAccessible:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: record.data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw KeyboardAssistPendingStorageError.duplicate
        }
        guard status == errSecSuccess else {
            throw KeyboardAssistPendingStorageError.unavailable
        }
    }

    func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyboardAssistPendingStorageError.unavailable
        }
    }
}

final class KeyboardAssistPendingReplayStore:
    KeyboardAssistPendingReplayStoring
{
    private struct ValidRecord {
        let account: String
        let metadata: KeyboardAssistPendingMetadata
    }

    private let storage: KeyboardAssistPendingStorage
    private let lock = NSLock()

    init(storage: KeyboardAssistPendingStorage) {
        self.storage = storage
    }

    convenience init() {
        self.init(storage: KeyboardAssistPendingKeychainStorage())
    }

    @discardableResult
    func persist(
        _ metadata: KeyboardAssistPendingMetadata,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata {
        lock.lock()
        defer { lock.unlock() }
        do {
            try metadata.validate(
                now: now,
                expectedOwnerUserId: metadata.ownerUserId
            )
            var existing = try validRecords(now: now)
            if let sameRequest = existing.first(where: {
                $0.metadata.requestId == metadata.requestId
            }) {
                guard sameRequest.metadata.hasSameRequestIdentity(as: metadata)
                else {
                    throw KeyboardAssistPendingReplayError.conflict
                }
                return sameRequest.metadata
            }

            while existing.count >=
                    KeyboardSharedConfig.maximumKeyboardAssistPendingCount
            {
                guard let oldest = existing.first else {
                    throw KeyboardAssistPendingReplayError.unavailable
                }
                try storage.delete(account: oldest.account)
                existing.removeFirst()
            }

            let record = try Self.record(for: metadata)
            do {
                try storage.insert(record)
                return metadata
            } catch KeyboardAssistPendingStorageError.duplicate {
                let winner = try validRecords(now: now).first {
                    $0.metadata.requestId == metadata.requestId
                }
                guard let winner,
                      winner.metadata.hasSameRequestIdentity(as: metadata)
                else {
                    throw KeyboardAssistPendingReplayError.conflict
                }
                return winner.metadata
            }
        } catch let error as KeyboardAssistPendingReplayError {
            throw error
        } catch {
            throw KeyboardAssistPendingReplayError.unavailable
        }
    }

    func latest(
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isExactOwner(ownerUserId) else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
        do {
            return try validRecords(now: now)
                .reversed()
                .first {
                    $0.metadata.ownerUserId == ownerUserId &&
                        $0.metadata.documentIdentifier ==
                            documentIdentifier
                }?
                .metadata
        } catch let error as KeyboardAssistPendingReplayError {
            throw error
        } catch {
            throw KeyboardAssistPendingReplayError.unavailable
        }
    }

    func matching(
        requestId: UUID,
        ownerUserId: String,
        documentIdentifier: UUID,
        now: Date
    ) throws -> KeyboardAssistPendingMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isExactOwner(ownerUserId) else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
        do {
            return try validRecords(now: now).first {
                $0.metadata.requestId == requestId &&
                    $0.metadata.ownerUserId == ownerUserId &&
                    $0.metadata.documentIdentifier ==
                        documentIdentifier
            }?.metadata
        } catch let error as KeyboardAssistPendingReplayError {
            throw error
        } catch {
            throw KeyboardAssistPendingReplayError.unavailable
        }
    }

    func clear(
        requestId: UUID,
        ownerUserId: String,
        now: Date
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isExactOwner(ownerUserId) else {
            throw KeyboardAssistPendingReplayError.invalidMetadata
        }
        do {
            let matching = try validRecords(now: now).first {
                $0.metadata.requestId == requestId &&
                    $0.metadata.ownerUserId == ownerUserId
            }
            if let matching {
                try storage.delete(account: matching.account)
            }
        } catch let error as KeyboardAssistPendingReplayError {
            throw error
        } catch {
            throw KeyboardAssistPendingReplayError.unavailable
        }
    }

    private func validRecords(now: Date) throws -> [ValidRecord] {
        var valid: [ValidRecord] = []
        for raw in try storage.records() {
            guard let metadata = Self.decode(raw),
                  (try? metadata.validate(now: now)) != nil
            else {
                try storage.delete(account: raw.account)
                continue
            }
            valid.append(
                ValidRecord(account: raw.account, metadata: metadata)
            )
        }
        valid.sort {
            if $0.metadata.createdAt == $1.metadata.createdAt {
                return $0.metadata.requestId.uuidString <
                    $1.metadata.requestId.uuidString
            }
            return $0.metadata.createdAt < $1.metadata.createdAt
        }
        while valid.count >
                KeyboardSharedConfig.maximumKeyboardAssistPendingCount
        {
            let oldest = valid.removeFirst()
            try storage.delete(account: oldest.account)
        }
        return valid
    }

    private static func record(
        for metadata: KeyboardAssistPendingMetadata
    ) throws -> KeyboardAssistPendingRawRecord {
        KeyboardAssistPendingRawRecord(
            account: account(for: metadata.requestId),
            data: try KeyboardAssistJSON.encoder.encode(metadata)
        )
    }

    private static func decode(
        _ record: KeyboardAssistPendingRawRecord
    ) -> KeyboardAssistPendingMetadata? {
        guard let object = try? JSONSerialization.jsonObject(
            with: record.data
        ),
            let dictionary = object as? [String: Any],
            Set(dictionary.keys) ==
                KeyboardAssistPendingMetadata.exactWireKeys,
            let metadata = try? KeyboardAssistJSON.decoder.decode(
                KeyboardAssistPendingMetadata.self,
                from: record.data
            ),
            record.account == account(for: metadata.requestId)
        else {
            return nil
        }
        return metadata
    }

    private static func account(for requestId: UUID) -> String {
        KeyboardSharedConfig.keyboardAssistPendingAccountPrefix +
            requestId.uuidString.lowercased()
    }

    private static func isExactOwner(_ ownerUserId: String) -> Bool {
        !ownerUserId.isEmpty &&
            ownerUserId ==
                ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines) &&
            ownerUserId.utf8.count <= 256
    }
}
