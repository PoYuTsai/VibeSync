import CryptoKit
import XCTest

final class KeyboardContextStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyboard-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAESGCMRoundTripAndAtomicReplacement() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = InMemoryKeyboardContextKeyProvider()
        let store = KeyboardContextStore(
            containerURL: directory,
            keyProvider: keys,
            now: { now }
        )
        let first = KeyboardContextTestFixture.makeEnvelope(now: now)
        try store.write(first)

        var second = first
        second.revision = String(repeating: "c", count: 64)
        second.generatedAt = now
        second.expiresAt = now.addingTimeInterval(24 * 60 * 60)
        try store.write(second)

        XCTAssertEqual(try store.read(expectedOwnerUserID: "user-a"), second)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("keyboard-context.\(first.revision).enc")
                    .path
            )
        )
    }

    func testTamperWrongKeyAndWrongOwnerFailClosed() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = InMemoryKeyboardContextKeyProvider()
        let store = KeyboardContextStore(
            containerURL: directory,
            keyProvider: keys,
            now: { now }
        )
        let envelope = KeyboardContextTestFixture.makeEnvelope(now: now)
        try store.write(envelope)

        XCTAssertThrowsError(try store.read(expectedOwnerUserID: "user-b"))

        let ciphertextURL = directory
            .appendingPathComponent("keyboard-context.\(envelope.revision).enc")
        var ciphertext = try Data(contentsOf: ciphertextURL)
        ciphertext[ciphertext.startIndex] ^= 0xff
        try ciphertext.write(to: ciphertextURL, options: .atomic)
        XCTAssertThrowsError(try store.read(expectedOwnerUserID: "user-a"))

        try store.write(envelope)
        let otherStore = KeyboardContextStore(
            containerURL: directory,
            keyProvider: InMemoryKeyboardContextKeyProvider(),
            now: { now }
        )
        XCTAssertThrowsError(try otherStore.read(expectedOwnerUserID: "user-a"))
    }

    func testPurgeRemovesEncryptedSnapshotAndKey() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = InMemoryKeyboardContextKeyProvider()
        let store = KeyboardContextStore(
            containerURL: directory,
            keyProvider: keys,
            now: { now }
        )
        try store.write(KeyboardContextTestFixture.makeEnvelope(now: now))

        try store.purge(removeKey: true)

        XCTAssertThrowsError(try store.read(expectedOwnerUserID: "user-a"))
        XCTAssertNil(keys.existingKey())
    }
}

private final class InMemoryKeyboardContextKeyProvider:
    KeyboardContextKeyProviding
{
    private var key: SymmetricKey?

    func loadOrCreateKey() throws -> SymmetricKey {
        if let key { return key }
        let created = SymmetricKey(size: .bits256)
        key = created
        return created
    }

    func loadKey() throws -> SymmetricKey? { key }

    func deleteKey() throws { key = nil }

    func existingKey() -> SymmetricKey? { key }
}
