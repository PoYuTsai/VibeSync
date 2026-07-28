import Foundation
import UIKit

struct KeyboardScreenshotConsentReceipt: Codable, Equatable {
    static let storageKey = "keyboard_screenshot_consent_receipt_v1"

    let ownerUserId: String
    let version: String
    let enabled: Bool
    let acceptedAt: Date
    let updatedAt: Date

    func isUsable(ownerUserId expectedOwner: String, now: Date) -> Bool {
        enabled &&
            !expectedOwner.isEmpty &&
            ownerUserId == expectedOwner &&
            version ==
                KeyboardSharedConfig.keyboardScreenshotConsentVersion &&
            acceptedAt <= updatedAt &&
            acceptedAt <= now &&
            updatedAt <= now
    }
}

protocol KeyboardScreenshotConsentProviding: AnyObject {
    func usableConsent(
        ownerUserId: String,
        now: Date
    ) -> KeyboardScreenshotConsentReceipt?
}

final class KeyboardAppGroupScreenshotConsentProvider:
    KeyboardScreenshotConsentProviding
{
    private let defaults: UserDefaults?

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: KeyboardSharedConfig.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
    }

    func usableConsent(
        ownerUserId: String,
        now: Date
    ) -> KeyboardScreenshotConsentReceipt? {
        guard let defaults,
              let data = defaults.data(
                forKey: KeyboardScreenshotConsentReceipt.storageKey
              )
        else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = KeyboardISO8601.decodingStrategy
        guard let receipt = try? decoder.decode(
            KeyboardScreenshotConsentReceipt.self,
            from: data
        ),
            receipt.isUsable(ownerUserId: ownerUserId, now: now)
        else {
            return nil
        }
        return receipt
    }
}

