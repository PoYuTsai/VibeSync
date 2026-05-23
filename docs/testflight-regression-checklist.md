# TestFlight 回歸與簽核清單

最後更新：2026-05-23
適用範圍：送審前所有 TestFlight build

目的：
- 每次新的 TestFlight build 出來後，用同一份清單驗證核心流程
- 避免只看 CI 綠燈就誤判可發版

## 0.1 Phase 13 送審候選版最小 smoke

這段是 2026-05-23 送審候選 build 的最小必跑路徑；下面 A-J 仍保留作完整回歸清單。

### Repo 端已完成

- [x] HEAD：`50dda0c`
- [x] `flutter analyze` passed
- [x] Targeted tests passed：analysis hint、analysis screen、analysis service、opener cache、coach follow-up provider、paywall、settings、partner delete/cascade、partner-scoped new conversation，共 103 tests

### 真機 TestFlight 必跑

- [ ] Reviewer path：登入 reviewer account → 建立對象/對話 → 手動貼 2-5 則訊息 → 分析 → 問 Coach → Settings 查看 subscription/quota → Restore Purchases → Privacy / Terms / Support → 找到 Delete Account 入口。
- [ ] OCR path：清楚聊天截圖 → OCR confirm → 修改我說/她說 → 匯入目前對話 → 分析 → 長按 bubble 編輯。
- [ ] Analysis coach mark：同一對象只跳一次；換新對象會再跳一次；OCR 匯入後的下方區塊不應遮住必要操作。
- [ ] Subscription path：Paywall 顯示 4 個產品；Starter / Essential package 對應正確；Restore Purchases、管理訂閱、升級、降級排程都能跑到可理解狀態。
- [ ] Privacy/legal path：Privacy、Terms、Support URL 都可從 app 內打開；support email 可接住帳號、付款、OCR 失敗回報。
- [ ] Recent regression path：純 OCR 不扣額度、完整分析扣額度失敗有可理解 fallback、opener 草稿不跨對象污染、partner delete 有 conversation-count guard。

### Phase 13 No-Go

- reviewer 無法登入
- monthly / quarterly 或 Starter / Essential package 對錯
- OCR / analyze / Coach 主路徑 crash
- raw JSON、raw exception、internal schema error 外漏給使用者
- Privacy / Terms / Support dead link
- 未完成 IAP 或 booster 入口在送審 build 可見
- logout / delete account 後有本地 session 或資料污染

## 0. 開始前

- [ ] 安裝最新 TestFlight build
- [ ] 準備 2 個帳號：
  - 付費或可升級帳號
  - 一般帳號或免費帳號
- [ ] 準備至少 4 類截圖：
  - 正常雙人聊天
  - LINE 引用回覆
  - 長繁中截圖
  - 明顯錯圖 / 社群圖

## A. 登入 / 註冊

- [ ] Apple Sign In 成功
- [ ] Google Sign In 成功
- [ ] Email sign up + verify 成功
- [ ] Resend verification 成功
- [ ] Forgot password warm start 成功
- [ ] Forgot password cold start 成功
- [ ] 登出後重新登入，不殘留前一個 session

## B. 訂閱 / Paywall

- [ ] Paywall 文案正常，沒有 mojibake
- [ ] 月繳 / 季繳標示正確，當前方案不會把同 tier 其他週期誤判成「目前方案」
- [ ] Privacy / Terms 可正常開啟
- [ ] Starter 購買成功
- [ ] Essential 購買成功
- [ ] `恢復購買` 成功
- [ ] `管理訂閱` 可正常跳 App Store 管理頁
- [ ] `Starter -> Essential` 升級後立即刷新成高 tier 權限
- [ ] `Essential -> Starter` 會顯示已排程降級，當期額度仍維持 Essential
- [ ] 去 App Store 取消降級後，回 App 點 `我已取消降級，更新狀態` 會清掉 pending 狀態
- [ ] 升級後回分析頁，不會停留在舊 free-tier 結果

## C. OCR 識別

### C1 正常案例
- [ ] 單張正常雙人聊天截圖成功
- [ ] 2-3 張連續截圖成功
- [ ] 長繁中截圖成功

### C2 Speaker / 結構
- [ ] 左側基本上是她，右側基本上是我
- [ ] 圖片泡泡 speaker 不會亂翻
- [ ] 多張截圖有重疊時，不會重複匯入同一則

### C3 LINE 引用回覆
- [ ] 她引用我後回覆
- [ ] 我引用她後回覆
- [ ] 我引用我自己
- [ ] 引用卡不會被拆成新訊息
- [ ] 若引用內容可讀，會保留為 `quotedReplyPreview`

### C4 錯圖 / 混圖
- [ ] 社群圖被拒絕
- [ ] 群組圖被拒絕
- [ ] 不同人的截圖混入同一批時，會警告並偏向另存新對話
- [ ] 非聊天圖不會默默 append 到目前對話

## D. 匯入 / 對話邏輯

- [ ] 可選 `加入目前對話`
- [ ] 可選 `另存成新對話`
- [ ] OCR dialog 取消後，結果仍可稍後再匯入
- [ ] 新建對話時，辨識到的名字會正確取代 placeholder 標題
- [ ] 既有對話追加截圖後，順序與上下文合理

## E. 分析

