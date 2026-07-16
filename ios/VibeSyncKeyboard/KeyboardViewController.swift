import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Mode { case ai, typing }

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
    private var styleButtons: [KeyboardReplyStyle: UIButton] = [:]
    private var loadedMessage = ""
    private var mode: Mode = .ai
    private var deleteTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ink
        configureRoot()
        configureAIPanel()
        configureTypingPanel()
        show(.ai)
        refreshAvailability()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAvailability()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preferredContentSize.height = mode == .ai ? 300 : 280
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
        aiPanel.addArrangedSubview(makeUtilityRow(aiToggleTitle: "ABC"))
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
        let backspace = makeButton("⌫", action: #selector(deleteBackward))
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
        aiPanel.isHidden = newMode != .ai
        typingPanel.isHidden = newMode != .typing
        view.setNeedsLayout()
    }

    private func refreshAvailability() {
        let enabled = hasFullAccess
        pasteButton.isEnabled = enabled
        pasteButton.alpha = enabled ? 1 : 0.45
        if !enabled {
            statusLabel.text = "請在設定開啟「允許完整取用」；ABC 基本輸入仍可使用"
        } else if SharedAuth.currentSession() == nil {
            statusLabel.text = "請先開啟 VibeSync App 更新登入狀態"
        }
        updateStyleButtons()
    }

    private func updateStyleButtons(isLoading: Bool = false, selected: KeyboardReplyStyle? = nil) {
        for (style, button) in styleButtons {
            let enabled = hasFullAccess && !loadedMessage.isEmpty && !isLoading
            button.isEnabled = enabled
            button.alpha = enabled || style == selected ? 1 : 0.45
            button.backgroundColor = style == selected ? primary : surface
            button.setTitle(style == selected && isLoading ? "產生中…" : style.title, for: .normal)
        }
    }

    @objc private func loadClipboard() {
        guard hasFullAccess else { refreshAvailability(); return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            statusLabel.text = "剪貼簿沒有文字"
            return
        }
        loadedMessage = String(text.prefix(2000))
        contextLabel.text = loadedMessage
        statusLabel.text = "已載入，選一種回覆風格"
        updateStyleButtons()
    }

    @objc private func clearContext() {
        loadedMessage = ""
        contextLabel.text = "先複製對方訊息，再點載入"
        statusLabel.text = "只會送出你主動載入的文字"
        updateStyleButtons()
    }

    @objc private func generateReply(_ sender: UIButton) {
        guard let raw = sender.accessibilityIdentifier,
              let style = KeyboardReplyStyle(rawValue: raw),
              !loadedMessage.isEmpty else { return }
        guard hasFullAccess else { refreshAvailability(); return }
        guard let session = SharedAuth.currentSession() else {
            statusLabel.text = "登入已過期，請先開啟 VibeSync App 再回來"
            return
        }
        updateStyleButtons(isLoading: true, selected: style)
        statusLabel.text = "正在幫你接住這句話…"
        api.generate(message: loadedMessage, style: style, session: session) { [weak self] result in
            guard let self else { return }
            self.updateStyleButtons()
            switch result {
            case .success(let reply):
                self.textDocumentProxy.insertText(reply)
                self.statusLabel.text = "已插入輸入框；你確認後再送出。再點同風格可換一則"
            case .failure(let error):
                self.statusLabel.text = self.message(for: error)
            }
        }
    }

    private func message(for error: KeyboardAPIError) -> String {
        switch error {
        case .unauthorized: return "登入已過期，請先開啟 VibeSync App 再回來"
        case .quotaExceeded: return "額度已用完，請回 VibeSync 查看方案"
        case .modelRateLimited(let message): return message
        case .fullAccessRequired: return "請在設定開啟「允許完整取用」"
        case .network: return "網路不穩，請稍後再試"
        case .invalidResponse, .server(_): return "這次沒有產生成功，不會扣額度，請再試一次"
        }
    }

    @objc private func showTyping() { show(.typing) }
    @objc private func showAI() { show(.ai); refreshAvailability() }
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
