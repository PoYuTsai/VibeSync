# practice-chat hint/debrief 503 通用解 — 實作報告

日期：2026-07-21 · 狀態：實作完成、全測綠、離線 eval 完成，**待 Codex 雙審＋真機 dogfood**

## 一、根因與設計（照 spec）

503 多半不是格式解析或 provider 掛掉，而是「一張已過客觀硬內容 gate 的合法候選，
被第二個模型的主觀語意複審 reject（或 game grounding 一票否決），重試預算燒完後統一
轉 retryable 503」。通用解：把「reject → 燒 budget → 503」改成「保留最佳候選 → 到出口
時供給」，安全類（unsafe / debrief 誤導性 unsupported_fact）維持硬底線 503。

## 二、設計核對結果（每個 Change 對得上真實碼嗎）

- **Change A（保留並供給 best gate-passing candidate）** — 對得上。hint 迴圈在
  `handler.ts` `parseGeneratedHint` 內、debrief 在 `parseGeneratedDebrief` 內，兩者
  都在 semantic catch 取得 pre-semantic 候選；出口整合點選在 `if (hintResult===null)`
  / `if (debriefCard===null)` 的 throw 前，讓降級候選走與正式成功完全相同的下游
  persist/response 路徑（比在 503 return 處另接一條供給路徑安全得多）。
- **Change B（非安全 reject 降 repair-only）** — 部分對不上 spec 字面，已按實際碼結構
  實作：spec 指的 `terminalSemanticRejection`／`terminal...` 其實在
  `semantic_quality.ts`（非 handler），且該檔是一個約 1200 行的多 provider 裁決狀態機。
  **我刻意不改該狀態機內部**（風險過高、測試面極廣）。改在 handler 出口層用
  `SemanticAdjudicationError.issueKinds` 做安全分流：hint 排除 `unsafe`；debrief 排除
  `unsafe`＋`unsupported_fact`。效果等同 spec 意圖（非安全 reject 不再終局 503），但
  blast radius 只在出口層。
- **Change C（venue/third-party 幻覺改 strip 再驗）** — 對得上、但範圍收斂到「偵測得到
  的第三方實體」。實測發現：(1) 嚴格接地 gate（semanticAdjudicated=false）對已知良好的
  game hint 會誤殺（`unsupported_detail:user:preference`），與正式成功門檻不一致；
  (2) 低信心 venue 散句（2026-07-13 分層信心後）本來就不被 deterministic gate 抓，是
  semantic reviewer 在管。故最終設計：降級候選一律用「與正式成功相同」的 gate
  （`semanticAdjudicated=true`）驗證，供給前主動用 `stripUnsupportedThirdPartyDetails`
  移除 owner=world/third_party 的未接地子句。使用者自陳事實（user/partner/shared）
  一律不 strip（屬 Change B 安全底線）。debrief 未套用 strip（事實風險已由 issueKinds
  排除涵蓋，且 suggestedLine 是外送句，保守處理）。

**衝突/暫停點**：spec 把 `terminalSemanticRejection ~3260/3282/3334` 標成 handler，
實際在 `semantic_quality.ts`；spec 的 hint 迴圈行號（2916-3243）與 503 出口（3238/3243/
4142）大致相符（±1~數行）。無其他對不上的點需暫停。

## 三、各 commit 摘要

| commit | 一句話 | 關鍵位置 |
|---|---|---|
| `a00223f6` | 新增第三方幻覺 strip 基礎設施（Change C） | `hint_fact_ledger.ts` 新增 `collectUnsupportedHintFactClaims`／`stripUnsupportedThirdPartyDetails`；`assertHintFactClaimsSupported` 改用 collector |
| `a4f9e864` | 提示主觀 reject 改供給最佳客觀-gate 候選 | `handler.ts` hint 迴圈：`bestGatePassingHint`＋semantic catch salvage＋null-check 出口供給 |
| `0f564c1b` | 拆解主觀 reject 改供給最佳客觀-gate 候選 | `handler.ts` debrief 迴圈：`bestGatePassingDebrief`＋semantic catch salvage＋null-check 出口供給 |
| `c212bb93` | 降級 gate 對齊正式成功門檻＋提示改主動第三方 strip | `handler.ts` `salvageHintCandidate`／`salvageDebriefCandidate` |

