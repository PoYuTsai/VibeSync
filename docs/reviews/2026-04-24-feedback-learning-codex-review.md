# 2026-04-24 Feedback Learning Codex Review

## 本輪直接補強

- `analysis_screen.dart`
  - 反饋送出加上 in-flight lock，避免連點造成重複寫入。
  - 負評表單新增「附上最後 6 則對話片段」明示勾選，預設不傳原始對話。
  - `aiResponse` 改成最小化、結構化 payload，不再整包上傳原始分析回應。
  - 補上 `unnatural` 類別，避免「太直接」與「不自然」資料混在一起。
- `submit-feedback`
  - Telegram email masking 改為安全 helper，避免短 email 洩漏完整 local part。
  - 伺服器端新增 `sanitizeFeedbackAiResponse()`，只收白名單欄位。
- `privacy-policy`
  - 補明 feedback 上下文為 opt-in，並揭露 Telegram Bot 可能接觸的資料。

## 仍保留的設計限制

- 這套機制目前是 **learning-ready feedback inbox**，不是 autonomous self-learning。
- `feedback` payload 仍屬 user-originated data，不能直接當成 prompt 自動修補依據，否則有 dataset poisoning 風險。
- 若試運行期後要做真正閉環，下一步建議加：
  - server-trusted `analysis_id`
  - prompt/model version
  - human review queue
  - before/after eval gate

## Verdict

試運行期可安全拿來做人工 review 與 prompt 收斂，不建議直接串成自動學習器。
