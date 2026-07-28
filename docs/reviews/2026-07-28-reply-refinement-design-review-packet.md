# Review Packet — 回覆風格微調（設計審查，無 code 變更）

> 2026-07-28。審查標的：`../plans/2026-07-28-reply-refinement-design.md`
> 白話版（產品面，非本次審查標的）：`../plans/2026-07-28-reply-refinement-plain.md`
> **本 packet 沒有任何 runtime code 變更**，請審查的是設計本身的正確性與風險，不是 diff。

## Range

- Branch：`claude/reply-style-refinement-j6br3y`
- 現況基準 SHA：`c7cefb4405bcacd1bb127e56e6e5e8b46fd145af`（`c7cefb4` 鍵盤：底部三列併成一列）
- 變更檔案：僅三個新增文件檔（本 packet ＋ 設計文件 ＋ 白話版）
- Migration：**無**
- Secrets：**無**
- 尚未執行：全部實作、全部 live steps

## 產品決策（Eric 已拍板，非審查範圍）

- D-1 微調對**全部用戶**開放，每次成功微調扣 1 則。
- D-2 入口三處：AI 推薦回覆、五張風格卡、草稿潤飾結果。
- D-3 Phase 2（微調偏好回寫「關於我」）納入本次設計。

請 review 的是**這些決策的實作可行性與風險**，不是決策本身。

## 已驗證讀碼事實（2026-07-28 逐條核對，附證據）

| # | 事實 | 證據 |
|---|---|---|
| F1 | 草稿潤飾是 Essential **雙閘**：client 與 server 各一道 | `lib/features/analysis/data/services/optimize_message_request_session.dart:12`（`canSendOptimizeMessageRequest`）；`supabase/functions/analyze-chat/index.ts:7121-7142`（403 `FEATURE_NOT_AVAILABLE`） |
| F2 | server input hash 的 canonical 陣列目前恰 8 個元素 | `optimize_message_billing.ts:39-48`（messages, userDraft, sessionContext, conversationSummary, partnerSummary, effectiveStyleContext, knownContactName, forceModel） |
| F3 | client fingerprint 的陣列元素與順序與 F2 對應但獨立計算 | `optimize_message_request_session.dart:295-340`（`fingerprintFor`），且註解明說 server 獨立算權威 hash |
| F4 | `isOptimizeMessageMode` 共 **13 個使用點** | `index.ts:6875, 6880, 7124, 7148, 7218, 7350, 7484, 8280, 8887, 9111, 9115, 9119, 9212` |
| F5 | requestType 由**請求形狀**推導，非顯式旗標 | `quota_usage.ts:3-27` `deriveRequestType`；`index.ts:4711` `isOptimizeMessageRequestShape` |
| F6 | 回覆風格是固定五槽＋tier 過濾，且**只有輸出、沒有輸入** | `index.ts:582-603` `TIER_FEATURES`；`tier_sync_contract.ts:55` `streamReplyStylesForTier`；`analysis_stream_runs.selected_style` 為記錄欄 |
| F7 | 微調會共用 `analyze` rate-limit scope＝6/分、60/日 | `supabase/functions/_shared/model_rate_limit.ts:12` |
| F8 | 限流 429 payload **絕不可帶訂閱額度鍵**，否則 client 誤判成 paywall | `model_rate_limit.ts:45-49` 註解 |
| F9 | 分析片段快照不可變 | `analysis_screen.dart:8394` 註解「分析完成後關閉原片段；任何新內容都另開獨立片段」；`AnalysisFragmentPolicy` |
| F10 | exactly-once 全套目前塞在 UI method 內 | `analysis_screen.dart:4916-5088`（`beginAttempt` → 送出 → `_clearOptimizePendingAfterVisibleFrame` → mismatch `reset`） |
| F11 | `userDraft` 硬上限 1500 字 | `index.ts:656` `MAX_USER_DRAFT_LENGTH`；驗證於 `index.ts:6591-6600` |
| F12 | replay 命中會**刻意繞過 Essential 閘門**，避免降級後結果被鎖死 | `index.ts:7144-7148` 註解 |
| F13 | mismatch／invalid requestId 都回 **400**，且文案硬寫「草稿潤飾」 | `index.ts:6884-6892`、`index.ts:6934-6942`、`index.ts:9273-9274` |
| F14 | Coach 已有「3 次免費釐清後才扣 1」的先例 | `lib/features/coach_chat/data/providers/coach_chat_providers.dart:93` |

