# 上架前總體審查計畫（App Review Readiness）

> 建立：2026-07-03。對照 2026-05-27 Apple reject（3.1.2(c)×2、2.1(b)、5.1.1(i)/5.1.2(i)）。
> 本檔是跨 session 的執行主控台：每個 batch 一個 session，做完勾掉、commit 本檔。
> 工作流：高風險修 = TDD + Codex 雙審；全部 batch 完成後跑「對抗式總驗證」（Codex 攻擊四個 guideline 直到雙方共識）。

## 拒審點現況判定（2026-07-03 四路唯讀掃描結論）

| 拒審點 | 現況 | 殘餘工作 |
|---|---|---|
| 3.1.2(c) 帳單金額不醒目 | **已大致修復**：priceString 28px/22px 粗體為最大價格元素，無 trial/折算價搶版面 | 硬編碼「省 27%/36%」徽章未與真實 store 價連動（R2-1）；EULA 屬性待確認（R2-2） |
| 3.1.2(c) 必要資訊四件套 | **app 內齊全**（名稱/長度/價格/可點連結） | App Store metadata 側：描述加 EULA 連結、Privacy Policy 欄位（H-2） |
| 2.1(b) 購買鈕無限轉圈 | **code 已修**：45s 購買 timeout、20s 方案刷新 timeout、失敗變「重新載入」可點重試 | 必須 iPad sandbox 實測（拒審機就是 iPad Air 11 M3）＋ Paid Apps Agreement 確認（H-1） |
| 5.1.1(i)/5.1.2(i) AI 同意 | **同意閘已建**（v2, 20260527）：五大 AI 功能＋OCR＋草稿潤飾全 gate，內容滿足四要件 | **P1 破口＝同意存 SharedPreferences 裝置級，登出/刪帳/換帳號不清**（R1-1）；onboarding 無揭露頁（R1-4，建議） |

## Batch R1 — 合規 P0（code，1 session）✅ 高風險：auth/consent → Codex 雙審
> **DONE 2026-07-03**：range `2ceb1beb..3235dc57`，Codex R1 抓 1 P2（ensure() 身份競態）→ 修＝scopedKey 單次解析＋寫前驗證 → R2 APPROVED 四攻擊面全 SAFE。R1-4 待 Eric 拍板。

- [x] R1-1【P1】AI 同意帳號級化：**選型＝consent key 內部綁 userId**（effective key＝`<key>::<userId>`，未登入 fallback 裝置級；換帳號天然隔離、同帳號重登不重問、裝置級舊同意不跨帳號沿用）。`2ceb1beb`，TDD 5 新測＋回歸 190/190 綠
- [x] R1-2【P1】「複製訂閱診斷」兩入口 → `SubscriptionDiagnosticsGate`（`!kIsWeb && kDebugMode`）＋測試 seam，settings tile＋paywall 頁尾都走 gate。`1e93512f`
- [x] R1-3【P3】forceSyncTier debugPrint 去 user.id。`9ab02bf9`
- [x] R1-4【Eric 拍板 2026-07-03＝**做輕量版**】onboarding 第 4 頁靜態「AI 與隱私」揭露（點名 Anthropic Claude／練習室 DeepSeek＋後端外送路徑＋同意閘說明）。TDD 2 新測；順手修 OnboardingPage 小螢幕 overflow（scroll-safe 容器）。client 行為需 V-3 新 TF build 才吃得到。低風險靜態 UI（非高風險區）未送 Codex

## Batch R2 — paywall 殘餘（0.5 session）✅ 高風險：paywall → Codex 雙審
> **DONE 2026-07-03**：range `32be3ca3..f5e08a79`（與 F2 併一刀，Codex 三輪）。

- [x] R2-1 「省 X%」徽章改 store 實價動態計算（`quarterlySavingsLabel`，floor 絕不高報、抓不到價/幣別不符不顯示）。`5b10169e`，TDD 9 新測
- [x] R2-2 `https://vibesyncai.app/terms` WebFetch 查核＝六項 EULA 要素齊全（授權/訂閱付款/IP/免責/終止/禁止行為），app 內不需補 Apple Standard EULA；metadata 側 EULA 連結歸 H-2

## Batch F2 — 夥伴報告修復（1 session）✅ 高風險：auth＋Edge schema → Codex 雙審
> **DONE 2026-07-03（1 殘餘 WAITING_ON_ERIC）**：F2-1 經 Codex 三輪升級成「清理未完成擋在重試 dialog」；R3 抓批前既有 spinner 無 PopScope＝兩輪上限停手，見 queue 2026-07-03 item。

