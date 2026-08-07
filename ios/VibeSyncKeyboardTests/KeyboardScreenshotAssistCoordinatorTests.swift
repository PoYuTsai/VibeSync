import UIKit
import XCTest

final class KeyboardScreenshotAssistCoordinatorTests: XCTestCase {
    func testConsentReceiptIsOwnerBoundAndDoesNotInventADailyTTL() {
        let now = Date()
        let oldButStillConsented = KeyboardScreenshotConsentReceipt(
            ownerUserId: "owner-a",
            version:
                KeyboardSharedConfig.keyboardScreenshotConsentVersion,
            enabled: true,
            acceptedAt: now.addingTimeInterval(-31_536_000),
            updatedAt: now.addingTimeInterval(-31_536_000)
        )
        let future = KeyboardScreenshotConsentReceipt(
            ownerUserId: "owner-a",
            version:
                KeyboardSharedConfig.keyboardScreenshotConsentVersion,
            enabled: true,
            acceptedAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(1)
        )

        XCTAssertTrue(
            oldButStillConsented.isUsable(
                ownerUserId: "owner-a",
                now: now
            )
        )
        XCTAssertFalse(
            oldButStillConsented.isUsable(
                ownerUserId: "owner-b",
                now: now
            )
        )
        XCTAssertFalse(
            future.isUsable(ownerUserId: "owner-a", now: now)
        )
    }