## Invariants（鐵律，請以此為審查基準）

1. 沒帶 `refineInstruction` 的請求，client fingerprint 與 server input hash 必須與今日 **byte-identical**。
2. 一次成功微調恰扣 1；格式失敗／400／429 一律不扣。
3. 草稿潤飾器維持 Essential；放行 Free 的只有 `refine_reply`。
4. 指令永遠是資料，不能改變訊息在對話中的動作，也不能覆蓋安全／同意／界線條款。
5. 微調結果不寫入 `AnalysisRecord`，分析片段快照維持不可變。
6. 不新增 migration、不動五風格 enum、不動模型路由（Sonnet 5）。

## 待裁決問題（請給明確 verdict，不要只給評論）

### Q-1（必答）條件式 append 是否真能保證舊請求 hash byte-identical？

設計主張：`refineInstruction` 只在非空時才 append 進 canonical 陣列，因此舊請求（無指令）的序列化字串一個 byte 都不變。

請同時檢查兩側：Deno 的 `JSON.stringify` 對「陣列長度 8 vs 9」的輸出差異，以及 Dart `jsonEncode` 在 `fingerprintFor` 的對應行為。**若此假設不成立**，部署當下 7 天窗內所有未結算 pending 請求會全變成 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`，使用者拿不回已付結果。

請裁決：假設成立/不成立；若成立，需要哪種測試才足以鎖住（快照 hash 常數？黃金向量？）。

### Q-2 新增 `refine_reply` requestType 後，F4 的 13 個使用點各自該怎麼處理？

設計主張：改為 `isOptimizePathMode`（涵蓋兩種 requestType），**唯一保留窄判斷的是 7121-7142 的 Essential 閘門**。

請逐點裁決是否正確，特別是這幾處漏改的後果：

- `7124`（quota preflight 豁免條件）
- `7148`（replay 短路回傳）
- `9115 / 9119`（client shape 驗證與「無效結果不扣費」）
- `9212`（settlement ledger 寫入）

請明確指出：**哪幾點漏改會導致重複扣費或漏扣費**，哪幾點只是退化成一般 analyze 行為。

### Q-3（必答）Essential 閘門只放行 `refine_reply`，是否存在繞過潤飾器付費牆的路徑？

請針對這些邊界給裁決：

- 送空字串或全空白字元指令（trim 後為空）→ 應被判成 `optimize_message` 並擋在付費牆，還是回 400？
- 送只有標點／emoji 的指令
- client 帶一個無意義指令（例如「.」）把自己的草稿偽裝成微調，藉此免費用潤飾器
- `deriveRequestType` 靠形狀推導（F5），是否足以承擔付費邊界的判斷責任

若設計有洞，請給出建議的收斂方式（顯式旗標？最短指令長度？server 端語意判斷？）。

### Q-4 迭代與 `userDraft` 1500 字上限的互動

微調把上一輪 `optimized` 當下一輪 `userDraft`。整組訊息（`_copyAllText` 換行合併）可能本來就不短。

請裁決：多輪迭代是否可能單調成長到撞上 F11 的 400？若會，應該在 client 先擋並給文案，還是設計上就限制只能微調單句？

### Q-5 共用 `analyze` rate-limit scope 是否合適？

F7＝6/分。一次分析＋三輪快速微調＝4 次/分。

請裁決：這是否會把正常來回誤判成濫用？若建議拆出獨立 scope，請說明代價（新 scope 要不要進 SQL？既有 fail-open 行為是否受影響？）。

### Q-6 80 字自由指令的 prompt injection 面

設計主張「指令當資料、以分隔區塊注入 user prompt、不進 system prompt」，並由 prompt 契約要求模型忽略越界要求且在 `reason` 誠實說明。

請裁決：這樣是否足夠？是否需要額外的字元類別或關鍵詞防線，還是那樣反而會誤傷正常需求（例如使用者正當地說「不要那麼客氣」）？

### Q-7（必答）微調版本的複製會污染卡片 outcome telemetry

**本次額外發現。** 現況每張卡的複製行為記在該卡的 key 上（`_recordAnalysisCopy(cardKey: ...)`、`_buildAnalysisOutcomeBar(cardKey: type)`，見 `analysis_screen.dart:5642-5648, 5619`）。若使用者複製的是**微調過**的版本，資料仍會記到原卡 key，讓「這張卡有沒有被採用」的統計失真。

請裁決三選一：(a) outcome 事件新增「是否經過微調」維度；(b) 微調版本的複製不計入卡片 outcome；(c) 另立獨立事件。並說明哪一個對現有資料的連續性傷害最小。

### Q-8 用「不同指令＝不同 hash」取代 regenerate 鍵，是否可接受？

同 draft ＋ 同指令 ＝ 同 hash ＝ replay 同一段文字且不扣費，因此不提供「同輸入再擲一次」。

請裁決這是否是可接受的產品行為，以及有沒有兼顧「換一版」與冪等的更好做法（不得放棄 exactly-once）。

### Q-9 錯誤文案硬寫「草稿潤飾」

F13：`INVALID_OPTIMIZE_MESSAGE_REQUEST_ID` 與 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH` 的 message 都是「草稿潤飾請求格式有誤…」。微調路徑會顯示錯誤功能名。

