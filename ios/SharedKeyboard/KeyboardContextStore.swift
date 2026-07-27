import CryptoKit
import Foundation
import Security

protocol KeyboardContextKeyProviding: AnyObject {
    func loadOrCreateKey() throws -> SymmetricKey
    func loadKey() throws -> SymmetricKey?
    func deleteKey() throws
}

enum KeyboardContextStoreError: Error {
    case appGroupUnavailable
    case missingSnapshot
    case invalidPointer
    case ciphertextTooLarge
    case missingKey
    case invalidCiphertext
    case keychain(OSStatus)
}

final class KeyboardKeychainContextKeyProvider:
    KeyboardContextKeyProviding
{
    func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: KeyboardSharedConfig.contextKeyAccount,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let winner = try loadKey() {
            return winner
        }
        guard status == errSecSuccess else {
            throw KeyboardContextStoreError.keychain(status)
        }
        return key
    }

    func loadKey() throws -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: KeyboardSharedConfig.contextKeyAccount,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyboardContextStoreError.keychain(status)
        }
        guard data.count == 32 else {
            throw KeyboardContextStoreError.invalidCiphertext
        }
        return SymmetricKey(data: data)
    }

    func deleteKey() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: KeyboardSharedConfig.contextKeyAccount,
            kSecAttrService: KeyboardSharedConfig.keychainService,
            kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyboardContextStoreError.keychain(status)
        }
    }
}

final class KeyboardContextStore {
    private let containerURL: URL
    private let keyProvider: KeyboardContextKeyProviding
    private let fileManager: FileManager
    private let defaults: UserDefaults?
    private let now: () -> Date

    static func live() throws -> KeyboardContextStore {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                KeyboardSharedConfig.appGroupIdentifier
        ) else {
            throw KeyboardContextStoreError.appGroupUnavailable
        }
        return KeyboardContextStore(
            containerURL: containerURL,
            keyProvider: KeyboardKeychainContextKeyProvider(),
            defaults: UserDefaults(
                suiteName: KeyboardSharedConfig.appGroupIdentifier
            )
        )
    }

    init(
        containerURL: URL,
        keyProvider: KeyboardContextKeyProviding,
        fileManager: FileManager = .default,
        defaults: UserDefaults? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.containerURL = containerURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
        self.defaults = defaults
        self.now = now
    }

    func write(_ envelope: KeyboardContextEnvelope) throws {
        let plaintext = try Self.encoder.encode(envelope)
        try envelope.validate(
            expectedOwnerUserID: envelope.ownerUserId,
            now: now(),
            encodedByteCount: plaintext.count
        )

        let key = try keyProvider.loadOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let ciphertext = sealed.combined else {
            throw KeyboardContextStoreError.invalidCiphertext
        }
        let revisionURL = fileURL(for: envelope.revision)
        try ciphertext.write(
            to: revisionURL,
            options: [.atomic, .completeFileProtection]
        )

        // The pointer contains only the content hash. It is committed after the
        // immutable ciphertext so readers see either the old or the new whole
        // snapshot, never a partially overwritten envelope.
        try Data(envelope.revision.utf8).write(
            to: pointerURL,
            options: [.atomic, .completeFileProtection]
        )
        defaults?.set(
            envelope.revision,
            forKey: KeyboardSharedConfig.currentContextRevisionSignal
        )
        try removeSupersededSnapshots(keeping: envelope.revision)
    }

    func read(expectedOwnerUserID: String) throws -> KeyboardContextEnvelope {
        let revision = try currentRevision()
        let ciphertext = try Data(
            contentsOf: fileURL(for: revision),
            options: [.mappedIfSafe]
        )
        guard ciphertext.count <=
                KeyboardSharedConfig.maximumContextCiphertextBytes
        else {
            throw KeyboardContextStoreError.ciphertextTooLarge
        }
        guard let key = try keyProvider.loadKey() else {
            throw KeyboardContextStoreError.missingKey
        }
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: ciphertext)
        } catch {
            throw KeyboardContextStoreError.invalidCiphertext
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealed, using: key)
        } catch {
            throw KeyboardContextStoreError.invalidCiphertext
        }
        guard plaintext.count <=
                KeyboardSharedConfig.maximumContextPlaintextBytes
        else {
            throw KeyboardContextValidationError.plaintextTooLarge
        }
        let envelope = try Self.decoder.decode(
            KeyboardContextEnvelope.self,
            from: plaintext
        )
        guard envelope.revision == revision else {
            throw KeyboardContextStoreError.invalidPointer
        }
        try envelope.validate(
            expectedOwnerUserID: expectedOwnerUserID,
            now: now(),
            encodedByteCount: plaintext.count
        )
        return envelope
    }

    func purge(removeKey: Bool) throws {
        if fileManager.fileExists(atPath: pointerURL.path) {
            try fileManager.removeItem(at: pointerURL)
        }
        for url in try contextSnapshotURLs() {
            try fileManager.removeItem(at: url)
        }
        defaults?.removeObject(
            forKey: KeyboardSharedConfig.currentContextRevisionSignal
        )
        if removeKey {
            try keyProvider.deleteKey()
        }
    }

    private var pointerURL: URL {
        containerURL.appendingPathComponent(
            KeyboardSharedConfig.contextPointerFilename,
            isDirectory: false
        )
    }

    private func fileURL(for revision: String) -> URL {
        containerURL.appendingPathComponent(
            KeyboardSharedConfig.contextFilePrefix +
                revision +
                KeyboardSharedConfig.contextFileSuffix,
            isDirectory: false
        )
    }

    private func currentRevision() throws -> String {
        guard fileManager.fileExists(atPath: pointerURL.path) else {
            throw KeyboardContextStoreError.missingSnapshot
        }
        let pointer = try Data(contentsOf: pointerURL)
        guard pointer.count == 64,
              let revision = String(data: pointer, encoding: .utf8),
              revision.unicodeScalars.allSatisfy({
                  (48...57).contains(Int($0.value)) ||
                      (97...102).contains(Int($0.value))
              })
        else {
            throw KeyboardContextStoreError.invalidPointer
        }
        return revision
    }

    private func contextSnapshotURLs() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasPrefix(
                KeyboardSharedConfig.contextFilePrefix
            ) &&
            $0.lastPathComponent.hasSuffix(
                KeyboardSharedConfig.contextFileSuffix
            )
        }
    }

    private func removeSupersededSnapshots(keeping revision: String) throws {
        let keepURL = fileURL(for: revision).standardizedFileURL
        for url in try contextSnapshotURLs()
        where url.standardizedFileURL != keepURL {
            try fileManager.removeItem(at: url)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = KeyboardISO8601.encodingStrategy
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = KeyboardISO8601.decodingStrategy
        return decoder
    }()
}