    func testPhotoLibraryIsUntouchedUntilAuthenticatedCapabilitySucceeds() {
        let harness = ScreenshotAssistHarness()

        harness.coordinator.start(hasFullAccess: true)

        XCTAssertEqual(harness.network.capabilityFetchCount, 1)
        XCTAssertEqual(harness.screenshots.fetchCount, 0)
        XCTAssertEqual(harness.contextReadCount, 0)
        XCTAssertEqual(harness.consents.readCount, 0)

        harness.network.completeCapability(.success(harness.capability))

        XCTAssertGreaterThanOrEqual(harness.consents.readCount, 1)
        XCTAssertEqual(harness.contextReadCount, 1)
        XCTAssertEqual(harness.screenshots.fetchCount, 1)
        guard case .screenshotDetected =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Expected a detected screenshot")
        }
    }

    func testPendingRecoveryCompletesBeforeFirstPhotoLibraryRead() {
        let harness = ScreenshotAssistHarness()
        harness.network.automaticallyCompleteRecovery = false

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        XCTAssertEqual(harness.network.recoveryDocumentIdentifiers, [
            harness.documentIdentifier,
        ])
        XCTAssertEqual(harness.screenshots.fetchCount, 0)
        XCTAssertEqual(harness.screenshots.exactFetchCount, 0)

        harness.network.completeRecovery(
            .failure(.noPendingReplay)
        )

        XCTAssertEqual(harness.screenshots.fetchCount, 1)
    }

    func testPendingRecoveryRetryRepeatsBoundGetWithoutPhotoOrPost() {
        let harness = ScreenshotAssistHarness()
        harness.network.automaticRecoveryResult =
            .failure(.requestPending(retryAfterMs: 500))

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))
        harness.coordinator.retryFailedRequest()
        harness.network.completeCapability(.success(harness.capability))

        XCTAssertEqual(harness.network.recoveryDocumentIdentifiers, [
            harness.documentIdentifier,
            harness.documentIdentifier,
        ])
        XCTAssertEqual(harness.screenshots.fetchCount, 0)
        XCTAssertEqual(harness.screenshots.exactFetchCount, 0)
        XCTAssertTrue(harness.network.submissions.isEmpty)
    }

    func testDetectionAndPreviewNeverSubmitUntilExplicitConfirmation() {
        let harness = ScreenshotAssistHarness()
        harness.reachDetectedScreenshot()

        XCTAssertEqual(harness.network.submissions.count, 0)
        harness.coordinator.requestLocalPreview()
        XCTAssertEqual(harness.network.submissions.count, 0)

        harness.coordinator.confirmPreviewAndGenerate()

        XCTAssertEqual(harness.screenshots.fetchCount, 2)
        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertEqual(
            harness.network.submissions[0].request.speakerOverride,
            .none
        )
        XCTAssertEqual(
            harness.network.submissions[0].authorization
                .binding.contextRevision,
            harness.context.revision
        )
    }

    func testDisabledCapabilityNeverReadsContextOrPhotos() {
        let harness = ScreenshotAssistHarness()
        let disabled = KeyboardAssistCapabilityReceipt(
            contractVersion: .v1,
            ownerUserId: harness.ownerUserID,
            enabled: false,
            pipelineVersion: "compiler-judge-v1",
            receivedAt: harness.now,
            expiresAt: harness.now.addingTimeInterval(300)
        )

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(disabled))

        XCTAssertEqual(harness.contextReadCount, 0)
        XCTAssertEqual(harness.consents.readCount, 0)
        XCTAssertEqual(harness.screenshots.fetchCount, 0)
        XCTAssertEqual(
            harness.coordinator.stateMachine.state,
            .featureUnavailable
        )
    }

    func testConsentRevokedWhilePreviewingPreventsAnotherPhotoRead() {
        let harness = ScreenshotAssistHarness()
        harness.reachDetectedScreenshot()
        harness.coordinator.requestLocalPreview()
        harness.consents.resultProvider = { nil }

        harness.coordinator.confirmPreviewAndGenerate()

        XCTAssertEqual(harness.screenshots.fetchCount, 1)
        XCTAssertEqual(harness.network.submissions.count, 0)
        XCTAssertEqual(harness.coordinator.stateMachine.state, .idle)
    }

    func testMissingContextStillUsesStrictScreenshotOnlyRequest() {
        let harness = ScreenshotAssistHarness()
        harness.contextAvailable = false

        harness.reachSubmittedRequest()

        let submission = harness.network.submissions[0]
        XCTAssertNil(submission.request.voice.primary)
        XCTAssertNil(submission.request.voice.secondary)
        XCTAssertNil(submission.authorization.binding.partnerID)
        XCTAssertNil(submission.authorization.binding.contextRevision)
    }

    func testTransportUncertaintyOnlyLooksUpTheSameRequest() {
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let requestID = harness.network.submissions[0].request.requestId

        harness.network.completeSubmission(
            at: 0,
            with: .failure(.transportUncertain)
        )

        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertEqual(harness.network.lookupRequestIDs, [requestID])
        guard case .lookingUpStatus(let binding) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Expected same-request status lookup")
        }
        XCTAssertEqual(binding.requestID, requestID)

        harness.network.completeLookup(
            at: 0,
            with: .success(.ready(harness.ready(requestID: requestID)))
        )
        guard case .resultsPreview =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("GET should recover the settled result")
        }
        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertEqual(harness.network.clearedRequestIDs, [])
    }

    func testReadyResponseNeverInsertsUntilCandidateTap() {
        let harness = ScreenshotAssistHarness()
        harness.reachResults()
        let requestID = harness.network.submissions[0].request.requestId

        XCTAssertEqual(harness.inserter.insertions.count, 0)
        XCTAssertEqual(harness.network.clearedRequestIDs, [])
        let candidateID = harness.ready(
            requestID:
                harness.network.submissions[0].request.requestId
        ).options[0].candidateID

        harness.coordinator.insertCandidate(candidateID: candidateID)

        XCTAssertEqual(harness.inserter.insertions, [candidateID])
        guard case .inserted(let insertedID) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Explicit tap should insert exactly once")
        }
        XCTAssertEqual(insertedID, candidateID)
        XCTAssertEqual(harness.network.clearedRequestIDs, [requestID])

        harness.coordinator.insertCandidate(candidateID: candidateID)
        XCTAssertEqual(harness.inserter.insertions, [candidateID])
        XCTAssertEqual(harness.network.clearedRequestIDs, [requestID])
    }

    func testFreshInsertionHashMismatchNeverInsertsAndClearsUnsafePending() {
        let harness = ScreenshotAssistHarness()
        harness.reachResults()
        let requestID = harness.network.submissions[0].request.requestId
        harness.preprocessor.sha256 = String(repeating: "c", count: 64)
        let candidateID = harness.ready(
            requestID: requestID
        ).options[0].candidateID

        harness.coordinator.insertCandidate(candidateID: candidateID)

        XCTAssertTrue(harness.inserter.insertions.isEmpty)
        XCTAssertEqual(harness.network.clearedRequestIDs, [requestID])
        XCTAssertEqual(harness.screenshots.exactFetchCount, 1)
    }

    func testInsertionStopsBeforeInsertTextWhenPendingCleanupFails() {
        let harness = ScreenshotAssistHarness()
        harness.reachResults()
        let requestID = harness.network.submissions[0].request.requestId
        harness.network.clearPendingError = .pendingReplayUnavailable
        let candidateID = harness.ready(
            requestID: requestID
        ).options[0].candidateID

        harness.coordinator.insertCandidate(candidateID: candidateID)

        XCTAssertTrue(harness.inserter.insertions.isEmpty)
        XCTAssertTrue(harness.network.clearedRequestIDs.isEmpty)
        XCTAssertTrue(
            harness.network.events.contains(
                "clear:\(requestID.uuidString)"
            )
        )
        XCTAssertTrue(harness.messages.last?.contains("尚未插入") == true)
        guard case .resultsPreview =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("The visible card should remain retryable")
        }
    }

    func testCancelKeepsSameRequestForLookupAndNeverCreatesAnotherPost() {
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let requestID = harness.network.submissions[0].request.requestId

        harness.coordinator.cancel()
        harness.coordinator.retryFailedRequest()

        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertEqual(harness.network.lookupRequestIDs, [requestID])
    }

    func testSecondCancelWhileAlreadyStoppedFullyDismissesInsteadOfNoOp() {
        // 第一次 cancel 進「已停止等待」畫面；outbound 保留給「查詢同一筆
        // 結果」用。第二次按 X 是使用者要整個關掉——2026-08-06 dogfood 回
        // 饋：這裡以前會重繪一模一樣的畫面，看起來像 X 沒反應。
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let requestID = harness.network.submissions[0].request.requestId

        harness.coordinator.cancel()
        guard case .failed(let binding, .lookupSameRequest) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("First cancel should enter the stopped state")
        }
        XCTAssertEqual(binding?.requestID, requestID)

        harness.coordinator.cancel()
        if case .failed = harness.coordinator.stateMachine.state {
            XCTFail("Second cancel while already stopped must not re-enter .failed")
        }
        XCTAssertEqual(harness.messages.last, "本次截圖未送出。")

        harness.coordinator.retryFailedRequest()
        XCTAssertEqual(
            harness.network.lookupRequestIDs,
            [],
            "outbound should be cleared, so retry has nothing to look up"
        )
    }

    func testCancelFromResultsReturnsToArmedIdleAndNewScreenshotRestarts() {
        // 2026-08-07 Bruce 真機：分析完按 X，同畫面連截兩張都沒反應。
        // 結果頁的 X＝「收起結果、回待命」——不可掉進「已停止等待」
        // （該狀態被新截圖偵測白名單擋掉），也不可清 capability（清了
        // libraryDidChange 的 guard 永遠失敗，直到鍵盤重開都是死的）。
        let harness = ScreenshotAssistHarness()
        harness.reachResults()
        // ready 的重放標記刻意留到「插入」才清，所以此刻 durable store
        // 裡還有這一筆可回收的舊結果——收起後的新截圖絕不能被它綁架。
        let firstRequestID = harness.network.submissions[0].request.requestId
        harness.network.automaticRecoveryResult = .success(
            KeyboardAssistRecoveredPending(
                metadata: harness.pendingMetadata(requestID: firstRequestID),
                response: .ready(harness.ready(requestID: firstRequestID))
            )
        )

        harness.coordinator.cancel()

        XCTAssertEqual(
            harness.coordinator.stateMachine.state,
            .idle,
            "cancel from results must re-arm idle, not enter the stopped state"
        )
        XCTAssertEqual(
            harness.network.clearedRequestIDs,
            [firstRequestID],
            "deliberate dismissal must void the ready replay marker"
        )

        harness.now = harness.now.addingTimeInterval(5)
        harness.screenshot = LatestScreenshot(
            assetIdentifier: "asset-b",
            creationDate: harness.now.addingTimeInterval(-1),
            thumbnail: UIImage()
        )
        harness.coordinator.libraryDidChange(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .screenshotDetected(let summary) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail(
                "a new screenshot after dismissing results must restart detection"
            )
        }
        XCTAssertEqual(summary.assetIdentifier, "asset-b")

        harness.coordinator.requestLocalPreview()
        harness.coordinator.confirmPreviewAndGenerate()
        XCTAssertEqual(harness.network.submissions.count, 2)
        XCTAssertNotEqual(
            harness.network.submissions[0].request.requestId,
            harness.network.submissions[1].request.requestId,
            "the new run must be a fresh request, not a replay of the old one"
        )
    }

    func testStoppedWaitingAllowsNewScreenshotToStartFreshRun() {
        // 分析中按 X＝停止等待（保 requestId 供查詢、不重複送出），但新
        // 截圖必須能開新一輪：狀態白名單要放行，且已取消請求的重放標記
        // 要作廢，否則 recoverLatestPending 會把舊請求撿回來蓋掉新截圖。
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let cancelledRequestID =
            harness.network.submissions[0].request.requestId

        harness.coordinator.cancel()
        guard case .failed(_, .lookupSameRequest) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("cancel mid-flight should enter the stopped state")
        }
        XCTAssertEqual(
            harness.network.clearedRequestIDs,
            [cancelledRequestID],
            "an abandoned request must not hijack the next run via pending replay"
        )

        harness.now = harness.now.addingTimeInterval(5)
        harness.screenshot = LatestScreenshot(
            assetIdentifier: "asset-b",
            creationDate: harness.now.addingTimeInterval(-1),
            thumbnail: UIImage()
        )
        harness.coordinator.libraryDidChange(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .screenshotDetected(let summary) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("stopped-waiting must still pick up a new screenshot")
        }
        XCTAssertEqual(summary.assetIdentifier, "asset-b")
    }

    func testPreviewTapTimestampIsNotResetAfterPreprocessing() {
        let harness = ScreenshotAssistHarness()
        harness.reachDetectedScreenshot()
        harness.coordinator.requestLocalPreview()
        let tappedAt = harness.now
        harness.preprocessingScheduler = { work in
            harness.now = tappedAt.addingTimeInterval(60)
            work()
        }

        harness.coordinator.confirmPreviewAndGenerate()

        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertEqual(
            harness.network.submissions[0].authorization.previewConfirmedAt,
            tappedAt
        )
    }

    func testExpiredPreviewTapFailsClosedBeforePost() {
        let harness = ScreenshotAssistHarness()
        harness.reachDetectedScreenshot()
        harness.coordinator.requestLocalPreview()
        let tappedAt = harness.now
        harness.preprocessingScheduler = { work in
            harness.now = tappedAt.addingTimeInterval(
                KeyboardSharedConfig.resultsPresentationTTL + 1
            )
            work()
        }

        harness.coordinator.confirmPreviewAndGenerate()

        XCTAssertTrue(harness.network.submissions.isEmpty)
        guard case .failed(nil, .terminal) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Expired tap must fail closed locally")
        }
    }

    func testStartupRecoveryRebindsExactDocumentAssetAndHashWithoutPost() {
        let harness = ScreenshotAssistHarness()
        let requestID = UUID()
        harness.network.automaticRecoveryResult = .success(
            KeyboardAssistRecoveredPending(
                metadata: harness.pendingMetadata(requestID: requestID),
                response: .ready(harness.ready(requestID: requestID))
            )
        )

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .resultsPreview(let presentation) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Expected recovered ready result")
        }
        XCTAssertEqual(presentation.binding.requestID, requestID)
        XCTAssertEqual(
            presentation.binding.documentIdentifier,
            harness.documentIdentifier
        )
        XCTAssertEqual(harness.network.submissions.count, 0)
        XCTAssertEqual(harness.screenshots.fetchCount, 0)
        XCTAssertEqual(harness.screenshots.exactFetchCount, 1)
        XCTAssertTrue(harness.network.clearedRequestIDs.isEmpty)
    }

    func testOldRecoveredResultNeverGetsANewInsertionWindow() {
        let harness = ScreenshotAssistHarness()
        let requestID = UUID()
        let oldCreatedAt = harness.now.addingTimeInterval(
            -KeyboardSharedConfig.resultsPresentationTTL - 1
        )
        harness.network.automaticRecoveryResult = .success(
            KeyboardAssistRecoveredPending(
                metadata: harness.pendingMetadata(
                    requestID: requestID,
                    createdAt: oldCreatedAt
                ),
                response: .ready(harness.ready(requestID: requestID))
            )
        )

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .failed(nil, .newRequestAfterUserChange) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Old result must not be presented as insertable")
        }
        XCTAssertTrue(harness.inserter.insertions.isEmpty)
        XCTAssertEqual(harness.screenshots.exactFetchCount, 0)
        XCTAssertEqual(harness.network.clearedRequestIDs, [requestID])
    }

    func testRecoveredMetadataForAnotherDocumentIsPreservedButNeverShown() {
        let harness = ScreenshotAssistHarness()
        let requestID = UUID()
        harness.network.automaticRecoveryResult = .success(
            KeyboardAssistRecoveredPending(
                metadata: harness.pendingMetadata(
                    requestID: requestID,
                    documentIdentifier: UUID()
                ),
                response: .ready(harness.ready(requestID: requestID))
            )
        )

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .failed(nil, .terminal) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Cross-document metadata must fail closed")
        }
        XCTAssertEqual(harness.screenshots.exactFetchCount, 0)
        XCTAssertTrue(harness.network.clearedRequestIDs.isEmpty)
        XCTAssertTrue(harness.inserter.insertions.isEmpty)
    }

    func testRecoveredHashMismatchClearsUnsafePendingAndNeverShowsResult() {
        let harness = ScreenshotAssistHarness()
        let requestID = UUID()
        harness.network.automaticRecoveryResult = .success(
            KeyboardAssistRecoveredPending(
                metadata: harness.pendingMetadata(
                    requestID: requestID,
                    imageSHA256: String(repeating: "c", count: 64)
                ),
                response: .ready(harness.ready(requestID: requestID))
            )
        )

        harness.coordinator.start(hasFullAccess: true)
        harness.network.completeCapability(.success(harness.capability))

        guard case .failed(nil, .newRequestAfterUserChange) =
                harness.coordinator.stateMachine.state
        else {
            return XCTFail("Changed screenshot must not show old results")
        }
        XCTAssertEqual(harness.network.clearedRequestIDs, [requestID])
        XCTAssertTrue(harness.inserter.insertions.isEmpty)
    }

    func testDocumentChangeInvalidatesLateNetworkCallback() {
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let requestID = harness.network.submissions[0].request.requestId

        harness.documentIdentifier = UUID()
        harness.coordinator.documentDidChange(
            to: harness.documentIdentifier
        )
        harness.network.completeSubmission(
            at: 0,
            with: .success(.ready(harness.ready(requestID: requestID)))
        )

        XCTAssertEqual(harness.coordinator.stateMachine.state, .idle)
        XCTAssertEqual(harness.inserter.insertions.count, 0)
    }

    func testSpeakerChoiceUsesNewRequestOnlyAfterExplicitSelection() throws {
        let harness = ScreenshotAssistHarness()
        harness.reachSubmittedRequest()
        let firstRequestID =
            harness.network.submissions[0].request.requestId
        harness.network.completeSubmission(
            at: 0,
            with: .success(
                .needsSpeakerConfirmation(
                    KeyboardAssistSpeakerConfirmationResponse(
                        contractVersion: .v1,
                        requestId: firstRequestID,
                        suggestedMySide: .right,
                        sideConfidence: .low
                    )
                )
            )
        )

        XCTAssertEqual(harness.network.submissions.count, 1)
        XCTAssertTrue(harness.network.clearedRequestIDs.isEmpty)
        harness.coordinator.chooseSpeakerSide(.right)

        XCTAssertEqual(harness.screenshots.fetchCount, 3)
        XCTAssertEqual(harness.network.submissions.count, 2)
        XCTAssertNotEqual(
            harness.network.submissions[1].request.requestId,
            firstRequestID
        )
        XCTAssertEqual(
            harness.network.submissions[1].request.speakerOverride,
            .rightIsMe
        )
        XCTAssertEqual(harness.network.clearedRequestIDs, [firstRequestID])
        let clearEvent = harness.network.events.firstIndex(
            of: "clear:\(firstRequestID.uuidString)"
        )
        let secondSubmitEvent = harness.network.events.firstIndex(
            of:
                "submit:\(harness.network.submissions[1].request.requestId.uuidString)"
        )
        XCTAssertNotNil(clearEvent)
        XCTAssertNotNil(secondSubmitEvent)
        let clearIndex = try XCTUnwrap(clearEvent)
        let secondSubmitIndex = try XCTUnwrap(secondSubmitEvent)
        XCTAssertLessThan(clearIndex, secondSubmitIndex)
    }
}

