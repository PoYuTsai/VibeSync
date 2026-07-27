import CryptoKit
import Flutter
import Foundation
import Photos
import Security

protocol KeyboardContextStoreWriting: AnyObject {
  func write(_ envelope: KeyboardContextEnvelope) throws
  func purge(removeKey: Bool) throws
}

extension KeyboardContextStore: KeyboardContextStoreWriting {}

protocol KeyboardPendingReplayIdentityPurging: AnyObject {
  func purgeAll() throws
}

protocol KeyboardScreenshotConsentReceiptStoring: AnyObject {
  func currentEpoch() throws -> Int
  func read() throws -> Data?
  func write(_ data: Data, expectedEpoch: Int) throws
  func invalidateAndClear() throws
}

final class KeyboardAppGroupScreenshotConsentReceiptStore:
  KeyboardScreenshotConsentReceiptStoring
{
  private static let consentEpochKey =
    "keyboard_screenshot_consent_epoch_v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  convenience init() throws {
    guard let defaults = UserDefaults(
      suiteName: KeyboardSharedConfig.appGroupIdentifier
    ) else {
      throw KeyboardContextBridgeError.appGroupUnavailable
    }
    self.init(defaults: defaults)
  }

  func currentEpoch() throws -> Int {
    max(
      0,
      defaults.integer(
        forKey: Self.consentEpochKey
      )
    )
  }

  func write(_ data: Data, expectedEpoch: Int) throws {
    guard expectedEpoch >= 0,
          try currentEpoch() == expectedEpoch
    else {
      throw KeyboardContextBridgeError.staleConsentEpoch
    }
    defaults.set(
      data,
      forKey: KeyboardSharedConfig.keyboardScreenshotConsentReceipt
    )
  }

  func read() throws -> Data? {
    defaults.data(
      forKey: KeyboardSharedConfig.keyboardScreenshotConsentReceipt
    )
  }

  func invalidateAndClear() throws {
    let epoch = try currentEpoch()
    guard epoch < Int.max else {
      throw KeyboardContextBridgeError.invalidConsentEpoch
    }
    defaults.set(
      epoch + 1,
      forKey: Self.consentEpochKey
    )
    defaults.removeObject(
      forKey: KeyboardSharedConfig.keyboardScreenshotConsentReceipt
    )
  }
}

private struct KeyboardScreenshotConsentReceiptPayload: Codable {
  let ownerUserId: String
  let version: String
  let enabled: Bool
  let acceptedAt: Date
  let updatedAt: Date

  func validate(now: Date) throws {
    let owner = ownerUserId.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !owner.isEmpty,
          owner == ownerUserId,
          version ==
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          enabled,
          acceptedAt <= updatedAt,
          acceptedAt <= now.addingTimeInterval(
            KeyboardSharedConfig.futureClockSkewAllowance
          ),
          updatedAt <= now.addingTimeInterval(
            KeyboardSharedConfig.futureClockSkewAllowance
          )
    else {
      throw KeyboardContextBridgeError.invalidConsentReceipt
    }
  }
}

private struct KeyboardScreenshotConsentReceiptExpectation: Decodable {
  let ownerUserId: String
  let version: String
  let acceptedAt: Date

  func validate(now: Date) throws {
    let owner = ownerUserId.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !owner.isEmpty,
          owner == ownerUserId,
          version ==
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
          acceptedAt <= now.addingTimeInterval(
            KeyboardSharedConfig.futureClockSkewAllowance
          )
    else {
      throw KeyboardContextBridgeError.invalidConsentReceipt
    }
  }
}

enum KeyboardContextBridgeError: Error, Equatable {
  case invalidArguments
  case invalidSchema
  case revisionMismatch
  case invalidPurgeScope
  case invalidConsentReceipt
  case appGroupUnavailable
  case invalidConsentEpoch
  case staleConsentEpoch
  case keychain(OSStatus)
}