- [x] F2-1【auth】刪帳成功/本機清理失敗分流＝遠端失敗才報錯；清理未完成**擋在非可關閉重試 dialog**（絕不放行 login 見前用戶資料），重試在 dialog 內執行成功才 pop。`fc061337`＋`0ed5855e`＋`f5e08a79`
- [x] F2-2【follow-up】429 文案改用 server message（月/日 server 已分流），fallback 中性文案。`5d2216ca`
- [x] F2-3【follow-up】partnerHint.name Edge `.max(50)`＋client 同值 clamp 防 400。`8afcfa6f`
- [x] F2-4【follow-up】上游錯誤改通用碼 `generation_failed`；telemetry 依 privacy C6 只留 errorClass。`a20ebfaa`
- [x] F2-5 初始清理 spinner 包 `PopScope(canPop:false)`（Codex R3 P1，Eric 放行）。`3f9a2ebe`，Codex R4 APPROVED

## Batch F1 — tier 行為對齊（1 session）
> **DONE 2026-07-03**：F1-1 Eric 拍板＝接受為轉換投資（doc-only）；F1-2 前提證偽不修；F1-3 對照表補齊。零 code 變更。

- [x] F1-1【P2，Eric 拍板 2026-07-03＝**接受為轉換投資、不 clamp**】Free full 分析升 Sonnet（首次/長對話/冷淡/複雜情緒）＝品質優先，成本被額度＋per-user 限流雙層封頂；pricing-final.md 已註記（footnote ¹＋Free 成本行更新）
- [x] F1-2【證偽不修，2026-07-03】原主張「client 無前置 gate 直接吃 403」**前提不成立**：全 lib 無任何入口送 `analyzeMode: "my_message"`（唯一送出點 `analysis_service.dart:1459` 三個 caller 都不傳），`MyMessageAnalysis` 無 UI 消費——「我說」量測是 server 休眠面（`index.ts:5710` 403 閘為未來/舊 client 防禦），現行用戶打不到。若日後做「我說」入口，開工時才補 Essential 鎖卡（比照草稿潤飾 `analysis_screen.dart:3846`）
- [x] F1-3【P3，doc】pricing-final.md 功能對照表補齊：opener Free 僅 extend（`index.ts:527`）、草稿潤飾=Essential 雙閘、翻牌 1/3/5＋加購扣 5 則（Free 導升級，`draw_decision.ts`）、Free 續玩僅第 1 輪（`quota_decision.ts:79`）。「我說」不入表（無用戶可見入口）
- [ ] 已記錄不修：練習室 roundIndex 弱閘（`quota_decision.ts:70-72` 自承，需 per-thread ledger，非上架 blocker）；額度數字五處重複定義（值一致，漂移風險另案）

## Batch F3 — opener 體驗對齊（1–2 session）✅ 高風險：prompt → Codex 雙審

- [x] F3-1 opener 完全不吃「關於我/對象設定」→ SHIPPED：`buildForOpener` 專用切片（防用戶興趣被捏成共同點）＋`openerStyleContextProvider`（partnerId 可空、Spec 3 flag 守門）＋body/`fingerprintFor`/server input hash 三處對齊（hash 缺席時保 2 元素舊形狀）＋opener branch sanitize 在 gate 前＋userContent 注入在對方資訊分流後＋OPENER_PROMPT 消費段；順手修 opener_prompt_test 扣費錨點 stale（HEAD 既有，`p_messages: effectiveOpenerCost` 已隨 chargeOpenerQuota 重構搬家）
- [x] F3-2 opener 等待只有轉圈 → SHIPPED（`bb904890`＋`3921aa56`，Codex R2 APPROVED）：`OpenerGenerationProgress` staged 本地進度文案（截圖/手動兩套、每 3 秒進一段、到底停住並 cancel timer 守 pumpAndSettle 收斂）；文案雙層凍結在生成送出的 input（widget mount 快照＋screen `_generationProgressPhrases`，Codex R1 P2＝生成中切 tab/移除截圖不得漂移）；純 client，需新 TF build（V-3）；真 streaming 另開 design session（非上架 blocker）

## Batch F5 — UI/UX 文案總審（1 session，可與 F4 併）

- [x] 分頁 fan-out 文案審完成（2026-07-03，7 路唯讀掃描）→ 改字清單＝`docs/reviews/2026-07-03-f5-copy-review.md`（A 級 8 條 App Review 風險／B 級 5 條計費語意／C 級術語標點批改）；**WAITING_ON_ERIC 挑字**，挑完一顆純文案 commit 批次收
- [ ] 資訊架構觀察（非 blocker）：練習室入口在「學習」tab、opener 在新增對話 sheet，首頁無直接入口＝發現性弱

## Batch F4 — 高階技術文件 → prompt（1 session，建議上架後）