private final class ScreenshotAssistHarness {
    var now = Date()
    let ownerUserID = "owner-a"
    let network = RecordingScreenshotAssistNetwork()
    let screenshots = RecordingScreenshotProvider()
    let preprocessor = StubScreenshotPreprocessor()
    let inserter = RecordingScreenshotInserter()
    let consents = RecordingScreenshotConsentProvider()
    var documentIdentifier = UUID()
    var contextReadCount = 0
    var contextAvailable = true
    var preprocessingScheduler: (() -> Void) -> Void = {
        work in work()
    }
    var renders: [KeyboardAssistState] = []
    var messages: [String?] = []

    lazy var session = KeyboardAuthSession(
        accessToken: "token",
        userId: ownerUserID,
        expiresAt: now.addingTimeInterval(3_600)
    )
    lazy var capability = KeyboardAssistCapabilityReceipt(
        contractVersion: .v1,
        ownerUserId: ownerUserID,
        enabled: true,
        pipelineVersion: "compiler-judge-v1",
        receivedAt: now,
        expiresAt: now.addingTimeInterval(300)
    )
    lazy var consent = KeyboardScreenshotConsentReceipt(
        ownerUserId: ownerUserID,
        version:
            KeyboardSharedConfig.keyboardScreenshotConsentVersion,
        enabled: true,
        acceptedAt: now.addingTimeInterval(-60),
        updatedAt: now.addingTimeInterval(-60)
    )
    lazy var context = KeyboardContextEnvelope(
        schemaVersion: 1,
        ownerUserId: ownerUserID,
        revision: String(repeating: "a", count: 64),
        generatedAt: now.addingTimeInterval(-10),
        expiresAt: now.addingTimeInterval(3_600),
        consent: KeyboardContextConsent(
            version:
                KeyboardSharedConfig.keyboardScreenshotConsentVersion,
            acceptedAt: now.addingTimeInterval(-60),
            latestScreenshotDetectionEnabled: true,
            partnerContextSharingEnabled: false
        ),
        globalVoice: KeyboardVoice(
            primary: .steady,
            secondary: .playful,
            sourceUpdatedAt: now.addingTimeInterval(-60)
        ),
        partners: []
    )
    lazy var screenshot = LatestScreenshot(
        assetIdentifier: "asset-a",
        creationDate: now.addingTimeInterval(-5),
        thumbnail: UIImage()
    )
    lazy var coordinator = KeyboardScreenshotAssistCoordinator(
        network: network,
        screenshotProvider: screenshots,
        preprocessor: preprocessor,
        insertionCoordinator: inserter,
        consentProvider: consents,
        sessionProvider: { [unowned self] in self.session },
        contextProvider: { [unowned self] owner in
            self.contextReadCount += 1
            XCTAssertEqual(owner, self.ownerUserID)
            return self.contextAvailable ? self.context : nil
        },
        documentProvider: {
            [unowned self] in self.documentIdentifier
        },
        now: { [unowned self] in self.now },
        schedulePreprocessing: { [unowned self] work in
            self.preprocessingScheduler(work)
        },
        deliverToMain: { work in work() },
        onRender: { [unowned self] render in
            self.renders.append(render.state)
            self.messages.append(render.message)
        }
    )

