import UIKit

final class KeyboardViewController: UIInputViewController {
    /// `assist` is the product: screenshot in, replies out, nothing else on
    /// screen. `text` is the older paste-a-message flow, kept because it is the
    /// only path when the conversation cannot be screenshotted, but it no
    /// longer shares the surface — competing for the same half-screen made the
    /// screenshot panel read as one widget among many.
    private enum Mode { case assist, text, typing }
    private struct PendingLegacyReply {
        let success: KeyboardReplySuccess
        let operationID: UUID
        let ownerUserID: String
        let documentIdentifier: UUID?
    }

    private let ink = UIColor(red: 21/255, green: 12/255, blue: 36/255, alpha: 1)
    private let surface = UIColor(red: 42/255, green: 24/255, blue: 64/255, alpha: 1)
    private let primary = UIColor(red: 107/255, green: 78/255, blue: 230/255, alpha: 1)
    private let flame = UIColor(red: 255/255, green: 106/255, blue: 43/255, alpha: 1)

    private let api = KeyboardAPI()
    private let rootStack = UIStackView()
    private let assistPanel = UIStackView()
    private let aiPanel = UIStackView()
    private let typingPanel = UIStackView()
    private let typingBannerTitle = UILabel()
    private let typingBannerSubtitle = UILabel()
    private let assistIdleView = UIStackView()
    private let assistIdleTitle = UILabel()
    private let assistIdleSubtitle = UILabel()
    private let assistPreSessionButton = UIButton(type: .system)
    private let contextLabel = UILabel()
    private let statusLabel = UILabel()
    private let pasteButton = UIButton(type: .system)
    private let resultButton = UIButton(type: .system)
    private let screenshotPanel = UIStackView()
    private let screenshotStatusLabel = UILabel()
    private let screenshotStatusBubble = UIStackView()
    private let screenshotProgressRow = UIStackView()
    private let screenshotPreviewImageView = UIImageView()
    private let screenshotRetryButton = UIButton(type: .system)
    private let screenshotCancelButton = UIButton(type: .system)
    private let screenshotSpeakerRow = UIStackView()
    private let screenshotCandidateStack = UIStackView()
    private let screenshotContinuationHint = UILabel()
    private let analysisCard = UIStackView()
    private let analysisCueLabel = UILabel()
    private let analysisStateLabel = UILabel()
    private let analysisUncertaintyLabel = UILabel()
    private let screenshotSwapButton = UIButton(type: .system)
    private let screenshotActionRow = UIStackView()
    private let screenshotFlowMark = UILabel()
    private var isMarkPulsing = false
    private var styleButtons: [KeyboardReplyStyle: UIButton] = [:]
    private var loadedMessage = ""
    private var pendingLegacyReply: PendingLegacyReply?
    private var activeLegacyOperationID: UUID?
    private var isGenerating = false
    private var mode: Mode = .assist
    private var deleteTimer: Timer?
    private var lastObservedOwnerUserID: String?
    private var screenshotRenderState: KeyboardAssistState = .boot
    private var keyboardVisibleSince: Date?
    private var overlayHeightSamples: [(at: Date, height: CGFloat)] = []
    private var statusLineBorrowed = false
    private lazy var replyInsertionCoordinator =
        ReplyInsertionCoordinator { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }
    private lazy var screenshotCoordinator =
        KeyboardScreenshotAssistCoordinator(
            documentProvider: { [weak self] in
                guard let self else { return nil }
                return self.currentDocumentIdentifier
            },
            overlayFractionProvider: { [weak self] capturedAt in
                self?.keyboardOverlayFraction(capturedAt: capturedAt) ?? 0
            },
            sessionStartedAt: { [weak self] in
                self?.keyboardVisibleSince
            },
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onRender: { [weak self] renderState in
                self?.renderScreenshotAssist(renderState)
            }
        )

    /// A screenshot captured while this keyboard was on screen contains our own
    /// panel — including the candidates we just produced. Everything below the
    /// host app's input row is our UI, so it is trimmed before upload. A capture
    /// taken before the keyboard appeared is left untouched, because there the
    /// bottom of the image is real conversation.
    private func keyboardOverlayFraction(capturedAt: Date) -> CGFloat {
        guard let visibleSince = keyboardVisibleSince,
              capturedAt >= visibleSince
        else {
            return 0
        }
        let screenHeight = (
            view.window?.windowScene?.screen ?? UIScreen.main
        ).bounds.height
        let overlayHeight = heightWhenCaptured(capturedAt)
        guard screenHeight > 0, overlayHeight > 0 else { return 0 }
        // Clamped so an unexpected geometry reading can never eat the chat.
        return min(overlayHeight / screenHeight, 0.7)
    }

    /// The panel is short while it waits for a screenshot and tall once results
    /// are on screen, so by the time a capture reaches preprocessing the
    /// keyboard is usually taller than it was in the picture. Trimming by
    /// today's height would eat conversation the shot really did contain — and
    /// a capture with two messages left in it is exactly what comes back as
    /// "not a one-to-one chat".
    private func heightWhenCaptured(_ capturedAt: Date) -> CGFloat {
        overlayHeightSamples.last(
            where: { $0.at <= capturedAt }
        )?.height ?? view.bounds.height
    }

    /// Remembers how tall the keyboard actually was, and when. Only transitions
    /// are kept, so this stays a handful of entries per keyboard session.
    private func recordOverlayHeightSample() {
        let height = view.bounds.height
        guard height > 0 else { return }
        if let last = overlayHeightSamples.last, last.height == height {
            return
        }
        overlayHeightSamples.append((at: Date(), height: height))
        if overlayHeightSamples.count > 12 {
            overlayHeightSamples.removeFirst()
        }
    }

