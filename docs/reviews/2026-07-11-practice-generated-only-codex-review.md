# Practice Hint／Debrief generated-only — Codex 高風險雙審

日期：2026-07-11  
分支：`codex/no-canned-practice-ai`  
範圍：Beginner＋Game Hint、兩型 Debrief、quota／idempotency migration、Flutter crash/retry durability

## 出貨契約

- DeepSeek 最多 12 秒；失敗、逾時或品質不合格才交 Claude 再跑最多 12 秒。
- 只有通過 schema、可見安全、逐欄 grounding 與策略一致性檢查的 model output 才能成功。
- 兩個 provider 都失敗時只回 retryable error；不落 fallback snapshot、不扣費、不計 Hint／Debrief 次數。
- replay 只回 generated-only snapshot，當次 `costDeducted=0`，剩餘額度一律覆蓋最新 subscription usage。
- Hint 選項各自帶 server decision；Debrief 不得在沒有 Hint 後新回覆的情況下推翻它。

## 對抗審查修正

- 封住短中文、短 Latin 與 emoji 最新回覆讓萬用句 fail-open。
- 邀約分類改讀「她是否真的被放進計畫」；`明天我也想喝咖啡` 不算邀約，非白名單活動的具體共同計畫仍算。
- Debrief 可見策略與最後一筆權威 Hint route 比對；build→soft/direct、repair→invite 等改判必須帶 Hint 後逐字證據。
- Game breakdown 五欄各自 grounding，不能由 summary 或 nextFirstLine 的單一具體詞替其他空泛欄位洗白。
- Debrief fresh claim 後才 rate-limit；replay bypass。只有成功 `record_practice_debrief` 才計次，record/release 失敗不吃次數。
- Hint normal／legacy／無 requestId 都使用精確 owner token fence；A worker 的 late record/release 不能清掉或扣到 B worker。
- client 在請求前保存 requestId，重啟沿用；完整 Hint envelope、套用 lineage 與 Debrief pending 狀態按 session 隔離，晚到結果不能回寫另一場或把 quota 往上蓋。

## Review verdict

- SQL／quota／token-fence 高風險審：**APPROVED，P0/P1/P2 = 0/0/0**。
- Client durability 最終審：**APPROVED，P0/P1/P2 = 0/0/0**。
- Backend generated-quality／lineage convergence：兩個獨立 bounded final gate 均 **APPROVED，P0/P1/P2 = 0/0/0**。最終補驗涵蓋陳述式／隱含對象邀約、口語見面與接送、否定／取消、自我／第三方敘述，以及 `Okay`／`Thanks`／`haha` grounding。

## 驗證

- practice-chat 全套 Deno：**746 passed / 0 failed**；`index_test.ts` **180/180**。
- migration/source＋PGlite／真 PostgreSQL：**17/17**。
- Flutter practice-chat unit＋widget：**516/516**；scoped analyze 0 issue、format 0 changed。
- `deno check index.ts`、changed TS fmt/lint（32 files）、`git diff --check`：通過。
- 使用者既有 `pubspec.lock` diff hash 維持 `155151b4d3096ddc42a4457638cd8984fb9d8620`，不納入本功能提交。

## Deployment evidence

PENDING — 只允許 Edge-first → 等舊 worker drain → 目標式 migration up；完成後補 revision、migration ledger、production smoke 與 TestFlight workflow run。
