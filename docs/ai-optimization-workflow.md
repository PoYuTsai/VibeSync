# AI 回覆優化流程

> Claude API 不會從單次呼叫中「學習」。優化是透過改進 System Prompt + 調整路由。

---

## 核心循環

```
1. 沙盒測試對話
   ↓
2. 記錄「不滿意的回覆」+ 原因（情境 / AI 回覆 / 問題 / 期望）
   ↓
3. 分析問題模式（太直接？太婉轉？太長？不自然？）
   ↓
4. 修改 System Prompt（supabase/functions/analyze-chat/index.ts）
   ↓
5. 重新部署 Edge Function
   ↓
6. 再次測試驗證
```

---

## System Prompt 位置

`supabase/functions/analyze-chat/index.ts` — `SYSTEM_PROMPT` 常數

---

## 部署指令

```bash
SUPABASE_ACCESS_TOKEN=sbp_xxx \
  npx supabase functions deploy analyze-chat \
  --no-verify-jwt \
  --project-ref fcmwrmwdoqiqdnbisdpg
```

⚠️ **`analyze-chat` 必須 `--no-verify-jwt`**（見 CLAUDE.md OCR Guardrail）。
⚠️ deploy 前確認改動不是 OCR 相關路徑混著其他變動（OCR 要獨立 commit 獨立 deploy）。

---

## 記錄格式

新問題收斂到 `docs/bug-log.md`（若是 AI 品質回歸 bug）或 GitHub Issue：

```markdown
#### [YYYY-MM-DD] 回覆優化 — [問題類型]
**對話情境**: [簡述]
**AI 回覆**: [原回覆]
**問題**: [為什麼不好]
**期望**: [應該怎麼回]
**Prompt 修改**: [改了什麼]
```

---

## 當前 System Prompt 重要規則（見 ADR #9 + #4）

- **1.8x 黃金法則**：回覆字數 ≤ 對方字數 × 1.8
- **70/30 法則**：聆聽多於說話（原稱 82/18，2026-03-04 規避著作權改名）
- **話題深度階梯**：Event-oriented → Personal-oriented → Intimate-oriented
- **熱度分析**：**只從對方訊息**判斷（回覆長度、emoji、主動提問、話題延伸、回應態度）
- **五種回覆風格**：延展 / 共鳴 / 調情 / 幽默 / 冷讀
- **面試式提問警告**：避免連續疑問句
- **真人一致性提醒**：鼓勵線下見面

---

## 反饋機制

- 分析結果頁底部 👍👎 按鈕
- 負面反饋展開表單（分類 + 補充說明）
- 反饋存 Supabase `feedback` 表
- 負面反饋自動發送 Telegram（`@vibesync_feedback_bot`）

**Edge Function**: `submit-feedback`

---

## 相關文件

- System Prompt 優化設計：`docs/plans/2026-03-04-system-prompt-optimization-design.md`
- System Prompt 優化實作：`docs/plans/2026-03-04-system-prompt-optimization-impl.md`
