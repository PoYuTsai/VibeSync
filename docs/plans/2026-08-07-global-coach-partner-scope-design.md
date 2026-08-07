# 問教練 @對象（partner scope 切換）設計

日期：2026-08-07｜狀態：Eric 已核可｜來源：Bruce dogfood feedback

## 需求

首頁「問教練」目前只有 general 串，教練不知道你在問誰。要能「可 tag 可不 tag」：
tag 某個對象＝帶該對象脈絡問；不 tag＝general 問題（現狀）。

## 拍板：方案 A——頂部對象 chips ＝ 切換聊天串

`GlobalCoachScreen` 在招呼語與引導問句之間加一排「問誰」chips：
`[💬 一般] [Alice] [Mia] …`（橫向可捲動）。

- 預設「一般」＝現在的 `CoachScope.global()`，行為零變。
- 點對象 → `CoachSurface` 換 `CoachScope.partner(id)`：跟對象頁「跟進」**共用
  同一條聊天串**（同一份歷史與脈絡，教練不失憶）。chips 高亮標示目前在誰的檔案。
- 切換保留輸入框草稿（不給 CoachSurface 加 key，State 不重建）。
- 沒有對象卡 → chips 整排不渲染，畫面同現狀。
- 引導問句照舊：只預填、不送出，兩種 scope 都適用。
- 首頁卡片不動；server 零改動（partner scope wire 契約 Phase C 已支援）。

**否決**：inline @（輸入框內選單、單則換脈絡、global 串混雜多對象歷史——server
新語意＋歷史錯亂，工程數倍）；本頁顯示對象熱度摘要（對象頁已有）。

## 技術

- `GlobalCoachScreen` → ConsumerStatefulWidget；狀態 `CoachScope _scope`。
- chips watch `partnerListProvider`；controller/history/progress 都是 scope-keyed
  family，換 scope 自動換串。
- 舊 scope in-flight 請求不取消，在自己串裡跑完。
- `lifecyclePhase` 不傳；quota 沿用 `onQuotaExceeded → /paywall`；埋點 v1 不加
  （等案 6-1 telemetry 一起）。
- 風險：CoachSurface 內部若有 scope 初始化後不更新的狀態，切換會殘留——實作時
  檢查 `didUpdateWidget`。

## 測試（widget）

1. 無對象 → chips 不存在。
2. 有對象 → chips 出現、預設「一般」。
3. 點對象 → CoachSurface 實際收到 `partner:<id>` scope。
4. 切回「一般」→ global。
5. 草稿跨切換保留。
