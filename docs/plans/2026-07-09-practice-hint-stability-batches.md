# 練習室 hint 穩定性＋高手化＋溫度契約 三批計畫

> 需求日：2026-07-09（Eric）。真相源：本檔。原始調查全文在 session transcript
> `~/.claude/projects/-mnt-c-Users-eric1-OneDrive-Desktop-VibeSync/995cbc33-6eeb-4411-8205-3a30d56eb7c8.jsonl`
> （穩定性 line 73、溫度契約 line 75、Game hint 高手度 line 57）。

## 原始需求（Eric 逐字）

> 有時候還是不太穩定，等很久，回來 fallback 很差的回覆，"牛頭不對馬嘴"。
> 溫度計、後台關係度、debrief 契約行為是否一致？
> game hint 應該要是真的聊天高手，定位是速約。明明已經餵過很多資料（聊天7步法則、速約、高階技術）還不夠高手。
> 這輪分 batch 處理掉，按 TDD 工作流，高風險走 Codex 雙審，都處理完最後白話文報告，預期測試會看到什麼。

## 批1 穩定性 — ✅ SHIPPED（33e6c105..c5b9fe47 共 7 commit，2026-07-10 push＝自動部署）

三關全過：驗證（Deno 526 綠、Dart 123 綠、analyze 零錯）→ 內部審查（F1 in-flight 403 rotate 重複扣費窗口→d21355cd 修；F2 timeout 20s→25s→60dc53bf）→ Codex 雙審（首審 NEEDS_FIX 抓 P1 跨回合 stale hint replay→c5b9fe47 指紋修；重審 APPROVED 零 finding）。
部署後觀察項：`practice_chat_*_hint_fallback_used` 日誌盯一週，fallback 率暴升再考慮回調 9s 預算（nit-1）。
記錄在案不修：chat 路徑無 requestId 冪等（F3，歷史既有，另案）。

| 項 | 內容 | Commit |
|---|---|---|
| S1 | `HINT_TIMEOUT_MS` 12000→9000；timeout 首敗即 fallback 不重試；格式/驗證類維持重試 1 次 | 0a660e17 |
| S2 | `hintRetryReason` 修掉 timeout 誤標「格式或安全規則不合格」 | 0a660e17 |
| S3 | fallback 用 `fallbackAnchorSnippet` 錨定對方最新一句；收斂疲累/話題偵測器（同句命中時話題優先） | 3f896e4c |
| S4 | fallback 罐頭 `p_charge_quota: false` 不扣 quota；replay 快照照寫、冪等不變 | 5bb98512 |
| C1 | client `requestHint`/`sendMessage` 補 `.timeout`；timeout 轉可重試 state、不 rotate requestId | 105d12ef |

待辦：flutter analyze＋全測試複跑 → spec 審＋品質審 → **Codex 雙審（S4 動 quota＝高風險）** → push（=自動部署）。

## 批2 Game hint 高手化（Batch D 補做）— ⬜ 未動工

素材源：`docs/plans/2026-07-08-social-knowledge-integration-design.md` 3.3 節。

1. 把七步轉譯（聊她/聊我/聊我們、給她一顆球、生活樣本）接進 hint prompt（現只進了 NPC 演法 `prompt.ts:76` 與 debrief `prompt.ts:328`）
2. hint 的抽象英文祈使句改成繁中 few-shot 示範句（可借用現成 fallback 高手句 `hint.ts:588-606`）
3. 統一七步骨架，與 NPC/debrief 對齊
4. 速約推進階梯從 fallback-only 升為主 prompt 明確指令
5. 非 SR 卡也給具體招式（`game_fsm.ts:753` 放寬）
6. 選配（先不做，批2 完看體感）：hint 模型升檔或溫度 0.45→0.7

高風險（AI prompt 行為）→ Codex 雙審。

## 批3 溫度契約補洞 — ⬜ 未動工

1. debrief prompt 注入實際溫度 band，要求評語不得與溫度矛盾（`prompt.ts:376-431`）
2. `buildFallbackDebriefCard` 吃溫度參數分檔，不再恆為中性/低機會（`debrief_card.ts:34-92`）
3. client 溫度計顏色改讀 server 回的 `band` 欄位，廢棄 client 自建 4 桶（`practice_chat_screen.dart:1573-1578`）
4. 附帶：beginner fallback hint 不看溫度 → 一併接 band

高風險（AI prompt 行為）→ Codex 雙審。

## 收尾

三批全過審後：push（觸發 Edge 自動部署）→ 白話文總報告（含「預期測試會看到什麼」）。