final class KeyboardPendingReplayKeychainPurger:
  KeyboardPendingReplayIdentityPurging
{
  private static let accountPrefixes = [
    "pending_",
    "keyboard_assist_pending_",
  ]

  func purgeAll() throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: KeyboardSharedConfig.keychainService,
      kSecAttrAccessGroup: KeyboardSharedConfig.keychainAccessGroup,
      kSecReturnAttributes: true,
      kSecReturnPersistentRef: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return }
    guard status == errSecSuccess,
          let rows = result as? [[String: Any]]
    else {
      throw KeyboardContextBridgeError.keychain(status)
    }

    for row in rows {
      guard let account = row[kSecAttrAccount as String] as? String,
            Self.accountPrefixes.contains(where: account.hasPrefix),
            let persistentRef =
              row[kSecValuePersistentRef as String] as? Data
      else {
        continue
      }
      let deleteStatus = SecItemDelete(
        [
          kSecClass: kSecClassGenericPassword,
          kSecValuePersistentRef: persistentRef,
        ] as CFDictionary
      )
      guard deleteStatus == errSecSuccess ||
              deleteStatus == errSecItemNotFound
      else {
        throw KeyboardContextBridgeError.keychain(deleteStatus)
      }
    }
  }
}

final class KeyboardContextBridgeHandler {
  private let storeProvider: () throws -> KeyboardContextStoreWriting
  private let pendingReplayPurger: KeyboardPendingReplayIdentityPurging
  private let screenshotConsentStoreProvider:
    () throws -> KeyboardScreenshotConsentReceiptStoring
  private let now: () -> Date

  init(
    storeProvider: @escaping () throws -> KeyboardContextStoreWriting = {
      try KeyboardContextStore.live()
    },
    pendingReplayPurger: KeyboardPendingReplayIdentityPurging =
      KeyboardPendingReplayKeychainPurger(),
    screenshotConsentStoreProvider:
      @escaping () throws -> KeyboardScreenshotConsentReceiptStoring = {
        try KeyboardAppGroupScreenshotConsentReceiptStore()
      },
    now: @escaping () -> Date = Date.init
  ) {
    self.storeProvider = storeProvider
    self.pendingReplayPurger = pendingReplayPurger
    self.screenshotConsentStoreProvider =
      screenshotConsentStoreProvider
    self.now = now
  }