protocol KeyboardScreenshotAssistNetworking: AnyObject {
    @discardableResult
    func fetchCapability(
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func submit(
        _ request: KeyboardAssistV1Request,
        session: KeyboardAuthSession,
        authorization: KeyboardAssistSendAuthorization,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func lookup(
        requestID: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable?

    @discardableResult
    func recoverLatestPending(
        documentIdentifier: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable?

    func clearPendingAfterPresentation(
        requestID: UUID,
        session: KeyboardAuthSession
    ) throws
}

final class KeyboardScreenshotAssistAPIAdapter:
    KeyboardScreenshotAssistNetworking
{
    private let transport: KeyboardAssistTransporting

    init(transport: KeyboardAssistTransporting) {
        self.transport = transport
    }

    @discardableResult
    func fetchCapability(
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistCapabilityReceipt,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        transport.fetchCapability(
            session: session,
            completion: completion
        )
    }

    @discardableResult
    func submit(
        _ request: KeyboardAssistV1Request,
        session: KeyboardAuthSession,
        authorization: KeyboardAssistSendAuthorization,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        transport.submit(
            request,
            session: session,
            authorization: authorization,
            completion: completion
        )
    }

    @discardableResult
    func lookup(
        requestID: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<KeyboardAssistResponse, KeyboardAssistAPIError>
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        transport.lookup(
            requestID: requestID,
            session: session,
            completion: completion
        )
    }

    @discardableResult
    func recoverLatestPending(
        documentIdentifier: UUID,
        session: KeyboardAuthSession,
        completion: @escaping (
            Result<
                KeyboardAssistRecoveredPending,
                KeyboardAssistAPIError
            >
        ) -> Void
    ) -> KeyboardAssistCancellable? {
        guard let recovering = transport as? KeyboardAssistPendingRecovering
        else {
            completion(.failure(.pendingReplayUnavailable))
            return nil
        }
        return recovering.recoverLatestPending(
            documentIdentifier: documentIdentifier,
            session: session,
            completion: completion
        )
    }

    func clearPendingAfterPresentation(
        requestID: UUID,
        session: KeyboardAuthSession
    ) throws {
        guard let clearing =
                transport as? KeyboardAssistPendingPresentationClearing
        else {
            return
        }
        try clearing.clearPendingAfterPresentation(
            requestID: requestID,
            session: session
        )
    }
}

protocol KeyboardScreenshotProviding: AnyObject {
    /// `ignoringSessionFloor` belongs in the protocol rather than as a default
    /// argument on the concrete type: Swift conformance ignores default values,
    /// so a defaulted parameter here silently breaks the conformance instead.
    func fetchLatest(
        capability: KeyboardAssistCapabilityReceipt?,
        ownerUserId: String,
        userAuthorizedDetection: Bool,
        ignoringSessionFloor: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    )

    func fetch(
        assetIdentifier: String,
        capability: KeyboardAssistCapabilityReceipt?,
        ownerUserId: String,
        userAuthorizedDetection: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    )

    /// Notifies when the photo library changes so a screenshot taken while the
    /// panel is already showing results can be picked up without the user
    /// having to dismiss and reopen the keyboard.
    func startObservingLibraryChanges(_ onChange: @escaping () -> Void)
    func stopObservingLibraryChanges()
}

extension KeyboardScreenshotProviding {
    func startObservingLibraryChanges(_ onChange: @escaping () -> Void) {}
    func stopObservingLibraryChanges() {}
}

extension LatestScreenshotProvider: KeyboardScreenshotProviding {}

protocol KeyboardScreenshotPreprocessing {
    func prepare(_ source: UIImage) throws -> KeyboardPreparedImage
    func prepare(
        _ source: UIImage,
        croppingBottomFraction fraction: CGFloat
    ) throws -> KeyboardPreparedImage
}

extension KeyboardScreenshotPreprocessing {
    func prepare(
        _ source: UIImage,
        croppingBottomFraction fraction: CGFloat
    ) throws -> KeyboardPreparedImage {
        try prepare(source)
    }
}

extension KeyboardImagePreprocessor: KeyboardScreenshotPreprocessing {}

protocol KeyboardScreenshotCandidateInserting: AnyObject {
    func insert(
        option: KeyboardAssistOption,
        presentation: KeyboardResultsPresentation,
        context: KeyboardInsertionContext
    ) throws -> KeyboardInsertionOutcome
}

extension ReplyInsertionCoordinator:
    KeyboardScreenshotCandidateInserting
{}

struct KeyboardScreenshotAssistRenderState {
    let state: KeyboardAssistState
    let message: String?
}

private struct KeyboardScreenshotOutboundOperation {
    let request: KeyboardAssistV1Request
    let binding: KeyboardRequestBinding
    let authorization: KeyboardAssistSendAuthorization
    let session: KeyboardAuthSession
}

final class KeyboardScreenshotAssistCoordinator {
    typealias SessionProvider = () -> KeyboardAuthSession?
    typealias ContextProvider =
        (_ ownerUserID: String) throws -> KeyboardContextEnvelope?
    typealias DocumentProvider = () -> UUID?
    typealias WorkScheduler = (@escaping () -> Void) -> Void
    /// Fraction of the capture that our own keyboard covered when a screenshot
    /// with this creation date was taken. Zero means the keyboard was not on
    /// screen and nothing may be trimmed.
    typealias OverlayFractionProvider = (_ capturedAt: Date) -> CGFloat

    private enum NetworkOrigin {
        case post
        case lookup
    }

    private let network: KeyboardScreenshotAssistNetworking
    private let screenshotProvider: KeyboardScreenshotProviding
    private let preprocessor: KeyboardScreenshotPreprocessing
    private let insertionCoordinator: KeyboardScreenshotCandidateInserting
    private let consentProvider: KeyboardScreenshotConsentProviding
    private let sessionProvider: SessionProvider
    private let contextProvider: ContextProvider
    private let documentProvider: DocumentProvider
    private let overlayFractionProvider: OverlayFractionProvider
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let schedulePreprocessing: WorkScheduler
    private let deliverToMain: WorkScheduler
    private let onRender: (KeyboardScreenshotAssistRenderState) -> Void

    private(set) var stateMachine = KeyboardAssistStateMachine()
    private(set) var previewImage: UIImage?
    private(set) var message: String?

    private var capability: KeyboardAssistCapabilityReceipt?
    private var context: KeyboardContextEnvelope?
    private var latestScreenshot: LatestScreenshot?
    private var preparedImage: KeyboardPreparedImage?
    private var outbound: KeyboardScreenshotOutboundOperation?
    private var activeTask: KeyboardAssistCancellable?
    private var lifecycleID = UUID()
    private var insertionCheckID: UUID?
    private var speakerChoiceCheckID: UUID?
    private var previewConfirmationCheckID: UUID?
    private var newBatchCheckID: UUID?
    private var preprocessingID: UUID?
    private var boundOwnerUserID: String?
    private var boundDocumentIdentifier: UUID?
    /// A run is billed, so reopening the keyboard must not re-analyse the same
    /// capture in the same chat. A new capture, a different chat, or an
    /// explicit retry all count as genuinely new work.
    private var lastAnalyzedAsset: String?
    private var lastAnalyzedDocument: UUID?
    private var lastLibraryTriggerAt: Date?
    private var isObservingLibrary = false
    /// True for exactly one detection pass, and only when the user asked for it
    /// by tapping. Automatic runs must stay inside this keyboard session.
    private var includePreSessionCapture = false
    /// What was offered last time in this exact chat. Carried into the next
    /// request so the model does not repeat itself and so the server can spot
    /// its own candidates being read back out of a screenshot.
    private var priorTurn: KeyboardAssistPriorTurn?
    private var priorTurnDocument: UUID?
    /// nil keeps the person's app-side voice, which is what makes the keyboard
    /// and the app feel like one coach instead of two products.
    private var voiceOverride: KeyboardVoiceName?

    init(
        network: KeyboardScreenshotAssistNetworking,
        screenshotProvider: KeyboardScreenshotProviding,
        preprocessor: KeyboardScreenshotPreprocessing,
        insertionCoordinator: KeyboardScreenshotCandidateInserting,
        consentProvider: KeyboardScreenshotConsentProviding,
        sessionProvider: @escaping SessionProvider,
        contextProvider: @escaping ContextProvider,
        documentProvider: @escaping DocumentProvider,
        overlayFractionProvider: @escaping OverlayFractionProvider = { _ in 0 },
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        schedulePreprocessing: @escaping WorkScheduler = { work in
            DispatchQueue.global(qos: .userInitiated).async(
                execute: work
            )
        },
        deliverToMain: @escaping WorkScheduler = { work in
            DispatchQueue.main.async(execute: work)
        },
        onRender: @escaping (
            KeyboardScreenshotAssistRenderState
        ) -> Void
    ) {
        self.network = network
        self.screenshotProvider = screenshotProvider
        self.preprocessor = preprocessor
        self.insertionCoordinator = insertionCoordinator
        self.consentProvider = consentProvider
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
        self.documentProvider = documentProvider
        self.overlayFractionProvider = overlayFractionProvider
        self.now = now
        self.makeUUID = makeUUID
        self.schedulePreprocessing = schedulePreprocessing
        self.deliverToMain = deliverToMain
        self.onRender = onRender
    }

    convenience init(
        documentProvider: @escaping DocumentProvider,
        overlayFractionProvider: @escaping OverlayFractionProvider,
        sessionStartedAt: @escaping () -> Date?,
        insertText: @escaping (String) -> Void,
        onRender: @escaping (
            KeyboardScreenshotAssistRenderState
        ) -> Void
    ) {
        self.init(
            network: KeyboardScreenshotAssistAPIAdapter(
                transport: KeyboardAssistAPI()
            ),
            screenshotProvider: LatestScreenshotProvider(
                sessionStartedAt: sessionStartedAt
            ),
            preprocessor: KeyboardImagePreprocessor(),
            insertionCoordinator: ReplyInsertionCoordinator(
                insertText: insertText
            ),
            consentProvider:
                KeyboardAppGroupScreenshotConsentProvider(),
            sessionProvider: {
                SharedAuth.currentSession()
            },
            contextProvider: { ownerUserID in
                try? KeyboardContextStore.live().read(
                    expectedOwnerUserID: ownerUserID
                )
            },
            documentProvider: documentProvider,
            overlayFractionProvider: overlayFractionProvider,
            onRender: onRender
        )
    }

    func start(hasFullAccess: Bool) {
        start(hasFullAccess: hasFullAccess, includingPreSessionCapture: false)
    }

    private func start(
        hasFullAccess: Bool,
        includingPreSessionCapture: Bool
    ) {
        includePreSessionCapture = includingPreSessionCapture
        invalidateAsyncWork()
        clearBoundData()
        setState(.boot, message: nil)

        guard hasFullAccess else {
            setState(
                .fullAccessRequired,
                message: "請先在設定開啟「允許完整取用」。"
            )
            return
        }
        guard let session = sessionProvider() else {
            setState(
                .authRequired,
                message: "請先開啟 VibeSync App 更新登入狀態。"
            )
            return
        }
        guard let documentIdentifier = documentProvider() else {
            setState(
                .failed(nil, .terminal),
                message: "目前無法安全綁定聊天室，請切回對話後再試。"
            )
            return
        }

        boundOwnerUserID = session.userId
        boundDocumentIdentifier = documentIdentifier
        let expectedLifecycle = lifecycleID
        activeTask = network.fetchCapability(
            session: session
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  )
            else {
                return
            }
            self.activeTask = nil
            switch result {
            case .failure(.unauthorized):
                self.setState(
                    .authRequired,
                    message: "登入已過期，請開啟 VibeSync 後再回來。"
                )
            case .failure:
                self.setState(
                    .featureUnavailable,
                    message: "暫時無法取得截圖分析授權，請確認網路後再開一次鍵盤。"
                )
            case .success(let receipt):
                guard receipt.isUsable(
                    ownerUserId: session.userId,
                    now: self.now()
                ) else {
                    self.setState(
                        .featureUnavailable,
                        message: "截圖分析尚未對這個帳號開啟；請開啟 VibeSync App 後再回來。"
                    )
                    return
                }
                self.capability = receipt
                self.loadConsentContextThenDetectScreenshot(
                    session: session,
                    expectedLifecycle: expectedLifecycle
                )
            }
        }
    }

    /// The preview must describe the same pixels the upload will carry, so it
    /// goes through the identical trim.
    private func trimmedPreview(_ screenshot: LatestScreenshot) -> UIImage {
        KeyboardImagePreprocessor.croppingBottom(
            screenshot.thumbnail,
            fraction: overlayFractionProvider(screenshot.creationDate)
        )
    }

    func requestLocalPreview() {
        guard case .screenshotDetected = stateMachine.state,
              latestScreenshot != nil
        else {
            return
        }
        stateMachine.send(.previewRequested)
        setMessage("找到最近截圖，正在分析…")
    }

    func confirmPreviewAndGenerate() {
        let previewConfirmedAt = now()
        guard previewConfirmationCheckID == nil,
              preprocessingID == nil,
              case .localPreview = stateMachine.state,
              let session = currentBoundSession(),
              let receipt = capability,
              let selectedScreenshot = latestScreenshot,
              let documentIdentifier = boundDocumentIdentifier,
              let freshConsent = consentProvider.usableConsent(
                  ownerUserId: session.userId,
                  now: now()
              )
        else {
            contextDidChange()
            setMessage("登入、同意或偏好已更新，請重新選擇截圖。")
            return
        }
        let freshContext = optionalContext(for: session.userId)
        guard freshContext?.revision == context?.revision else {
            contextDidChange()
            setMessage("偏好脈絡已更新，請重新選擇截圖。")
            return
        }
        context = freshContext

        let checkID = makeUUID()
        previewConfirmationCheckID = checkID
        let expectedLifecycle = lifecycleID
        setMessage("正在本機確認這張截圖…")
        // Re-read the latest screenshot after the explicit tap. If another
        // screenshot appeared while the preview was open, the old preview is
        // invalidated instead of silently uploading it.
        screenshotProvider.fetchLatest(
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: freshConsent.enabled,
            // Scoped to the run this re-read belongs to: a run the user started
            // by tapping must not invalidate itself here.
            ignoringSessionFloor: includePreSessionCapture
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.previewConfirmationCheckID == checkID,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  )
            else {
                return
            }
            self.previewConfirmationCheckID = nil
            guard case .success(let currentScreenshot) = result,
                  currentScreenshot.assetIdentifier ==
                    selectedScreenshot.assetIdentifier,
                  currentScreenshot.creationDate ==
                    selectedScreenshot.creationDate
            else {
                self.screenshotDidChange()
                self.setMessage("偵測到更新的截圖，請重新預覽。")
                return
            }
            self.prepareAndSubmit(
                screenshot: currentScreenshot,
                session: session,
                receipt: receipt,
                documentIdentifier: documentIdentifier,
                speakerOverride: .none,
                previewConfirmedAt: previewConfirmedAt
            )
        }
    }

    func chooseSpeakerSide(
        _ side: KeyboardAssistSpeakerConfirmationResponse.Side
    ) {
        let previewConfirmedAt = now()
        guard speakerChoiceCheckID == nil,
              case .needsSpeakerConfirmation(
                let previousBinding,
                _
              ) = stateMachine.state,
              let session = currentBoundSession(),
              let receipt = capability,
              let screenshot = latestScreenshot,
              let documentIdentifier = boundDocumentIdentifier,
              let preparedImage,
              let confirmedConsent = consentProvider.usableConsent(
                  ownerUserId: session.userId,
                  now: now()
              )
        else {
            failCurrentOperation(
                policy: .terminal,
                message: "狀態已更新，請重新分析截圖。"
            )
            return
        }
        let confirmedContext = optionalContext(for: session.userId)
        guard confirmedContext?.revision == context?.revision else {
            contextDidChange()
            setMessage("偏好脈絡已更新，請重新分析截圖。")
            return
        }
        context = confirmedContext
        let checkID = makeUUID()
        speakerChoiceCheckID = checkID
        let expectedLifecycle = lifecycleID
        setMessage("正在確認截圖與聊天室仍相同…")
        screenshotProvider.fetchLatest(
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: confirmedConsent.enabled,
            ignoringSessionFloor: includePreSessionCapture
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.speakerChoiceCheckID == checkID
            else {
                return
            }
            self.speakerChoiceCheckID = nil
            guard case .needsSpeakerConfirmation =
                    self.stateMachine.state,
                  case .success(let currentScreenshot) = result,
                  currentScreenshot.assetIdentifier ==
                    screenshot.assetIdentifier,
                  currentScreenshot.creationDate ==
                    screenshot.creationDate,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  ),
                  let freshConsent =
                    self.consentProvider.usableConsent(
                        ownerUserId: session.userId,
                        now: self.now()
                    )
            else {
                self.invalidateForChangedInput(
                    event: .screenshotChanged,
                    message:
                        "截圖、聊天室或偏好已更新，請重新分析。"
                )
                return
            }
            let freshContext = self.optionalContext(
                for: session.userId
            )
            guard freshContext?.revision == self.context?.revision else {
                self.contextDidChange()
                self.setMessage(
                    "偏好脈絡已更新，請重新分析截圖。"
                )
                return
            }
            self.context = freshContext
            let confirmationAge = self.now().timeIntervalSince(
                previewConfirmedAt
            )
            guard confirmationAge >= 0,
                  confirmationAge <=
                    KeyboardSharedConfig.resultsPresentationTTL
            else {
                self.failCurrentOperation(
                    policy: .terminal,
                    message: "這次確認已過期；不會建立新請求。"
                )
                return
            }
            do {
                // The explicit side choice supersedes the settled no-charge
                // confirmation. Remove it before creating the new request so
                // startup recovery cannot resurrect and charge it again.
                try self.network.clearPendingAfterPresentation(
                    requestID: previousBinding.requestID,
                    session: session
                )
            } catch {
                self.failCurrentOperation(
                    policy: .terminal,
                    message:
                        "無法安全結束上一筆確認；本次不會建立新請求。"
                )
                return
            }
            self.submitPreparedImage(
                preparedImage,
                screenshot: screenshot,
                session: session,
                receipt: receipt,
                documentIdentifier: documentIdentifier,
                context: freshContext,
                consent: freshConsent,
                speakerOverride:
                    side == .left ? .leftIsMe : .rightIsMe,
                previewConfirmedAt: previewConfirmedAt
            )
        }
    }

    func retryFailedRequest() {
        if case .failed(nil, .lookupSameRequest) = stateMachine.state {
            // Startup recovery has not touched Photos and intentionally does
            // not hydrate an unverified payload. Restarting repeats the
            // owner/document-bound GET before any new request is possible.
            start(hasFullAccess: true)
            return
        }
        guard case .failed(
            let binding?,
            let policy
        ) = stateMachine.state,
            let outbound,
            outbound.binding == binding,
            currentBoundSession()?.userId == outbound.session.userId
        else {
            return
        }

        switch policy {
        case .lookupSameRequest:
            lookupSameRequest(outbound)
        case .retrySamePayload:
            stateMachine.send(.generationStarted(binding))
            stateMachine.send(
                .generationStageChanged(
                    operationID: binding.operationID,
                    stage: .readingChat
                )
            )
            setMessage("正在安全重送同一筆 payload 與 requestId…")
            send(outbound)
        case .newRequestAfterUserChange, .terminal:
            break
        }
    }

    func insertCandidate(candidateID: String) {
        guard insertionCheckID == nil,
              case .resultsPreview(let presentation) =
                stateMachine.state,
              let option = presentation.options.first(where: {
                  $0.candidateID == candidateID
              }),
              let receipt = capability,
              let screenshot = latestScreenshot,
              let session = currentBoundSession(),
              let documentIdentifier = boundDocumentIdentifier,
              documentProvider() == documentIdentifier,
              let freshConsent = consentProvider.usableConsent(
                  ownerUserId: session.userId,
                  now: now()
              )
        else {
            invalidateForChangedInput(
                event: .contextChanged,
                message: "聊天室或偏好已變更，請重新分析。"
            )
            return
        }
        let freshContext = optionalContext(for: session.userId)
        guard freshContext?.revision ==
                presentation.binding.contextRevision
        else {
            contextDidChange()
            setMessage("偏好脈絡已更新，請重新分析。")
            return
        }
        context = freshContext

        let checkID = makeUUID()
        insertionCheckID = checkID
        let expectedLifecycle = lifecycleID
        screenshotProvider.fetch(
            assetIdentifier: screenshot.assetIdentifier,
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: freshConsent.enabled
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.insertionCheckID == checkID
            else {
                return
            }
            guard case .success(let currentScreenshot) = result,
                  currentScreenshot.assetIdentifier ==
                    screenshot.assetIdentifier,
                  currentScreenshot.creationDate == screenshot.creationDate,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  ),
                  self.consentProvider.usableConsent(
                    ownerUserId: session.userId,
                    now: self.now()
                  ) != nil
            else {
                self.invalidateForChangedInput(
                    event: .screenshotChanged,
                    message: "截圖、聊天室或偏好已更新，請重新分析。"
                )
                return
            }
            // The overlay fraction is read on the main thread because it comes
            // from live keyboard geometry; the worker only sees the value.
            let overlayFraction = self.overlayFractionProvider(
                currentScreenshot.creationDate
            )
            self.schedulePreprocessing { [weak self] in
                guard let self else { return }
                let verification: Result<KeyboardPreparedImage, Error>
                do {
                    verification = .success(
                        try self.preprocessor.prepare(
                            currentScreenshot.thumbnail,
                            croppingBottomFraction: overlayFraction
                        )
                    )
                } catch {
                    verification = .failure(error)
                }
                self.deliverToMain { [weak self] in
                    guard let self,
                          self.lifecycleID == expectedLifecycle,
                          self.insertionCheckID == checkID
                    else {
                        return
                    }
                    self.insertionCheckID = nil
                    guard case .success(let verified) = verification,
                          case .resultsPreview(let currentPresentation) =
                            self.stateMachine.state,
                          currentPresentation == presentation,
                          self.currentIdentityMatches(
                            ownerUserID: session.userId,
                            documentIdentifier: documentIdentifier
                          ),
                          receipt.isUsable(
                            ownerUserId: session.userId,
                            now: self.now()
                          ),
                          self.consentProvider.usableConsent(
                            ownerUserId: session.userId,
                            now: self.now()
                          ) != nil
                    else {
                        self.invalidateForChangedInput(
                            event: .screenshotChanged,
                            message:
                                "截圖、聊天室或偏好已更新，請重新分析。"
                        )
                        return
                    }
                    guard verified.sha256 ==
                            presentation.binding.screenshotHash
                    else {
                        try? self.network.clearPendingAfterPresentation(
                            requestID:
                                presentation.binding.requestID,
                            session: session
                        )
                        self.invalidateForChangedInput(
                            event: .screenshotChanged,
                            message: "原截圖內容已變更，舊結果不會插入。"
                        )
                        return
                    }
                    let currentContext = self.optionalContext(
                        for: session.userId
                    )
                    guard currentContext?.revision ==
                            presentation.binding.contextRevision
                    else {
                        self.contextDidChange()
                        self.setMessage(
                            "偏好脈絡已更新，請重新分析。"
                        )
                        return
                    }

                    let insertionContext = KeyboardInsertionContext(
                        operationID:
                            presentation.binding.operationID,
                        requestID: presentation.binding.requestID,
                        ownerUserID: session.userId,
                        documentIdentifier: documentIdentifier,
                        assetIdentifier:
                            currentScreenshot.assetIdentifier,
                        screenshotHash: verified.sha256,
                        partnerID: presentation.binding.partnerID,
                        contextRevision:
                            presentation.binding.contextRevision,
                        now: self.now()
                    )
                    do {
                        // Validate first, then consume the durable replay
                        // record before reaching the only insertText path.
                        // The insertion coordinator repeats the same
                        // validation and its insert closure is non-throwing.
                        // If Keychain cleanup fails, nothing is inserted and
                        // the visible card remains available for an explicit
                        // retry; a restart can never re-present a result that
                        // was already inserted.
                        try presentation.binding.validateForInsertion(
                            context: insertionContext,
                            presentedAt: presentation.presentedAt
                        )
                        do {
                            try self.network
                                .clearPendingAfterPresentation(
                                    requestID:
                                        presentation.binding.requestID,
                                    session: session
                                )
                        } catch {
                            self.setMessage(
                                "尚未插入：無法安全完成本機清理，請再點一次。"
                            )
                            return
                        }
                        let outcome =
                            try self.insertionCoordinator.insert(
                                option: option,
                                presentation: presentation,
                                context: insertionContext
                            )
                        guard outcome == .inserted else { return }
                        self.stateMachine.send(
                            .candidateInserted(
                                operationID:
                                    presentation.binding.operationID,
                                candidateID: option.candidateID
                            )
                        )
                        self.rememberInserted(option.text)
                        self.setMessage(
                            "已插入輸入框；送出前你仍可自行修改。"
                        )
                    } catch {
                        self.invalidateForChangedInput(
                            event: .documentChanged,
                            message:
                                "結果已過期或聊天室已變更，請重新分析。"
                        )
                    }
                }
            }
        }
    }

