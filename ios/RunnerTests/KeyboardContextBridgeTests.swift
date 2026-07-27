import CryptoKit
import Photos
import XCTest
@testable import Runner

final class KeyboardContextBridgeTests: XCTestCase {
  func testPhotoAuthorizationWireIsBounded() {
    XCTAssertEqual(
      KeyboardContextBridge.photoAuthorizationWire(.authorized),
      "authorized"
    )
    XCTAssertEqual(
      KeyboardContextBridge.photoAuthorizationWire(.denied),
      "denied"
    )
    XCTAssertEqual(
      KeyboardContextBridge.photoAuthorizationWire(.notDetermined),
      "not_determined"
    )
    if #available(iOS 14, *) {
      XCTAssertEqual(
        KeyboardContextBridge.photoAuthorizationWire(.limited),
        "limited"
      )
    }
  }

  func testAppGroupConsentStoreRejectsWriteFromStaleEpoch() throws {
    let suiteName =
      "KeyboardContextBridgeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = KeyboardAppGroupScreenshotConsentReceiptStore(
      defaults: defaults
    )
    let initial = Data("initial".utf8)

    XCTAssertEqual(try store.currentEpoch(), 0)
    try store.write(initial, expectedEpoch: 0)
    XCTAssertEqual(try store.read(), initial)

    try store.invalidateAndClear()

    XCTAssertEqual(try store.currentEpoch(), 1)
    XCTAssertNil(try store.read())
    XCTAssertThrowsError(
      try store.write(Data("stale".utf8), expectedEpoch: 0)
    ) {
      XCTAssertEqual(
        $0 as? KeyboardContextBridgeError,
        .staleConsentEpoch
      )
    }
    XCTAssertNil(try store.read())
  }

  func testWriteSnapshotAcceptsFractionalDartDatesAndReturnsRevision() throws {
    let store = RecordingKeyboardContextStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { store },
      pendingReplayPurger: RecordingPendingReplayPurger()
    )
    let payload = try makePayload()

    let result = try XCTUnwrap(
      try handler.handle(
        method: "writeSnapshot",
        arguments: payload
      ) as? [String: String]
    )

    XCTAssertEqual(result["storedRevision"], payload["revision"] as? String)
    XCTAssertEqual(store.writes.count, 1)
    XCTAssertEqual(store.writes[0].partners[0].effectiveVoice?.primary, .playful)
  }

  func testWriteSnapshotRejectsUnknownContextAndRevisionMismatch() throws {
    let store = RecordingKeyboardContextStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { store },
      pendingReplayPurger: RecordingPendingReplayPurger()
    )
    var extra = try makePayload()
    extra["rawMessages"] = ["must never be persisted"]

    XCTAssertThrowsError(
      try handler.handle(method: "writeSnapshot", arguments: extra)
    )

    var mismatch = try makePayload()
    mismatch["ownerUserId"] = "changed-after-hash"
    XCTAssertThrowsError(
      try handler.handle(method: "writeSnapshot", arguments: mismatch)
    ) {
      XCTAssertEqual(
        $0 as? KeyboardContextBridgeError,
        .revisionMismatch
      )
    }
    XCTAssertTrue(store.writes.isEmpty)
  }

  func testWriteSnapshotRejectsStalePartnerRevision() throws {
    let store = RecordingKeyboardContextStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { store },
      pendingReplayPurger: RecordingPendingReplayPurger()
    )
    var payload = try makePayload()
    var partners = try XCTUnwrap(
      payload["partners"] as? [[String: Any]]
    )
    var facts = try XCTUnwrap(
      partners[0]["facts"] as? [[String: Any]]
    )
    facts[0]["text"] = "changed while keeping stale contextRevision"
    partners[0]["facts"] = facts
    payload["partners"] = partners
    payload = try withTopRevision(payload)

    XCTAssertThrowsError(
      try handler.handle(method: "writeSnapshot", arguments: payload)
    ) {
      XCTAssertEqual(
        $0 as? KeyboardContextBridgeError,
        .revisionMismatch
      )
    }
    XCTAssertTrue(store.writes.isEmpty)
  }

  func testPurgeScopesDeleteTheRightMaterial() throws {
    let store = RecordingKeyboardContextStore()
    let purger = RecordingPendingReplayPurger()
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { store },
      pendingReplayPurger: purger,
      screenshotConsentStoreProvider: { consentStore }
    )

    _ = try handler.handle(
      method: "purgeContext",
      arguments: [
        "scope": "consent_revoked",
        "purgePendingReplayIdentity": false,
      ]
    )
    XCTAssertEqual(store.removeKeyCalls, [false])
    XCTAssertEqual(purger.calls, 0)
    XCTAssertEqual(consentStore.clearCalls, 1)

    _ = try handler.handle(
      method: "purgeContext",
      arguments: [
        "scope": "account_deletion",
        "purgePendingReplayIdentity": true,
      ]
    )
    XCTAssertEqual(store.removeKeyCalls, [false, true])
    XCTAssertEqual(purger.calls, 1)
    XCTAssertEqual(consentStore.clearCalls, 2)
  }

  func testPurgeScopeAndReplayBooleanCannotDisagree() {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore }
    )

    XCTAssertThrowsError(
      try handler.handle(
        method: "purgeContext",
        arguments: [
          "scope": "logout",
          "purgePendingReplayIdentity": true,
        ]
      )
    ) {
      XCTAssertEqual(
        $0 as? KeyboardContextBridgeError,
        .invalidPurgeScope
      )
    }
    XCTAssertEqual(consentStore.clearCalls, 0)
  }

  func testWritesExactOwnerBoundScreenshotConsentReceipt() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
    )
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore },
      now: { now }
    )

    let result = try XCTUnwrap(
      try handler.handle(
        method: "writeScreenshotConsentReceipt",
        arguments: [
          "ownerUserId": "owner-1",
          "version":
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          "enabled": true,
          "acceptedAt": "2025-01-01T00:00:00.000Z",
          "updatedAt": "2026-07-27T12:00:00.000Z",
          "expectedEpoch": 0,
        ]
      ) as? [String: String]
    )

    XCTAssertEqual(result["storedOwnerUserId"], "owner-1")
    XCTAssertEqual(
      result["storedVersion"],
      KeyboardSharedConfig.keyboardScreenshotConsentVersion
    )
    XCTAssertEqual(consentStore.writes.count, 1)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = KeyboardISO8601.decodingStrategy
    let stored = try decoder.decode(
      TestScreenshotConsentReceipt.self,
      from: try XCTUnwrap(consentStore.writes.first)
    )
    XCTAssertEqual(stored.ownerUserId, "owner-1")
    XCTAssertTrue(stored.enabled)
    XCTAssertEqual(
      stored.version,
      KeyboardSharedConfig.keyboardScreenshotConsentVersion
    )
  }

  func testScreenshotConsentReceiptRejectsUnsafeOrFuturePayloads() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
    )
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore },
      now: { now }
    )
    let base: [String: Any] = [
      "ownerUserId": "owner-1",
      "version": KeyboardSharedConfig.keyboardScreenshotConsentVersion,
      "enabled": true,
      "acceptedAt": "2026-07-27T11:00:00.000Z",
      "updatedAt": "2026-07-27T12:00:00.000Z",
      "expectedEpoch": 0,
    ]

    var disabled = base
    disabled["enabled"] = false
    XCTAssertThrowsError(
      try handler.handle(
        method: "writeScreenshotConsentReceipt",
        arguments: disabled
      )
    )

    var future = base
    future["updatedAt"] = "2026-07-27T12:06:00.000Z"
    XCTAssertThrowsError(
      try handler.handle(
        method: "writeScreenshotConsentReceipt",
        arguments: future
      )
    )

    var extra = base
    extra["rawScreenshot"] = "never accepted"
    XCTAssertThrowsError(
      try handler.handle(
        method: "writeScreenshotConsentReceipt",
        arguments: extra
      )
    )
    XCTAssertTrue(consentStore.writes.isEmpty)
  }

  func testExplicitScreenshotConsentClearHasNoArguments() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore }
    )

    _ = try handler.handle(
      method: "clearScreenshotConsentReceipt",
      arguments: nil
    )
    XCTAssertEqual(consentStore.clearCalls, 1)
    XCTAssertThrowsError(
      try handler.handle(
        method: "clearScreenshotConsentReceipt",
        arguments: [:]
      )
    )
  }

  func testVerifiesStoredReceiptAgainstOwnerVersionAndAcceptedAt() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
    )
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore },
      now: { now }
    )
    let receipt: [String: Any] = [
      "ownerUserId": "owner-1",
      "version": KeyboardSharedConfig.keyboardScreenshotConsentVersion,
      "enabled": true,
      "acceptedAt": "2026-07-01T00:00:00.000Z",
      "updatedAt": "2026-07-27T12:00:00.000Z",
      "expectedEpoch": 0,
    ]
    _ = try handler.handle(
      method: "writeScreenshotConsentReceipt",
      arguments: receipt
    )

    XCTAssertEqual(
      try handler.handle(
        method: "verifyScreenshotConsentReceipt",
        arguments: [
          "ownerUserId": "owner-1",
          "version":
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          "acceptedAt": "2026-07-01T00:00:00.000Z",
        ]
      ) as? Bool,
      true
    )
    XCTAssertEqual(
      try handler.handle(
        method: "verifyScreenshotConsentReceipt",
        arguments: [
          "ownerUserId": "owner-2",
          "version":
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          "acceptedAt": "2026-07-01T00:00:00.000Z",
        ]
      ) as? Bool,
      false
    )
  }

  func testVerificationClearsMalformedStoredReceipt() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    consentStore.readData = Data("not-json".utf8)
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
    )
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore },
      now: { now }
    )

    XCTAssertEqual(
      try handler.handle(
        method: "verifyScreenshotConsentReceipt",
        arguments: [
          "ownerUserId": "owner-1",
          "version":
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          "acceptedAt": "2026-07-01T00:00:00.000Z",
        ]
      ) as? Bool,
      false
    )
    XCTAssertEqual(consentStore.clearCalls, 1)
    XCTAssertNil(consentStore.readData)
  }

  func testStaleScreenshotConsentSetupCannotWriteAfterPurge() throws {
    let consentStore = RecordingScreenshotConsentReceiptStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
    )
    let handler = KeyboardContextBridgeHandler(
      storeProvider: { RecordingKeyboardContextStore() },
      pendingReplayPurger: RecordingPendingReplayPurger(),
      screenshotConsentStoreProvider: { consentStore },
      now: { now }
    )
    let setup = try XCTUnwrap(
      try handler.handle(
        method: "beginScreenshotConsentSetup",
        arguments: nil
      ) as? [String: Int]
    )
    XCTAssertEqual(setup["epoch"], 0)

    _ = try handler.handle(
      method: "purgeContext",
      arguments: [
        "scope": "logout",
        "purgePendingReplayIdentity": false,
      ]
    )
    XCTAssertEqual(consentStore.epoch, 1)

    XCTAssertThrowsError(
      try handler.handle(
        method: "writeScreenshotConsentReceipt",
        arguments: [
          "ownerUserId": "owner-1",
          "version":
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          "enabled": true,
          "acceptedAt": "2025-01-01T00:00:00.000Z",
          "updatedAt": "2026-07-27T12:00:00.000Z",
          "expectedEpoch": 0,
        ]
      )
    ) {
      XCTAssertEqual(
        $0 as? KeyboardContextBridgeError,
        .staleConsentEpoch
      )
    }
    XCTAssertTrue(consentStore.writes.isEmpty)
  }

  private func makePayload() throws -> [String: Any] {
    var partner: [String: Any] = [
      "partnerId": "partner-1",
      "displayName": "Candy",
      "confirmedAliases": ["Candy L."],
      "contextStatus": "available",
      "facts": [
        [
          "kind": "user_note",
          "text": "喜歡爬山",
          "updatedAt": "2026-07-27T02:00:00.000Z",
        ],
      ],
      "outcomeStats": [
        "sampleSize": 6,
        "engaged": 3,
        "cold": 1,
        "noReply": 1,
        "negative": 0,
      ],
      "effectiveVoice": [
        "primary": "playful",
        "secondary": "steady",
      ],
      "sourceUpdatedAt": "2026-07-27T03:00:00.000Z",
    ]
    partner["contextRevision"] = try hash(partner)

    let payload: [String: Any] = [
      "schemaVersion": 1,
      "ownerUserId": "user-a",
      "generatedAt": "2026-07-27T04:00:00.000Z",
      "expiresAt": "2026-07-28T04:00:00.000Z",
      "consent": [
        "version": "keyboard_screenshot_ai_202607_v1",
        "acceptedAt": "2026-07-27T03:00:00.000Z",
        "latestScreenshotDetectionEnabled": true,
        "partnerContextSharingEnabled": true,
      ],
      "globalVoice": [
        "primary": "steady",
        "secondary": NSNull(),
        "sourceUpdatedAt": "2026-07-27T03:00:00.000Z",
      ],
      "partners": [partner],
    ]
    return try withTopRevision(payload)
  }

  private func withTopRevision(
    _ value: [String: Any]
  ) throws -> [String: Any] {
    var payload = value
    payload.removeValue(forKey: "revision")
    let revision = try hash(payload)
    payload["revision"] = revision
    return payload
  }

  private func hash(_ value: [String: Any]) throws -> String {
    let canonical = try JSONSerialization.data(
      withJSONObject: value,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return SHA256.hash(data: canonical)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private final class RecordingKeyboardContextStore:
  KeyboardContextStoreWriting
{
  var writes: [KeyboardContextEnvelope] = []
  var removeKeyCalls: [Bool] = []

  func write(_ envelope: KeyboardContextEnvelope) throws {
    writes.append(envelope)
  }

  func purge(removeKey: Bool) throws {
    removeKeyCalls.append(removeKey)
  }
}

private final class RecordingPendingReplayPurger:
  KeyboardPendingReplayIdentityPurging
{
  var calls = 0

  func purgeAll() throws {
    calls += 1
  }
}

private final class RecordingScreenshotConsentReceiptStore:
  KeyboardScreenshotConsentReceiptStoring
{
  var writes: [Data] = []
  var readData: Data?
  var clearCalls = 0
  var epoch = 0

  func currentEpoch() throws -> Int {
    epoch
  }

  func read() throws -> Data? {
    readData
  }

  func write(_ data: Data, expectedEpoch: Int) throws {
    guard expectedEpoch == epoch else {
      throw KeyboardContextBridgeError.staleConsentEpoch
    }
    writes.append(data)
    readData = data
  }

  func invalidateAndClear() throws {
    epoch += 1
    clearCalls += 1
    readData = nil
  }
}

private struct TestScreenshotConsentReceipt: Decodable {
  let ownerUserId: String
  let version: String
  let enabled: Bool
  let acceptedAt: Date
  let updatedAt: Date
}
