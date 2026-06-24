# AI 實戰練習室 MVP — 設計

> 2026-06-24 · 狀態：實作中

## 目標

學習 tab 最上方新入口「AI 實戰練習室」。點入直接進聊天（不選目標）。AI 扮演**模擬對象女生**（非教練），真人手機聊天口吻。練完可看一張**教練拆解卡**。

## 已定案決策

- **開場**：使用者先發；進畫面不打 API、不扣額度。使用者送出第一則 → AI 第一則回覆成功才扣 **1 則 Coach 額度**。
- **拆解卡**：聊天中 AI 全程是「她」，不切教練。只有按「結束練習」或滿 10 則 AI 回覆，才走 `debrief` mode 產 **一張**卡，同場**不另扣**額度。
- **模型**：一律 DeepSeek `deepseek-v4-flash`，不分 tier、不改 coach-chat/analyze-chat。
- **額度單位**：一場 = 1（在 session 第一則 AI 回覆成功時扣）。失敗（API/format）不扣。測試帳號不扣。
- **上限**：一場最多 10 則 AI 回覆。
- **保留**：最近 5 場 local-only（Hive 加密）。不寫 partner memory、不綁真實對象。

## Edge Function：`supabase/functions/practice-chat/`

| 檔 | 內容 | 測試 |
|---|---|---|
| `index.ts` | HTTP handler：CORS→auth→validate→sub+resets→10則 guard→quota preflight(僅扣點時)→DeepSeek→parse→成功才扣→回應 | — |
| `prompt.ts` | 純函式：`buildChatMessages(turns)`、`buildDebriefMessages(turns)`、`CHAT_SYSTEM_PROMPT`、`DEBRIEF_SYSTEM_PROMPT` | ✅ prompt |
| `validate.ts` | 純函式：`validateRequest(raw)`（mode enum、turns 陣列、長度上限） | ✅ schema |
| `quota_decision.ts` | 純函式：`decideDeduction({mode, aiTurnCount, isTestAccount})`、`isSessionComplete(n)`、`MAX_AI_REPLIES=10` | ✅ quota |
| `deepseek.ts` | DeepSeek fetch（OpenAI 相容 `/chat/completions`，`Bearer DEEPSEEK_API_KEY`） | — |
| `logger.ts` | log helper | — |

共用 `_shared/quota.ts`（checkQuota / applyResetsIfNeeded / resolveLimits / TEST_EMAILS / `increment_usage` RPC，cost=1）。

### Request
```
{ mode: "chat" | "debrief",
  sessionId: string,
  turns: [{ role: "user" | "ai", text: string }] }  // 含這次要回的 user 訊息，不含待生成的 AI 回覆
```
`aiTurnCount = turns.filter(role==="ai").length`。chat 扣點條件：`mode==="chat" && aiTurnCount===0 && !test`。

### Response
- chat：`{ reply, aiTurnCount, sessionComplete, costDeducted, monthlyRemaining, dailyRemaining, provider:"deepseek", model, generatedAt }`
- debrief：`{ card:{summary, strengths[], watchouts[], suggestedLine, vibe}, costDeducted:0, monthlyRemaining, dailyRemaining, ... }`

### 失敗→不扣
扣點只在 DeepSeek 成功且 parse 成功之後。任何前置失敗回 4xx/5xx，未扣。

## Flutter：`lib/features/practice_chat/`

- `domain/entities/practice_message.dart`（@HiveType 22）、`practice_session.dart`（@HiveType 23：id, createdAt, messages, debrief 欄位, aiReplyCount）
- `data/services/practice_chat_api_service.dart`：可注入 invoker，`sendMessage` / `requestDebrief`；429→quota 例外、5xx→generation 例外、format→failure 例外
- `data/repositories/practice_session_repository.dart`：Hive CRUD + trim 到 5
- `data/providers/practice_chat_providers.dart`：Notifier（messages, loading, aiReplyCount, complete, debrief, error；失敗不 append AI 泡）；成功後 `syncUsageFromServer`
- `presentation/screens/practice_chat_screen.dart`：全螢幕聊天（user 右/AI 左）、輸入列（loading/complete 禁用）、「結束練習」、剩餘則數提示、quota chip、429→paywall、拆解卡、app bar 歷史 icon→最近 5 場 read-only
- `presentation/widgets/practice_room_entry_card.dart`：學習 tab 最上方，`BrandSurfaceCard`，`context.push('/practice-chat')`
- route `/practice-chat` 進 `lib/app/routes.dart`；adapter 註冊 + 開 box 進 `storage_service.dart`

## 測試

- Deno：`prompt_test.ts`、`validate_test.ts`、`quota_decision_test.ts`
- Flutter：repository trim-to-5、api service 錯誤映射（注入 invoker）、provider send/10-cap/debrief/失敗不 mutate

## Ops

DEEPSEEK_API_KEY 需在 Supabase secrets 設定（push 後新函式自動部署；未設 key 時回 `config_missing`，不影響既有函式）。