    /// UIKit declares `documentIdentifier` as non-optional, but it is genuinely
    /// nil until a document is attached to the input session. Reading it
    /// directly makes Swift bridge a nil `NSUUID` into `UUID`, which traps
    /// (EXC_BREAKPOINT in `UUID._unconditionallyBridgeFromObjectiveC`) and kills
    /// the extension before the keyboard can appear. Read it through the ObjC
    /// runtime so an absent identifier stays nil and every binding fails closed.
    private var currentDocumentIdentifier: UUID? {
        guard let proxy = textDocumentProxy as? NSObject else { return nil }
        let selector = Selector(("documentIdentifier"))
        guard proxy.responds(to: selector),
              let identifier = proxy.perform(selector)?
                  .takeUnretainedValue() as? NSUUID
        else {
            return nil
        }
        return identifier as UUID
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ink
        configureRoot()
        configureAssistPanel()
        configureScreenshotAssist()
        configureAIPanel()
        configureTypingPanel()
        show(.assist)
        refreshAvailability()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardVisibleSince = Date()
        refreshAvailability()
        refreshScreenshotIdentity()
        screenshotCoordinator.start(hasFullAccess: hasFullAccess)
        // Attunely's keyboard picks up the next screenshot on its own; ours has
        // to do the same, otherwise the user must close and reopen the keyboard
        // between turns.
        screenshotCoordinator.startObservingLibrary(
            hasFullAccess: hasFullAccess
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardVisibleSince = nil
        overlayHeightSamples.removeAll()
        invalidatePendingReply()
        screenshotCoordinator.viewDidDisappear()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        invalidatePendingReply()
        screenshotCoordinator.documentDidChange(
            to: currentDocumentIdentifier
        )
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        invalidatePendingReply()
        screenshotCoordinator.documentDidChange(
            to: currentDocumentIdentifier
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recordOverlayHeightSample()
        updatePreferredHeight()
    }

    private func configureRoot() {
        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -7),
        ])
    }

    /// The screenshot flow's own surface. Everything above the utility row is
    /// about one screenshot: what we are doing with it, and what you can send.
    private func configureAssistPanel() {
        assistPanel.axis = .vertical
        assistPanel.spacing = 7
        rootStack.addArrangedSubview(assistPanel)

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 8
        screenshotFlowMark.text = "💜 VibeSync"
        screenshotFlowMark.textColor = .white
        screenshotFlowMark.font = .systemFont(ofSize: 15, weight: .bold)
        header.addArrangedSubview(screenshotFlowMark)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(
            makeButton("單句速回", action: #selector(showTextAssist))
        )
        assistPanel.addArrangedSubview(header)

        configureAssistIdleView()
    }

    /// What the user sees before they have done anything. It has to answer one
    /// question — what do I do now — because there is no button to press.
    private func configureAssistIdleView() {
        assistIdleView.axis = .vertical
        assistIdleView.spacing = 4
        assistIdleView.alignment = .center
        assistIdleView.isLayoutMarginsRelativeArrangement = true
        assistIdleView.layoutMargins = UIEdgeInsets(
            top: 18,
            left: 12,
            bottom: 18,
            right: 12
        )

        assistIdleTitle.text = "截圖這則對話就開始"
        assistIdleTitle.textColor = .white
        assistIdleTitle.font = .systemFont(ofSize: 17, weight: .bold)
        assistIdleTitle.textAlignment = .center
        assistIdleView.addArrangedSubview(assistIdleTitle)

        assistIdleSubtitle.text = "鍵盤開著時截圖，會自動分析並給你回覆"
        assistIdleSubtitle.textColor = UIColor.white.withAlphaComponent(0.6)
        assistIdleSubtitle.font = .systemFont(ofSize: 12)
        assistIdleSubtitle.textAlignment = .center
        assistIdleSubtitle.numberOfLines = 2
        assistIdleView.addArrangedSubview(assistIdleSubtitle)

        // "Screenshot the chat, then switch keyboards" is a habit, and that
        // capture is older than this keyboard session. It is not analysed
        // automatically — that would put a charge behind merely opening the
        // keyboard — but it must not be a dead end either.
        assistPreSessionButton.setTitle("分析我剛剛截的圖", for: .normal)
        styleScreenshotButton(assistPreSessionButton, color: surface)
        assistPreSessionButton.addTarget(
            self,
            action: #selector(retryScreenshotAssist),
            for: .touchUpInside
        )
        assistPreSessionButton.isHidden = true
        assistIdleView.addArrangedSubview(assistPreSessionButton)

        assistPanel.addArrangedSubview(assistIdleView)
    }

    private func configureAIPanel() {
        aiPanel.axis = .vertical
        aiPanel.spacing = 7
        rootStack.addArrangedSubview(aiPanel)

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 8
        let mark = UILabel()
        mark.text = "💜 文字模式"
        mark.textColor = .white
        mark.font = .systemFont(ofSize: 15, weight: .bold)
        header.addArrangedSubview(mark)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(
            makeButton("截圖", action: #selector(showAssist))
        )
        aiPanel.addArrangedSubview(header)

        let contextRow = UIStackView()
        contextRow.axis = .horizontal
        contextRow.spacing = 7
        contextLabel.text = "先複製對方訊息，再點載入"
        contextLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        contextLabel.font = .systemFont(ofSize: 13)
        contextLabel.numberOfLines = 2
        contextLabel.backgroundColor = surface
        contextLabel.layer.cornerRadius = 9
        contextLabel.layer.masksToBounds = true
        contextLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pasteButton.setTitle("載入", for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        pasteButton.backgroundColor = flame
        pasteButton.tintColor = .white
        pasteButton.layer.cornerRadius = 9
        pasteButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        pasteButton.addTarget(self, action: #selector(loadClipboard), for: .touchUpInside)
        contextRow.addArrangedSubview(contextLabel)
        contextRow.addArrangedSubview(pasteButton)
        aiPanel.addArrangedSubview(contextRow)

        let firstRow = UIStackView()
        let secondRow = UIStackView()
        for row in [firstRow, secondRow] {
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 7
        }
        for (index, style) in KeyboardReplyStyle.allCases.enumerated() {
            let button = makeButton(style.title, action: #selector(generateReply(_:)))
            button.accessibilityIdentifier = style.rawValue
            styleButtons[style] = button
            (index < 3 ? firstRow : secondRow).addArrangedSubview(button)
        }
        secondRow.addArrangedSubview(makeButton("清空", action: #selector(clearContext)))
        aiPanel.addArrangedSubview(firstRow)
        aiPanel.addArrangedSubview(secondRow)

        statusLabel.text = Self.emptyStateStatus
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        aiPanel.addArrangedSubview(statusLabel)

        resultButton.setTitleColor(.white, for: .normal)
        resultButton.titleLabel?.font = .systemFont(
            ofSize: 14,
            weight: .semibold
        )
        resultButton.titleLabel?.numberOfLines = 2
        resultButton.titleLabel?.textAlignment = .center
        resultButton.backgroundColor = primary
        resultButton.layer.cornerRadius = 9
        resultButton.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 44
        ).isActive = true
        resultButton.addTarget(
            self,
            action: #selector(insertGeneratedReply),
            for: .touchUpInside
        )
        resultButton.isHidden = true
        aiPanel.addArrangedSubview(resultButton)
        // No utility row. 空白／換行／⌫ cannot type a word between them, so
        // editing always meant switching keyboards anyway; they only ever cost
        // a row. The globe is the system's.
    }

    private func configureScreenshotAssist() {
        screenshotPanel.axis = .vertical
        screenshotPanel.spacing = 7
        screenshotPanel.isHidden = true

        // Laid out like the conversation it came from: the capture sits on the
        // left where the other person's messages are, and what we have to say
        // about it answers from the right.
        screenshotStatusLabel.textColor =
            UIColor.white.withAlphaComponent(0.85)
        screenshotStatusLabel.font = .systemFont(ofSize: 13)
        screenshotStatusLabel.numberOfLines = 4
        screenshotStatusLabel.textAlignment = .left

        screenshotStatusBubble.axis = .vertical
        screenshotStatusBubble.isLayoutMarginsRelativeArrangement = true
        screenshotStatusBubble.layoutMargins = UIEdgeInsets(
            top: 10,
            left: 13,
            bottom: 10,
            right: 13
        )
        screenshotStatusBubble.backgroundColor = surface
        screenshotStatusBubble.layer.cornerRadius = 15
        screenshotStatusBubble.layer.masksToBounds = true
        screenshotStatusBubble.addArrangedSubview(screenshotStatusLabel)

        screenshotPreviewImageView.contentMode = .scaleAspectFill
        screenshotPreviewImageView.backgroundColor = surface
        screenshotPreviewImageView.layer.cornerRadius = 8
        screenshotPreviewImageView.layer.masksToBounds = true
        screenshotPreviewImageView.setContentHuggingPriority(
            .required,
            for: .horizontal
        )
        NSLayoutConstraint.activate([
            screenshotPreviewImageView.widthAnchor.constraint(
                equalToConstant: 104
            ),
            screenshotPreviewImageView.heightAnchor.constraint(
                equalToConstant: 150
            ),
        ])
        screenshotPreviewImageView.isHidden = true

        screenshotProgressRow.axis = .horizontal
        screenshotProgressRow.alignment = .top
        screenshotProgressRow.spacing = 8
        screenshotProgressRow.addArrangedSubview(screenshotPreviewImageView)
        screenshotProgressRow.addArrangedSubview(UIView())
        screenshotProgressRow.addArrangedSubview(screenshotStatusBubble)
        screenshotPanel.addArrangedSubview(screenshotProgressRow)

        configureAnalysisCard()

        screenshotRetryButton.setTitle("再試一次", for: .normal)
        styleScreenshotButton(
            screenshotRetryButton,
            color: primary
        )
        screenshotRetryButton.addTarget(
            self,
            action: #selector(retryScreenshotAssist),
            for: .touchUpInside
        )
        screenshotSwapButton.setTitle("換一批", for: .normal)
        styleScreenshotButton(screenshotSwapButton, color: primary)
        screenshotSwapButton.addTarget(
            self,
            action: #selector(requestNewCandidateBatch),
            for: .touchUpInside
        )
        screenshotSwapButton.isHidden = true

        screenshotSpeakerRow.axis = .horizontal
        screenshotSpeakerRow.spacing = 7
        screenshotSpeakerRow.distribution = .fillEqually
        let leftButton = makeButton(
            "左邊是我",
            action: #selector(confirmLeftSpeaker)
        )
        let rightButton = makeButton(
            "右邊是我",
            action: #selector(confirmRightSpeaker)
        )
        screenshotSpeakerRow.addArrangedSubview(leftButton)
        screenshotSpeakerRow.addArrangedSubview(rightButton)
        screenshotPanel.addArrangedSubview(screenshotSpeakerRow)

        screenshotCandidateStack.axis = .vertical
        screenshotCandidateStack.spacing = 7
        screenshotPanel.addArrangedSubview(screenshotCandidateStack)

        // The loop only works if the user knows there is a loop.
        screenshotContinuationHint.text = "💡 對方回覆後再截一次圖，就能接著聊"
        screenshotContinuationHint.font = .systemFont(ofSize: 11)
        screenshotContinuationHint.textColor =
            UIColor.white.withAlphaComponent(0.55)
        screenshotContinuationHint.textAlignment = .center
        screenshotContinuationHint.numberOfLines = 2
        screenshotContinuationHint.isHidden = true
        screenshotPanel.addArrangedSubview(screenshotContinuationHint)

        screenshotPanel.addArrangedSubview(screenshotRetryButton)

        // Cancelling is the escape hatch, not the thing the user came for, so it
        // shares the row it used to sit below. Full width made it read like a
        // peer of 換一批 and cost the suggestions a row of their own.
        screenshotCancelButton.setTitle("✕", for: .normal)
        screenshotCancelButton.accessibilityLabel = "取消，不送出截圖"
        styleScreenshotButton(
            screenshotCancelButton,
            color: surface
        )
        screenshotCancelButton.widthAnchor.constraint(
            equalToConstant: 44
        ).isActive = true
        screenshotCancelButton.addTarget(
            self,
            action: #selector(cancelScreenshotAssist),
            for: .touchUpInside
        )
        screenshotActionRow.axis = .horizontal
        screenshotActionRow.spacing = 7
        screenshotSwapButton.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        screenshotActionRow.addArrangedSubview(screenshotSwapButton)
        screenshotActionRow.addArrangedSubview(screenshotCancelButton)
        screenshotActionRow.isHidden = true
        screenshotPanel.addArrangedSubview(screenshotActionRow)

        assistPanel.addArrangedSubview(screenshotPanel)
        // No utility row here either; see configureAIPanel.
        resetScreenshotControls()
    }

    /// The analysis is the part a coach owes the user: what is going on, and
    /// whether it is even their turn. Deliberately three short lines rather
    /// than a scrollable essay — the keyboard already eats half the screen.
    private func configureAnalysisCard() {
        analysisCard.axis = .vertical
        analysisCard.spacing = 4
        analysisCard.isHidden = true
        analysisCard.isLayoutMarginsRelativeArrangement = true
        analysisCard.layoutMargins = UIEdgeInsets(
            top: 9,
            left: 11,
            bottom: 9,
            right: 11
        )
        analysisCard.backgroundColor = surface
        analysisCard.layer.cornerRadius = 10
        analysisCard.layer.masksToBounds = true

        analysisCueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        analysisCueLabel.textColor = .white
        analysisCueLabel.numberOfLines = 3
        analysisCard.addArrangedSubview(analysisCueLabel)

        analysisStateLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        analysisStateLabel.numberOfLines = 1
        analysisCard.addArrangedSubview(analysisStateLabel)

        analysisUncertaintyLabel.font = .systemFont(ofSize: 11)
        analysisUncertaintyLabel.textColor =
            UIColor.white.withAlphaComponent(0.62)
        analysisUncertaintyLabel.numberOfLines = 2
        analysisUncertaintyLabel.isHidden = true
        analysisCard.addArrangedSubview(analysisUncertaintyLabel)

        screenshotPanel.addArrangedSubview(analysisCard)
    }

    private func renderAnalysisCard(
        _ presentation: KeyboardResultsPresentation
    ) {
        guard !presentation.cue.isEmpty else {
            analysisCard.isHidden = true
            return
        }
        analysisCard.isHidden = false
        analysisCueLabel.text = "💡 \(presentation.cue)"
        switch presentation.turnState {
        case .replyDue:
            analysisStateLabel.text =
                "● 輪到你回 · 讀到 \(presentation.messageCount) 則"
            analysisStateLabel.textColor = flame
        case .optionalFollowUp:
            analysisStateLabel.text =
                "○ 她沒在等你回 · 讀到 \(presentation.messageCount) 則"
            analysisStateLabel.textColor =
                UIColor.white.withAlphaComponent(0.72)
        }
        // Saying what we could not read is cheaper than being confidently wrong.
        if let uncertainty = presentation.uncertainty,
           !uncertainty.isEmpty
        {
            analysisUncertaintyLabel.text = "⚠︎ \(uncertainty)"
            analysisUncertaintyLabel.isHidden = false
        } else {
            analysisUncertaintyLabel.isHidden = true
        }
    }

    private func strategyColor(
        _ strategy: KeyboardAssistStrategy
    ) -> UIColor {
        switch strategy {
        case .extend, .keepPace:
            return UIColor(red: 78/255, green: 132/255, blue: 230/255, alpha: 1)
        case .flirt, .buildConnection:
            return UIColor(red: 214/255, green: 84/255, blue: 168/255, alpha: 1)
        case .humor, .moveForward:
            return flame
        case .clarify:
            return UIColor(red: 96/255, green: 168/255, blue: 132/255, alpha: 1)
        case .deescalate:
            return UIColor(red: 120/255, green: 120/255, blue: 156/255, alpha: 1)
        }
    }

    /// Three parts per row: what kind of move this is, the line itself, and why
    /// it works. The third part is the whole difference between a coach and a
    /// word picker, and it used to be crammed into the button title.
    private func makeCandidateRow(
        _ option: KeyboardAssistOption
    ) -> UIView {
        let chip = UILabel()
        chip.text = strategyTitle(option.strategy)
        chip.font = .systemFont(ofSize: 11, weight: .semibold)
        chip.textColor = .white
        chip.textAlignment = .center
        chip.backgroundColor = strategyColor(option.strategy)
        chip.layer.cornerRadius = 7
        chip.layer.masksToBounds = true
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        chip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 62),
            chip.heightAnchor.constraint(equalToConstant: 24),
        ])

        let bubble = UIButton(type: .system)
        bubble.accessibilityIdentifier = option.candidateID
        bubble.setTitle(option.text, for: .normal)
        styleScreenshotButton(bubble, color: primary)
        bubble.contentHorizontalAlignment = .leading
        bubble.contentEdgeInsets = UIEdgeInsets(
            top: 8,
            left: 11,
            bottom: 8,
            right: 11
        )
        bubble.addTarget(
            self,
            action: #selector(insertScreenshotCandidate(_:)),
            for: .touchUpInside
        )

        let caption = UILabel()
        caption.text = "\(option.why) · \(option.effect)"
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = UIColor.white.withAlphaComponent(0.6)
        caption.numberOfLines = 2

        let column = UIStackView(arrangedSubviews: [bubble, caption])
        column.axis = .vertical
        column.spacing = 2

        let row = UIStackView(arrangedSubviews: [chip, column])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 7
        return row
    }

    private func styleScreenshotButton(
        _ button: UIButton,
        color: UIColor
    ) {
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(
            ofSize: 13,
            weight: .semibold
        )
        button.titleLabel?.numberOfLines = 3
        button.titleLabel?.textAlignment = .center
        button.backgroundColor = color
        button.layer.cornerRadius = 9
        button.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 40
        ).isActive = true
    }

    private func configureTypingPanel() {
        typingPanel.axis = .vertical
        typingPanel.spacing = 6
        rootStack.addArrangedSubview(typingPanel)

        // This panel only ever appears as the 4.4.1 compliance floor, before
        // 完整取用 is granted. A bare qwerty grid with no explanation reads as
        // a broken leftover — the banner is what makes it look intentional and
        // tells the user how to get the keyboard they installed this for.
        typingBannerTitle.text = "💜 VibeSync"
        typingBannerTitle.textColor = .white
        typingBannerTitle.font = .systemFont(ofSize: 15, weight: .bold)
        typingBannerSubtitle.text =
            "開啟「允許完整取用」後，這裡就會換成 AI 回覆鍵盤\n設定 → 一般 → 鍵盤 → VibeSync 鍵盤"
        typingBannerSubtitle.textColor = UIColor.white.withAlphaComponent(0.65)
        typingBannerSubtitle.font = .systemFont(ofSize: 12)
        typingBannerSubtitle.numberOfLines = 2
        typingBannerSubtitle.textAlignment = .center
        let banner = UIStackView()
        banner.axis = .vertical
        banner.spacing = 2
        banner.alignment = .center
        banner.addArrangedSubview(typingBannerTitle)
        banner.addArrangedSubview(typingBannerSubtitle)
        typingPanel.addArrangedSubview(banner)

        for rowText in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 4
            row.distribution = .fillEqually
            for character in rowText {
                let button = makeButton(String(character), action: #selector(typeCharacter(_:)))
                row.addArrangedSubview(button)
            }
            typingPanel.addArrangedSubview(row)
        }
        let common = UIStackView()
        common.axis = .horizontal
        common.spacing = 4
        common.distribution = .fillEqually
        for text in ["，", "。", "？", "！", "～"] {
            common.addArrangedSubview(makeButton(text, action: #selector(typeCharacter(_:))))
        }
        typingPanel.addArrangedSubview(common)
        // No AI toggle here. The typing panel only exists while 完整取用 is
        // off, and every AI surface is gated on it — the old toggle called
        // showAssist, whose refreshAvailability bounced straight back to
        // .typing, so the button was a silent no-op that read as a bug. The
        // banner above explains how to unlock AI instead.
        typingPanel.addArrangedSubview(makeUtilityRow())
    }

    private func makeUtilityRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillProportionally

        // iOS draws its own globe under third-party keyboards on most devices,
        // and `needsInputModeSwitchKey` is how it says whether it did. Drawing a
        // second one unconditionally cost a slot in every row for a key the
        // system was already providing an inch below it.
        if needsInputModeSwitchKey {
            let globe = makeButton("🌐", action: #selector(noop))
            globe.addTarget(self, action: #selector(showInputModeList(_:event:)), for: .allTouchEvents)
            row.addArrangedSubview(globe)
        }
        let space = makeButton("空白", action: #selector(insertSpace))
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(space)
        row.addArrangedSubview(makeButton("換行", action: #selector(insertReturn)))
        let backspace = makeButton("⌫", action: #selector(noop))
        backspace.addTarget(self, action: #selector(startDeleting), for: .touchDown)
        backspace.addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        row.addArrangedSubview(backspace)
        return row
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = surface
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func show(_ newMode: Mode) {
        mode = newMode
        updatePreferredHeight()

        // Switch both panels and flush the host keyboard layout in the same
        // transaction. Without this, iOS can briefly composite the previous
        // panel while the input view changes height, which looks like a
        // one-frame ghost during AI/ABC switching.
        UIView.performWithoutAnimation {
            assistPanel.isHidden = newMode != .assist
            aiPanel.isHidden = newMode != .text
            typingPanel.isHidden = newMode != .typing
            view.setNeedsLayout()
            view.layoutIfNeeded()
            view.superview?.setNeedsLayout()
            view.superview?.layoutIfNeeded()
        }
    }

    private func refreshAvailability() {
        let fullAccessEnabled = hasFullAccess
        let enabled = fullAccessEnabled && !isGenerating
        pasteButton.isEnabled = enabled
        pasteButton.alpha = enabled ? 1 : 0.45
        if !fullAccessEnabled {
            // Guideline 4.4.1: a keyboard extension must still type characters
            // before 完整取用 is granted. There is no manual ABC entry point
            // any more (2026-08-06 product decision — nobody actually types
            // inside a third-party keyboard, they switch to iOS's own), so the
            // typing panel becomes the automatic floor instead of an opt-in one.
            statusLabel.text = "請在設定開啟「允許完整取用」"
            show(.typing)
        } else {
            // The floor is a one-way door without this: nothing else ever
            // leaves .typing, so a keyboard session that outlives the toggle
            // would keep showing the qwerty grid after access was granted.
            // Callers re-arm the screenshot coordinator right after this.
            if mode == .typing {
                show(.assist)
            }
            if SharedAuth.currentSession() == nil {
                statusLabel.text = "請先開啟 VibeSync App 更新登入狀態"
            }
        }
        updateStyleButtons()
    }

    private func refreshScreenshotIdentity() {
        let ownerUserID = SharedAuth.currentSession()?.userId
        if let previousOwner = lastObservedOwnerUserID,
           previousOwner != ownerUserID
        {
            screenshotCoordinator.ownerDidChange()
        }
        lastObservedOwnerUserID = ownerUserID
        screenshotCoordinator.documentDidChange(
            to: currentDocumentIdentifier
        )
    }

    private func renderScreenshotAssist(
        _ renderState: KeyboardScreenshotAssistRenderState
    ) {
        screenshotRenderState = renderState.state
        resetScreenshotControls()
        screenshotStatusLabel.text = renderState.message
        screenshotStatusBubble.isHidden = (renderState.message ?? "").isEmpty
        renderAssistIdleView(renderState)
        setMarkPulsing(isWaitingOnProvider(renderState.state))

        switch renderState.state {
        // These states hide the screenshot panel, which means their own status
        // label is invisible. Surfacing the reason on the always-visible line
        // is the difference between "nothing happens when I screenshot" and a
        // user who knows what to do next.
        case .boot, .featureUnavailable:
            screenshotPanel.isHidden = true
            surfaceUnavailableReason(renderState.message)
        case .fullAccessRequired, .authRequired:
            screenshotPanel.isHidden = true
            surfaceUnavailableReason(renderState.message)
        case .consentRequired,
             .photoPermissionRequired:
            // The invitation block is already saying exactly this, and saying
            // it twice on a half-screen panel reads as a bug.
            screenshotPanel.isHidden = true
            surfaceUnavailableReason(renderState.message)
        case .idle:
            // Nothing to detect until the user takes a shot, so the surface is
            // just the invitation. A button here would only offer to re-run a
            // search that is already listening.
            screenshotPanel.isHidden = true
        // Detection and preview are transient now that a detected capture runs
        // straight away. The image stays on screen so the user always sees
        // which screenshot was used, but nothing waits for a tap.
        case .screenshotDetected, .localPreview:
            screenshotPanel.isHidden = false
            showCapture(screenshotCoordinator.previewImage)
            screenshotCancelButton.isHidden = false
        case .preparing,
             .generating,
             .lookingUpStatus:
            invalidatePendingReply()
            screenshotPanel.isHidden = false
            showCapture(screenshotCoordinator.previewImage)
            screenshotCancelButton.isHidden = false
        case .needsSpeakerConfirmation:
            screenshotPanel.isHidden = false
            screenshotSpeakerRow.isHidden = false
            screenshotCancelButton.isHidden = false
        case .recognitionRejected,
             .partnerConfirmation:
            screenshotPanel.isHidden = false
            screenshotRetryButton.setTitle(
                "換一張截圖再試",
                for: .normal
            )
            screenshotRetryButton.isHidden = false
            screenshotCancelButton.isHidden = false
        case .failed(_, let policy):
            screenshotPanel.isHidden = false
            switch policy {
            case .lookupSameRequest:
                screenshotRetryButton.setTitle(
                    "查詢同一筆結果",
                    for: .normal
                )
                screenshotRetryButton.isHidden = false
            case .retrySamePayload:
                screenshotRetryButton.setTitle(
                    "安全重試同一請求",
                    for: .normal
                )
                screenshotRetryButton.isHidden = false
            case .newRequestAfterUserChange:
                screenshotRetryButton.setTitle(
                    "重新選擇截圖",
                    for: .normal
                )
                screenshotRetryButton.isHidden = false
            case .terminal:
                break
            }
            screenshotCancelButton.isHidden = false
        case .resultsPreview(let presentation):
            screenshotPanel.isHidden = false
            // analysisCard already renders cue／turn-state／uncertainty in full
            // (renderAnalysisCard below); the plain status bubble above it was
            // showing the same cue text a second time (2026-08-06 dogfood —
            // real screenshot showed the two blocks saying the same thing).
            screenshotStatusBubble.isHidden = true
            renderAnalysisCard(presentation)
            renderScreenshotCandidates(presentation.options)
            screenshotCandidateStack.isHidden = false
            screenshotContinuationHint.isHidden = false
            // Always offered: a new batch is this screenshot analysed again,
            // not a reserve batch that may or may not have been produced.
            screenshotSwapButton.isHidden =
                !screenshotCoordinator.canRequestNewBatch
            screenshotRetryButton.setTitle("重新分析", for: .normal)
            screenshotRetryButton.isHidden = false
            screenshotCancelButton.isHidden = false
        case .inserted:
            screenshotPanel.isHidden = false
        }
        // A stack view still occupies its spacing when every child is hidden, so
        // the shared row has to be told to disappear with them.
        screenshotActionRow.isHidden =
            screenshotSwapButton.isHidden && screenshotCancelButton.isHidden
        updatePreferredHeight()
    }

    private func isWaitingOnProvider(_ state: KeyboardAssistState) -> Bool {
        switch state {
        case .preparing, .generating, .lookingUpStatus:
            return true
        default:
            return false
        }
    }

    /// A quiet pulse on the brand mark instead of a static "loading" state —
    /// the wait is a single blocking call with no real progress signal
    /// (2026-08-06 product decision), so this and the status-line wording
    /// cycle are the only two things telling the user something is happening.
    private func setMarkPulsing(_ pulsing: Bool) {
        guard pulsing != isMarkPulsing else { return }
        isMarkPulsing = pulsing
        screenshotFlowMark.layer.removeAllAnimations()
        guard pulsing else {
            screenshotFlowMark.alpha = 1
            return
        }
        UIView.animate(
            withDuration: 0.9,
            delay: 0,
            options: [.repeat, .autoreverse, .allowUserInteraction],
            animations: { self.screenshotFlowMark.alpha = 0.45 }
        )
    }

    /// The capture arrives where the other person's messages live, with one
    /// short move so it reads as "this is what I looked at" rather than a panel
    /// that silently swapped contents. One-shot, no repeat: an input view that
    /// never settles is an input view that never stops redrawing.
    private func showCapture(_ image: UIImage?) {
        let isNewCapture = screenshotPreviewImageView.image !== image
        screenshotPreviewImageView.image = image
        screenshotPreviewImageView.isHidden = image == nil
        guard isNewCapture, image != nil else { return }
        screenshotPreviewImageView.transform = CGAffineTransform(
            translationX: -18,
            y: 8
        ).scaledBy(x: 0.88, y: 0.88)
        screenshotPreviewImageView.alpha = 0
        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) { [weak self] in
            self?.screenshotPreviewImageView.transform = .identity
            self?.screenshotPreviewImageView.alpha = 1
        }
    }

    private static let assistIdleTitleText = "截圖這則對話就開始"
    private static let assistIdleSubtitleText =
        "鍵盤開著時截圖，會自動分析並給你回覆"

    /// The screenshot panel hides itself in the states where there is nothing
    /// to show, and hiding the panel used to hide the reason with it. In this
    /// layout the invitation block is the one thing that is always on screen,
    /// so it doubles as the place a blocked feature explains itself.
    private func renderAssistIdleView(
        _ renderState: KeyboardScreenshotAssistRenderState
    ) {
        assistPreSessionButton.isHidden = true
        switch renderState.state {
        case .idle:
            assistIdleView.isHidden = false
            assistIdleTitle.text = Self.assistIdleTitleText
            assistIdleSubtitle.text = renderState.message
                ?? Self.assistIdleSubtitleText
            assistPreSessionButton.isHidden = false
        case .boot:
            assistIdleView.isHidden = false
            assistIdleTitle.text = Self.assistIdleTitleText
            assistIdleSubtitle.text = Self.assistIdleSubtitleText
        case .featureUnavailable,
             .fullAccessRequired,
             .authRequired,
             .consentRequired,
             .photoPermissionRequired:
            assistIdleView.isHidden = false
            assistIdleTitle.text = "還不能自動分析截圖"
            assistIdleSubtitle.text = renderState.message
                ?? "請開啟 VibeSync App 檢查鍵盤設定"
        default:
            assistIdleView.isHidden = true
        }
    }

    /// Only speaks when there is something to say. Transitions that merely
    /// stand the screenshot flow down — dismissing the keyboard, or handing
    /// over to the paste flow — carry no message and must not overwrite what
    /// the paste flow is telling the user.
    private static let emptyStateStatus =
        "複製對方訊息後點「載入」，或切回截圖模式"

    private func surfaceUnavailableReason(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        statusLabel.text = message
        statusLineBorrowed = true
    }

    /// Once the screenshot flow is back on its feet it owns its own status
    /// label again, so the shared line must stop repeating a stale failure.
    private func returnStatusLine() {
        guard statusLineBorrowed else { return }
        statusLineBorrowed = false
        statusLabel.text = Self.emptyStateStatus
    }

    private func resetScreenshotControls() {
        analysisCard.isHidden = true
        screenshotContinuationHint.isHidden = true
        screenshotSwapButton.isHidden = true
        returnStatusLine()
        screenshotRetryButton.isHidden = true
        screenshotCancelButton.isHidden = true
        screenshotActionRow.isHidden = true
        screenshotSpeakerRow.isHidden = true
        screenshotCandidateStack.isHidden = true
        screenshotPreviewImageView.isHidden = true
        screenshotPreviewImageView.image = nil
        screenshotPreviewImageView.transform = .identity
        screenshotPreviewImageView.alpha = 1
        for view in screenshotCandidateStack.arrangedSubviews {
            screenshotCandidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func renderScreenshotCandidates(
        _ options: [KeyboardAssistOption]
    ) {
        for option in options {
            screenshotCandidateStack.addArrangedSubview(
                makeCandidateRow(option)
            )
        }
    }

    private func strategyTitle(
        _ strategy: KeyboardAssistStrategy
    ) -> String {
        switch strategy {
        case .extend:
            return "延展"
        case .flirt:
            return "調情"
        case .humor:
            return "幽默"
        // Retired taxonomy; still labelled so an older server cannot leave a
        // row with a blank chip.
        case .keepPace:
            return "順著聊"
        case .buildConnection:
            return "拉近距離"
        case .moveForward:
            return "自然推進"
        case .clarify:
            return "先確認"
        case .deescalate:
            return "降低壓力"
        }
    }

    private func updateStyleButtons(selected: KeyboardReplyStyle? = nil) {
        pasteButton.isEnabled = hasFullAccess && !isGenerating
        pasteButton.alpha = pasteButton.isEnabled ? 1 : 0.45
        for (style, button) in styleButtons {
            let enabled = hasFullAccess && !loadedMessage.isEmpty && !isGenerating
            button.isEnabled = enabled
            button.alpha = enabled || style == selected ? 1 : 0.45
            button.backgroundColor = style == selected ? primary : surface
            button.setTitle(style == selected && isGenerating ? "產生中…" : style.title, for: .normal)
        }
    }

    @objc private func loadClipboard() {
        guard !isGenerating else { return }
        guard hasFullAccess else { refreshAvailability(); return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            statusLabel.text = "剪貼簿沒有文字"
            return
        }
        invalidatePendingReply()
        loadedMessage = String(text.prefix(2000))
        contextLabel.text = loadedMessage
        statusLabel.text = "已載入，選一種回覆風格"
        updateStyleButtons()
    }

    @objc private func clearContext() {
        guard !isGenerating else { return }
        invalidatePendingReply()
        loadedMessage = ""
        contextLabel.text = "先複製對方訊息，再點載入"
        statusLabel.text = "只會送出你主動載入的文字"
        updateStyleButtons()
    }

    @objc private func generateReply(_ sender: UIButton) {
        guard !isGenerating else { return }
        guard let raw = sender.accessibilityIdentifier,
              let style = KeyboardReplyStyle(rawValue: raw),
              !loadedMessage.isEmpty else { return }
        guard hasFullAccess else { refreshAvailability(); return }
        guard let session = SharedAuth.currentSession() else {
            statusLabel.text = "登入已過期，請先開啟 VibeSync App 再回來"
            return
        }
        screenshotCoordinator.suspendForLegacyFlow()
        invalidatePendingReply()
        let operationID = UUID()
        activeLegacyOperationID = operationID
        let boundDocumentIdentifier = currentDocumentIdentifier
        isGenerating = true
        updateStyleButtons(selected: style)
        statusLabel.text = "正在幫你接住這句話…"
        api.generate(message: loadedMessage, style: style, session: session) { [weak self] result in
            guard let self else { return }
            guard self.activeLegacyOperationID == operationID else {
                return
            }
            self.isGenerating = false
            self.updateStyleButtons()
            switch result {
            case .success(let success):
                self.pendingLegacyReply = PendingLegacyReply(
                    success: success,
                    operationID: operationID,
                    ownerUserID: session.userId,
                    documentIdentifier: boundDocumentIdentifier
                )
                self.resultButton.setTitle(
                    "點一下才插入：\(success.reply)",
                    for: .normal
                )
                self.resultButton.isHidden = false
                self.updatePreferredHeight()
                self.statusLabel.text =
                    "結果尚未插入；確認目前聊天室後再點候選。"
            case .failure(let error):
                self.activeLegacyOperationID = nil
                self.statusLabel.text = self.message(for: error)
            }
        }
    }

    @objc private func insertGeneratedReply() {
        guard let pending = pendingLegacyReply,
              activeLegacyOperationID == pending.operationID,
              let session = SharedAuth.currentSession(),
              session.userId == pending.ownerUserID,
              // An unknown identifier on either side must never count as the
              // same chat, so a nil document can never unlock an insertion.
              let boundDocumentIdentifier = pending.documentIdentifier,
              currentDocumentIdentifier == boundDocumentIdentifier
        else {
            invalidatePendingReply()
            statusLabel.text = "聊天或登入狀態已變更，請重新產生"
            return
        }

        let outcome = replyInsertionCoordinator.insertLegacy(
            candidateID: pending.success.requestId,
            text: pending.success.reply
        )
        if outcome == .inserted {
            api.markPresented(requestId: pending.success.requestId)
            statusLabel.text = "已插入輸入框；你確認後再送出"
        }
        pendingLegacyReply = nil
        activeLegacyOperationID = nil
        resultButton.isHidden = true
        updatePreferredHeight()
    }

    private func invalidatePendingReply() {
        pendingLegacyReply = nil
        activeLegacyOperationID = nil
        isGenerating = false
        resultButton.isHidden = true
        updateStyleButtons()
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        switch mode {
        case .typing:
            preferredContentSize.height = 316
        case .text:
            preferredContentSize.height = resultButton.isHidden ? 300 : 352
        case .assist:
            if !screenshotCandidateStack.isHidden {
                preferredContentSize.height = 620
            } else if !screenshotPreviewImageView.isHidden {
                preferredContentSize.height = 500
            } else if screenshotPanel.isHidden {
                // Just the invitation (or the reason it cannot run). Asking for
                // half the screen to say one sentence looks broken — and a
                // shorter panel also leaves more conversation in the capture.
                preferredContentSize.height = 296
            } else {
                preferredContentSize.height = 410
            }
        }
    }

    private func message(for error: KeyboardAPIError) -> String {
        switch error {
        case .unauthorized: return "登入已過期，請先開啟 VibeSync App 再回來"
        case .quotaExceeded:
            if let userId = SharedAuth.currentSession()?.userId {
                SharedAuth.markQuotaExceeded(userId: userId)
            }
            return "額度已用完，打開 VibeSync 即可查看方案"
        case .modelRateLimited(let message): return message
        case .fullAccessRequired: return "請在設定開啟「允許完整取用」"
        case .requestIdentityUnavailable:
            return "無法建立安全重試識別，本次未送出，請稍後再試"
        case .requestPending:
            return "上一個回覆仍在處理，請稍後用同一段文字再試。"
        case .requestConflict:
            return "重試狀態已更新，請再點一次產生"
        case .network: return "網路不穩，請稍後再試"
        case .invalidResponse, .server(_):
            return "結果暫時未收到，請再試一次；系統不會重複扣額度"
        }
    }

    /// Coming back to the screenshot surface re-arms detection. The coordinator
    /// was stood down while the other panels were up, so without this the panel
    /// would sit on whatever it last rendered and ignore a fresh capture.
    @objc private func showAssist() {
        show(.assist)
        refreshAvailability()
        screenshotCoordinator.start(hasFullAccess: hasFullAccess)
        screenshotCoordinator.startObservingLibrary(
            hasFullAccess: hasFullAccess
        )
    }

    /// The paste flow and the screenshot flow both spend quota, so only one of
    /// them may be live at a time.
    @objc private func showTextAssist() {
        screenshotCoordinator.suspendForLegacyFlow()
        show(.text)
        refreshAvailability()
    }
    @objc private func requestNewCandidateBatch() {
        screenshotCoordinator.requestNewBatch()
    }

    @objc private func retryScreenshotAssist() {
        invalidatePendingReply()
        switch screenshotRenderState {
        case .failed(_, .lookupSameRequest),
             .failed(_, .retrySamePayload):
            screenshotCoordinator.retryFailedRequest()
        default:
            screenshotCoordinator.startForcingReanalysis(
                hasFullAccess: hasFullAccess
            )
        }
    }
    @objc private func cancelScreenshotAssist() {
        screenshotCoordinator.cancel()
    }
    @objc private func confirmLeftSpeaker() {
        screenshotCoordinator.chooseSpeakerSide(.left)
    }
    @objc private func confirmRightSpeaker() {
        screenshotCoordinator.chooseSpeakerSide(.right)
    }
    @objc private func insertScreenshotCandidate(_ sender: UIButton) {
        guard let candidateID = sender.accessibilityIdentifier else {
            return
        }
        screenshotCoordinator.insertCandidate(
            candidateID: candidateID
        )
    }
    @objc private func typeCharacter(_ sender: UIButton) { if let text = sender.currentTitle { textDocumentProxy.insertText(text) } }
    @objc private func insertSpace() { textDocumentProxy.insertText(" ") }
    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
    @objc private func deleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func noop() {}
    @objc private func showInputModeList(_ sender: UIButton, event: UIEvent) { handleInputModeList(from: sender, with: event) }
    @objc private func startDeleting() {
        deleteBackward()
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in self?.deleteBackward() }
    }
    @objc private func stopDeleting() { deleteTimer?.invalidate(); deleteTimer = nil }
}
