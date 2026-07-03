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
- [ ] R1-4【建議，Eric 拍板】onboarding 加一頁輕量「AI 與隱私」揭露（點名 Anthropic/DeepSeek＋資料外送說明）。per-feature 同意閘理論上已滿足「使用前同意」，此項是保險

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

- [ ] F1-1【P2，Eric 拍板】Free 用戶 full 分析會被 `selectModel`（`analyze-chat/index.ts:4315-4322`）升到 Sonnet（首次分析必中），違反 pricing「Free=Haiku」＝成本/毛利縫。選項：Free clamp Haiku（圖片除外）or 接受為轉換投資並更新 pricing-final.md
- [ ] F1-2【P3】「我說」量測 Essential-only 但 client 無前置 gate，非 Essential 直接吃 403 → 補鎖卡＋paywall 導引（比照草稿潤飾 `analysis_screen.dart:3847-3849`）
- [ ] F1-3【P3，doc】pricing-final.md 功能對照表補齊已上線 gating（草稿潤飾/我說=Essential、翻牌 1/3/5、opener 僅 extend、練習室續玩規則）
- [ ] 已記錄不修：練習室 roundIndex 弱閘（`quota_decision.ts:70-72` 自承，需 per-thread ledger，非上架 blocker）；額度數字五處重複定義（值一致，漂移風險另案）

## Batch F3 — opener 體驗對齊（1–2 session）✅ 高風險：prompt → Codex 雙審

- [ ] F3-1 opener 完全不吃「關於我/對象設定」（`opener_service.dart:306-338` 只送 profileInfo＋images）→ 注入 effectiveStyleContext（複用 `effective_style_prompt_builder.dart`），prompt 對應吃進去
- [ ] F3-2 opener 等待只有轉圈（`opening_rescue_screen.dart:727-745`）→ 低配版先做：staged 本地進度文案（比照 analyze prelude）；真 streaming 另開 design session（Edge＋client 改動大，非上架 blocker）

## Batch F5 — UI/UX 文案總審（1 session，可與 F4 併）

- [ ] 分頁 fan-out 文案審（首頁/分析/opener/coach/練習室/paywall/設定），輸出「改字清單」給 Eric 挑
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

- [ ] V-1 黑箱驗證：Edge 層測試＋TestFlight regression checklist（`docs/testflight-regression-checklist.md`）
- [ ] V-2 Codex 對抗式審查：餵拒審原文＋我方修復證據，要求 Codex 扮演 App Reviewer 逐條攻擊四個 guideline，來回直到雙方共識「無殘餘破口」（無輪數上限）
- [ ] V-3 出新 TF build，Eric 全動線 dogfood（含既欠的：練習室導覽、限流 client 行為、圖鑑動線）
- [ ] V-4 更新 `docs/app-review-submission-package.md`，判定 Submit GO/HOLD

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
