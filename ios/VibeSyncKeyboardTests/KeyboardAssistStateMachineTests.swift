import XCTest

final class KeyboardAssistStateMachineTests: XCTestCase {
    func testGenerationRequiresMatchingConfirmedPreviewOrExactRetry() {
        let binding = KeyboardRequestBinding.fixture()
        let summary = KeyboardScreenshotSummary(
            assetIdentifier: binding.assetIdentifier,
            creationDate: binding.createdAt
        )
        var machine = KeyboardAssistStateMachine(state: .idle)

        machine.send(.generationStarted(binding))
        XCTAssertEqual(machine.state, .idle)

        machine = KeyboardAssistStateMachine(state: .localPreview(summary))
        machine.send(.generationStarted(binding))
        XCTAssertEqual(machine.state, .preparing(binding))

        machine = KeyboardAssistStateMachine(
            state: .failed(binding, .retrySamePayload)
        )
        machine.send(.generationStarted(binding))
        XCTAssertEqual(machine.state, .preparing(binding))
    }

    func testLatePreflightCannotOverwriteActiveOrTerminalState() {
        let binding = KeyboardRequestBinding.fixture()
        let preflight = KeyboardAssistPreflight(
            hasFullAccess: false,
            hasSession: false,
            hasCapability: false,
            hasConsent: false,
            photoAuthorization: .denied
        )
        for state in [
            KeyboardAssistState.generating(binding, .readingChat),
            .resultsPreview(
                KeyboardResultsPresentation(
                    binding: binding,
                    options: KeyboardAssistReadyResponse
                        .fixture(requestID: binding.requestID)
                        .options,
                    presentedAt: Date()
                )
            ),
        ] {
            var machine = KeyboardAssistStateMachine(state: state)
            machine.send(.preflightCompleted(preflight))
            XCTAssertEqual(machine.state, state)
        }
    }

    func testSuccessCallbackOnlyRendersResultsAndNeverRepresentsInsertion() throws {
        let binding = KeyboardRequestBinding.fixture()
        let response = KeyboardAssistResponse.ready(
            KeyboardAssistReadyResponse.fixture(requestID: binding.requestID)
        )
        var machine = KeyboardAssistStateMachine(state: .preparing(binding))

        machine.send(
            .responseReceived(
                operationID: binding.operationID,
                response: response,
                presentedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        guard case .resultsPreview(let presentation) = machine.state else {
            return XCTFail("Success must render a preview")
        }
        XCTAssertEqual(presentation.binding, binding)
        XCTAssertEqual(presentation.options.count, 3)
    }

    func testOutOfOrderCallbackCannotOverwriteNewOperation() {
        let old = KeyboardRequestBinding.fixture()
        let latest = KeyboardRequestBinding.fixture(
            operationID: UUID(),
            requestID: UUID()
        )
        var machine = KeyboardAssistStateMachine(state: .generating(latest, .readingChat))

        machine.send(
            .responseReceived(
                operationID: old.operationID,
                response: .ready(
                    KeyboardAssistReadyResponse.fixture(requestID: old.requestID)
                ),
                presentedAt: Date()
            )
        )

        XCTAssertEqual(machine.state, .generating(latest, .readingChat))
    }

    func testDocumentChangeInvalidatesResults() {
        let binding = KeyboardRequestBinding.fixture()
        var machine = KeyboardAssistStateMachine(
            state: .resultsPreview(
                KeyboardResultsPresentation(
                    binding: binding,
                    options: KeyboardAssistReadyResponse
                        .fixture(requestID: binding.requestID)
                        .options,
                    presentedAt: Date()
                )
            )
        )

        machine.send(.documentChanged)

        XCTAssertEqual(machine.state, .idle)
    }

    func testReadyStateIgnoresAllLateNetworkEvents() {
        let binding = KeyboardRequestBinding.fixture()
        let response = KeyboardAssistResponse.ready(
            KeyboardAssistReadyResponse.fixture(requestID: binding.requestID)
        )
        let terminal = KeyboardAssistState.resultsPreview(
            KeyboardResultsPresentation(
                binding: binding,
                options: KeyboardAssistReadyResponse
                    .fixture(requestID: binding.requestID)
                    .options,
                presentedAt: Date()
            )
        )
        var machine = KeyboardAssistStateMachine(state: terminal)

        let lateEvents: [KeyboardAssistEvent] = [
            .generationStageChanged(
                operationID: binding.operationID,
                stage: .choosingBest
            ),
            .generationFailed(
                operationID: binding.operationID,
                retryPolicy: .lookupSameRequest
            ),
            .responseReceived(
                operationID: binding.operationID,
                response: response,
                presentedAt: Date().addingTimeInterval(1)
            ),
        ]
        for event in lateEvents {
            machine.send(event)
            XCTAssertEqual(machine.state, terminal)
        }
    }

    func testConfirmationAndFailureStatesIgnoreLateNetworkEvents() {
        let binding = KeyboardRequestBinding.fixture()
        let response = KeyboardAssistResponse.ready(
            KeyboardAssistReadyResponse.fixture(requestID: binding.requestID)
        )
        let confirmation = KeyboardAssistSpeakerConfirmationResponse(
            contractVersion: .v1,
            requestId: binding.requestID,
            suggestedMySide: .right,
            sideConfidence: .low
        )
        let terminalStates: [KeyboardAssistState] = [
            .needsSpeakerConfirmation(binding, confirmation),
            .failed(binding, .terminal),
        ]

        for terminal in terminalStates {
            var machine = KeyboardAssistStateMachine(state: terminal)
            machine.send(
                .generationStageChanged(
                    operationID: binding.operationID,
                    stage: .choosingBest
                )
            )
            machine.send(
                .generationFailed(
                    operationID: binding.operationID,
                    retryPolicy: .lookupSameRequest
                )
            )
            machine.send(
                .responseReceived(
                    operationID: binding.operationID,
                    response: response,
                    presentedAt: Date()
                )
            )
            XCTAssertEqual(machine.state, terminal)
        }
    }

    func testExplicitStatusLookupCanRecoverAmbiguousFailure() {
        let binding = KeyboardRequestBinding.fixture()
        var machine = KeyboardAssistStateMachine(
            state: .failed(binding, .lookupSameRequest)
        )

        machine.send(
            .statusLookupStarted(operationID: binding.operationID)
        )
        XCTAssertEqual(machine.state, .lookingUpStatus(binding))

        machine.send(
            .responseReceived(
                operationID: binding.operationID,
                response: .ready(
                    KeyboardAssistReadyResponse.fixture(
                        requestID: binding.requestID
                    )
                ),
                presentedAt: Date()
            )
        )

        guard case .resultsPreview(let presentation) = machine.state else {
            return XCTFail("GET replay should recover the settled result")
        }
        XCTAssertEqual(presentation.binding, binding)
    }
}
