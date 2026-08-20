# VibeSync Snapshot

> Rewrite when the project phase changes. This file is the current-state anchor for Claude/Codex sessions.

## 2026-08-20 Current Focus Guardrail

Rotate / new sessions must treat this file plus `git log --oneline -15` as the source of truth.
Old chat memory, Claude persisted output, and terminal screenshots are supporting context only.

Do not revive archived roadmap labels or old planning tracks unless Eric explicitly asks.

Current state:

- Coach 1:1 is shipped into dogfood and is part of the core product. Global `/coach` scope shipped 8 月。
- Older spec discussions are product fuel, not active task labels.
- Consumer-facing category word is `戀愛教練`（2026-08-18 拍板，真相源 `docs/positioning.md` ＋ ADR #30）。`約會教練` 是已淘汰用語（翻譯腔、且描述的是見面當天），程式碼內已無殘留，不要在任何門面文案復活它。
- Internal moat: VibeSync remembers the person, conversation, user intent, and coaching context, then helps users converge on a better next action.
- 學習專區（電子書《成為獎賞》＋聊天測驗）是 7 月底至 8 月初新增的核心區塊，已是 paywall 主打賣點之一。
- We are in TestFlight dogfood / App Review readiness stabilization.

Default priority:

1. P0/P1 dogfood bugs from Eric/Bruce.
2. Subscription, quota, RevenueCat, 429, paywall upgrade/downgrade safety.
3. Opener, analyze-chat, Coach 1:1 quality and UX stability.
4. App Review / launch-readiness cleanup.
5. 開場白／新話題 prompt 品質（8 月主戰場，見下方 2026-08-20 條目）。

## Recent Stabilization Train

Recent commit themes, newest first:

