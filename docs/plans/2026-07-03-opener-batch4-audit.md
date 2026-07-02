# Batch 4：opener 產品邏輯全鏈路盤點（2026-07-03）

> 方法：4 路平行掃描（契約/計費/儲存/導流）→ 8 條 load-bearing findings 逐條讀碼複核。
> 結論：**本批無 P0/P1**。掃描層報的 3 條 P1 全數複核證偽。
> 狀態：WAITING_ON_ERIC 拍板哪些修。基準 HEAD `d9c90b80`。

## 確認成立（已複核，全 P3）

1. **opener draft 生命週期孤兒**（併一案修）：
   - partner 刪除 cascade（`partner_repository.dart:161-172`）清 style/quality/followUp/outcome 但不清 opener drafts；`clearDrafts`（`opener_result_cache_service.dart:235`）零呼叫者。
   - 同源：`mergeInto`（`partner_repository.dart:128-133`）也不清/不搬被併 partner 的 drafts。
   - 下游：`_seedFromLatestOpener`（`new_conversation_screen.dart:118-147`）不驗 partner 存在（僅 stale-stack 時序可達，seed 已套 visibleForAccess 無 tier 洩漏）。
   - 修法：cascade＋merge 補清（或搬移）drafts，即同時封掉 seed 孤兒路徑。
2. **opener 無 idempotency，傳輸層重試雙扣窗口**：RPC commit 後回應在 PostgREST→Edge 或 Edge→client 網路丟失 → client 見錯重試 → 再扣 3 額度。handler 內 commit 後無可失敗步驟（`index.ts:5226-5253`），窗口窄但真實。修法：request-id idempotency key 或扣費追蹤表。
3. **free 標題「・5 種風格」hardcode 與畫面不符**（`opening_rescue_screen.dart:958-963`）：free payload 只含 extend（server 過濾 `opener_payload.ts:99-105`），free 新生成只有 1 張卡但標題寫 5 種；連帶 **free 永遠看不到 4 張「升級解鎖」鎖卡**（鎖卡 UI 只在降級回看舊付費 draft 的罕見路徑出現）。修法含產品決策：free 要不要看到鎖卡 upsell（server 改回骨架或 client 補渲染鎖卡）。
4. **`markDraftContinued` 用過濾後結果覆寫 draft**（`opening_rescue_screen.dart:266-272`＋`opener_result_cache_service.dart:214-227`）：free/降級用戶「繼續」付費期 draft 時，5 風格結果被永久降級成 extend-only，再升級也回不來。修法：覆寫時存 raw result 或不覆寫 result 欄位。

## 未複核、低嚴重度或需產品拍板（挑了才修）

5. repair 路徑欄位可缺（profileAnalysis/pioneerPlan）→ 卡片靜默消失，client 有 null 防禦不 crash（`index.ts:406`、`opener_payload.ts:62-85`）。
6. 改 bio 後「最近開場草稿」仍可回看舊輸入的結果（無 input hash）——可能是「草稿=歷史記錄」設計意圖，需拍板是 bug 還是 feature。
7. draft payload 無版本欄位，prompt 大改版後舊 draft 重播舊契約形狀（`opener_latest_result_v1` 終身不變）。
8. 手動輸入表單不持久化，未生成就離開全丟——產品決策：要不要 debounce 存輸入。
9. 雜項 hygiene：saveDraft 異常吞掉（catch (_)）、`shouldChargeQuota` client 不消費（冗餘信號）、server image validation error 可能英文（client 已兜底）、client 防雙擊 setState 窗口（server 原子扣費已擋 TOCTOU）。

## 複核證偽（不列，別再開案）

- **A1** client 讀巢狀 `recommendation` 解析不到 → 假：wire format 含巢狀欄位，badge 正常顯示；client 不讀 server 頂層 `recommendedPick`（6114d0fb 對 client 是 no-op、純契約衛生）。
- **A4** free fallback 後推薦理由語意錯配 → 假：client 兩道閘（`opener_service.dart:147`＋`opening_rescue_screen.dart:1000-1001`）擋掉錯配顯示；付費 tier 5 型全開無 subset。
- **A5/B1** `usage?['cost'] ?? 3` 誤扣本地額度 → 假：500/502 時 client 直接 throw 不建 OpenerResult；client 無任何本地額度遞減邏輯（`costUsed` 零消費點，餘量走 server 刷新）。
- **C8** 降級回看付費 draft 洩漏全風格 → 假：顯示層 inline gating（`isLocked` → `_buildLockedContent` 不 render content、無複製鈕）。
- **D1** 429 升級取消 error 永久卡死 → 假：清除路徑至少四條（輸入變更/tab 切換/圖片增刪/重進頁面），且生成按鈕不被 error 態擋、可直接重試。

## 掃過無 finding（陰性證據）

Free 首用不鎖、no-charge 路徑 cost:0、repair 不重複扣、increment_usage 原子性（Batch C）、429/500 分類、tier 限額、狀態機各態轉移、錯誤文案中文兜底、導流 CTA partnerId 綁定、sanitize 哨兵、openerType 值域。
