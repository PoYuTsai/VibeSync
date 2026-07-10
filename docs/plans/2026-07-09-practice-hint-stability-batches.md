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

## 批2 Game hint 高手化（Batch D 補做）— ✅ SHIPPED（fc00c7cf..5523a80e，Codex 首審 P1→修→重審 APPROVED 零 finding，2026-07-10 push＝自動部署）

素材源：`docs/plans/2026-07-08-social-knowledge-integration-design.md` 3.3 節。
TDD 全程（每項先紅後綠）；Deno 528→540 綠（新增 12 測試）；Game prompt 長度 5933→5488（英文抽象句改繁中反而變短）。

| 項 | 內容 | Commit |
|---|---|---|
| G3 | 七步骨架對齊 NPC/debrief 的 P1 開場/資訊交換→P5 鎖定/收尾，捨棄 Codex 自編英文骨架 | ba893f0c |
| G2 | 兩段 contract 改繁中規則＋`GAME_HINT_MOVE_EXAMPLES` few-shot（6 句借自 fallback 高手句；測試鎖 80 字、guard 管道原樣通過、1.2 原詞不外露） | f781cbb0 |
| G1 | `sevenStepBalanceContract`：聊她/聊我/聊我們、查戶口補狀態＋感受、給球、近邀約門檻低壓不硬衝（3.3 節） | b7f280a4 |
| G4 | `speedInviteLadderPrompt`：server FSM 判本輪階梯位置以白話標籤注入；階梯建議抽 `GAME_INVITE_ROUTE_ADVICE` 與 fallback 共用；coaching 須講這輪哪一階、下一階怎麼推 | f552cf4e |
| 清理 | `gameStrategyPrompt` 恆真 ternary 三處收斂 | f483c966 |
| 補 | gameHint header 英文段繁中化＋明禁可見輸出用 1.2 原詞（舊 header 允許 coaching 點名「框架、性張力」與紅線衝突）＋`repairGameVisibleLabels` 補 speedInviteLadder 映射 | 66252ae2 |
| 補 | deno fmt；coaching 明示 140 字內防 160 hard-cap silent slice | e95d5be9、da7b83ba |
| 審修 | 品質審 3 Important＋1 Nit：repair 表 Frame→節奏與主見對齊新紅線（FRAME_COLLAPSE→「框架掉了」刻意保留＝debrief 既定白話、口語狀態非招式語境）＋fallback 罐頭招式語境「框架」改白話；route LABEL/ADVICE export＋守門管道測試；階梯 rung 行常數插值去雙份真相；coaching 軟上限抽常數釘 headroom（140<160） | 2f496b20、9a638351、20a097f0、63b5dba5 |
| Codex P1 | 可見輸出補中文 1.2 原詞轉譯（篩選→互相合適度、推拉→輕鬆張力、可得性→安全感釋放、框架→節奏與主見、資格篩選/賦格→品味門檻、DHV→生活樣本）；選 repair 不選 reject（詞彙可安全轉譯；reject 觸發重試/fallback 懲罰過重）；「框架掉了」sentinel 限縮為唯一放行固定短語；被釘綠的 hint_test/index_test 補明確斷言（index_test＝handler 全路徑蓋 LLM 路徑） | 5523a80e |

項5 非 SR 具體招式已於本批 T1 完成（fc00c7cf 放寬 `buildSrGameStrategy` 非 SR gate＋6760dc86 改名 `buildGameStrategy`，spec/品質雙審過）。項6 模型升檔/溫度選配未做（如計畫，看體感另議）。

**待 Eric 拍板（產品決策）**：handler 有 `practice_game_sr_only` 403 gate（handler.ts:430-435、1182、1343、1669），非 SR 卡今日進不了 Game 模式——T1 放寬目前是鋪路死碼。若拍板開放，gate 拆除案 checklist：①拆三處 403；②`prompt.ts:76/98`「Game is SR 限定」「SR-character training」文案同步改（模板字串語意漂移沒有測試會抓）；③`visible_text_guard.ts:33` `srstrategy` 加 legacy 註解。

## 批3 溫度契約補洞 — ⬜ 未動工

1. debrief prompt 注入實際溫度 band，要求評語不得與溫度矛盾（`prompt.ts:376-431`）
2. `buildFallbackDebriefCard` 吃溫度參數分檔，不再恆為中性/低機會（`debrief_card.ts:34-92`）
3. client 溫度計顏色改讀 server 回的 `band` 欄位，廢棄 client 自建 4 桶（`practice_chat_screen.dart:1573-1578`）
4. 附帶：beginner fallback hint 不看溫度 → 一併接 band

高風險（AI prompt 行為）→ Codex 雙審。

## 收尾

三批全過審後：push（觸發 Edge 自動部署）→ 白話文總報告（含「預期測試會看到什麼」）。
