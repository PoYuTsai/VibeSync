# 開場救星兩段式 · 內容守門 交接（給下一個 CC session）— 2026-09-18

> 本檔只交接，不改產品程式、不重跑全套、不跑付費模型。維持：不 push、不 PR、不 merge、不部署、不套 production migration、不觸發 workflow、不跑付費模型／付費 reviewer。

## 0. 結案狀態（2026-09-18 晚間，最新；以下各節是歷史脈絡）

- 產品候選：`d72820ce7fbca416b58b29d6f010b55dc64c7b30`（內容守門第七輪）；工具交付：`75fbf17f26d334d00e3a133490eb2cad50c2f842`（`tools/opener-repair-replay/`，只供驗收）。HEAD＝75fbf17f＋本檔 docs-only commit；產品檔相對 d72820ce 零 diff；工作樹乾淨。
- 付費驗收全部結案：真模型確認跑 70 次 $1.26（tag `g1g2-d4824177-confirm`）＋一次內容修正 12 次 $0.3615（tag `repair-d72820ce`，Free 8／paid 4）。**不再重抽、不追加模型呼叫、不為 repair-01 提高 token 上限或加第二次修正。**
- Reviewer 最終裁決（`opener-cc-final-repair-review-d72820ce.zip`，`review/REVIEW.md`）：**建議 `APPROVE_WITH_RISK — 僅限下一階段內部 iPhone 候選`**。不是原規格全文 PASS、不是一般用戶公開上線通過。**新增內測風險由 Eric 決定是否採納，尚未採納。**
  - 已修好：家庭用品／妹妹腳痠／妹妹引語的指定捏造已在修正結果移除；咖啡四筆推薦已接住邀約目標。
  - 未完全符合：海邊三筆把「猜她喜歡海邊」擴成用戶沒明示的邀約，且可見備選仍全是滑板；咖啡備選只同主題不同邀約目標（原規格「推薦＋至少一張可見備選」仍有缺口；這是 `checkMaterialAdoption` 一張即過＋修正只改標記卡的既有範圍，不是執行漏改）。
  - repair-01（single-hook-dog A2 Free）保持未交付：stop_reason=max_tokens、2800 tokens、text 為空；失敗不交付不結算的設計可接受；完整 HTTP body 當時未存，原因不可事後補造。
- 保留風險（reviewer 命名，供內測候選記錄）：R-CONTENT-INTENT（猜測被擴成輕邀約）、R-CONTENT-ALT（採用下限一張，備選未必接原料）、R-CONTENT-WORDING（同行家屬／看人臉色／成癮玩笑等用語）、R-REPAIR-AVAILABILITY（一次修正可能無可用文字，照契約不結算）。
- 勘誤：`opener-repair-confirmation-d72820ce.zip/REPORT.md` 的「51／56 份未修正內容」應為 **55／59**（與 55＋8、59＋4 一致）；只改文案，原 ZIP 不重製、不重跑。
- 統計的正確讀法：Free 62/63、paid 63/63 是「歷史初次輸出＋離線修正」的機器放行數，不是端到端實測，也不是內容通過率；12 筆中 1 筆未交付不能推成一般用戶失敗率。
- 下一階段＝整合＋限定真機驗收，**需要 Eric 另行明確授權**。屆時走本 repo 的 PR、必要 CI 與正式 ruleset，不用 owner bypass；目前仍不 push、不 PR、不 merge、不部署、不套 production migration、不觸發 build／release、不另跑付費模型或 reviewer。
- 隔離／放行能力（本輪唯讀核對，供決策）：Edge 只有全域旗標 `OPENER_TWO_STAGE_ENABLED`（`opener_flow_handler.ts` 第 374 行，`=false` 只擋新局），**沒有帳號白名單**；`accountIsTest` 只影響扣額與限流，不是放行。App 端沒有旗標，裝了新版 client 的帳號就會走兩段式，舊版 client 走舊單段（Edge 收到舊請求仍走舊路徑）。所以「限定內測」實際上只能靠 TestFlight build 的發放範圍限制 client，Edge 一旦部署就是全域可達；要真正只對內測帳號開放需另做帳號級放行，本輪未做、也不在授權內。
- 工程、PostgreSQL、Flutter、保存佇列、已接受 P2 全部不重開。

## 1. 目前狀態（交接當下核對）