- **2026-07-24 → 2026-08-20（697 commits，本區塊上次更新後的整段空白）**：產品重心從「把核心 AI 功能做對」轉向「把整個產品面向使用者做完整」。要點如下，細節一律以 commit message 與各自真相源文件為準：

  - **開場白／新話題 prompt 品質戰役（8/17–8/20，最密集，方向未定）**：Eric 真機判定五句全對仗、像星座分析、像唸她的自介稿。三層根因——157 條列規則讓模型找一個同時滿足全部的骨架套五句；prompt 內的示範句被當素材庫逐字照抄（等於發罐頭）；輸入不變輸出就不變。對策：刪光同域示範句（`40afdb72`）、prompt 兩輪瘦身 15750→13240 字元（`b67d2f18`、`d9eaa9b4`）、最上層明寫「判準不是填空題、規則衝突時選體溫」（`757c89b9`）、用 requestId 取模輪替十個切入角度（`eeeea218`，跨輪重複 65%→33%）。**8/20 最後一次靶改（複述式）被 Eric 肉眼判定兩組都不好、已還原（`68851b00`），下一步方向尚未拍板。** 未解指標：唸稿開頭仍 5、分則仍 13。
  - **「prompt 治不了的缺陷改在資料層確定性處理」成為明確原則**：人稱（你/妳）、繁簡、標點正規化全部從 prompt 規則搬進 `outgoing_message_text`／`normalizeNewTopicModelPayload` 這類確定性 helper，開場五張卡與新話題共用（`d1c5359c`、`423beac5`、`2ebb53e5`、`c79f02df`）。理由：這些是使用者原封複製貼給對方的文字，錯一個字就露餡，而間歇性缺陷 prompt 賭不到。
  - **A/B 評測工具鏈 `tools/opener-prompt-ab`**：同資料、同模型、只換 system prompt 跑多輪，量轉折骨架／長度／唸稿開頭／分則／問號／照抄 prompt／你妳混用。三個量測坑已修：前十批跑在 `claude-sonnet-4-5` 而生產端是 sonnet-5（`d477e878`）、沒關 thinking 會吃光 token、正則有結構性盲點故補 LLM judge（`2b8b6697`、`c3379b2c`）。指標雜訊帶寫在 harness 檔頭（`b5c63875`）——沒量過雜訊帶不要拿指標比大小。
  - **練習室 NPC 安全與台味語感**：「咩修桿某」繞過字面粗俗 gate 還讓溫度 +2，連帶挖出四層漏接（台語諧音、髒話諧音詞組、英文粗俗詞組、注音火星文「厂厂」過繁簡轉換變「廠廠」）（`d97d2351`、`e36c27b5`、`0203cafb`、`1495168d`）。另加冒犯冷卻窗與笑聲量級語意。`tools/practice-behavior-smoke` 鎖模型行為（非 prompt 文字），**刻意不進 CI，pre-release 手動跑**。
  - **守門哲學翻轉**：Game hint／debrief 的 salvage 從白名單改成黑名單（只有紅線可擋，其餘一律端出去，`5f6a9a68`），守門嚴重度分級把偏好門從否決權降成 finding（`df764b3a`、`6e2e7466`）。根因是機械 gate 誤殺讓合格輸出回 503。
  - **AI 鍵盤進階化**：偵測到截圖直接分析（`d36de925`）、一次分析產兩批候選讓「換一批」不再扣第二次費（`ee0bad72`）、整段 judge 拿掉改單次呼叫（`3c56906c`）。**無完整取用時的 qwerty 地板整組移除，App Review 4.4.1 風險由 Eric 拍板承擔（`d6e736c0`），尚無替代合規面。**
  - **學習專區**：互動電子書《成為獎賞》（帳號隔離進度、訂閱閘門，免費範圍＝第一冊全部＋第二冊第一章）與聊天測驗（關卡地圖、fail-closed 解析器、60+ 題）。權限走 ADR #38：access 只表達訂閱檔位，不由取材推導。
  - **訂閱與抽卡經濟三次調整**：訪客模式完整上線又整案拆除（ADR #33 → ADR #34，`ddaeb873` → `39c03925`）；Free 每日抽卡移除改成起步清單一次性贈抽（ADR #35）；訂閱送 SR 限定翻牌券（獨立券表，主 RPC 計數排除券抽）；回覆微調拆掉 Essential 付費牆改成每天前十次免費（`6912b97f`）。
  - **設計語言整頓**：`DESIGN.md`／`PRODUCT.md` 成為設計憲法單一事實來源（`d2cc3c67`），四種機械檢查對 `slop_baseline.json` 逐檔比對的防回歸棘輪（`e09ea366`，399 筆既存債入基準，後降到 145）、16 份動效實作計畫完成、觸覺階梯全 App 鋪開並整條抬一級。
  - **對象資料主詞污染治本**：Bruce dogfood 抓到自由文字備註讓模型分不清主詞（「想約出來見面」被當成她的意願）。備註改 chips-only，手填入口與 `PartnerNoteEditDialog` 已刪除不留復活路徑（`6c875a8b`、`9ebe65a2`），prompt 端補主詞契約（備註永不得引用成對方發言，`f479870b`）。
  - **基礎建設**：CI Flutter 3.44.9 → 全 workflow pin 3.47.0（砍殭屍 codegen 依賴才解得開，`498e72c8` → `3046198d`）；GitHub Actions 供應鏈安全強化＋Node 24；新增跨環境執行契約 `.agent/environment.json`；反蒸餾三件套與隱私優先錯誤黑盒子；migration 帳本全量對帳 79↔79（`682ce456`）。

- **本次更新明確作廢的舊敘述**（新 session 若從舊記憶讀到，一律以此為準）：
  - 「公式開場／公式新話題」7/24 上線、**8/19 整功能下架**（`5cb637f8` → `1fd8e503`），只留 ledger 讀取相容；SQL migration 刻意不回滾。
  - 「訪客模式」8/01 上線、**同日整案移除**；任何提到訪客額度 3/30 則的記憶都已作廢。
  - 「Free Opener 只有延展」已過期：7/24 起免費版有延展／幽默／微調侃三種（`cff08291`）。
  - 「關於我」**不再影響**回覆／開場白／新話題的輸出內容，8/04 起只增進 Coach 1:1 理解（`ec13887e`）。
  - paywall 賣點已改成電子書／測驗兩列，「陪練女孩每日抽」不再是 Free 權益。

