# App Store 審核策略

## 產品定位

### 不建議使用的定位
- 戀愛操控工具
- 把 AI 包裝成追女生捷徑
- 暗示操縱、套路、操盤異性

### 建議對外定位
- 社交溝通教練
- 對話品質輔助工具
- 溝通表達訓練
- 人際互動分析與回覆建議

---

## App Store 基本資訊建議

### App 名稱
`VibeSync - 社交溝通教練`

### 一句話描述
幫助使用者理解聊天互動訊號、整理對話脈絡，並取得 AI 輔助的回覆建議。

### 分類建議
- `Lifestyle`
- `Education`

### 年齡分級
- `17+`
- 原因：可能包含戀愛、曖昧、成人互動語境，但不主打露骨內容

---

## App Review 重點說明

以下內容可作為審核說明的基礎版本：

```text
VibeSync is a communication coaching app that helps users review chat context,
understand conversation signals, and receive AI-assisted reply suggestions.

KEY POINTS FOR REVIEW:

1. PURPOSE
   - This is a communication support tool focused on conversational quality.
   - It is not a dating manipulation app and does not guarantee outcomes.
   - Suggestions are intended to help users communicate more clearly and naturally.

2. PRIVACY
   - Conversation content is stored locally on the user's device by default.
   - When a user explicitly requests analysis or screenshot recognition, only the
     content required for that request is sent through our backend processing
     service and AI providers to generate the response.
   - We do not use users' raw conversation content to train our own models.

3. CONTENT AND SAFETY
   - The app does not provide social networking, public posting, or user-to-user messaging.
   - The app focuses on private drafting, analysis, and communication support.
   - The app can reject unsupported, unreadable, or inappropriate screenshot inputs.

4. ACCOUNT AND BILLING
   - The app supports email / Apple / Google sign-in.
   - Paid plans are managed through Apple App Store subscriptions.

5. DEMO FLOW
   - Reviewers can paste a short conversation or use a provided test account.
   - The app then returns analysis and reply suggestions for communication improvement.
```

---

## 隱私說法準則

### 可以說
- 對話內容預設儲存在本地裝置
- 用戶主動發起分析或截圖辨識時，必要內容會送往處理服務與 AI 供應商
- 不把原始對話內容拿去訓練自家模型
- 保留有限技術性中繼資料用於穩定性、安全性與成本控管

### 不要再說
- 所有資料永遠不會離開裝置
- 絕不上傳雲端
- Zero server-side storage of all user-submitted content
- 我們完全不處理任何對話內容

---

## 若 Apple 問到資料流

建議回答方向：

```text
Conversation content is local-first.

When the user explicitly taps analysis or screenshot-recognition features,
the minimum required content for that request is transmitted to our backend
processing service and AI providers so we can generate the requested result.

We do not position the app as a social network, we do not expose user content
to other users, and we do not use raw conversation submissions to train our own model.
```

---

## 若 Apple 擔心產品定位

建議回覆：

```text
VibeSync should be understood as a communication coaching and drafting tool.

It helps users review conversation tone, identify interaction patterns,
and consider clearer reply options. The app does not promise dating outcomes,
does not automate messaging to third parties, and does not function as a social platform.
```

---

## 若 Apple 要求補充說明

可用這版作為申訴 / 補件模板：

```text
Dear App Review Team,

Thank you for reviewing VibeSync.

VibeSync is a communication coaching app that helps users improve the clarity,
tone, and quality of their private conversations. It is not intended as a
dating manipulation tool, and it does not guarantee social or romantic outcomes.

Regarding privacy:
- user conversation content is stored locally by default
- when the user explicitly requests analysis or screenshot recognition, the
  minimum required content is sent through backend processing and AI providers
  to generate that request's result
- we do not use raw user conversations to train our own model

The app does not provide a public social feed, user-to-user messaging network,
or public content sharing. It is a private analysis and drafting tool.

We appreciate your review and are happy to provide any additional clarification.

Best regards,
VibeSync Team
```

---

## 上線前自查

- [ ] App Store Connect 的 privacy disclosure 與實際資料流一致
- [ ] 官網、隱私權政策、條款、審核文案對資料流的描述一致
- [ ] 不再使用「絕不上傳雲端」這類絕對說法
- [ ] 若尚未公開上架，官網不要放假的 App Store 下載連結
