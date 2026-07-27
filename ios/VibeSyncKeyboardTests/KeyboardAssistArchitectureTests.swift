import XCTest

final class KeyboardAssistArchitectureTests: XCTestCase {
    func testTransportCannotReachTextDocumentProxyOrInsertionCoordinator() throws {
        let source = try sourceFile(named: "KeyboardAssistAPI.swift")

        XCTAssertFalse(source.contains("textDocumentProxy"))
        XCTAssertFalse(source.contains("ReplyInsertionCoordinator"))
        XCTAssertFalse(source.contains(".insertText("))
    }

    func testLegacyNetworkCallbackOnlyPresentsTapTarget() throws {
        let source = try sourceFile(named: "KeyboardViewController.swift")
        let callbackStart = try XCTUnwrap(
            source.range(of: "api.generate(message:")
        )
        let tapHandlerStart = try XCTUnwrap(
            source.range(
                of: "@objc private func insertGeneratedReply",
                range: callbackStart.lowerBound..<source.endIndex
            )
        )
        let callback = source[
            callbackStart.lowerBound..<tapHandlerStart.lowerBound
        ]

        XCTAssertFalse(callback.contains("textDocumentProxy.insertText"))
        XCTAssertTrue(callback.contains("resultButton.isHidden = false"))
    }

    private func sourceFile(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return try String(
            contentsOf: testFile
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("VibeSyncKeyboard/\(name)"),
            encoding: .utf8
        )
    }

    func testScreenshotCapabilityDefaultsOffAndIgnoresLegacyBool() {
        let suite = "keyboard-feature-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(
            true,
            forKey: "keyboard_screenshot_assist_enabled"
        )
        let store = KeyboardAssistCapabilityStore(defaults: defaults)

        XCTAssertFalse(
            store.usableReceipt(
                ownerUserId: "owner-a",
                now: Date()
            ) != nil
        )
    }

    func testInsertionCoordinatorCannotReopenAnOperation() throws {
        let source = try sourceFile(named: "ReplyInsertionCoordinator.swift")

        XCTAssertFalse(source.contains("func reset("))
    }

    func testLegacyInvalidationCannotLeaveKeyboardGeneratingForever() throws {
        let source = try sourceFile(named: "KeyboardViewController.swift")
        let start = try XCTUnwrap(
            source.range(of: "private func invalidatePendingReply()")
        )
        let end = try XCTUnwrap(
            source.range(
                of: "private func updatePreferredHeight()",
                range: start.lowerBound..<source.endIndex
            )
        )
        let invalidation = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(invalidation.contains("isGenerating = false"))
        XCTAssertTrue(invalidation.contains("activeLegacyOperationID = nil"))
    }
}

extension KeyboardAssistReadyResponse {
    static func fixture(requestID: UUID) -> KeyboardAssistReadyResponse {
        KeyboardAssistReadyResponse(
            contractVersion: .v1,
            requestId: requestID,
            source: KeyboardAssistSource(
                scope: .screenshotOnly,
                messageCount: 3,
                confidence: .high,
                sideConfidence: .high,
                partnerId: nil,
                contextRevision: nil,
                contextUpdatedAt: nil
            ),
            turnState: .replyDue,
            cue: "對方剛問了一個具體問題。",
            uncertainty: nil,
            options: [
                KeyboardAssistOption(
                    strategy: .keepPace,
                    text: "可以呀",
                    why: "自然接住",
                    effect: "低壓"
                ),
                KeyboardAssistOption(
                    strategy: .buildConnection,
                    text: "聽起來不錯，你最期待哪一段？",
                    why: "延伸共同感",
                    effect: "增加互動"
                ),
                KeyboardAssistOption(
                    strategy: .moveForward,
                    text: "那週六下午如何？",
                    why: "把話題變具體",
                    effect: "向安排推進"
                ),
            ]
        )
    }
}
