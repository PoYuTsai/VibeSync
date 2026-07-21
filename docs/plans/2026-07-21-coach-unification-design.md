# 教練統一案設計文件（問教練一句 × 教練跟進 合併）

> **For Claude:** 本檔為 Phase A 設計鎖定產出＝後續各 Phase 的真相源。各 Phase 開工時另出 bite-sized 實作計畫（superpowers:writing-plans），執行用 superpowers:executing-plans。
> **狀態**: Phase A — 待 Eric/Bruce 拍板 D-1~D-6
> **分支**: `claude/coach-question-followup-integration-5twkr6`
> **日期**: 2026-07-21

**Goal:** 把 coach-chat（分析頁聰明教練）與 coach-follow-up（對象頁罐頭卡教練）合併為單一統一大腦，讓對象頁獲得多輪/串流/歷史/成效追蹤完整能力，同時以 exactly-once 帳本修掉「斷線可能重複扣費」。

**Architecture:** 就地擴充 coach-chat 為統一入口（加性選填欄位，不動 response 契約），coach-follow-up 凍結為 legacy shim；本機紀錄新增統一 Hive model（typeId 26）走 read-bridge 合併顯示、不搬不刪舊資料；扣費複製 keyboard-reply exactly-once 範本（ADR #22）。

**Tech Stack:** Supabase Edge Functions（Deno/zod）、Postgres RPC（claim/settle/release）、Flutter + Riverpod + Hive（AES-256）。

---

## 0. 白話摘要（給 Eric / Bruce）

- 現在 App 裡有兩個教練：分析頁的「問教練一句」很聰明（多輪、記歷史、串流、釐清免費），對象頁的「教練跟進」很陽春（單發罐頭卡、不可追問、每次扣 1）。
- 合併後：對象頁也享有聰明版全能力；三種罐頭情境（準備邀約/約會前提醒/約會後復盤）保留、改由聰明教練回答。
- 順手修掉現有小毛病：斷線時可能「扣了額度卻沒拿到卡片、重問再扣一次」→ 同一個問題只算一次錢。
- 風險帶：扣費/本機 Hive 紀錄/Edge schema 三個敏感地帶 → 分六個 Phase 小步走，高風險段（C、D 及 B/E 觸 Edge-schema/cost/Hive 部分）Codex APPROVED 才稱 dogfood safe。

## 1. 已驗證讀碼事實（2026-07-21 subagent 抽查，10 條中 7 條全實、3 條修正）

- `coach-chat/schemas.ts:68` 起 `RequestSchema`，`.strict()` 在 **:85**（新欄位未部署前 client 先送＝硬 400）→ **部署順序鐵律：Edge 先容忍、App 後送**。`partnerId` 已選填（`:70`）。
- 成本已是 server 純函式：`schemas.ts:144-147` transform `costDeducted = responseType === "clarifyingQuestion" ? 0 : 1`；`generation.ts:237-244` 僅 `coachAnswer` 才 `deductCredit`。此契約已涵蓋 follow-up「結構卡扣 1」。
- `schemas.ts:3` `CoachChatModeEnum` 只用於 response card（`:101`），**不在** RequestSchema → 情境折入必須新增輸入欄位，不可挪用 `mode`。
- coach-follow-up 輸入：`phase` 選擇器在 `coach-follow-up/schemas.ts:45-46`；結構化答案欄位**實名 `answers`**（`:47-51`，`{q1,q2?,q3?}`）——非先前草案寫的 `structuredAnswers`。
- exactly-once production 範本：`supabase/migrations/20260717120000_keyboard_reply_exactly_once.sql`（`:107 claim`、`:263 settle`＋`:271 p_charge_quota`、replay kind `:177`）。對應決策為 **ADR #22**（`docs/decisions.md:685`；`:780` 明言 Coach/Follow-up exactly-once 為獨立專案）。**勿自創、照抄範本。**
- `_shared/model_rate_limit.ts:5` `(user_id, scope)` 複合鍵、FOR UPDATE＋超限（新增 scope 純加性）。`increment_usage` 的 row lock＋tier RAISE 實作在 **DB RPC（SQL migration）**；`_shared/quota.ts:206-207` 只是 Edge 側 RAISE 偵測。
- Hive typeId 已用 0–25（`storage_service.dart:33-58`），**下一空號 = 26**；typeId 16（CoachFollowUpResult）/17（CoachChatResult）adapter 續留註冊（`:49-50`）。
- 成效已 partner-aware：`coach_chat_providers.dart:161`（partnerId 有值走 `coachingOutcomeDigestProvider(partnerId)`）。
- 直接重用、不可重造：`effective_style_prompt_builder.dart:121 buildForCoachFollowUp`、`_shared/{quota,model_rate_limit,banned_tokens}.ts`、`AiDataSharingConsent.ensure`、既有 deep-link（`routes.dart:118 coachPrefillQuestion`／`partner_detail_screen.dart:70-73 focus=coachFollowUp&focusAction=openCoachInput`／`partner_detail_screen.dart:884 _CoachFocusOrchestrator`、路由組裝 `routes.dart:134-137`）。