- worktree：`/home/eric1/worktrees/vibesync-opener-two-stage-20260917`
- branch：`opener-two-stage`（基準 main `3134c513`）
- **目前 HEAD＝這份交接檔本身的 docs-only commit**（SHA 用 `git rev-parse HEAD` 讀，因為檔內無法寫自己的 commit SHA），其父 commit 為最後交付 `214af4ca15092b9a86bc69f54f00d3345b0f5b7a`（2026-09-18 11:09 +0800）之上；兩者之間只有本檔，沒有產品程式差異。
- `git status`：乾淨，**無未提交修改、無未追蹤檔**。沒有 reset、沒有清工作樹、沒有為交接湊 commit。
- 最後已審基準：工程複核 `bf658fae`（產品程式凍結點；第五輪 APPROVE_WITH_RISK）；內容補修最後交付 `214af4ca`（等 reviewer 複核，尚無裁決）。
- 相對 `bf658fae` 的產品檔改動只有 Edge 內容層：`opener_material.ts`、`opener_flow_payload.ts`、`opener_flow_handler.ts`、`opener_flow_prompt.ts`（＋三個對應測試檔）；lib／migration 未動。
- 正在處理到哪裡：G1／G2 本機補修與離線回歸已完成並交付（`214af4ca`），停在「等 ChatGPT 複核本輪 diff＋回放」與「新 prompt 需一輪新輸出確認（要 Eric 另授權預算）」。
- 本 session 沒有留下背景工作：可丟棄 Postgres 叢集已 `pg_ctl stop`；付費評估、Deno／Flutter 全套都已結束；本機系統 postgres（/var/lib/postgresql/16/main）與本案無關，不要碰。

commit 序列（新→舊）：`214af4ca` 複核包 §13 ｜ `2e5a470c` 離線回放工具 ｜ `47fb3eee` 內容補修 ｜ `ccbabe98` 複核包 §12 ｜ `a94621ad` 驗收腳本（PG 並行＋eval 預算守門）｜ `971e2878` 第五輪裁決紀錄 ｜ `bf658fae` 產品凍結。

## 2. 已完成、不得重開

- 工程複核：五輪（BLOCK×4→第五輪 **APPROVE_WITH_RISK on `bf658fae`**），Eric 已採納；殘留 P2-R5-IO 另案（`docs/reviews/ai-arbitration-queue.md` OPEN 頂端）。
- **真 PostgreSQL 並行 11/11 PASS 已驗收結案**（`tools/opener-pg-concurrency/`；環境與 log 見 §4）。不重跑。
- DB（migration `20260917120000_opener_two_stage_sessions.sql`、六支 RPC、租約 fencing）、Flutter 保存架構（`OpenerFlowController`／`OpenerResultCacheService` 的 owner／世代／建檔目標鏈）、B（選項授權＝用戶看見的 label）、C（舊單段控制組）、既有 P2：**不再重做**。
- 產品決策已採用：分析免費；首次成功可交付生成扣一般 3／既有客觀條件 0；一局共三組；伺服器快照／結果 24h 固定保存。不再列待拍板。
- 一次真模型評估（156 呼叫、$3.634、上限 $5）已跑完；**原 $5 是一次性授權，剩餘額度不自動延伸**。

## 3. 尚未關閉：內容守門 G1／G2（第五輪驗收裁決「真模型內容未過→BLOCK 部署」）

reviewer 檔：`/mnt/c/Users/eric1/Downloads/OPENER_ACCEPTANCE_bf658fae_REVIEW.md`（已收到，§6 根因範圍、§7 下一步）。reviewer 的 `offline_replay_cases.json` **沒有以檔案送到本機**；其 27 筆內容由 Eric 貼入對話，已整理成 `tools/opener-content-replay/labels.json`（來源欄位對應捕獲檔名）。