    init() {
        consents.resultProvider = { [unowned self] in
            self.consent
        }
        screenshots.resultProvider = { [unowned self] in
            .success(self.screenshot)
        }
    }

    func reachDetectedScreenshot() {
        coordinator.start(hasFullAccess: true)
        network.completeCapability(.success(capability))
    }

    func reachSubmittedRequest() {
        reachDetectedScreenshot()
        coordinator.requestLocalPreview()
        coordinator.confirmPreviewAndGenerate()
    }

    func reachResults() {
        reachSubmittedRequest()
        let requestID = network.submissions[0].request.requestId
        network.completeSubmission(
            at: 0,
            with: .success(.ready(ready(requestID: requestID)))
        )
    }

    func ready(requestID: UUID) -> KeyboardAssistReadyResponse {
        KeyboardAssistReadyResponse(
            contractVersion: .v1,
            requestId: requestID,
            source: KeyboardAssistSource(
                scope: .screenshotOnly,
                messageCount: 4,
                confidence: .high,
                sideConfidence: .high,
                partnerId: nil,
                contextRevision: nil,
                contextUpdatedAt: nil
            ),
            turnState: .replyDue,
            cue: "對方正在延續一個輕鬆話題。",
            uncertainty: nil,
            options: [
                KeyboardAssistOption(
                    strategy: .keepPace,
                    text: "有啊，我也覺得那家很有趣",
                    why: "先自然接住",
                    effect: "維持節奏"
                ),
                KeyboardAssistOption(
                    strategy: .buildConnection,
                    text: "你最喜歡那裡的哪一點？",
                    why: "延伸對方興趣",
                    effect: "增加互動"
                ),
                KeyboardAssistOption(
                    strategy: .moveForward,
                    text: "那改天一起去看看？",
                    why: "把話題變具體",
                    effect: "推進邀約"
                ),
            ]
        )
    }