請裁決：文案分支放 server（依 requestType 切）還是 client（依當前入口切）？後者能否避免動到既有 Edge 契約。

## Failure Matrix（請驗證預期是否正確）

| 情境 | 預期行為 | 預期扣費 |
|---|---|---|
| 送出中斷／網路失敗 | durable requestId 已先落地，重試打同一個 id；server replay 回原結果 | 恰 1 |
| App 被殺後回來、貼回同一內容＋同一指令 | 指紋相同 → 命中 pending → replay | 恰 1（不重扣） |
| 指令超長（>80） | 模型與 quota 工作前 400 | 0 |
| `refineInstruction` 有值但無 `userDraft` | 400 | 0 |
| quota 剛好用完 | 429（訂閱額度 payload）＋paywall | 0 |
| 觸發 6/分限流 | 429（`MODEL_RATE_LIMITED`，**不得帶額度鍵**） | 0 |
| tier 中途降級、replay 命中 | 依 F12 刻意繞過閘門，取回已付結果 | 0（先前已扣） |
| 模型回傳格式無效 | 不寫 ledger、不扣費 | 0 |
| input hash mismatch | 400 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`，client reset session | 0 |

## 請 Codex 明確 falsify 的三個命題

- **P1**：本設計不需要任何 migration。
- **P2**：本設計不改變既有 Free／付費邊界，唯一新增的是 `refine_reply` 對 Free 開放。
- **P3**：本設計對現有 7 天窗內的 pending optimize 請求零影響。

每一條請給 SUPPORTED / REFUTED，並附證據路徑。

## 通過標準

- **Q-1、Q-3、Q-7 必須有結論**，本次 review 才算完成。
- Q-2、Q-4、Q-5、Q-6、Q-8、Q-9 可標記為「實作階段再定」，但需明確標記，不得默認略過。
- P1–P3 三條命題必須各有 verdict。
- 本 packet 無 code，因此不附測試證據；實作階段的 packet 會另出，屆時附 Deno／Flutter 測試輸出與 live smoke。
