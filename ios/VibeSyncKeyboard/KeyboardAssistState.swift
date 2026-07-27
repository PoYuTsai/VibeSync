import Foundation

enum KeyboardAssistGenerationStage: Equatable {
    case readingChat
    case organizingStrategies
    case choosingBest
}

enum KeyboardAssistRetryPolicy: Equatable {
    case lookupSameRequest
    case retrySamePayload
    case newRequestAfterUserChange
    case terminal
}

struct KeyboardScreenshotSummary: Equatable {
    let assetIdentifier: String
    let creationDate: Date
}

enum KeyboardAssistState: Equatable {
    case boot
    case fullAccessRequired
    case authRequired
    case featureUnavailable
    case consentRequired
    case photoPermissionRequired(KeyboardPhotoAuthorization)
    case idle
    case screenshotDetected(KeyboardScreenshotSummary)
    case localPreview(KeyboardScreenshotSummary)
    case preparing(KeyboardRequestBinding)
    case generating(
        KeyboardRequestBinding,
        KeyboardAssistGenerationStage
    )
    case lookingUpStatus(KeyboardRequestBinding)
    case needsSpeakerConfirmation(
        KeyboardRequestBinding,
        KeyboardAssistSpeakerConfirmationResponse
    )
    case recognitionRejected
    case partnerConfirmation(KeyboardRequestBinding)
    case failed(KeyboardRequestBinding?, KeyboardAssistRetryPolicy)
    case resultsPreview(KeyboardResultsPresentation)
    case inserted(String)

    var providerMutableBinding: KeyboardRequestBinding? {
        switch self {
        case .preparing(let binding),
             .generating(let binding, _):
            return binding
        default:
            return nil
        }
    }

    var networkResponseBinding: KeyboardRequestBinding? {
        switch self {
        case .preparing(let binding),
             .generating(let binding, _),
             .lookingUpStatus(let binding):
            return binding
        default:
            return nil
        }
    }
}

struct KeyboardAssistPreflight: Equatable {
    let hasFullAccess: Bool
    let hasSession: Bool
    let hasCapability: Bool
    let hasConsent: Bool
    let photoAuthorization: KeyboardPhotoAuthorization
}

enum KeyboardAssistEvent: Equatable {
    case preflightCompleted(KeyboardAssistPreflight)
    case screenshotFound(KeyboardScreenshotSummary)
    case previewRequested
    case generationStarted(KeyboardRequestBinding)
    case generationStageChanged(
        operationID: UUID,
        stage: KeyboardAssistGenerationStage
    )
    case responseReceived(
        operationID: UUID,
        response: KeyboardAssistResponse,
        presentedAt: Date
    )
    case generationFailed(
        operationID: UUID,
        retryPolicy: KeyboardAssistRetryPolicy
    )
    case statusLookupStarted(operationID: UUID)
    case documentChanged
    case ownerChanged
    case screenshotChanged
    case contextChanged
    case viewDisappeared
    case candidateInserted(operationID: UUID, candidateID: String)
    case reset
}

struct KeyboardAssistStateMachine {
    private(set) var state: KeyboardAssistState

    init(state: KeyboardAssistState = .boot) {
        self.state = state
    }

    mutating func send(_ event: KeyboardAssistEvent) {
        switch event {
        case .preflightCompleted(let preflight):
            guard state == .boot || state == .idle else { return }
            if !preflight.hasFullAccess {
                state = .fullAccessRequired
            } else if !preflight.hasSession {
                state = .authRequired
            } else if !preflight.hasCapability {
                state = .featureUnavailable
            } else if !preflight.hasConsent {
                state = .consentRequired
            } else if preflight.photoAuthorization != .authorized &&
                        preflight.photoAuthorization != .limited
            {
                state = .photoPermissionRequired(
                    preflight.photoAuthorization
                )
            } else {
                state = .idle
            }
        case .screenshotFound(let summary):
            guard state == .idle else { return }
            state = .screenshotDetected(summary)
        case .previewRequested:
            guard case .screenshotDetected(let summary) = state else {
                return
            }
            state = .localPreview(summary)
        case .generationStarted(let binding):
            switch state {
            case .localPreview(let summary)
                where summary.assetIdentifier == binding.assetIdentifier:
                state = .preparing(binding)
            case .failed(let existing?, .retrySamePayload)
                where existing == binding:
                state = .preparing(binding)
            default:
                return
            }
        case .generationStageChanged(let operationID, let stage):
            guard let binding = state.providerMutableBinding,
                  binding.operationID == operationID
            else {
                return
            }
            state = .generating(binding, stage)
        case .responseReceived(
            let operationID,
            let response,
            let presentedAt
        ):
            guard let binding = state.networkResponseBinding,
                  binding.operationID == operationID
            else {
                // A response for an invalidated or superseded operation is
                // intentionally ignored.
                return
            }
            switch response {
            case .ready(let ready):
                guard ready.requestId == binding.requestID else { return }
                state = .resultsPreview(
                    KeyboardResultsPresentation(
                        binding: binding,
                        options: ready.options,
                        presentedAt: presentedAt
                    )
                )
            case .needsSpeakerConfirmation(let confirmation):
                guard confirmation.requestId == binding.requestID else {
                    return
                }
                state = .needsSpeakerConfirmation(
                    binding,
                    confirmation
                )
            case .partnerMismatchConfirmation(let mismatch):
                guard mismatch.requestId == binding.requestID else { return }
                state = .partnerConfirmation(binding)
            }
        case .generationFailed(let operationID, let retryPolicy):
            guard let binding = state.networkResponseBinding,
                  binding.operationID == operationID
            else {
                return
            }
            state = .failed(binding, retryPolicy)
        case .statusLookupStarted(let operationID):
            guard case .failed(
                let binding?,
                .lookupSameRequest
            ) = state,
                binding.operationID == operationID
            else {
                return
            }
            state = .lookingUpStatus(binding)
        case .candidateInserted(let operationID, let candidateID):
            guard case .resultsPreview(let presentation) = state,
                  presentation.binding.operationID == operationID,
                  presentation.options.contains(where: {
                      $0.candidateID == candidateID
                  })
            else {
                return
            }
            state = .inserted(candidateID)
        case .documentChanged,
             .ownerChanged,
             .screenshotChanged,
             .contextChanged,
             .viewDisappeared,
             .reset:
            state = .idle
        }
    }
}