## 2. 目標架構

就地擴充 coach-chat 為統一大腦，coach-follow-up 凍結為 legacy 相容 shim（D-1 建議案：port 成本最低、避免第三個部署函式）。

1. **情境折入為加性欄位**（不動 `mode`）：新增選填 `lifecyclePhase?`（`prepareInvite`/`preDateReminder`/`postDateReflection`；`openCoach`＝一般自由首輪）＋ `structuredAnswers?{q1,q2?,q3?}`（形狀沿用 coach-follow-up 的 `answers`，統一端命名 `structuredAnswers` 避免與既有語意混淆）；`prompts.ts` 加情境 framing 段落。
2. **scope 判別式**：新增選填 `scope: {type:"conversation",conversationId} | {type:"partner",partnerId}`，同時保留頂層 `conversationId`/`partnerId` 相容舊 client；server 導出 `scopeKey="${type}:${id}"`。**response 契約不變。**
3. **單一 Hive model**（typeId 26）：read-bridge 遷移（Phase D）。
4. **單一 rate-limit scope `coach`** ＋ 不變成本 transform。
5. **durable requestId exactly-once**：複製 keyboard 範本（Phase C）。

## 3. Invariants（鐵律——動碼前先寫進 review 文件）

1. 單一邏輯請求至多扣一次（有 requestId＝exactly-once；無＝維持今日行為）；絕無「扣費卻遺失卡片」。
2. settle 扣費與存卡同一交易：不會有已扣費卻無卡、或標記已扣但 increment_usage 未 commit。
3. 釐清輪（clarifyingQuestion）在任何 scope／路徑永不扣費。
4. 生成在 settle 前失敗永不扣費（沿用 `generation_test.ts` `deductCalls.length === 0` 慣例）。
5. quota preflight 語意不變（月先於日、測試帳號 bypass、free 用到真正耗盡前不擋）。
6. 付費用戶永不因暫態訊號降級為 Free（RC refresh 只升不降，不動）。
7. 遷移／read-bridge 永不刪改 legacy typeId-16/17；但 `clearAll` 與 per-scope 刪除**必須**清 unified box（防跨用戶外洩）。
8. `result_json` 與 telemetry 只存卡片/欄位形狀，永不存來源訊息/prompt/原始輸出。

## 4. Failure Matrix（摘錄）

