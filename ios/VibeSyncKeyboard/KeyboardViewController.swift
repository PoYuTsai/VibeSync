import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Mode { case ai, typing }
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
    private let aiPanel = UIStackView()
    private let typingPanel = UIStackView()
    private let contextLabel = UILabel()
    private let statusLabel = UILabel()
    private let pasteButton = UIButton(type: .system)
    private let resultButton = UIButton(type: .system)
    private let screenshotPanel = UIStackView()
    private let screenshotStatusLabel = UILabel()
    private let screenshotPreviewImageView = UIImageView()
    private let screenshotPreviewButton = UIButton(type: .system)
    private let screenshotConfirmButton = UIButton(type: .system)
    private let screenshotRetryButton = UIButton(type: .system)
    private let screenshotCancelButton = UIButton(type: .system)
    private let screenshotSpeakerRow = UIStackView()
    private let screenshotCandidateStack = UIStackView()
    private var styleButtons: [KeyboardReplyStyle: UIButton] = [:]
    private var loadedMessage = ""
    private var pendingLegacyReply: PendingLegacyReply?
    private var activeLegacyOperationID: UUID?
    private var isGenerating = false
    private var mode: Mode = .ai
    private var deleteTimer: Timer?
    private var lastObservedOwnerUserID: String?
    private var screenshotRenderState: KeyboardAssistState = .boot
    private var keyboardVisibleSince: Date?
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
        let overlayHeight = view.bounds.height
        guard screenHeight > 0, overlayHeight > 0 else { return 0 }
        // Clamped so an unexpected geometry reading can never eat the chat.
        return min(overlayHeight / screenHeight, 0.7)
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
        configureAIPanel()
        configureScreenshotAssist()
        configureTypingPanel()
        show(.ai)
        refreshAvailability()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardVisibleSince = Date()
        refreshAvailability()
        refreshScreenshotIdentity()
        screenshotCoordinator.start(hasFullAccess: hasFullAccess)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardVisibleSince = nil
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

    private func configureAIPanel() {
        aiPanel.axis = .vertical
        aiPanel.spacing = 7
        rootStack.addArrangedSubview(aiPanel)

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 8
        let mark = UILabel()
        mark.text = "💜 VibeSync AI"
        mark.textColor = .white
        mark.font = .systemFont(ofSize: 15, weight: .bold)
        header.addArrangedSubview(mark)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(makeButton("ABC", action: #selector(showTyping)))
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

        statusLabel.text = "只會送出你主動載入的文字"
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
        aiPanel.addArrangedSubview(makeUtilityRow(aiToggleTitle: "ABC"))
    }

    private func configureScreenshotAssist() {
        screenshotPanel.axis = .vertical
        screenshotPanel.spacing = 7
        screenshotPanel.isHidden = true

        screenshotStatusLabel.textColor =
            UIColor.white.withAlphaComponent(0.78)
        screenshotStatusLabel.font = .systemFont(ofSize: 12)
        screenshotStatusLabel.numberOfLines = 4
        screenshotStatusLabel.textAlignment = .center
        screenshotPanel.addArrangedSubview(screenshotStatusLabel)

        screenshotPreviewImageView.contentMode = .scaleAspectFit
        screenshotPreviewImageView.backgroundColor = surface
        screenshotPreviewImageView.layer.cornerRadius = 10
        screenshotPreviewImageView.layer.masksToBounds = true
        screenshotPreviewImageView.heightAnchor.constraint(
            equalToConstant: 112
        ).isActive = true
        screenshotPreviewImageView.isHidden = true
        screenshotPanel.addArrangedSubview(screenshotPreviewImageView)

        screenshotPreviewButton.setTitle(
            "預覽最新截圖",
            for: .normal
        )
        styleScreenshotButton(
            screenshotPreviewButton,
            color: primary
        )
        screenshotPreviewButton.addTarget(
            self,
            action: #selector(showScreenshotPreview),
            for: .touchUpInside
        )
        screenshotPanel.addArrangedSubview(screenshotPreviewButton)

        screenshotConfirmButton.setTitle(
            "使用這張圖產生回覆",
            for: .normal
        )
        styleScreenshotButton(
            screenshotConfirmButton,
            color: flame
        )
        screenshotConfirmButton.addTarget(
            self,
            action: #selector(confirmScreenshotPreview),
            for: .touchUpInside
        )
        screenshotPanel.addArrangedSubview(screenshotConfirmButton)

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
        screenshotPanel.addArrangedSubview(screenshotRetryButton)

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

        screenshotCancelButton.setTitle(
            "取消，不送出截圖",
            for: .normal
        )
        styleScreenshotButton(
            screenshotCancelButton,
            color: surface
        )
        screenshotCancelButton.addTarget(
            self,
            action: #selector(cancelScreenshotAssist),
            for: .touchUpInside
        )
        screenshotPanel.addArrangedSubview(screenshotCancelButton)

        aiPanel.insertArrangedSubview(screenshotPanel, at: 2)
        resetScreenshotControls()
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
        typingPanel.addArrangedSubview(makeUtilityRow(aiToggleTitle: "AI"))
    }

    private func makeUtilityRow(aiToggleTitle: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillProportionally

        let globe = makeButton("🌐", action: #selector(noop))
        globe.addTarget(self, action: #selector(showInputModeList(_:event:)), for: .allTouchEvents)
        row.addArrangedSubview(globe)
        row.addArrangedSubview(makeButton(aiToggleTitle, action: aiToggleTitle == "AI" ? #selector(showAI) : #selector(showTyping)))
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
            aiPanel.isHidden = newMode != .ai
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
            statusLabel.text = "請在設定開啟「允許完整取用」；ABC 基本輸入仍可使用"
        } else if SharedAuth.currentSession() == nil {
            statusLabel.text = "請先開啟 VibeSync App 更新登入狀態"
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

        switch renderState.state {
        case .boot, .featureUnavailable:
            screenshotPanel.isHidden = true
        case .fullAccessRequired, .authRequired:
            screenshotPanel.isHidden = true
        case .consentRequired,
             .photoPermissionRequired:
            screenshotPanel.isHidden = false
        case .idle:
            screenshotPanel.isHidden = false
            screenshotRetryButton.setTitle(
                "重新偵測最新截圖",
                for: .normal
            )
            screenshotRetryButton.isHidden = false
        case .screenshotDetected:
            screenshotPanel.isHidden = false
            screenshotPreviewButton.isHidden = false
            screenshotCancelButton.isHidden = false
        case .localPreview:
            screenshotPanel.isHidden = false
            screenshotPreviewImageView.image =
                screenshotCoordinator.previewImage
            screenshotPreviewImageView.isHidden = false
            screenshotConfirmButton.isHidden = false
            screenshotCancelButton.isHidden = false
        case .preparing,
             .generating,
             .lookingUpStatus:
            screenshotPanel.isHidden = false
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
            renderScreenshotCandidates(presentation.options)
            screenshotCandidateStack.isHidden = false
            screenshotCancelButton.isHidden = false
        case .inserted:
            screenshotPanel.isHidden = false
        }
        updatePreferredHeight()
    }

    private func resetScreenshotControls() {
        screenshotPreviewButton.isHidden = true
        screenshotConfirmButton.isHidden = true
        screenshotRetryButton.isHidden = true
        screenshotCancelButton.isHidden = true
        screenshotSpeakerRow.isHidden = true
        screenshotCandidateStack.isHidden = true
        screenshotPreviewImageView.isHidden = true
        screenshotPreviewImageView.image = nil
        for view in screenshotCandidateStack.arrangedSubviews {
            screenshotCandidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func renderScreenshotCandidates(
        _ options: [KeyboardAssistOption]
    ) {
        for option in options {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = option.candidateID
            button.setTitle(
                "\(strategyTitle(option.strategy))\n\(option.text)\n\(option.why) · \(option.effect)",
                for: .normal
            )
            styleScreenshotButton(button, color: primary)
            button.contentHorizontalAlignment = .leading
            button.contentEdgeInsets = UIEdgeInsets(
                top: 9,
                left: 11,
                bottom: 9,
                right: 11
            )
            button.addTarget(
                self,
                action: #selector(insertScreenshotCandidate(_:)),
                for: .touchUpInside
            )
            screenshotCandidateStack.addArrangedSubview(button)
        }
    }

    private func strategyTitle(
        _ strategy: KeyboardAssistStrategy
    ) -> String {
        switch strategy {
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
        if mode == .typing {
            preferredContentSize.height = 280
            return
        }
        if !screenshotPanel.isHidden {
            if !screenshotCandidateStack.isHidden {
                preferredContentSize.height = 570
            } else if !screenshotPreviewImageView.isHidden {
                preferredContentSize.height = 500
            } else {
                preferredContentSize.height = 410
            }
            return
        }
        preferredContentSize.height = resultButton.isHidden ? 300 : 352
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

    @objc private func showTyping() { show(.typing) }
    @objc private func showAI() { show(.ai); refreshAvailability() }
    @objc private func showScreenshotPreview() {
        screenshotCoordinator.requestLocalPreview()
    }
    @objc private func confirmScreenshotPreview() {
        invalidatePendingReply()
        screenshotCoordinator.confirmPreviewAndGenerate()
    }
    @objc private func retryScreenshotAssist() {
        invalidatePendingReply()
        switch screenshotRenderState {
        case .failed(_, .lookupSameRequest),
             .failed(_, .retrySamePayload):
            screenshotCoordinator.retryFailedRequest()
        default:
            screenshotCoordinator.start(hasFullAccess: hasFullAccess)
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