- [ ] 一般分析成功
- [ ] `我有想說的，幫我優化` 成功
- [ ] `對話延續 / 我說` 成功
- [ ] 分析後重開同一段對話，舊分析仍可看到
- [ ] 補新訊息後，能再重新分析

## F. 額度 / 計費

- [ ] 純 OCR 識別顯示 `本次純識別，不扣額度`
- [ ] 完整分析前預覽顯示按訊息數扣點
- [ ] 完整分析後量測卡可看出這次有沒有真的扣點
- [ ] 測試白名單帳號顯示 `未扣額度（原本會扣 X 則）`
- [ ] 一般帳號完整分析後，remaining quota 正確更新

## G. Telemetry / Guardrails

至少手動記錄 3 組：
- [ ] 正常單圖
- [ ] LINE 引用圖
- [ ] 長圖或 2-3 張連續截圖

每組至少記：
- classification
- side confidence
- uncertain side count
- quoted preview attach/remove count
- overlap removed count
- payload
- round-trip
- AI latency
- 是否扣額度 / 扣幾則

## H. 可簽核條件

- [ ] A 全過
- [ ] B 全過
- [ ] C1 / C2 全過
- [ ] C3 至少過 2 種
- [ ] D 全過
- [ ] E 全過
- [ ] F 全過
- [ ] G 至少記滿 3 組量測

如果 C3 / C4 失敗，記錄以下 5 件再回報：
1. 原始截圖情境
2. 哪一則 speaker 判錯
3. 是否誤拆引用卡 / 誤放行錯圖
4. warning / confidence 文案是什麼
5. telemetry 數字
## I. Partner Entity A2 soak

- [ ] Home 第一個 tab 顯示 Partner list，而不是舊 Conversation list。
- [ ] 從 Home FAB 建立新對象後，進入該對象 detail；按返回應回到 Partner list，不應回到新增對象表單。
- [ ] 從 Partner detail 點「新增對話」→ 手動輸入，建立後該 conversation 的 `partnerId` 應掛在當前對象，回到 detail 後會出現在該對象的對話列表。
- [ ] 從 Partner detail 點「新增對話」→ 截圖開始，建立的新 conversation 也應掛在當前對象。
- [ ] Partner detail radar 在沒有分析資料時顯示 fallback，不應 crash；有分析資料時顯示 5 維 radar。
- [ ] Partner detail 的 merge / edit / delete 選單項目前為 disabled，不可誤觸。

## J. Partner Entity A2 ship (Phase 4 — 2026-04-28)

對應 ADR-15 v2 ship 段落 D-P4-1 ~ D-P4-5；含 PartnerListCard 5 件套、delete two-mode、per-account dedupe banner、merge picker preselect、PR-B 回歸驗。

### J1 Partner delete（D-P4-1 cascade=block-when-non-empty）
- [ ] Partner 對話數 = 0 → 點刪除 icon 跳 confirm dialog（destructive 樣式）→ 確認後 Partner 從 list 消失，跳成功 SnackBar。
- [ ] Partner 對話數 ≥ 1（任何 round 數，含 0-round 對話）→ 點刪除 icon 跳 informational dialog（無 destructive action，僅關閉），Partner 仍存在。
- [ ] Partner 對話數 ≥ 1 且該對話 totalRounds = 0 → 仍走 informational dialog（驗 conversationCount guard，不是 aggregate.totalRounds 判斷）。

### J2 Same-name dedupe banner（D-P4-5 per-account dismissed key）
- [ ] 兩個或以上 Partner 同名 → Partner list 頂部出現 dedupe banner（avatar + 名稱 + CTA）。
- [ ] 點 banner CTA「立即合併」→ 跳 merge picker，較舊 partner 預選為 target，bottom CTA 可見、不會 auto-open destructive dialog。
- [ ] 點 banner CTA「以後再說」→ banner 立即隱藏；殺 app 重開仍不出現（per-uid SharedPreferences 永久關）。
- [ ] 切到另一個帳戶 → 該帳戶若也有同名 Partner，banner 仍會出現（A 帳戶「以後再說」不外洩到 B 帳戶）。

### J3 Merge picker preselect（D-P4-2 newer=source / older=target）
- [ ] Banner 帶 `?target=` → 點其他列改選擇 → preselect 切到新列，不會 auto-open destructive confirm。
- [ ] Merge picker 直接從 Partner detail menu 進入（無 `?target=`）→ 維持 PR-B 原行為（user 自選 target，不預選）。

### J4 PartnerListCard 視覺 5 件套（D-P4-3 / D-P4-4）
- [ ] PartnerListCard 5 區塊全顯示：avatar、名稱+最後更新時間、熱度 indicator、興趣/特質 interleave 預覽 tag、刪除 icon。
- [ ] 熱度 = null 時顯示「🌡️ 待分析」灰字 fallback（D-P4-4），不顯示 0 或空白。
- [ ] Partner 同時有 interests 和 traits → 預覽 tag 為 interleave `[i0, t0, i1, t1, i2]` 取 3，至少保留 1 個 trait（D-P4-3，traits 不被餓死）。

### J5 文案掃尾（Task 15 copy sweep）
- [ ] Home FAB tooltip / popup 文案 = 「+ 新增對象」（對象 vocabulary）；Partner detail 內「+ 新增對話」維持原樣（對話 vocabulary, partner-scoped 語意正確）。