| # | 情境 | 無 requestId（今日） | 有 requestId（統一） | 守門 |
|---|------|--------------------|--------------------|------|
| F1 | 扣費後、收 200 前斷線 | 卡遺失、重送重扣 | `claim=replay` 回存卡、`charged=false` | claim replay |
| F3 | 同 requestId 併發雙送 | 兩者都可能扣 | 首 claimed／次 pending/replay＝單扣 | lease＋PK |
| F4 | 不同問題撞同 requestId | n/a | `REPLAY_MISMATCH` RAISE | `input_hash` |
| F5 | 釐清輪重試 | 不扣但可能重生不同問句 | replay 回同一釐清卡 | settle `charge=false` |
| F6 | claim 後生成失敗 | 5xx、未扣 | `release` 刪 pending、乾淨重試 | `release_coach_claim` |
| F8 | preflight↔settle 間 quota race | RAISE→429 | 同 RAISE 於 settle 交易內→429、不存已扣卡 | row-locked `increment_usage` |
| F9 | ledger 表缺（Edge 早於 migration） | 走 legacy（OK） | **fail closed 503、不扣** | `coach_contract_version()` |
| F11 | 同裝置換新用戶 | n/a | `clearAll` 也清 unified box | `storage_service.dart:210` |

## 5. 分階段

### Phase A — 設計鎖定（本檔；無 code，安全）
- 產出：本設計文件＋Codex 審查包資訊（§7）。
- 驗收：Eric 拍板 D-1~D-6；Codex packet（base ref／檔案清單／高風險焦點）就緒。

### Phase B — 後端加欄位、行為不變（先鋪路）
- 目標：coach-chat 看得懂新選填欄位（`requestId`/`scope`/`lifecyclePhase`/`structuredAnswers`），沒人送時行為與今日 byte-for-byte 相同；prompt 加情境段落。
- 改檔：`supabase/functions/coach-chat/{schemas,prompts,validate,index}.ts` ＋各 `_test.ts`。
- 驗收：Deno 測舊 body 仍過、新欄位選填、response byte-identical、情境 prompt 段落形狀；測試帳號 live 舊格式仍 200。可先部署、對現況零影響。

### Phase C — 扣費只算一次（最敏感、單獨隔離）
- 目標：新增帳本表 `coach_requests`，複製 keyboard exactly-once（ADR #22 範本）：同 requestId 只生成/扣費一次，斷線重送回放同卡不重扣；釐清不扣；生成失敗不扣；帳本沒裝好 fail-closed 503 不扣。`input_hash`＝server-keyed HMAC over（userQuestion＋sessionId＋activeSessionTurns＋forceAnswer＋scopeKey＋lifecyclePhase/structuredAnswers）。`result_json` 只存卡＋envelope（CHECK 結構檢查、不存來源文字）。requestId 缺席→今日 deduct-on-success 路徑。
- 改檔：新 `supabase/migrations/<new>_coach_exactly_once.sql`（範本＝`20260717120000_keyboard_reply_exactly_once.sql`）、`coach-chat/{index,generation,progress_stream}.ts`、重用 increment_usage RPC。
- 部署順序：先 apply_migration＋對齊 ledger 版本 → 再部署 Edge → 最後才出 App。**絕不 `supabase db push`。**
- 驗收：Deno 測 claim=claimed/replay/pending/mismatch、settle charge=1 vs 0、release-then-retry、owner mismatch、quota-RAISE→429、contract 缺→503；測試帳號 live 三態 smoke（fresh／斷線重送／mismatch）驗 DB row＋零殘留；串流 replay 只發單一 `coach.done`。**Codex adversarial APPROVED 才可稱 safe。**

### Phase D — 本機紀錄合成一套（不動舊資料）
- 目標：新增 `UnifiedCoachResult`（typeId 26，CoachChatResult 超集＋`scopeType`/`scopeId`/`lifecyclePhase`）；新版只寫此 box；舊 16/17 box 唯讀、讀取時即時合併顯示（不搬不刪）；泛化 repository 為 scope-keyed（保留 keepPerConversation=10 trim/rollup）。特別確保換用戶零殘留。
- 合併規則：conversation scope＝unified ⊕ typeId-17 by conversationId；partner scope＝unified ⊕ typeId-16 `get(partnerId)`（欄位映射 observation→userState/answer、task→nextStep、phase→lifecyclePhase）；依 id 去重、generatedAt 排序。
- 改檔：新 entity＋`.g.dart`、`coach_chat_repository_impl.dart`（泛化）、`lib/core/services/storage_service.dart`（`clearAll()` **必加清 unified box**——防跨用戶外洩的最高後果一行、`initialize()` 用同 `HiveAesCipher` 開 box）、`coach_follow_up_repository_impl.dart`（唯讀來源）。
- 驗收：Flutter unit 測合併/去重/排序、rollup 與今日對等、clearAll 清 unified、換用戶零殘留、刪對象/刪對話清對應 unified rows。Codex APPROVED。

