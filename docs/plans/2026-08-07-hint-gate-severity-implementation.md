# Hint 守門嚴重度分級 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計真相源:`docs/plans/2026-08-06-hint-gate-severity-design.md`(Eric 逐段拍板,判定表以它為準)。

**Goal:** hint 偏好門第一發即收卡+finding 進 telemetry;紅線/結構照擋;salvage 退役、改窄版結構 degrade pass;prefetch 同一套分級。

**Architecture:** 全部改動在 `supabase/functions/practice-chat/` 的 `hint.ts` + `handler.ts` 兩檔(+測試)。鏡射 debrief 的 `onQualityFinding` callback 模式(`debrief_card.ts:837-858` 的 `soft()`)。wire 形狀零改動、`HINT_QUALITY_SCHEMA_VERSION` 不 bump。

**Tech Stack:** Deno(Edge Function)、既有 `hint_test.ts`/`handler` 測試慣例。測試跑法:`deno test --allow-env supabase/functions/practice-chat/hint_test.ts`、收尾 `deno check supabase/functions/practice-chat/index.ts`。

**Commit 紀律:** 一 commit 一關注點、繁體中文訊息。每個 Task 結尾 commit。

---

## 現況地圖(執行者必讀)

| 位置 | 內容 |
|---|---|
| `hint.ts:128-194` | `HintParseOptions`——本案要動的旗標全在這 |
| `hint.ts:1486-1521` | `rejectBossyPasteableHintReply`(降 finding) |
| `hint.ts:1523-1578` | `requiredString`——紅線/超長/bossy/generic-pasteable 都在這裡跑 |
| `hint.ts:2476-2577` | `assertGeneratedHintQuality`——主戰場 |
| `hint.ts:2587-2608` | `salvageHintCandidate`(退役→改窄版 degrade) |
| `hint.ts:2633-2751` | `parseHintResult` 主流程(旁白句/degrade 剪句在尾段) |
| `hint.ts:854-990` | `buildHintDecision`——`salvagePass` 讓路旗標(913/934/973/989 的 throw) |
| `handler.ts:2573-2790` | hint 生成區塊:`hintParseCandidate`、`runSingleShot`、salvage catch |
| `handler.ts:3608-3615` | debrief finding log——鏡射目標 |
| `practice_visible_quality.ts:443-455` | 紅線黑名單(不動,hint/debrief 共用) |

**嚴重度判定表(拍板,不得自行增減)**

- 照擋(否決權):紅線四類、壞 JSON/缺欄/型別錯、`hint_quality_invalid_overlong`、`hint_quality_invalid_duplicate_replies`、`hint_stage_direction_reply`(單欄旁白)、Game 契約 slug(`hint_quality_invalid_game_contract`)、`hint_no_pasteable_conflict`/`_unsupported_client`/`_unsupported_state`、`buildHintDecision` 的邀約階梯 throw(913/934/973/989——邀約階梯是 server 契約,維持前兩發照擋、degrade pass 讓路,同今日 salvage 行為)。
- 降 finding(收卡+記碼):`hint_quality_invalid_not_grounded`、fact ledger(`…unsupported_detail`)、`hint_bossy_pasteable_reply`、雙欄純問句(`hint_quality_invalid_pure_questions`)、generic-pasteable(`hint_quality_invalid`)。
- 靜默跳過→復活為 finding:`hint_quality_invalid_substantive_move`、`hint_quality_invalid_invite_coaching_conflict`、`hint_quality_invalid_game_coaching_substance`。
- degrade 白名單(最後手段剪救,Task 5):`hint_quality_invalid_overlong`、`hint_quality_invalid_duplicate_replies`、`hint_stage_direction_reply`。

---

### Task 1:`HintParseOptions` 換血——加 `onQualityFinding`,拍板刪四旗標

**Files:** Modify `hint.ts:128-194`;Test `hint_test.ts`。

1. `HintParseOptions` 新增:

```ts
/**
 * 守門嚴重度分級(2026-08-06 Eric 拍板,同 debrief):偏好門不否決,
 * 違規碼經此 callback 記 telemetry。未注入=finding 靜默丟棄(直呼 parser 的舊測試)。
 */
onQualityFinding?: (code: string) => void;
```

2. 刪除四個旗標與其所有讀點:`skipLexicalGrounding`(grounding 永遠只記 finding)、`salvagePass`(salvage 退役)、`relaxSubjectiveQualityRubrics`(主觀門一律 finding,不再有「跳過」檔位)、`semanticAdjudicated`(無 prod 生產者,死旗標;先 `grep -rn semanticAdjudicated` 確認只剩 hint.ts 與測試)。`degradeStructuralDefects` **留下**,註解改寫為「只有結構 degrade pass(最後手段)可開」。
3. 這步只改型別與註解,讀點的行為改動在 Task 2-4;先讓 `deno check` 紅起來當守望清單,逐點修掉。
4. 測試檔裡 17 處引用這些旗標的測試:引用 `relaxSubjectiveQualityRubrics`/`semanticAdjudicated` 的改成驗「主觀門記 finding 且照收卡」;引用 `salvagePass`/`skipLexicalGrounding` 的併入 Task 4/5 改寫。
5. Commit:`改:HintParseOptions 換血——onQualityFinding 進場、salvage/semantic/relax 三旗標退役`

### Task 2:`requiredString` 內的 bossy 與 generic-pasteable 降 finding

**Files:** Modify `hint.ts:1523-1578`;Test `hint_test.ts`。

1. **先寫紅測試**:bossy 句(如「妳先給我一個標準答案」)當 `warmUp`,`onQualityFinding` spy 收到 `hint_bossy_pasteable_reply`,且 parse 不丟、卡照回。generic-pasteable 同型測試(`hint_quality_invalid`)。跑:`deno test --allow-env supabase/functions/practice-chat/hint_test.ts --filter bossy`,預期 FAIL。
2. 實作:`rejectBossyPasteableHintReply` 與 `rejectGenericPasteablePracticeText` 的呼叫點包 `soft()`(自 debrief `debrief_card.ts:848-858` 抄同型 helper,收 `options.onQualityFinding`)。紅線三連發(`rejectInternalLabelLeak`/`rejectL4UnsafeVisibleText`/`rejectKnownCannedPracticeText`)與超長 throw **不動**。
3. 跑同 filter,預期 PASS;另跑既有紅線測試確認沒鬆(`--filter canned`、`--filter l4`)。
4. Commit:`改:hint bossy/萬用句降 finding——措辭偏好不再殺卡`

### Task 3:`assertGeneratedHintQuality` 分級重排

**Files:** Modify `hint.ts:2476-2577`、`hint.ts:80-88`;Test `hint_test.ts`。

1. **先寫紅測試**(各一正一反):
   - 雙欄純問句 → 收卡+finding `hint_quality_invalid_pure_questions`;單欄純問句 → 無 finding。
   - 不接地句 → 收卡+finding `hint_quality_invalid_not_grounded`。
   - 捏造事實 → 收卡+finding 含 `unsupported_detail`。
   - coaching 說不約但 warmUp 在約 → 收卡+finding `hint_quality_invalid_invite_coaching_conflict`(從跳過復活)。
   - 無實質行動句 → 收卡+finding `hint_quality_invalid_substantive_move`。
   - Game coaching 空洞 → 收卡+finding `hint_quality_invalid_game_coaching_substance`。
   - `duplicate_replies` 與 Game 契約 slug 缺失 → **照丟**(反例鎖住否決權)。