一 commit 一 concern、繁中訊息、未 `git add pubspec.lock`。

## 四、離線 eval 成功率（`tools/practice-503-eval/eval.ts`）

**誠實聲明**：離線 eval，不打模型。以「注入 semantic verdict(issueKinds)＋固定逐字稿
fixture＋候選卡」驅動 handler 的降級出口決策（salvage 走與 handler 相同的真實
`parseHintResult`／`parseDebriefCard`／`stripUnsupportedThirdPartyDetails`）。量的是
「到達終局 reject 出口時會轉 503 還是改供給」，非 prod 命中率。

各路徑「終局 reject 出口 → 503 率」舊 → 新：

| 路徑 | n | 舊 503% | 新 503% | 供給數 |
|---|---|---|---|---|
| newbie_hint | 5 | 100% | 40% | 3 |
| game_hint | 4 | 100% | 25% | 3 |
| newbie_debrief | 4 | 100% | 50% | 2 |
| game_debrief | 4 | 100% | 50% | 2 |

新 503% 的殘量全部來自「刻意放進 fixture 的安全/prefetch 案例」（unsafe、
unsupported_fact、prefetch），這些**本來就必須維持 503**。把安全/prefetch 案例排除後，
四條路徑的「純主觀 reject（subjective_reject / revision_required / venue_named）」
在新邏輯下**全部由 503 轉為供給**。venue_named 兩批（hint）由 strip 復原後過 gate。

## 五、測試結果

- practice-chat Deno 全套：**1138 passed / 0 failed**（含新增 `hint_fact_ledger_test.ts`
  三個測試：collector 對齊 assert、strip 移除第三方子句、strip 不碰 user/partner 事實）。
- **無 snapshot 變動**。生成 prompt bytes 一律未動；本案全部改在 post-parse／出口邏輯層。
- `deno check handler.ts` / `hint_fact_ledger.ts` 綠。

## 六、安全底線仍生效的證明

eval 內建「安全底線自檢」：所有 `safety_unsafe` 與 `safety_unsupported_fact` 案例在新
邏輯下**仍 503、未供給**，自檢輸出 `PASS`。對應碼證據：

- hint：`salvageHintCandidate` 只在 `!issueKinds.includes("unsafe")` 時被呼叫；
  prefetch 一律不供給。
- debrief：只在 `!unsafe && !unsupported_fact` 時被呼叫。
- Change C strip 僅移除 owner=world/third_party；使用者自陳事實永不被竄改。
- 降級候選仍須通過與正式成功相同的硬 gate（canned／bossy／game 契約／欄位角色），
  未過即回 null → 維持 503。

## 七、需主對話/Codex 決策的點

1. **未動 semantic 狀態機**：Change B 用 handler 出口層 `issueKinds` 分流取代改
   `semantic_quality.ts` 內部 reject→repair。若要更貼近 spec 字面（在裁決機內把非安全
   reject 降 repair-only），需大改該狀態機，風險高、建議獨立案＋Codex 深審。
2. **hint 降級容忍 unsupported_fact reject**：依 spec「hint 是給使用者的行動建議、
   過度保守主觀 reject 不該 503」，hint salvage 不排除 `unsupported_fact`（只排除
   unsafe），並靠 Change C strip 清掉可偵測的第三方幻覺。殘餘（如使用者自陳背景被
   模型虛構）仍可能供給——這是 spec 明訂的取捨。若判斷 hint 也要硬排除
   unsupported_fact，改一行即可（同 debrief）。
3. **debrief 未套用 Change C strip**：保守處理（suggestedLine 為外送句）。若要對 debrief
   third-party 也做 strip，可比照 hint 擴充。
4. 高風險區（AI prompt/token 行為）：依 CLAUDE.md **須 Codex 雙審通過才可宣稱 dogfood
   safe**；本報告只到「實作完成＋全測綠＋離線 eval」。
