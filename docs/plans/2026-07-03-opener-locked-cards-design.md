# Opener free 鎖卡補渲染設計（Batch 4 #3，2026-07-03）

> Eric 拍板：free 用戶要看到 4 張「升級解鎖」鎖卡（點擊導 paywall）＋修 free 標題「・5 種風格」hardcode 不符。
> 選型定案：**client 補渲染**（vs server 改回骨架）——server/Edge 零改動。

## 背景

- Server `filterOpenerPayloadForAllowedFeatures`（`opener_payload.ts`）把 free 不允許的 4 型整個從 payload 剝掉，free fresh 生成只有 `extend` 1 張卡。
- Client 鎖卡 UI 早已存在（`_buildOpenerCard` 的 `isLocked` 分支＋`_buildLockedContent`＋升級按鈕 `_showPaywallAndRefresh`），但卡片列表以 `result.openers.entries` 驅動，缺型不渲染 → 鎖卡分支只在降級回看舊付費 draft 的罕見路徑觸發。
- 標題「・5 種風格」hardcode（`opening_rescue_screen.dart`），free 畫面 1 張卡時與事實不符。

## 選型理由（client 補渲染 > server 骨架）

- server 骨架要動 analyze-chat 高風險區＋契約變更＋舊版 client 相容驗證＋Edge deploy；鎖定文字過濾一有 bug 就是洩漏面。
- client 已有完整鎖卡 UI 與 canonical 5 型清單；tier 規則（free=extend only）hardcode 本來就在 `isLocked` 邏輯裡，非新增債。
- tier 模型穩定（free=extend、付費全開），server 骨架的彈性目前用不到（YAGNI）。

## 設計

卡片列表改為 **canonical 5 型驅動**（`_openerTypeLabels` 順序，`extend` 恆第一）：

1. payload 有該型 → 既有邏輯（含降級回看 inline gating），零行為變更。
2. payload 缺該型且 free → 補渲染鎖卡（`isLocked: true`、content 空字串；鎖卡分支不 render content）。點「升級解鎖」→ 既有 `_showPaywallAndRefresh()`。
3. payload 缺該型且付費 → 跳過（sanitize 剝掉的型絕不對付費用戶顯示鎖卡）。

標題「・5 種風格」→ 動態 `・N 種風格`，N＝實際渲染卡數（free 恆 5；付費 sanitize 缺型時顯示真實數字）。

## 不變量

- server/Edge、draft 儲存格式零改動；鎖卡為渲染時合成，free draft 回看自動一致。
- AI 推薦 badge 維持 `!isLocked` guard；推薦理由區塊不變。
- 付費用戶任何情境不得看到「升級解鎖」。

## 測試

- free fresh 生成 → 5 卡、4 鎖、順序 extend 第一；鎖卡點擊觸發 paywall；badge 只在解鎖卡。
- 付費缺型 → 不補鎖卡、標題數字＝實際卡數。
- 降級回看付費 draft 路徑零回歸。

## 風險

opener＋paywall 導流＝高風險區，完成後 Codex 雙審；行為變更需新 TF build 才能 dogfood。