  func handle(method: String, arguments: Any?) throws -> Any? {
    switch method {
    case "writeSnapshot":
      let payload = try Self.validatedSnapshotPayload(arguments)
      try Self.verifyRevisions(in: payload)
      let data = try JSONSerialization.data(
        withJSONObject: payload,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      let envelope = try Self.decoder.decode(
        KeyboardContextEnvelope.self,
        from: data
      )
      try storeProvider().write(envelope)
      return ["storedRevision": envelope.revision]

    case "purgeContext":
      let payload = try Self.exactObject(
        arguments,
        keys: ["scope", "purgePendingReplayIdentity"]
      )
      guard let scope = payload["scope"] as? String,
            let purgePending =
              payload["purgePendingReplayIdentity"] as? Bool
      else {
        throw KeyboardContextBridgeError.invalidArguments
      }
      let removeKey: Bool
      switch scope {
      case "logout", "consent_revoked":
        guard !purgePending else {
          throw KeyboardContextBridgeError.invalidPurgeScope
        }
        removeKey = false
      case "account_deletion":
        guard purgePending else {
          throw KeyboardContextBridgeError.invalidPurgeScope
        }
        removeKey = true
      default:
        throw KeyboardContextBridgeError.invalidPurgeScope
      }
      // Delete the owner-bound consent receipt first. Even if encrypted
      // context cleanup later fails, the extension immediately fails closed.
      try screenshotConsentStoreProvider().invalidateAndClear()
      try storeProvider().purge(removeKey: removeKey)
      if purgePending {
        try pendingReplayPurger.purgeAll()
      }
      return nil

    case "writeScreenshotConsentReceipt":
      let payload = try Self.exactObject(
        arguments,
        keys: [
          "ownerUserId",
          "version",
          "enabled",
          "acceptedAt",
          "updatedAt",
          "expectedEpoch",
        ]
      )
      guard let expectedEpoch = payload["expectedEpoch"] as? Int,
            expectedEpoch >= 0
      else {
        throw KeyboardContextBridgeError.invalidConsentEpoch
      }
      var receiptPayload = payload
      receiptPayload.removeValue(forKey: "expectedEpoch")
      let data = try JSONSerialization.data(
        withJSONObject: receiptPayload,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      let receipt = try Self.decoder.decode(
        KeyboardScreenshotConsentReceiptPayload.self,
        from: data
      )
      try receipt.validate(now: now())
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = KeyboardISO8601.encodingStrategy
      let persisted = try encoder.encode(receipt)
      try screenshotConsentStoreProvider().write(
        persisted,
        expectedEpoch: expectedEpoch
      )
      return [
        "storedOwnerUserId": receipt.ownerUserId,
        "storedVersion": receipt.version,
      ]

    case "clearScreenshotConsentReceipt":
      guard arguments == nil else {
        throw KeyboardContextBridgeError.invalidArguments
      }
      try screenshotConsentStoreProvider().invalidateAndClear()
      return nil

    case "beginScreenshotConsentSetup":
      guard arguments == nil else {
        throw KeyboardContextBridgeError.invalidArguments
      }
      return [
        "epoch": try screenshotConsentStoreProvider().currentEpoch(),
      ]

    case "verifyScreenshotConsentReceipt":
      let expectedPayload = try Self.exactObject(
        arguments,
        keys: ["ownerUserId", "version", "acceptedAt"]
      )
      let expectedData = try JSONSerialization.data(
        withJSONObject: expectedPayload,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      let expected = try Self.decoder.decode(
        KeyboardScreenshotConsentReceiptExpectation.self,
        from: expectedData
      )
      try expected.validate(now: now())
      let store = try screenshotConsentStoreProvider()
      guard let storedData = try store.read() else {
        return false
      }
      do {
        let stored = try Self.decoder.decode(
          KeyboardScreenshotConsentReceiptPayload.self,
          from: storedData
        )
        try stored.validate(now: now())
        return stored.ownerUserId == expected.ownerUserId &&
          stored.version == expected.version &&
          stored.acceptedAt == expected.acceptedAt
      } catch {
        // Malformed or future receipts are actively removed so the keyboard
        // cannot keep retrying an invalid cross-process grant.
        try store.invalidateAndClear()
        return false
      }

    default:
      throw KeyboardContextBridgeError.invalidArguments
    }
  }

  private static func validatedSnapshotPayload(
    _ arguments: Any?
  ) throws -> [String: Any] {
    let root = try exactObject(
      arguments,
      keys: [
        "schemaVersion",
        "ownerUserId",
        "revision",
        "generatedAt",
        "expiresAt",
        "consent",
        "globalVoice",
        "partners",
      ]
    )
    _ = try exactObject(
      root["consent"],
      keys: [
        "version",
        "acceptedAt",
        "latestScreenshotDetectionEnabled",
        "partnerContextSharingEnabled",
      ]
    )
    _ = try exactObject(
      root["globalVoice"],
      keys: ["primary", "secondary", "sourceUpdatedAt"]
    )
    guard let partners = root["partners"] as? [Any] else {
      throw KeyboardContextBridgeError.invalidSchema
    }
    for value in partners {
      let partner = try exactObject(
        value,
        keys: [
          "partnerId",
          "displayName",
          "confirmedAliases",
          "contextStatus",
          "facts",
          "outcomeStats",
          "effectiveVoice",
          "contextRevision",
          "sourceUpdatedAt",
        ]
      )
      guard let facts = partner["facts"] as? [Any] else {
        throw KeyboardContextBridgeError.invalidSchema
      }
      for fact in facts {
        _ = try exactObject(
          fact,
          keys: ["kind", "text", "updatedAt"]
        )
      }
      if !(partner["outcomeStats"] is NSNull) {
        _ = try exactObject(
          partner["outcomeStats"],
          keys: ["sampleSize", "engaged", "cold", "noReply", "negative"]
        )
      }
      if !(partner["effectiveVoice"] is NSNull) {
        _ = try exactObject(
          partner["effectiveVoice"],
          keys: ["primary", "secondary"]
        )
      }
    }
    return root
  }

  private static func exactObject(
    _ value: Any?,
    keys: Set<String>
  ) throws -> [String: Any] {
    guard let object = value as? [String: Any],
          Set(object.keys) == keys
    else {
      throw KeyboardContextBridgeError.invalidSchema
    }
    return object
  }

  private static func verifyRevisions(
    in payload: [String: Any]
  ) throws {
    guard let claimed = payload["revision"] as? String else {
      throw KeyboardContextBridgeError.invalidSchema
    }
    var revisionPayload = payload
    revisionPayload.removeValue(forKey: "revision")
    guard try canonicalHash(revisionPayload) == claimed else {
      throw KeyboardContextBridgeError.revisionMismatch
    }

    guard let partners = payload["partners"] as? [[String: Any]] else {
      throw KeyboardContextBridgeError.invalidSchema
    }
    for partner in partners {
      guard let partnerClaim = partner["contextRevision"] as? String else {
        throw KeyboardContextBridgeError.invalidSchema
      }
      var partnerPayload = partner
      partnerPayload.removeValue(forKey: "contextRevision")
      guard try canonicalHash(partnerPayload) == partnerClaim else {
        throw KeyboardContextBridgeError.revisionMismatch
      }
    }
  }

  private static func canonicalHash(
    _ payload: [String: Any]
  ) throws -> String {
    let canonical = try JSONSerialization.data(
      withJSONObject: payload,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return SHA256.hash(data: canonical)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      if let date = fractionalDateFormatter.date(from: raw) ??
        internetDateFormatter.date(from: raw)
      {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date"
      )
    }
    return decoder
  }()

  private static let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds,
    ]
    return formatter
  }()

  private static let internetDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}

final class KeyboardContextBridge {
  static let channelName = "vibesync/keyboard_context"