- [ ] 先 `sudo apt-get install -y poppler-utils` 再讀桌面 2.pdf
- [ ] 蒸餾方向：評估(qualification)/敘事(narrative)/收尾(closing) → analyze-chat 回覆策略軸、coach 1:1 知識庫、練習室評分階段
- [ ] 鐵則：必須過「尊重/同意/界線」濾網再入 prompt；避免可被 App Review 讀成 manipulation 的字眼；prompt 全屬高風險區 → 雙審＋黑箱輸出比對

## Batch H — 人工／App Store Connect（Eric，非 code）

- [ ] H-1 Paid Apps Agreement 生效確認；4 IAP 掛回新版本送審、同 subscription group
- [ ] H-2 metadata：App 描述加 EULA 連結；Privacy Policy 欄位連結；Support URL
- [ ] H-3 Privacy Label 更新：**必須揭露分享給第三方 AI（Anthropic/DeepSeek）的資料類型**（上輪拒審後這是重點）
- [ ] H-4 App Review Notes 重寫：AI 資料流＋同意閘說明、測試帳號、IAP 測試步驟；**Apple 明說要附訂閱流程錄屏**（3.1.2(c) 回覆要求）
- [ ] H-5 iPad 真機/模擬器：paywall 佈局＋sandbox 訂閱矩陣（購買/restore/升降級）——拒審機就是 iPad
- [ ] H-6 網站 privacy/terms/support 頁面可開；vibesyncaiapp@gmail.com 可收信；年齡分級（dating/成人議題 → 17+）核對

## Batch V — 對抗式總驗證（1–2 session，全部完成後）

- [x] V-1 黑箱驗證：Edge 層測試**已過＝deno 全套 1176 passed / 0 failed（2026-07-04）**；TF 迴歸由 Eric 在 V-3 build 以白話 dogfood 清單跑過（2026-07-04）＝完成（正式 `docs/testflight-regression-checklist.md` 全表未逐項勾，風險已由 dogfood＋V-2 對抗審覆蓋）
- [x] V-2 **DONE 2026-07-04，Codex R4 APPROVED（四 guideline 全過）**：R1–R3 各抓一條 2.1(b) 同族破口並修——R1 P1＝paywall 購買/restore 後 refresh 無界 await（`f01d4474`，restorePurchases 45s＋post-success refresh 20s best-effort、成功呈現不依賴 refresh）；R2 P2＝取消降級同步 paywall/settings 兩處（`870069d3`，20s）；R3 P2＝settings 恢復購買 blocking dialog（`8697832b`，45s）；自掃同族收尾＝analysis 頁三處（`9d71673b`，20s，ensure 逾時放行由 server 把關）。文件破口＝privacy-policy/送審包漏 DeepSeek（`5daabb00` 補齊）。「不掛 blocking UI 的 await 不修」判斷 Codex 複核成立。全程 TDD：7 新 hang widget 測，paywall/settings/analysis 測試綠
- [x] V-3 **DONE 2026-07-04**：新 TF build 出爐，Eric 全動線 dogfood 通過（含既欠的：練習室導覽、限流 client 行為、圖鑑動線、opener staged 等待文案、onboarding AI 揭露頁）
- [x] V-4 **DONE 2026-07-04**：`docs/app-review-submission-package.md` 全文對齊（§0 拒審點修復對照、§1 Review Notes 加拒審回應段、§2F opener/練習室/限流測試路徑、§6.3 新 gate）；判定＝**Repo GO / Submit HOLD**，HOLD 僅剩 Eric 側 H batch（見送審包 §6.3 清單，缺一不送）
- Eric 側人工前置（Codex R4 收尾清單，對應 H batch）：H-1 Paid Apps Agreement＋4 IAP 掛回；H-2 metadata EULA/Privacy/Support；H-3 Privacy Label 實填**含 Anthropic＋DeepSeek**；H-4 Review Notes＋訂閱錄屏；H-5 iPad sandbox 矩陣；**live `vibesyncai.app/privacy` 重新部署含 DeepSeek**（repo 版已更新，live 站另部署）

## Session 估算

| 順序 | Batch | Session 數 |
|---|---|---|
| 1 | R1 合規 P0 | 1 |
| 2 | R2＋F2（可併一刀） | 1 |
| 3 | F1 tier 對齊 | 1 |
| 4 | F3 opener | 1–2 |
| 5 | F5 文案審（可選） | 1 |
| 6 | V 對抗式總驗證＋TF build | 1–2 |
| — | F4 高階技術 prompt（建議上架後） | 1 |
| — | H 人工項（Eric 平行進行） | — |

**送審必要路徑 ≈ 6–8 個 CC session**＋Eric 的 H batch 人工作業；含 F4/F5 全做 ≈ 8–10。