- Practice Hint＋Debrief 單發重設計 v2（2026-07-23）：96 秒 dogfood 失敗後整拆——hint/debrief 生成改 Claude Sonnet 5 單發（tool_use 強制 schema）＋敗一次補發 Haiku 4.5，DeepSeek 生成與 semantic reviewer 整層（semantic_quality.ts 3345 行）拆除，機械守門（parser 硬 gate／visible_text_guard／practice_visible_quality／hint_fact_ledger／白話 repair）與 prefetch claim/settle/discard、扣費語意原封。死線 hint 105s→35s、debrief 85s→45s、`DEBRIEF_IN_FLIGHT_STALE_MS` 105s→60s；telemetry `request_body.pipeline="single_shot_v2"` 供新舊對比。PUA/情勒 prompt 字面禁令拆除（Eric 拍板承擔）、硬安全條款與守門詞表零移除。練習聊天本體（chat/DeepSeek）、draw_profile、game_fsm 一行未動。收尾順序鐵則：四路黑箱 eval 三軸全綠 → Codex 雙審 APPROVED → 才可宣稱 dogfood safe。真相源：`docs/plans/2026-07-22-hint-single-shot-redesign-design.md`＋同名 plan。

- 教練統一 Phase C–F（2026-07-22）：Coach 1:1 抽出 scope 參數化 `CoachSurface`，對象頁掛同一聰明教練 engine（partner scope 串流／多輪／釐清＋三顆情境 chip＋deep-link focus），client 全路徑送 requestId 接 Phase C ledger replay；live e2e 兩 scope 全過、Codex R2 APPROVED。Phase F 收尾包 SHIPPED：三小債清償（partnerId 切換重置 auto-focus 閂鎖、`openCoachInputRequested` 改名、`CoachOpenCoachIntentEvent` 意圖事件改名）＋舊 coach_follow_up engine 死叢集刪除（7 lib＋7 test 檔＋LEGACY helper）；`flutter analyze` 0 issues、全套測試全綠。durable requestId 持久化仍為獨立案未做（見下方已知債條目）。

- Practice Debrief 語意複核根治（2026-07-19）：production v200 的連續失敗先定位為 Claude reviewer 沒有 provider-level JSON schema；第一階段 deploy 後又由 live Beginner smoke 定位第二層 fact-rejection state bug。最終契約是 surface-specific structured fact schema、reject 後強制點名欄位實際 repair＋fresh verifier、nested key shape 鎖定、Debrief semantic 4／總 provider 6／request-entry 85 秒 deadline。失敗仍 release owner、record 0、不增加 Debrief 次數。practice-chat Deno 934/934、三路高風險 review 0 P0/P1/P2；production v206 已部署，現役版 fresh Standard 單次 2/2、Beginner assisted 1/1 與 replay／continuity 全 PASS，deploy window 後四筆 telemetry 全 success、0 semantic reject。Server-only 已生效，無需新 App build。

- Analyze 串流與進度 UX 穩定化（2026-07-19）：Essential 五風格在 Sonnet 5 上沿用舊 `3200` output cap，真機輸出剛好寫滿後被標成 `STREAM_MAX_TOKENS`；Free 兩風格維持 `3200`，付費五風格提高為 `6000`，production `analyze-chat` v285（`verify_jwt=false`）同步記錄 120 秒 timeout／3 次 provider attempt。101 則訊息的 live contract smoke 完成五種核心風格與 `analysis.done`，用量 2546/6000、未扣 quota。App 端分析時「跟到最新」會持續顯示，點擊後跟隨目前串流，使用者往回滑即停止；中斷後保留「查看中斷」。OCR 左右歸屬提示改為延遲 650ms、示範 3.6 秒，之後保留靜態圖例。Practice v200 與 DeepSeek-first 路徑未變。驗證：Analyze Edge 643/643、相關 widget 69/69、OCR widget 28/28、Flutter 全套 2265 passed／4 skipped／0 failed、`flutter analyze` 0 issue，獨立複查 0 blocking/P2。