    func pendingMetadata(
        requestID: UUID,
        createdAt: Date? = nil,
        documentIdentifier: UUID? = nil,
        imageSHA256: String? = nil
    ) -> KeyboardAssistPendingMetadata {
        KeyboardAssistPendingMetadata(
            requestId: requestID,
            ownerUserId: ownerUserID,
            documentIdentifier:
                documentIdentifier ?? self.documentIdentifier,
            assetIdentifier: screenshot.assetIdentifier,
            imageSHA256: imageSHA256 ?? preprocessor.sha256,
            speakerOverride: .none,
            voice: KeyboardAssistVoice(
                primary: context.globalVoice.primary,
                secondary: context.globalVoice.secondary
            ),
            partnerId: nil,
            contextRevision: context.revision,
            createdAt: createdAt ?? now
        )
    }
}

private final class RecordingScreenshotConsentProvider:
    KeyboardScreenshotConsentProviding
{
    var readCount = 0
    var resultProvider: (() -> KeyboardScreenshotConsentReceipt?)!

    func usableConsent(
        ownerUserId _: String,
        now _: Date
    ) -> KeyboardScreenshotConsentReceipt? {
        readCount += 1
        return resultProvider()
    }
}

private final class RecordingScreenshotAssistNetwork:
    KeyboardScreenshotAssistNetworking
{
    struct Submission {
        let request: KeyboardAssistV1Request
        let authorization: KeyboardAssistSendAuthorization
    }

    var capabilityFetchCount = 0
    var submissions: [Submission] = []
    var lookupRequestIDs: [UUID] = []
    var clearedRequestIDs: [UUID] = []
    var recoveryDocumentIdentifiers: [UUID] = []
    var events: [String] = []
    var clearPendingError: Error?
    var automaticallyCompleteRecovery = true
    var automaticRecoveryResult: Result<
        KeyboardAssistRecoveredPending,
        KeyboardAssistAPIError
    > = .failure(.noPendingReplay)
    private var capabilityCompletion: ((
        Result<
            KeyboardAssistCapabilityReceipt,
            KeyboardAssistAPIError
        >
    ) -> Void)?
    private var submissionCompletions: [(
        Result<KeyboardAssistResponse, KeyboardAssistAPIError>
    ) -> Void] = []
    private var lookupCompletions: [(
        Result<KeyboardAssistResponse, KeyboardAssistAPIError>
    ) -> Void] = []
    private var recoveryCompletion: ((
        Result<
            KeyboardAssistRecoveredPending,
            KeyboardAssistAPIError
        >
    ) -> Void)?

    func fetchCapability(
        session _: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        capabilityFetchCount += 1
        capabilityCompletion = completion
        return nil
    }

    func submit(
        _ request: KeyboardAssistV1Request,
        session _: KeyboardAuthSession,
        authorization: KeyboardAssistSendAuthorization,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        events.append("submit:\(request.requestId.uuidString)")
        submissions.append(
            Submission(
                request: request,
                authorization: authorization
            )
        )
        submissionCompletions.append(completion)
        return nil
    }

    func lookup(
        requestID: UUID,
        session _: KeyboardAuthSession,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        lookupRequestIDs.append(requestID)
        lookupCompletions.append(completion)
        return nil
    }

    func recoverLatestPending(
        documentIdentifier: UUID,
        session _: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        recoveryDocumentIdentifiers.append(documentIdentifier)
        recoveryCompletion = completion
        if automaticallyCompleteRecovery {
            completion(automaticRecoveryResult)
        }
        return nil
    }

    func clearPendingAfterPresentation(
        requestID: UUID,
        session _: KeyboardAuthSession
    ) throws {
        events.append("clear:\(requestID.uuidString)")
        if let clearPendingError {
            throw clearPendingError
        }
        clearedRequestIDs.append(requestID)
        // 模擬 durable store 的真實行為：標記清掉之後，同一筆 requestId
        // 不可能再被 recoverLatestPending 撿回來。沒有這行，「收起結果後
        // 新截圖不被舊 pending 綁架」的測試會假綠。
        if case .success(let recovered) = automaticRecoveryResult,
           recovered.metadata.requestId == requestID {
            automaticRecoveryResult = .failure(.noPendingReplay)
        }
    }

    func completeCapability(
        _ result: Result<
            KeyboardAssistCapabilityReceipt,
            KeyboardAssistAPIError
        >
    ) {
        capabilityCompletion?(result)
    }

    func completeSubmission(
        at index: Int,
        with result: Result<
            KeyboardAssistResponse,
            KeyboardAssistAPIError
        >
    ) {
        submissionCompletions[index](result)
    }

    func completeLookup(
        at index: Int,
        with result: Result<
            KeyboardAssistResponse,
            KeyboardAssistAPIError
        >
    ) {
        lookupCompletions[index](result)
    }

    func completeRecovery(
        _ result: Result<
            KeyboardAssistRecoveredPending,
            KeyboardAssistAPIError
        >
    ) {
        recoveryCompletion?(result)
    }
}