  private let channel: FlutterMethodChannel
  private let handler: KeyboardContextBridgeHandler

  init(
    binaryMessenger: FlutterBinaryMessenger,
    handler: KeyboardContextBridgeHandler = KeyboardContextBridgeHandler()
  ) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    self.handler = handler
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "keyboard_context_unavailable",
            message: "Keyboard context bridge is unavailable.",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "writeSnapshot",
           "purgeContext",
           "writeScreenshotConsentReceipt",
           "clearScreenshotConsentReceipt",
           "beginScreenshotConsentSetup",
           "verifyScreenshotConsentReceipt":
        do {
          result(
            try self.handler.handle(
              method: call.method,
              arguments: call.arguments
            )
          )
        } catch {
          result(
            FlutterError(
              code: "keyboard_context_failed",
              message: "Unable to update encrypted keyboard context.",
              details: nil
            )
          )
        }
      case "requestPhotoAuthorization":
        guard call.arguments == nil else {
          result(
            FlutterError(
              code: "keyboard_photo_invalid_arguments",
              message: "Photo authorization does not accept arguments.",
              details: nil
            )
          )
          return
        }
        Self.requestPhotoAuthorization(result: result)
      case "currentPhotoAuthorization":
        guard call.arguments == nil else {
          result(
            FlutterError(
              code: "keyboard_photo_invalid_arguments",
              message: "Photo authorization does not accept arguments.",
              details: nil
            )
          )
          return
        }
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
          status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
          status = PHPhotoLibrary.authorizationStatus()
        }
        result(Self.photoAuthorizationWire(status))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func photoAuthorizationWire(
    _ status: PHAuthorizationStatus
  ) -> String {
    if #available(iOS 14, *), status == .limited {
      return "limited"
    }
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "not_determined"
    default:
      return "restricted"
    }
  }

  private static func requestPhotoAuthorization(
    result: @escaping FlutterResult
  ) {
    let finish: (PHAuthorizationStatus) -> Void = { status in
      DispatchQueue.main.async {
        result(Self.photoAuthorizationWire(status))
      }
    }
    if #available(iOS 14, *) {
      let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      guard current == .notDetermined else {
        finish(current)
        return
      }
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        finish(status)
      }
    } else {
      let current = PHPhotoLibrary.authorizationStatus()
      guard current == .notDetermined else {
        finish(current)
        return
      }
      PHPhotoLibrary.requestAuthorization { status in
        finish(status)
      }
    }
  }
}