- Build 334 Sonnet 5 穩定化（2026-07-18）：Build 333 升級 Sonnet 5 後，OCR／文字串流未適配其預設 adaptive thinking；隱藏思考可能吃完共用 output budget，舊 OCR 又只讀第一個 content block，造成長等、空回應與重試風暴。OCR 現在遍歷可見 text blocks、使用 structured output 並限制為單次 provider／client 嘗試；Sonnet 5 文字串流則明確關閉 thinking，4.6／Haiku 行為、Free 兩風格、付費五風格、quota 與扣費均不變。Production `analyze-chat` v277 雙圖 OCR 一次成功（18 則、28.5 秒），v278 付費五風格 stream 一次完成（15 events、32.4 秒、2175/3200 output tokens）；Edge 617/617、Flutter analysis 69/69，兩輪獨立 review 均 0 P0/P1/P2。Build 333 不再作為測試基線，下一個真機候選為 `1.0.1+334`。

- Build 333 產品校準（2026-07-17）：Free `analyze-chat` 回覆從單一延展改為固定產出延展＋調情兩種，保留共鳴／幽默／冷讀作為付費完整五種差異；Free Opener 仍只有延展。對方這次的投入度在完成回應層統一改為 `ceil(AI 原分 × 0.9)`（例 82 → 74），不改 prompt、AI 理由或回覆選擇。OCR 確認視窗每次開啟都會自動播放一次左右滑動教學；長 OCR 等待以準備／上傳／讀圖／辨識訊息／校對說話者／整理結果狀態切換，不傳輸中間分析內容。原定 Build 332 實際由舊 `main@1c4992be` 建置，未包含本輪功能；第一個完整 binary 改為 Build 333，release preflight 會拒絕 source version 與 run number 不一致的 ref。

- AI 鍵盤恰一次結算（2026-07-17）：extension 以共享 Keychain 分指紋原子保存、綁 user＋文字＋風格的 durable UUID（重試資格約 23 小時，多筆／多帳號在途不互蓋）；`keyboard-reply` 先以 DB claim／lease 序列化模型呼叫，再由原子 RPC 同交易保存結果與扣 1。Server replay window 為 24 小時、每小時清理，input identity 使用 user-bound server-keyed HMAC。Production 已依 DB migration `20260717120000` → 32-byte HMAC secret → JWT-verified Edge v6 順序部署，live contract、DB transaction 與測試帳號 fresh／replay／mismatch smoke 通過且零殘留。發布仍 blocked 於 signed iOS keyboard、非測試 quota／HTTP 並行與 lost-response、公開隱私更新，以及 LINE／Instagram／Messages Full Access 真機矩陣。

- Sonnet 5 production 主路由定案（2026-07-18）：所有客戶可見 Claude primary（Free／付費 Analyze、Opener、Coach／Follow-up、Keyboard 與圖片）都使用 Sonnet 5。`analyze-chat` 的 4.6 → Haiku 只在上游 timeout／429／5xx 等真正中斷時降級；截斷、拒答與 context-window stop 一律 fail closed。Practice 明確不改，仍以 DeepSeek 為第一供應商並保留既有 tiered Claude failover／reviewer。Production Analyze v283／Coach v62／Follow-up v55／Keyboard v6 已部署，Practice v200 未動；Opener／Quick／Coach／Follow-up、stream 與 OCR 1–3 張 live smoke 全綠。Keyboard 使用 24s server／30s client／45s lease；一般分析與 OCR 沒有 durable requestId 時不做背景重送，避免 lost-response 重複扣額。
- 已知非阻斷營運債（2026-07-18 記，**2026-08-20 覆核：兩項都仍然開著，這五週沒有任何 commit 處理**）：管理端成本圖目前只從 `ai_logs` 彙總；Coach／Follow-up／Keyboard 尚未寫入 Anthropic token usage，因此總 AI 成本會低估。另 Coach requestId＋server ledger replay 已上線（Phase C/E：同 controller instance 重試同值、24h replay、竄改 409），但 requestId session 非 durable——離開頁面/dispose/重啟後的 lost-response 重送仍鑄新 id、可能再扣；durable envelope 持久化留 Phase F/另案，這兩項不得被描述成已完成 exactly-once／完整成本監控。