2. 實作:引入同一個 `soft()`;`HintPureQuestionError` 類別刪除(`hint.ts:80-88`,無其他消費者),改 `onQualityFinding`。`relaxSubjectiveQualityRubrics` 讀點刪除=三道主觀門一律走 `soft()`。`semanticAdjudicated` 兩個 early-return(2382/2518)刪除。fact-claims 迴圈與 grounding 迴圈包 `soft()`。`duplicate_replies`(維持 `degradeStructuralDefects !== true` 才丟)與 game contract throw 不動。
3. 跑 `hint_test.ts` 全檔,預期 PASS。
4. Commit:`改:hint 守門嚴重度分級——偏好門降 finding、靜默主觀門復活為 finding`

### Task 4:`parseHintResult`/`buildHintDecision` 旗標對齊

**Files:** Modify `hint.ts:2633-2751`、`hint.ts:854-990`;Test `hint_test.ts`。

1. `requiredString`/`parseHintResult` 內殘存的 `salvagePass` 讀點(1560、1572、2483-2484)刪除;`buildHintDecision` 的 `salvagePass` 參數改名 `finalDegradePass`(行為不變:開了讓邀約階梯讓路)。
2. 既有 salvage 導向測試改寫:驗 `degradeStructuralDefects: true` 時超長剪裁、duplicate 剪一句(2740-2744 既有路徑)仍成立。
3. 跑全檔 PASS。Commit:`改:salvagePass 旗標退役——degrade 讓路只剩 finalDegradePass 一條`

### Task 5:`salvageHintCandidate` → `degradeStructuralHintCandidate`

**Files:** Modify `hint.ts:2587-2608`;Test `hint_test.ts`。

1. **先寫紅測試**:
   - 敗因 `hint_quality_invalid_duplicate_replies` 的候選 → degrade pass 剪一句端出。
   - 敗因 `hint_canned_visible_text`(紅線)→ 回 null。
   - 敗因 `hint_json_parse_failed` → 回 null(parse 再炸)。
   - 敗因 `hint_quality_invalid_not_grounded` → **不會出現**(已是 finding,不會進 failures;用反例註記而非測試)。
2. 實作:改名+把「`isSalvageableFailureCode` 黑名單反查」換成**白名單**:

```ts
const DEGRADABLE_STRUCTURAL_CODES = [
  "hint_quality_invalid_overlong",
  "hint_quality_invalid_duplicate_replies",
  "hint_stage_direction_reply",
] as const;
```

   只有敗因碼命中白名單的候選才試 `parse(raw)`(呼叫端帶 `degradeStructuralDefects: true` + `finalDegradePass`)。JSDoc 說明:偏好門已不殺卡,這裡只救「內容好、形狀壞」的三種結構瑕疵;其餘(紅線/JSON/Game 契約/no_pasteable 矛盾)一律 503 出口。
3. 跑全檔 PASS。Commit:`改:hint salvage 退役——改窄版結構 degrade pass(白名單三碼)`

### Task 6:handler 接線——finding 收集、log、salvage 分支替換

**Files:** Modify `handler.ts:2573-2790` 與 hint 回應組裝處(`~2881`/`~3030`);Test:handler 既有 hint 測試所在檔(先 `grep -n "practice_chat_generation_salvaged" supabase/functions/practice-chat/*_test.ts` 找到消費者)。

1. `hintParseCandidate`(2656-2682):每次呼叫建立區域 `codes: string[]`,`onQualityFinding: (c) => codes.push(c)` 傳進 parse options;成功回傳時把 codes 附掛(closure 寫回外層 `hintQualityFindingCodes`,**只保留最終被端出那發的 codes**——失敗發的 codes 隨候選一起丟棄,已在 `attemptFailures.code` 有跡)。
2. catch 分支(2740-2790):`salvageHintCandidate` 呼叫改 `degradeStructuralHintCandidate`,override 只剩 `degradeStructuralDefects: true`;degrade 成功時 push finding 碼 `hint_structural_degrade_served`。`hintSalvageUsed` 改名 `hintDegradeUsed`;`practice_chat_generation_salvaged` 事件改 `practice_chat_generation_degraded`(欄位形狀不變,`buildPracticeGenerationTelemetry` 的 `salvageUsed` 欄位同步改名——先 grep 確認 debrief 共用與否,共用就 hint 側傳新欄、debrief 欄不動)。
3. 成功出卡後,鏡射 debrief 3608-3615:

```ts
if (hintQualityFindingCodes.length > 0) {
  logInfo("practice_chat_hint_quality_finding", {
    user: summarizeUser(user.id),
    practiceMode: request.practiceMode,
    model: hintModel,
    prefetch: requestIsPrefetch,
    codes: hintQualityFindingCodes,
  });
}
```

   放在 hint 的 `practice_chat_generation_outcome` log 之後、response 組裝之前;prefetch 與冷路徑同一條(`requestIsPrefetch` 已在 1959)。
4. **回應 payload 不加欄位**(wire 凍結);`HINT_QUALITY_SCHEMA_VERSION` 不動。
5. 跑 handler 相關測試+`deno check supabase/functions/practice-chat/index.ts`。
6. Commit:`改:hint finding 進 telemetry——事件 practice_chat_hint_quality_finding、salvage 分支換 degrade pass`

### Task 7:收尾驗證與死碼掃除

1. `grep -rn "salvagePass\|skipLexicalGrounding\|relaxSubjectiveQualityRubrics\|semanticAdjudicated\|HintPureQuestionError\|salvageHintCandidate" supabase/functions/ lib/ 2>/dev/null | grep -v debrief` → hint 側必須零殘留(debrief 側的 `salvagePass`/`isSalvageableFailureCode` 是活碼,**不動**)。
2. 全套:`deno test --allow-env supabase/functions/practice-chat/` + `deno check supabase/functions/practice-chat/index.ts`。fmt 鐵則:**只 fmt 觸及檔**,絕不整目錄。
3. Commit(若有殘渣清理):`清:hint 分級死碼掃除`

### Task 8:對抗審查與交付

1. 高風險(AI 管線+quota 相鄰)→ 依共享審查流程派**對抗式雙審**。Codex 額度 2026-08-08 15:10 前用罄,期間主審派 **Grok 4.5**(`grok-codex`,大 diff 用 `--cd` 讓它讀檔,prompt 引數傳)。
2. 審過→依 AGENTS.md 交付鏈:push `main`(無 migration;`practice-chat` 由 push workflow 自動部署,不重複手動 deploy)→ 盯 Edge deploy + exact-SHA `Build & Distribute`。
3. 上線觀測(寫進收尾回報):隔幾天撈 ai_logs 對比——`practice_chat_generation_attempt` 敗因碼分佈會左移(偏好門碼消失),`practice_chat_hint_quality_finding` 分冷熱看 finding 率;長期偏高=修 prompt/門,**絕不加回否決權**。真機 dogfood:Game/新手各按一次 hint,體感延遲+內容不空話。

---

## 實作註記（2026-08-07 收官時補）

- Task 5 的 degrade 白名單三碼在實作時發現不足：舊 salvage 是黑名單，實際還原諒
  邀約階梯／Game 契約／無可貼句狀態接地——只留三碼會把 2026-08-05 的 503 修復
  倒退。白名單最終為**六碼**（+`invite_route`、`game_contract`、
  `no_pasteable_unsupported_state`）；`semantic_invite_move` 經 Grok 首審 P1
  拍掉（buildHintDecision 無讓路點，重解一樣炸，列入名單＝名實不符）。
- `degradeStructuralDefects` 與 `salvagePass` 合併為單一 `finalDegradePass`
  （兩者只會一起開，兩顆旋鈕是漂移源）。
- telemetry 鍵名為 `codes`（鏡射 debrief 實際事件形狀；design 檔原寫
  findingCodes 是措辭錯誤，已更正），並同碼去重。
- 對抗審由 Grok 4.5 執行（Codex 額度 8/8 前用罄）：APPROVED_WITH_FINDINGS，
  兩 P1 已修（見上）；P2 follow-up＝degrade 白名單 exact-match 對 code 形狀的
  契約測試、softQualityGate 只吞 hint_* 機器碼。