### Phase E — 前端合體（使用者真正有感）
- 目標：從 `CoachChatCard` 抽出 scope 參數化的共用 `CoachSurface`（串流渲染／threaded 歷史／釐清・forceAnswer／reflection・outcome）。分析頁掛 `CoachSurface(scope: conversation)`；`CoachFollowUpSection` 變薄 wrapper＝情境 chip row＋openCoach entry 疊在 `CoachSurface(scope: partner)` 上 → 夥伴層首次有 threading/串流/成效。chip 點擊以 `lifecyclePhase`＋`structuredAnswers` 種入；新 client 送 `requestId`（重送保持同值）；「問教練」全指向同一 engine，只差 scope。
- 改檔：`coach_chat_card.dart`、`coach_chat_api_service.dart`（＋requestId）、`coach_chat_providers.dart`、`coach_follow_up_section.dart`、`partner_detail_screen.dart`、`partner_mind_map_screen.dart`、`lib/app/routes.dart`。
- 驗收：Flutter widget/controller 測雙 scope、夥伴層 threading/串流/forceAnswer、consent gate、deep-link focus/prefill/mind-map redirect、requestId 重送穩定；`flutter test` 全套＋`flutter analyze` 0 issue；雙介面 live end-to-end。

### Phase F — 舊教練退場（等舊 App 汰換）
- 目標：凍結 coach-follow-up，定義「舊 build 汰換完成」觸發點以刪 shim＋清 legacy box，抵達單函式/單模型/單 scope 終態。
- 產出：更新 `docs/decisions.md`（新 ADR）。

## 6. 待拍板 D-1 ~ D-6（附建議預設）

- **D-1** 就地擴充 coach-chat（**建議**）vs 新開 `/coach` slug 強隔離。
- **D-2** 統一 rate-limit `coach` 數值（**建議**沿用較寬的 10/min、300/day）。
- **D-3**（billing）partner openCoach 改「釐清免費／正式扣 1」——比現在少扣，需 Eric 明確確認。
- **D-4** 夥伴層維持精簡 5 欄卡 vs 採用完整教練卡 UI。
- **D-5** 接受 read-bridge（**建議**，暫時並存 3 model、零觸碰 typeId-17）vs 一次性 copy 大遷移。
- **D-6**（次要）遷移的舊卡 `costDeducted` 未知（顯示用）→ 選中性 sentinel。

## 7. Codex 審查包（每高風險 Phase 出包）

- base ref：該 Phase 起點 commit（Phase B 起＝本分支對 main 的 merge-base）。
- 檔案清單：照各 Phase「改檔」節列。
- 高風險焦點：Phase B＝`.strict()` 相容性與 response byte-identity；Phase C＝claim/settle/release 交易邊界、F1/F3/F4/F8/F9 全矩陣、`input_hash` 覆蓋欄位完整性；Phase D＝clearAll 跨用戶外洩、read-bridge 去重映射；Phase E＝requestId 重送穩定性、consent gate、deep-link 回歸。
- 佐證慣例：Deno/Flutter 測試輸出＋live smoke 證據隨包附。

## 8. 執行紀律

- 一 commit 一 concern、繁中 commit message、完成即 commit＋push（本分支）。
- Phase B 起才動 Edge，嚴守部署順序（Edge 先容忍、App 後送；migration 先於 Edge）。
- 高風險階段（C、D，及 B/E 觸 Edge-schema/cost/Hive 部分）取得 Codex APPROVED evidence 才對 Eric/Bruce 稱 dogfood safe。
- 絕不 `git add pubspec.lock`；migration 一律 MCP apply_migration＋對齊帳本版本，絕不 `db push`。