### G1 生成內容與可見推薦忠實性
- reviewer 反例：三年樂團經歷被套到對方（multi-hook A.2／A.3）；曾在寵物店打工被加「過敏」（family-fact B.2）；妹妹職業被加「常說／嫌」（filter-heavy A.1／A.2）；「提過想去沖繩、還沒訂」變「說好要訂」（she-said A.1）；貓「比我早睡」被反轉成晚睡（multi-hook B.1）；推薦不接原料：single-hook-dog A（原料只在 resonate，推薦仍問摸狗）、she-said A/B 六次推薦仍聊滑板、goal-not-consent A 三次想約卻整組沒邀約。
- 已做（`47fb3eee`，`opener_material.ts`／`opener_flow_payload.ts`／`opener_flow_handler.ts`／`opener_flow_prompt.ts`）：
  - 新硬檢查 `sender_fact_transposed`（用戶經歷片段出現在沒有「我」的句子）、`sender_fact_extended`（加上用戶沒說的健康／人生事件，小型詞表）、`relative_quote_fabricated`（用戶只給家人職業，卡片替家人加引語）、`certainty_upgraded`（用戶有 hedge，卡片出現 說好／答應／已經訂）、`profile_fact_reversed`（自介早睡↔晚睡、早起↔晚起）。
  - 原料採用：`cardAdoptsMaterial`（原料正向內容雙字片段是否出現在卡內；不看模型自稱 references；目標型「想約」要帶輕邀約）、`checkMaterialAdoption`（有有效原料時，方案可見卡至少一張接住；被硬檢查標記的卡不算；純否定／排除補充不要求）→ `material_unused` 標在 rankedPicks 第一張可見卡 → 走既有一次內容修正 → 修不好 502 `OPENER_CONTENT_CONFLICT` 不扣不計次。
  - 投影推薦：先從有證據的可見卡依 rankedPicks 取，沒有原料時才照模型排序；`traceStatus=matched` 要證據＋來源紀錄。handler 在硬檢查前就決定方案可見卡。
  - prompt：補「經歷只能用我說、家人不加引語、不加狀況、不升級確定度、不反轉自介事實、想約要帶輕邀約、排前面的卡要在內容上接住原料」；修正提示對映新碼。版本常數 `OPENER_FLOW_PROMPT_VERSION` 未動（它進生成輸入 hash）。
- 未做／做不到（如實）：程度擴張（「自己選路」→「完全不聽指揮」，P029）與一般性細節新增沒有確定性守門，只靠 prompt 與盲審；`materialReading` 沒有被拿來逐項核對（reviewer §6-1 提到）；**新 prompt 是否真的生成得更好尚未驗**。

### G2 硬檢查誤報／漏報
- reviewer 反例：「柴犬：我養妳不是讓妳摸的」被當自述（single-hook-dog skip.1）；「還有沒有推薦」被當被否定經歷（real-life-scene B.2／B.3）；「下班只想放空不聊工作吧」被當使用排除話題（family-fact A.3）；反過來，「不聊工作」時以美容師／獸醫助理職業開話題沒被抓（filter-heavy B.2／B.3、family-fact A.3 humor）。
- 已做（同一 commit）：冒號／引號後的代言不算自述（`stripAttributedSpeech`）；`extractNegatedFacts` 跳過正反問句（前一字＝動詞：有沒有）；排除話題在卡片內以「不聊／不提…」形式出現算遵守；`WORK_TOPIC_RE` 類排除延伸到本局線索標籤裡的職業（`professionFromCueLabel`）。沒有刪保護、沒有放寬門檻、沒有按 fixture 名加例外。
- 未做：無。

### 測試結果（本機）
- 離線回放 `tools/opener-content-replay/run.ts`：先紅 `ccbabe98` **51/97**（`red_replay.txt`）→ `214af4ca` **97/97 PASS**（exit 0）。
- analyze-chat Deno 全套：**1062 passed**，exit 0；opener 單元＋E2E（material／payload／handler／stage／option）65 passed。
- 新增測試：`opener_material_test.ts` 第五輪 9 題（每條規則一個最小案例＋一個不得誤判對照）、`opener_flow_handler_test.ts` A（第五輪）material_unused 修正成功／失敗路徑、`opener_flow_payload_test.ts` 推薦改依證據。
- handler E2E 幾個佔位補充（「第 i 版回答」「二」「三」）改成 scripted 輸出接得住的內容（採用檢查會擋純佔位）。
- Flutter 未重跑（本輪無 Flutter 改動；上一次全套 3880 綠在 `bf658fae`）。

### 下一個具體步驟
1. 等 ChatGPT 複核 `opener-two-stage-content-fix-214af4ca.zip`（G1／G2 diff＋回放）；有 BLOCK 就在 `214af4ca` 上先紅後修，只動內容層。
2. 新 prompt 需新輸出確認：固定小集合＝受影響 7 情境（multi-hook／family-fact／filter-heavy／she-said-vs-guess／single-hook-dog／goal-not-consent／real-life-scene）× A／B／略過 × 3、不含舊單段，dry-run 估 **70 次≈$1.64**。**要 Eric 明確新授權才跑**：
   `deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com tools/opener-two-stage-eval/run.ts --tag=confirm-r1 --only=multi-hook,family-fact,filter-heavy,she-said-vs-guess,single-hook-dog,goal-not-consent,real-life-scene --repeat=3 --legacy-repeat=0 --head=<HEAD> --budget-usd=<授權上限> --run --confirm-paid`
   跑完再把新 raw 餵回離線回放（fixtures 換成新捕獲）看旗標／採用率，並出 Free／paid 盲審包。