private final class RecordingScreenshotProvider:
    KeyboardScreenshotProviding
{
    var fetchCount = 0
    var exactFetchCount = 0
    var resultProvider: (() -> Result<
        LatestScreenshot,
        LatestScreenshotError
    >)!

    private(set) var sessionFloorIgnoredOnEachFetch: [Bool] = []

    func fetchLatest(
        capability _: KeyboardAssistCapabilityReceipt?,
        ownerUserId _: String,
        userAuthorizedDetection _: Bool,
        ignoringSessionFloor: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    ) {
        fetchCount += 1
        sessionFloorIgnoredOnEachFetch.append(ignoringSessionFloor)
        completion(resultProvider())
    }

    func fetch(
        assetIdentifier: String,
        capability _: KeyboardAssistCapabilityReceipt?,
        ownerUserId _: String,
        userAuthorizedDetection _: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    ) {
        exactFetchCount += 1
        let result = resultProvider()
        guard case .success(let screenshot) = result,
              screenshot.assetIdentifier == assetIdentifier
        else {
            completion(.failure(.noRecentScreenshot))
            return
        }
        completion(.success(screenshot))
    }
}

private final class StubScreenshotPreprocessor:
    KeyboardScreenshotPreprocessing
{
    var sha256 = String(repeating: "b", count: 64)

    func prepare(_: UIImage) throws -> KeyboardPreparedImage {
        KeyboardPreparedImage(
            jpegData: Data([0xff, 0xd8, 0xff, 0xd9]),
            sha256: sha256,
            pixelWidth: 320,
            pixelHeight: 640
        )
    }
}

private final class RecordingScreenshotInserter:
    KeyboardScreenshotCandidateInserting
{
    var insertions: [String] = []

    func insert(
        option: KeyboardAssistOption,
        presentation _: KeyboardResultsPresentation,
        context _: KeyboardInsertionContext
    ) throws -> KeyboardInsertionOutcome {
        insertions.append(option.candidateID)
        return .inserted
    }
}