    func documentDidChange(to documentIdentifier: UUID?) {
        guard let boundDocumentIdentifier,
              documentIdentifier != boundDocumentIdentifier
        else {
            return
        }
        invalidateForChangedInput(
            event: .documentChanged,
            message: "聊天室已切換，截圖結果已清除。"
        )
    }

    func ownerDidChange() {
        lastAnalyzedAsset = nil
        lastAnalyzedDocument = nil
        priorTurn = nil
        priorTurnDocument = nil
        invalidateAsyncWork()
        stateMachine.send(.ownerChanged)
        clearBoundData()
        setState(
            .authRequired,
            message: "登入帳號已變更，截圖結果已清除。"
        )
    }

    /// "換一批" analyses this same screenshot again. Holding a second batch
    /// back from the first call meant every screenshot paid to generate three
    /// lines most users never asked for, and capped the feature at exactly one
    /// retry. Regenerating has no cap and no wasted work — the lines already on
    /// screen travel with the request so the new batch has to differ.
    func requestNewBatch() {
        let previewConfirmedAt = now()
        guard newBatchCheckID == nil,
              preprocessingID == nil,
              case .resultsPreview(let presentation) = stateMachine.state,
              let session = currentBoundSession(),
              let receipt = capability,
              let selectedScreenshot = latestScreenshot,
              let documentIdentifier = boundDocumentIdentifier,
              documentProvider() == documentIdentifier,
              presentation.binding.ownerUserID == session.userId,
              presentation.binding.assetIdentifier ==
                selectedScreenshot.assetIdentifier,
              let freshConsent = consentProvider.usableConsent(
                  ownerUserId: session.userId,
                  now: previewConfirmedAt
              )
        else {
            invalidateForChangedInput(
                event: .contextChanged,
                message: "聊天室或偏好已變更，請重新分析。"
            )
            return
        }
        let freshContext = optionalContext(for: session.userId)
        guard freshContext?.revision == presentation.binding.contextRevision
        else {
            contextDidChange()
            setMessage("偏好脈絡已更新，請重新分析。")
            return
        }
        context = freshContext
        // What is on screen is exactly what the next batch must not repeat.
        rememberOffered(presentation.options.map(\.text))

        let checkID = makeUUID()
        newBatchCheckID = checkID
        let expectedLifecycle = lifecycleID
        setMessage("正在重新想三個說法…")
        // The same re-read every other generation path does: if a newer
        // screenshot appeared while the result was on screen, re-rolling the
        // old one would analyse a conversation the user has already left.
        screenshotProvider.fetchLatest(
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: freshConsent.enabled,
            ignoringSessionFloor: includePreSessionCapture
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.newBatchCheckID == checkID,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  )
            else {
                return
            }
            self.newBatchCheckID = nil
            guard case .success(let currentScreenshot) = result,
                  currentScreenshot.assetIdentifier ==
                    selectedScreenshot.assetIdentifier,
                  currentScreenshot.creationDate ==
                    selectedScreenshot.creationDate
            else {
                self.screenshotDidChange()
                self.setMessage("偵測到更新的截圖，請重新預覽。")
                return
            }
            self.prepareAndSubmit(
                screenshot: currentScreenshot,
                session: session,
                receipt: receipt,
                documentIdentifier: documentIdentifier,
                speakerOverride: .none,
                previewConfirmedAt: previewConfirmedAt
            )
        }
    }

    /// Applies to the next analysis only. Changing it never re-sends anything,
    /// so it cannot cost a second charge.
    func setVoiceOverride(_ voice: KeyboardVoiceName?) {
        voiceOverride = voice
    }

    /// A result on screen can always be re-rolled, because re-rolling is just
    /// another analysis of the same capture.
    var canRequestNewBatch: Bool {
        guard case .resultsPreview = stateMachine.state else { return false }
        return latestScreenshot != nil
    }

    /// Everything this keyboard has shown in this chat, newest first. A re-roll
    /// is a fresh generation, so this list is the only thing stopping it from
    /// handing back the batch it just replaced. Capped by the contract; when it
    /// overflows the oldest lines are the ones the user is least likely to
    /// still have on screen.
    private func rememberOffered(_ texts: [String]) {
        var merged: [String] = []
        for text in texts + (priorTurnForCurrentDocument()?.offeredTexts ?? [])
        where !merged.contains(text) {
            merged.append(text)
        }
        let candidate = KeyboardAssistPriorTurn(
            offeredTexts: Array(
                merged.prefix(KeyboardSharedConfig.maximumPriorOfferedTexts)
            ),
            insertedText: nil
        )
        guard candidate.isValid else {
            // Never ship a payload the server would reject; losing the hint is
            // strictly better than losing the request.
            priorTurn = nil
            priorTurnDocument = nil
            return
        }
        priorTurn = candidate
        priorTurnDocument = boundDocumentIdentifier
    }

    private func rememberInserted(_ text: String) {
        guard let existing = priorTurn,
              existing.offeredTexts.contains(text)
        else {
            return
        }
        let updated = KeyboardAssistPriorTurn(
            offeredTexts: existing.offeredTexts,
            insertedText: text
        )
        guard updated.isValid else { return }
        priorTurn = updated
    }

    /// Only the same chat may inherit a prior turn. A different input field is
    /// a different conversation, and reusing the hint there would both mislead
    /// the model and risk rejecting an innocent transcript.
    private func priorTurnForCurrentDocument() -> KeyboardAssistPriorTurn? {
        guard let document = priorTurnDocument,
              document == boundDocumentIdentifier
        else {
            return nil
        }
        return priorTurn
    }

    private func alreadyAnalyzed(_ screenshot: LatestScreenshot) -> Bool {
        lastAnalyzedAsset == screenshot.assetIdentifier &&
            lastAnalyzedDocument == boundDocumentIdentifier
    }

    /// An explicit retry is the user asking for the work again, so the
    /// already-analysed guard is deliberately dropped for that one run.
    /// The one path that may look at a capture taken before this keyboard came
    /// up. It exists because "screenshot the chat, then switch keyboards" is a
    /// habit, and silently ignoring that screenshot is a dead end.
    func startForcingReanalysis(hasFullAccess: Bool) {
        lastAnalyzedAsset = nil
        lastAnalyzedDocument = nil
        start(hasFullAccess: hasFullAccess, includingPreSessionCapture: true)
    }

    /// A screenshot taken while results are already on screen should pick
    /// itself up, the way it does when the keyboard is first opened. Anything
    /// mid-flight is left alone so a library notification can never race, or
    /// duplicate, a request that is already being paid for.
    func libraryDidChange(hasFullAccess: Bool) {
        switch stateMachine.state {
        case .idle,
             .resultsPreview,
             .inserted,
             .recognitionRejected,
             .failed(_, .terminal),
             .failed(_, .newRequestAfterUserChange):
            break
        default:
            return
        }
        let moment = now()
        if let previous = lastLibraryTriggerAt,
           moment.timeIntervalSince(previous) < 1
        {
            // PhotoKit reports every library mutation; a burst must not turn
            // into a burst of capability round trips.
            return
        }
        lastLibraryTriggerAt = moment
        // PhotoKit reports every mutation, including deletions and edits to
        // unrelated photos. Restarting unconditionally would wipe the results
        // the user is reading, so the current capability is reused to peek
        // first and the run only restarts for a genuinely new capture. An
        // expired capability simply leaves the panel alone; the retry control
        // is still there.
        guard let session = currentBoundSession(),
              let receipt = capability,
              let consent = consentProvider.usableConsent(
                  ownerUserId: session.userId,
                  now: moment
              )
        else {
            return
        }
        let expectedLifecycle = lifecycleID
        screenshotProvider.fetchLatest(
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: consent.enabled,
            // Automatic. Never reaches back past this keyboard session.
            ignoringSessionFloor: false
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  case .success(let screenshot) = result,
                  !self.alreadyAnalyzed(screenshot)
            else {
                return
            }
            self.start(hasFullAccess: hasFullAccess)
        }
    }

    func startObservingLibrary(hasFullAccess: Bool) {
        guard !isObservingLibrary else { return }
        isObservingLibrary = true
        screenshotProvider.startObservingLibraryChanges { [weak self] in
            self?.libraryDidChange(hasFullAccess: hasFullAccess)
        }
    }

    func stopObservingLibrary() {
        guard isObservingLibrary else { return }
        isObservingLibrary = false
        screenshotProvider.stopObservingLibraryChanges()
    }

    func screenshotDidChange() {
        invalidateForChangedInput(
            event: .screenshotChanged,
            message: "截圖已更新，請重新預覽。"
        )
    }

    func contextDidChange() {
        invalidateForChangedInput(
            event: .contextChanged,
            message: "偏好設定已更新，請重新分析。"
        )
    }

    func viewDidDisappear() {
        stopObservingLibrary()
        invalidateAsyncWork()
        clearBoundData()
        stateMachine.send(.viewDisappeared)
        setState(.featureUnavailable, message: nil)
    }

    func suspendForLegacyFlow() {
        invalidateAsyncWork()
        clearBoundData()
        setState(.featureUnavailable, message: nil)
    }

    func cancel() {
        if let binding = outbound?.binding {
            invalidateAsyncWork()
            stateMachine = KeyboardAssistStateMachine(
                state: .failed(binding, .lookupSameRequest)
            )
            setMessage(
                "已停止等待；下次只會查詢同一筆 requestId，不會重複送出。"
            )
            return
        }
        invalidateAsyncWork()
        clearBoundData(keepingIdentity: true)
        stateMachine.send(.reset)
        setMessage("本次截圖未送出。")
    }

    private func loadConsentContextThenDetectScreenshot(
        session: KeyboardAuthSession,
        expectedLifecycle: UUID
    ) {
        guard consentProvider.usableConsent(
            ownerUserId: session.userId,
            now: now()
        ) != nil else {
            setState(
                .consentRequired,
                message: "請先在 VibeSync 開啟「截圖 AI 分析」同意。"
            )
            return
        }
        guard let receipt = capability,
              let documentIdentifier = boundDocumentIdentifier
        else {
            setState(.featureUnavailable, message: nil)
            return
        }

        let envelope = optionalContext(for: session.userId)
        context = envelope
        stateMachine.send(
            .preflightCompleted(
                KeyboardAssistPreflight(
                    hasFullAccess: true,
                    hasSession: true,
                    hasCapability: true,
                    hasConsent: true,
                    photoAuthorization: .authorized
                )
            )
        )
        notify()
        // Resolve durable recovery before the first PhotoKit read. A pending
        // POST must never be replaced with a fresh request ID.
        activeTask = network.recoverLatestPending(
            documentIdentifier: documentIdentifier,
            session: session
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  )
            else {
                return
            }
            self.activeTask = nil
            switch result {
            case .success(let recovered):
                self.validateAndPresentRecoveredPending(
                    recovered,
                    session: session,
                    receipt: receipt,
                    documentIdentifier: documentIdentifier,
                    expectedLifecycle: expectedLifecycle
                )
            case .failure(.noPendingReplay),
                 .failure(.requestNotFound),
                 .failure(.requestExpiredNoCharge),
                 .failure(.unsupportedConversation),
                 .failure(.invalidRequest),
                 .failure(.invalidResponse),
                 .failure(.replayMismatch):
                self.detectLatestScreenshot(
                    session: session,
                    receipt: receipt,
                    expectedLifecycle: expectedLifecycle
                )
            case .failure(.unauthorized):
                self.setState(
                    .authRequired,
                    message: "登入已過期，請開啟 VibeSync 後再回來。"
                )
            case .failure(.server(_, let disposition, _))
                where disposition == .newRequestAfterUserChange ||
                    disposition == .terminalClear:
                self.detectLatestScreenshot(
                    session: session,
                    receipt: receipt,
                    expectedLifecycle: expectedLifecycle
                )
            case .failure:
                // Preserve the record. A later start will query the same
                // request ID again before Photos or a new request is allowed.
                self.setState(
                    .failed(nil, .lookupSameRequest),
                    message:
                        "上一筆結果仍在確認；不會建立新 requestId，請稍後重新開啟。"
                )
            }
        }
    }

    private func detectLatestScreenshot(
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        expectedLifecycle: UUID
    ) {
        guard currentIdentityMatches(
            ownerUserID: session.userId,
            documentIdentifier: boundDocumentIdentifier
        ), let consent = consentProvider.usableConsent(
            ownerUserId: session.userId,
            now: now()
        ) else {
            setState(
                .consentRequired,
                message: "請先在 VibeSync 開啟「截圖 AI 分析」同意。"
            )
            return
        }
        // This is the first point at which the coordinator may touch Photos:
        // capability, consent, and durable pending recovery already succeeded.
        screenshotProvider.fetchLatest(
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: consent.enabled,
            ignoringSessionFloor: includePreSessionCapture
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier:
                        self.boundDocumentIdentifier
                  )
            else {
                return
            }
            switch result {
            case .success(let screenshot):
                self.latestScreenshot = screenshot
                self.previewImage = self.trimmedPreview(screenshot)
                self.stateMachine.send(
                    .screenshotFound(
                        KeyboardScreenshotSummary(
                            assetIdentifier:
                                screenshot.assetIdentifier,
                            creationDate: screenshot.creationDate
                        )
                    )
                )
                guard !self.alreadyAnalyzed(screenshot) else {
                    // Reopening the keyboard, or an unrelated photo library
                    // change, must never spend a second charge on a capture
                    // this chat has already seen.
                    self.setState(
                        .idle,
                        message: "這張截圖剛才分析過了；截新的一張就會自動分析。"
                    )
                    return
                }
                self.lastAnalyzedAsset = screenshot.assetIdentifier
                self.lastAnalyzedDocument = self.boundDocumentIdentifier
                // Consent is granted once in the app, so a detected capture
                // runs straight away instead of waiting for a second tap. The
                // panel still shows exactly which image was used, and
                // `confirmPreviewAndGenerate` keeps re-reading the newest
                // screenshot so a capture taken during this hop cannot be
                // uploaded in place of the one on screen.
                self.requestLocalPreview()
                self.confirmPreviewAndGenerate()
            case .failure(let error):
                self.handleScreenshotError(error)
            }
        }
    }

    private func validateAndPresentRecoveredPending(
        _ recovered: KeyboardAssistRecoveredPending,
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        documentIdentifier: UUID,
        expectedLifecycle: UUID
    ) {
        let metadata = recovered.metadata
        guard metadata.ownerUserId == session.userId,
              metadata.documentIdentifier == documentIdentifier
        else {
            // It may still be valid in its original document, so preserve it.
            setState(
                .failed(nil, .terminal),
                message: "上一筆結果屬於其他輸入欄位，本次不會顯示或插入。"
            )
            return
        }

        // A restart must not mint a fresh insertion window for an old result.
        let recoveredAge = now().timeIntervalSince(metadata.createdAt)
        guard recoveredAge >= 0,
              recoveredAge <=
                KeyboardSharedConfig.resultsPresentationTTL
        else {
            try? network.clearPendingAfterPresentation(
                requestID: metadata.requestId,
                session: session
            )
            setState(
                .failed(nil, .newRequestAfterUserChange),
                message: "上一筆回覆已超過安全插入時間，請重新確認截圖。"
            )
            return
        }

        let recoveredContext = optionalContext(for: session.userId)
        guard recoveredContext?.revision == metadata.contextRevision else {
            try? network.clearPendingAfterPresentation(
                requestID: metadata.requestId,
                session: session
            )
            setState(
                .failed(nil, .newRequestAfterUserChange),
                message: "目前脈絡已變更；舊結果不會顯示或插入。"
            )
            return
        }
        context = recoveredContext
        guard let consent = consentProvider.usableConsent(
            ownerUserId: session.userId,
            now: now()
        ) else {
            setState(
                .consentRequired,
                message: "請先在 VibeSync 開啟「截圖 AI 分析」同意。"
            )
            return
        }

        screenshotProvider.fetch(
            assetIdentifier: metadata.assetIdentifier,
            capability: receipt,
            ownerUserId: session.userId,
            userAuthorizedDetection: consent.enabled
        ) { [weak self] result in
            guard let self,
                  self.lifecycleID == expectedLifecycle,
                  self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                  )
            else {
                return
            }
            guard case .success(let screenshot) = result,
                  screenshot.assetIdentifier == metadata.assetIdentifier
            else {
                // Permission or limited-library selection can be repaired, so
                // preserve this exact request for the next safe recovery.
                self.setState(
                    .failed(nil, .lookupSameRequest),
                    message:
                        "無法重新驗證原截圖；已保留同一筆 requestId，不會建立新請求。"
                )
                return
            }
            self.preprocessRecoveredPending(
                recovered,
                screenshot: screenshot,
                session: session,
                receipt: receipt,
                documentIdentifier: documentIdentifier,
                expectedLifecycle: expectedLifecycle
            )
        }
    }

    private func preprocessRecoveredPending(
        _ recovered: KeyboardAssistRecoveredPending,
        screenshot: LatestScreenshot,
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        documentIdentifier: UUID,
        expectedLifecycle: UUID
    ) {
        let metadata = recovered.metadata
        let workID = makeUUID()
        preprocessingID = workID
        let overlayFraction = overlayFractionProvider(screenshot.creationDate)
        schedulePreprocessing { [weak self] in
            guard let self else { return }
            let result: Result<KeyboardPreparedImage, Error>
            do {
                result = .success(
                    try self.preprocessor.prepare(
                        screenshot.thumbnail,
                        croppingBottomFraction: overlayFraction
                    )
                )
            } catch {
                result = .failure(error)
            }
            self.deliverToMain { [weak self] in
                guard let self,
                      self.lifecycleID == expectedLifecycle,
                      self.preprocessingID == workID
                else {
                    return
                }
                self.preprocessingID = nil
                guard case .success(let prepared) = result else {
                    self.setState(
                        .failed(nil, .lookupSameRequest),
                        message:
                            "沒辦法重新確認原本那張截圖；這一筆會照原樣查，不會多扣。"
                    )
                    return
                }
                guard prepared.sha256 == metadata.imageSHA256 else {
                    try? self.network.clearPendingAfterPresentation(
                        requestID: metadata.requestId,
                        session: session
                    )
                    self.setState(
                        .failed(nil, .newRequestAfterUserChange),
                        message: "原截圖內容已變更；舊結果不會顯示或插入。"
                    )
                    return
                }
                guard self.currentIdentityMatches(
                    ownerUserID: session.userId,
                    documentIdentifier: documentIdentifier
                ), receipt.isUsable(
                    ownerUserId: session.userId,
                    now: self.now()
                ), self.consentProvider.usableConsent(
                    ownerUserId: session.userId,
                    now: self.now()
                ) != nil else {
                    self.setState(
                        .failed(nil, .lookupSameRequest),
                        message: "身分或同意狀態已變更；本次不會顯示結果。"
                    )
                    return
                }
                let recoveredAge = self.now().timeIntervalSince(
                    metadata.createdAt
                )
                guard recoveredAge >= 0,
                      recoveredAge <=
                        KeyboardSharedConfig.resultsPresentationTTL
                else {
                    try? self.network.clearPendingAfterPresentation(
                        requestID: metadata.requestId,
                        session: session
                    )
                    self.setState(
                        .failed(nil, .newRequestAfterUserChange),
                        message:
                            "上一筆回覆已超過安全插入時間，請重新確認截圖。"
                    )
                    return
                }
                let freshContext = self.optionalContext(
                    for: session.userId
                )
                guard freshContext?.revision ==
                        metadata.contextRevision
                else {
                    try? self.network.clearPendingAfterPresentation(
                        requestID: metadata.requestId,
                        session: session
                    )
                    self.setState(
                        .failed(nil, .newRequestAfterUserChange),
                        message: "目前脈絡已變更；舊結果不會顯示或插入。"
                    )
                    return
                }
                self.context = freshContext
                self.latestScreenshot = screenshot
                self.previewImage = self.trimmedPreview(screenshot)
                self.preparedImage = prepared
                self.presentRecoveredPending(
                    recovered,
                    prepared: prepared,
                    session: session,
                    receipt: receipt,
                    documentIdentifier: documentIdentifier
                )
            }
        }
    }

    private func presentRecoveredPending(
        _ recovered: KeyboardAssistRecoveredPending,
        prepared: KeyboardPreparedImage,
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        documentIdentifier: UUID
    ) {
        let metadata = recovered.metadata
        let binding = KeyboardRequestBinding(
            operationID: makeUUID(),
            requestID: metadata.requestId,
            ownerUserID: metadata.ownerUserId,
            documentIdentifier: documentIdentifier,
            assetIdentifier: metadata.assetIdentifier,
            screenshotHash: prepared.sha256,
            partnerID: metadata.partnerId,
            contextRevision: metadata.contextRevision,
            createdAt: metadata.createdAt
        )
        let request = KeyboardAssistV1Request(
            requestId: metadata.requestId,
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: prepared.jpegData.base64EncodedString()
            ),
            speakerOverride: metadata.speakerOverride,
            voice: metadata.voice
        )
        let authorization = KeyboardAssistSendAuthorization(
            binding: binding,
            capability: receipt,
            hasScreenshotAIConsent: true,
            consentVersion:
                KeyboardSharedConfig.keyboardScreenshotConsentVersion,
            previewConfirmedAt: metadata.createdAt
        )
        let operation = KeyboardScreenshotOutboundOperation(
            request: request,
            binding: binding,
            authorization: authorization,
            session: session
        )
        outbound = operation
        stateMachine = KeyboardAssistStateMachine(
            state: .lookingUpStatus(binding)
        )
        presentNetworkResponse(
            recovered.response,
            operation: operation,
            presentedAt: metadata.createdAt
        )
    }

    private func prepareAndSubmit(
        screenshot: LatestScreenshot,
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        documentIdentifier: UUID,
        speakerOverride: KeyboardSpeakerOverride,
        previewConfirmedAt: Date
    ) {
        guard consentProvider.usableConsent(
            ownerUserId: session.userId,
            now: now()
        ) != nil else {
            contextDidChange()
            setMessage("截圖 AI 同意已更新，請重新分析。")
            return
        }
        let freshContext = optionalContext(for: session.userId)
        guard freshContext?.revision == context?.revision else {
            contextDidChange()
            setMessage("偏好脈絡已更新，請重新分析。")
            return
        }
        context = freshContext
        let workID = makeUUID()
        preprocessingID = workID
        let expectedLifecycle = lifecycleID
        let expectedContextRevision = freshContext?.revision
        setMessage("正在本機壓縮截圖並移除原始中繼資料…")
        let overlayFraction = overlayFractionProvider(screenshot.creationDate)
        schedulePreprocessing { [weak self] in
            guard let self else { return }
            let result: Result<KeyboardPreparedImage, Error>
            do {
                result = .success(
                    try self.preprocessor.prepare(
                        screenshot.thumbnail,
                        croppingBottomFraction: overlayFraction
                    )
                )
            } catch {
                result = .failure(error)
            }
            self.deliverToMain { [weak self] in
                guard let self,
                      self.lifecycleID == expectedLifecycle,
                      self.preprocessingID == workID
                else {
                    return
                }
                self.preprocessingID = nil
                guard case .success(let prepared) = result,
                      self.currentIdentityMatches(
                        ownerUserID: session.userId,
                        documentIdentifier: documentIdentifier
                      ),
                      let currentConsent =
                        self.consentProvider.usableConsent(
                            ownerUserId: session.userId,
                            now: self.now()
                        )
                else {
                    self.contextDidChange()
                    self.setMessage(
                        "截圖處理失敗或偏好已更新，請重新預覽。"
                    )
                    return
                }
                let currentContext = self.optionalContext(
                    for: session.userId
                )
                guard currentContext?.revision ==
                        expectedContextRevision
                else {
                    self.contextDidChange()
                    self.setMessage(
                        "偏好脈絡已更新，請重新預覽。"
                    )
                    return
                }
                self.preparedImage = prepared
                self.context = currentContext
                self.submitPreparedImage(
                    prepared,
                    screenshot: screenshot,
                    session: session,
                    receipt: receipt,
                    documentIdentifier: documentIdentifier,
                    context: currentContext,
                    consent: currentConsent,
                    speakerOverride: speakerOverride,
                    previewConfirmedAt: previewConfirmedAt
                )
            }
        }
    }

    private func submitPreparedImage(
        _ prepared: KeyboardPreparedImage,
        screenshot: LatestScreenshot,
        session: KeyboardAuthSession,
        receipt: KeyboardAssistCapabilityReceipt,
        documentIdentifier: UUID,
        context: KeyboardContextEnvelope?,
        consent: KeyboardScreenshotConsentReceipt,
        speakerOverride: KeyboardSpeakerOverride,
        previewConfirmedAt: Date
    ) {
        let submittedAt = now()
        let previewAge = submittedAt.timeIntervalSince(
            previewConfirmedAt
        )
        guard previewAge >= 0,
              previewAge <= KeyboardSharedConfig.resultsPresentationTTL
        else {
            failCurrentOperation(
                policy: .terminal,
                message: "這次預覽確認已過期；本次不會送出。"
            )
            return
        }
        guard currentIdentityMatches(
            ownerUserID: session.userId,
            documentIdentifier: documentIdentifier
        ), receipt.isUsable(
            ownerUserId: session.userId,
            now: submittedAt
        ), consent.isUsable(
            ownerUserId: session.userId,
            now: submittedAt
        ) else {
            failCurrentOperation(
                policy: .terminal,
                message: "功能權限或登入已更新，請重新開始。"
            )
            return
        }

        let operationID = makeUUID()
        let requestID = makeUUID()
        let createdAt = submittedAt
        let binding = KeyboardRequestBinding(
            operationID: operationID,
            requestID: requestID,
            ownerUserID: session.userId,
            documentIdentifier: documentIdentifier,
            assetIdentifier: screenshot.assetIdentifier,
            screenshotHash: prepared.sha256,
            partnerID: nil,
            contextRevision: context?.revision,
            createdAt: createdAt
        )
        let request = KeyboardAssistV1Request(
            requestId: requestID,
            image: KeyboardAssistImage(
                mediaType: "image/jpeg",
                data: prepared.jpegData.base64EncodedString()
            ),
            speakerOverride: speakerOverride,
            voice: voiceOverride.map {
                // An explicit choice replaces the pair outright; a secondary
                // voice from the app would otherwise quietly dilute it.
                KeyboardAssistVoice(primary: $0, secondary: nil)
            } ?? KeyboardAssistVoice(
                primary: context?.globalVoice.primary,
                secondary: context?.globalVoice.secondary
            ),
            priorTurn: priorTurnForCurrentDocument()
        )
        let authorization = KeyboardAssistSendAuthorization(
            binding: binding,
            capability: receipt,
            hasScreenshotAIConsent: consent.enabled,
            consentVersion: consent.version,
            previewConfirmedAt: previewConfirmedAt
        )
        let operation = KeyboardScreenshotOutboundOperation(
            request: request,
            binding: binding,
            authorization: authorization,
            session: session
        )
        outbound = operation
        stateMachine = KeyboardAssistStateMachine(
            state: .localPreview(
                KeyboardScreenshotSummary(
                    assetIdentifier: screenshot.assetIdentifier,
                    creationDate: screenshot.creationDate
                )
            )
        )
        stateMachine.send(.generationStarted(binding))
        stateMachine.send(
            .generationStageChanged(
                operationID: operationID,
                stage: .readingChat
            )
        )
        setMessage("正在讀取這張截圖的對話脈絡…")
        send(operation)
    }

    private func send(
        _ operation: KeyboardScreenshotOutboundOperation
    ) {
        activeTask?.cancel()
        let expectedLifecycle = lifecycleID
        activeTask = network.submit(
            operation.request,
            session: operation.session,
            authorization: operation.authorization
        ) { [weak self] result in
            self?.handleNetworkResult(
                result,
                operation: operation,
                expectedLifecycle: expectedLifecycle,
                origin: .post
            )
        }
    }

    private func lookupSameRequest(
        _ operation: KeyboardScreenshotOutboundOperation
    ) {
        guard currentIdentityMatches(
            ownerUserID: operation.session.userId,
            documentIdentifier:
                operation.binding.documentIdentifier
        ) else {
            ownerDidChange()
            return
        }
        stateMachine.send(
            .statusLookupStarted(
                operationID: operation.binding.operationID
            )
        )
        setMessage("連線不確定，正在用同一筆 requestId 查詢結果…")
        activeTask?.cancel()
        let expectedLifecycle = lifecycleID
        activeTask = network.lookup(
            requestID: operation.binding.requestID,
            session: operation.session
        ) { [weak self] result in
            self?.handleNetworkResult(
                result,
                operation: operation,
                expectedLifecycle: expectedLifecycle,
                origin: .lookup
            )
        }
    }

    private func handleNetworkResult(
        _ result: Result<
            KeyboardAssistResponse,
            KeyboardAssistAPIError
        >,
        operation: KeyboardScreenshotOutboundOperation,
        expectedLifecycle: UUID,
        origin: NetworkOrigin
    ) {
        guard lifecycleID == expectedLifecycle,
              outbound?.binding == operation.binding,
              currentIdentityMatches(
                ownerUserID: operation.session.userId,
                documentIdentifier:
                    operation.binding.documentIdentifier
              )
        else {
            return
        }
        activeTask = nil
        switch result {
        case .success(let response):
            presentNetworkResponse(
                response,
                operation: operation,
                presentedAt: now()
            )
        case .failure(let error):
            handleNetworkError(
                error,
                operation: operation,
                origin: origin
            )
        }
    }

    private func presentNetworkResponse(
        _ response: KeyboardAssistResponse,
        operation: KeyboardScreenshotOutboundOperation,
        presentedAt: Date
    ) {
        stateMachine.send(
            .responseReceived(
                operationID: operation.binding.operationID,
                response: response,
                presentedAt: presentedAt
            )
        )
        switch (response, stateMachine.state) {
        case (.ready(let ready), .resultsPreview):
            // Everything shown to the user can leak back through a later
            // screenshot, and is also what the next "換一批" must not repeat.
            rememberOffered(ready.options.map(\.text))
            // Keep the durable record until an explicit candidate insertion.
            setMessage(Self.readyMessage(ready))
        case (
            .needsSpeakerConfirmation,
            .needsSpeakerConfirmation
        ):
            // Keep the original settled request until the user resolves the
            // speaker side; dismissing the keyboard must remain recoverable.
            setMessage("請確認哪一側是你；確認後才會重新分析。")
        case (
            .partnerMismatchConfirmation,
            .partnerConfirmation
        ):
            failCurrentOperation(
                policy: .terminal,
                message: "截圖無法安全對應脈絡；本次不會使用伴侶資料。"
            )
            try? network.clearPendingAfterPresentation(
                requestID: operation.binding.requestID,
                session: operation.session
            )
        default:
            break
        }
    }

    private func handleNetworkError(
        _ error: KeyboardAssistAPIError,
        operation: KeyboardScreenshotOutboundOperation,
        origin: NetworkOrigin
    ) {
        switch error {
        case .transportUncertain:
            if origin == .post {
                markFailed(
                    binding: operation.binding,
                    policy: .lookupSameRequest
                )
                lookupSameRequest(operation)
            } else {
                failCurrentOperation(
                    policy: .lookupSameRequest,
                    message: "結果仍在確認；只能以同一筆 requestId 再查詢。"
                )
            }
        case .requestPending:
            failCurrentOperation(
                policy: .lookupSameRequest,
                message: "還在產生中，稍等一下再看結果；不會多扣一次。"
            )
        case .server(_, let disposition, _):
            let policy = retryPolicy(for: disposition)
            if origin == .post, policy == .lookupSameRequest {
                markFailed(binding: operation.binding, policy: policy)
                lookupSameRequest(operation)
            } else {
                failCurrentOperation(
                    policy: policy,
                    message: message(for: policy)
                )
            }
        case .unauthorized:
            ownerDidChange()
            setMessage("登入已過期，請開啟 VibeSync 後再回來。")
        case .capabilityUnavailable:
            failCurrentOperation(
                policy: .terminal,
                message: "這項功能目前未開放。"
            )
        case .quotaExhausted:
            failCurrentOperation(
                policy: .terminal,
                message: "本期額度已用完；不會自動重送。"
            )
        case .modelRateLimited:
            failCurrentOperation(
                policy: .retrySamePayload,
                message: "請稍後再試；會沿用同一筆安全請求。"
            )
        case .requestNotFound, .requestExpiredNoCharge:
            failCurrentOperation(
                policy: .newRequestAfterUserChange,
                message: "原請求已失效，請重新預覽截圖後再產生。"
            )
        case .unsupportedConversation:
            stateMachine = KeyboardAssistStateMachine(
                state: .recognitionRejected
            )
            setMessage("這張圖不像可安全辨識的雙人對話，本次未產生回覆。")
        case .replayMismatch, .invalidRequest, .invalidResponse:
            failCurrentOperation(
                policy: .terminal,
                message: "請求驗證失敗；本次不會自動重送。"
            )
        case .pendingReplayUnavailable:
            failCurrentOperation(
                policy: .terminal,
                message: "本機安全儲存暫時不可用；本次未送出，請稍後再試。"
            )
        case .noPendingReplay:
            failCurrentOperation(
                policy: .terminal,
                message: "找不到可安全恢復的請求，請重新預覽截圖。"
            )
        }
    }

    private static func readyMessage(
        _ ready: KeyboardAssistReadyResponse
    ) -> String {
        let scope = ready.source.scope == .screenshotPlusGlobalVoice
            ? "只根據這張截圖判讀，並套用你的語氣偏好"
            : "只根據這張截圖判讀"
        let uncertainty = ready.uncertainty.map {
            "；限制：\($0)"
        } ?? ""
        return "\(scope)，不會假裝知道其他對話。\(ready.cue)\(uncertainty)\n點候選才插入。"
    }

    private func retryPolicy(
        for disposition: KeyboardAssistRetryDisposition
    ) -> KeyboardAssistRetryPolicy {
        switch disposition {
        case .lookupSameRequest:
            return .lookupSameRequest
        case .retrySamePayload:
            return .retrySamePayload
        case .newRequestAfterUserChange:
            return .newRequestAfterUserChange
        case .terminalClear:
            return .terminal
        }
    }

    /// These are read by someone mid-conversation who just wants a reply, not
    /// by whoever wrote the retry contract. Say what happened and what they can
    /// do; "payload" and "requestId" belong in the logs.
    private func message(
        for policy: KeyboardAssistRetryPolicy
    ) -> String {
        switch policy {
        case .lookupSameRequest:
            return "結果還沒確認，正在查同一筆；額度不會重複計算。"
        case .retrySamePayload:
            return "這次沒送成功，可以再試一次；不會多扣一次。"
        case .newRequestAfterUserChange:
            return "這張截圖已經過期了，重新截一次再試。"
        case .terminal:
            return "這次停在這裡，不會自己重送。"
        }
    }

    private func handleScreenshotError(
        _ error: LatestScreenshotError
    ) {
        switch error {
        case .capabilityRequired:
            setState(.featureUnavailable, message: nil)
        case .consentRequired:
            setState(
                .consentRequired,
                message: "請先在 VibeSync 開啟截圖 AI 同意。"
            )
        case .permissionRequired(let status):
            setState(
                .photoPermissionRequired(status),
                message: "請在 VibeSync App 內開啟照片權限。"
            )
        case .noRecentScreenshot:
            // Not an error. Opening the keyboard is not supposed to analyse
            // anything on its own any more, so the empty panel is an
            // invitation, not a failure report.
            setState(
                .idle,
                message: "截圖這則對話，就會自動分析"
            )
        case .photoLibraryFailed:
            setState(
                .failed(nil, .terminal),
                message: "目前無法讀取本機截圖；沒有任何圖片被送出。"
            )
        }
    }

    private func currentBoundSession() -> KeyboardAuthSession? {
        guard let session = sessionProvider(),
              session.userId == boundOwnerUserID
        else {
            return nil
        }
        return session
    }

    private func optionalContext(
        for ownerUserID: String
    ) -> KeyboardContextEnvelope? {
        do {
            return try contextProvider(ownerUserID)
        } catch {
            // Context enrichment is optional for the single-screenshot v1
            // contract. A missing or invalid snapshot must never be treated
            // as knowledge about the person in the screenshot.
            return nil
        }
    }

    private func currentIdentityMatches(
        ownerUserID: String,
        documentIdentifier: UUID?
    ) -> Bool {
        guard let session = sessionProvider() else { return false }
        return session.userId == ownerUserID &&
            boundOwnerUserID == ownerUserID &&
            boundDocumentIdentifier == documentIdentifier &&
            documentProvider() == documentIdentifier
    }

    private func markFailed(
        binding: KeyboardRequestBinding,
        policy: KeyboardAssistRetryPolicy
    ) {
        stateMachine.send(
            .generationFailed(
                operationID: binding.operationID,
                retryPolicy: policy
            )
        )
        notify()
    }

    private func failCurrentOperation(
        policy: KeyboardAssistRetryPolicy,
        message: String
    ) {
        if let binding = outbound?.binding,
           stateMachine.state.networkResponseBinding == binding
        {
            markFailed(binding: binding, policy: policy)
        } else {
            stateMachine = KeyboardAssistStateMachine(
                state: .failed(outbound?.binding, policy)
            )
        }
        setMessage(message)
    }

    private func invalidateForChangedInput(
        event: KeyboardAssistEvent,
        message: String
    ) {
        invalidateAsyncWork()
        stateMachine.send(event)
        clearBoundData()
        setMessage(message)
    }

    private func invalidateAsyncWork() {
        activeTask?.cancel()
        activeTask = nil
        lifecycleID = makeUUID()
        insertionCheckID = nil
        speakerChoiceCheckID = nil
        previewConfirmationCheckID = nil
        newBatchCheckID = nil
        preprocessingID = nil
    }

    private func clearBoundData(keepingIdentity: Bool = false) {
        capability = nil
        context = nil
        latestScreenshot = nil
        previewImage = nil
        preparedImage = nil
        outbound = nil
        if !keepingIdentity {
            boundOwnerUserID = nil
            boundDocumentIdentifier = nil
        }
    }

    private func setState(
        _ state: KeyboardAssistState,
        message: String?
    ) {
        stateMachine = KeyboardAssistStateMachine(state: state)
        self.message = message
        notify()
    }

    private func setMessage(_ message: String?) {
        self.message = message
        notify()
    }

    private func notify() {
        onRender(
            KeyboardScreenshotAssistRenderState(
                state: stateMachine.state,
                message: message
            )
        )
    }
}