3. 之後才是：盲審評分、iPhone 真機、部署 preflight（pg_cron／正式權限）、圖片／wrongSurface／App 鎖卡；都不在本輪。

## 4. 接續要用的檔案與指令（本機確實存在）

- 產品／測試：`supabase/functions/analyze-chat/{opener_material.ts,opener_flow_payload.ts,opener_flow_handler.ts,opener_flow_prompt.ts,opener_material_test.ts,opener_flow_payload_test.ts,opener_flow_handler_test.ts}`
- 離線回放：`tools/opener-content-replay/{run.ts,labels.json,fixtures/*.json}`（27 個 fixtures＝捕獲的 snapshot＋contribution＋raw）
  指令：`deno run --allow-read --allow-write tools/opener-content-replay/run.ts --out=<dir>`（exit 0＝全 PASS）
- 真模型捕獲原始輸出（gitignored，仍在工作樹）：`tools/opener-two-stage-eval/out/acceptance-r1/`（156 個 `<scenario>.<arm>.<n>.json`＋`*.analyze.json`、`cost.json`、`meta.json`、`summary.md`、`blind_review_free.md`、`blind_review_paid.md`、`answer_key.json`）；dry-run：`out/acceptance-dry/`、`out/confirm-dry/`
- 評估工具：`tools/opener-two-stage-eval/run.ts`（`--budget-usd` 硬上限、`--head`、`--only`、`--legacy-repeat`）；fixtures：`tools/opener-two-stage-eval/fixtures.ts`
- 真 PG 並行：`tools/opener-pg-concurrency/{run.ts,bootstrap.sql,README.md}`（README 有自建可丟棄叢集的完整指令；socket 目錄要短）
- Deno：`deno test --allow-read --allow-env --allow-net supabase/functions/analyze-chat/`
- 文件：`docs/reviews/2026-09-17-opener-two-stage-review-packet.md`（§8–§13）、`docs/decisions.md` ADR #47、`docs/reviews/ai-arbitration-queue.md`（P2-R5-IO）
- 本 session 的原始 log／ZIP（scratchpad，session 專屬、可能被清；需要就先複製）：
  `/tmp/claude-1000/-home-eric1-work-VibeSync/bee65b1c-67de-4bcf-b3d5-9e1d91eb30ef/scratchpad/acceptance2/`（`red_replay.txt`、`replay-red/`、`replay-after/`、`r6_deno_analyze_chat_full.log|.exit`、`r6_deno_opener_unit_e2e.log|.exit`、`confirm_budget_dry_run.log`、`REPORT2.md`）、`.../scratchpad/acceptance/`（PG 並行與真模型驗收）
  交付 ZIP（同時在 `/mnt/c/Users/eric1/Downloads/`）：`opener-two-stage-content-fix-214af4ca.zip`、`opener-two-stage-acceptance-bf658fae.zip`、`opener-two-stage-review-{bf658fae,5e0b693d,070cfbdb}.zip`
- 已收到的 reviewer 附件：`/mnt/c/Users/eric1/Downloads/OPENER_ACCEPTANCE_bf658fae_REVIEW.md`。**沒有收到**：`offline_replay_cases.json`（內容由 Eric 貼入對話）、前幾輪的 `opener_round1_review_feedback.zip`／`probes/`。
- `/mnt/c/Users/eric1/Downloads/opener_prompt_revised.ts`（2026-08-23，舊檔）：與本案無關、未採用。
- 模型 API key：`~/.config/anthropic/key`（付費呼叫前一律要 Eric 明確授權）。

## 5. 夥伴的 `claude/opener-architecture-optimization-661f51` 報告

- 只是另一分支的**參考**，不取代 `opener-two-stage`：不合併整套程式、不覆蓋 migration／controller、不重置驗收進度。
- 交接當下該分支**不在本機也不在 origin**（`git branch -a`、`git ls-remote --heads origin` 均無）；若之後拿到報告或分支，只讀取比對，取用要先在 `214af4ca` 之上先紅後修並走同一套回放／測試。