- Fable 5 回饋收斂（2026-07-16）：當次互動分數改成投入度語意；Coach 回答層級收合並改為只串流真實系統進度；空白對象／截圖續接與 Opener 三圖流程已修正。「我幫你修」成功固定扣 1，並以 owner-scoped durable requestId、原子 result/charge 與 7 天 live replay 防止新版 App 重複扣費。獨立 review、線上隱私政策、migration、Edge 與 live fresh/replay/mismatch smoke 均完成；同 commit 的 iOS／Android staging build 已成功上傳 Firebase App Distribution，下一關是真機 dogfood。舊 App 無 durable requestId，仍只有固定扣 1、沒有 exactly-once 保證。
- Analyze-chat 獨立分析紀錄（2026-07-15 起）：主畫面只顯示 current／pending 片段，舊成功案例由對象頁／分析頁右上封存入口開啟；每筆 owner-scoped、自足快照、無 FIFO、手動刪除。`metVia` 與每筆 `sourcePlatform` 分開；未知來源留在「全部」但不露出「未分類」，平台篩選只在至少兩種已知來源時出現。原整段封存改稱「已收起的對話」並降為抽屜次入口。cleanup marker＋tombstone 保護刪除，冷啟動 repair 失敗時禁止覆寫 canonical snapshot。AI request、prompt、quota、billing 不變；client-only，不需 Edge／DB deploy。

- Practice Hint／Debrief generated-only train（2026-07-11，branch `codex/no-canned-practice-ai`）：Beginner＋Game 共用 DeepSeek 12s → Claude 12s、逐欄品質閘與 Hint decision lineage；雙失敗不再把 fallback 當成功、不扣費不計次。local Deno 746/746、Flutter 516/516，SQL／client／兩路 backend gate 皆 0/0/0；等待 Edge-first deployment 與 TestFlight。
- Analyze-chat full streaming is the current product path. The old user-visible two-stage quick/full plan is superseded; frontend legacy naming cleanup landed in `d12009e`. Backend `quick/full` compatibility remains hidden rollback / old-client support only.
- `!codex` Phase 1 read-only Discord review gate: `dfde5f2`, `ec84bb0`.
- `!cc-rotate` external/mobile session rotation and bootstrap hardening: `80ce48a` through `abd8200`.
- CC dogfood handoff, queue, and current-state correction: `8b748c4`, `050f50e`, `e111550`, `128879f`, `2f72839`.
- Opener/paywall/quota/RevenueCat P0 fixes:
  - `6b18863` Free quota thresholds.
  - `4184c75`, `7c19994`, `1f49470` opener/analyze malformed JSON protection.
  - `26790b4` format failure no quota charge.
  - `4954581` paid tier cannot regress to Free on transient RevenueCat miss.
  - `a01cb0f`, `6dc38a2`, `54c0906` Paywall package mapping/fallback fixes.
  - `f0546c0`, `ce4aa9e`, `e660bcd` RevenueCat client key and paid quota sync.
  - `5f267c5` opener draft/save path.

If a new session sees older memory claiming an archived roadmap label is the current track, override it with this snapshot.

## Active Risk Areas

High-risk changes require Codex review before telling Eric/Bruce the build is safe to test:

- subscription, paywall, quota, RevenueCat, 429
- auth, account deletion, Hive/local persistence
- `analyze-chat`, opener, OCR, Edge response schema
- AI prompt changes that affect reply quality, safety, or token/cost behavior

Free user rule:

- Free users must be able to try core features until monthly/daily quota is exhausted.
- When exhausted, show a clear quota/paywall path.
- Do not accidentally block first-use opener/analyze/coach before quota is actually consumed.

RevenueCat rule:

- App client uses public `appl_` SDK key.
- Server/Edge uses secret RevenueCat key.
- Paid tier must not be downgraded to Free just because RevenueCat temporarily returns empty or delayed entitlement data.

Paywall rule:

- Monthly/quarterly products must map by exact product/package id.
- Do not use fuzzy title matching.
- Upgrade/downgrade behavior must be safe for all Free/Starter/Essential monthly/quarterly paths.

Opener rule:

- Opener is a "pioneer" feature: generate a useful first move, cache/save the paid result, and make the next step into analyze-chat/Coach 1:1 clear.
- If AI returns raw JSON or malformed schema, repair/retry and do not show raw JSON to users.
- Format failure should not charge quota.

Coach 1:1 rule:

- Coach should be practical, grounded, non-judgmental, and on the user's side.
- It can discuss dating escalation, nightlife, sexuality, short-term intent, and safety maturely.
- It must still maintain consent, boundaries, STI/contraception, and personal safety reminders without becoming preachy.

Analyze-chat rule:

- Current analyze-chat UX is full streaming analyze. Do not revive the old two-stage quick/full UX unless Eric explicitly reopens that decision.
- Client display separates each successful analysis into a self-contained record. The current/pending fragment stays on the main screen; only older successful records appear in the top-right analysis archive.
- Records have no FIFO and require manual deletion；8 月已補批次刪除（選取／長按多選／篩選內全選），分析紀錄 sheet、已收起的對話、最近練習三處對齊。`metVia` is partner-level; source platform is snapshotted per record and never guessed by OCR.
- The primary archive entry is the partner page's top-right box icon (the analysis page keeps a shortcut). Unknown source records stay in All without an “uncategorized” label; deletion lives in the read-only snapshot overflow menu.
- This record feature must not alter AI request messages, prompt, quota, billing, or Edge behavior.
- Existing backend `responseMode: quick/full` and `analysis_runs` artifacts are compatibility / rollback surfaces, not the official user-visible analyze design.
- Reply suggestions should read the actual conversation.
- Prefer "接住情緒 -> 互動感 -> 順勢延伸" over summary-like suggestions.
- For multiple incoming messages, identify catchable points and when useful suggest split replies; not every point needs a reply.

## Current Workflow State

權威來源是 `AGENTS.md`（授權、交付路徑、驗證要求）與 `.agent/environment.json`（跨環境執行契約：Git index 與 Flutter 產物歸 WSL，Windows 只跑允許清單內的唯讀指令）。動 Git／Flutter／build／test 前先讀執行契約。

Review：material R2/R3 走 dual-brain-review，由當前 host 直接叫設定好的 reviewer，不要請 Eric 手動搬 Review Packet。

外部／手機模式（**現況未經本次驗證，依賴前先自己確認還能跑**）：

- Discord listener 腳本 `~/.claude/channels/discord-vibesync/start.sh` 仍在（最後修改 2026-05-14），`tools/cc-rotate` 仍在（最後 commit 2026-07-25）。
- 但 `AGENTS.md` 與 `docs/shared-agent-rules.md` 現在**完全沒有提到** `!cc-rotate` 或 `!codex`，也就是說這不再是文件化的預設工作流。
- Codex CLI in WSL may need one-time login: `codex login --device-auth`.

## Validation Baseline

Recent targeted validations have included:

- `flutter analyze` after major Flutter changes.
- opener service/cache unit tests.
- targeted Edge Function tests around schema, quota, and malformed JSON.
- local bridge tests for `!cc-rotate` and `!codex` wrappers.

Before claiming a fix is safe, state what was actually tested. Do not imply full regression if only targeted tests ran.

## Next Default Action

When Eric or Bruce reports a bug:

1. Acknowledge the specific reporter and symptom.
2. Ask for missing repro details if needed: build number, account/tier, expected vs actual, screenshots, exact steps, reproducibility.
3. Investigate root cause.
4. Fix only the scoped issue.
5. Run targeted tests.
6. Commit + push.
7. If high risk, trigger Codex read-only review before saying "safe to build/test".
