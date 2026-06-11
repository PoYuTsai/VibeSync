# OCR 截圖分析鏈 Read-Only 全面審查（2026-06-12）

> 由 Claude 三路平行探查 + 關鍵引用抽查驗證。**零改動**。
> 背景：OCR 為高風險區——Codex 曾連改多輪致回歸，全面 revert（見 `docs/2026-04-05-ocr-rollback-note.md`），現基線穩定。
> Eric 已拍板：**golden set 量測案開案**（零風險先行項），其餘 code 改動暫不動。

## 總判決

**「精確度夠嗎」目前無法誠實回答**：架構防護健全，但 `docs/ocr-analysis-maturity-benchmark.md` 的「左右判斷 ≥98%」是期望值非實測值。全 pipeline 無 telemetry 追蹤實際 unknown 率與修復成功率，亦無 golden set 跑分。效能可用，有兩個體驗硬點（圖片禁 fallback、同圖重分析全額重跑）。

## 她說/我說歸屬機制

Layout-first 五層鏈：

1. Vision prompt 強制「外層氣泡位置決定 side、內容不得影響」（`index.ts` SCREENSHOT_OCR_ACCURACY_RULES）
2. `normalizeBubbleSide()`：水平位置 ≥58→right、≤42→left、**42-58→unknown**（`index.ts:2958-2961`，已驗證）
3. `layout_parser.ts` 多輪修復（unknown 夾心、系統列 strip、媒體橋接）
4. Continuity heuristics + 五層後處理（continuity / singleVisibleSpeaker / grouped / quotedPreview / trailing）
5. 用戶確認 dialog 可逐則手動翻轉 + 批次左右重套（`screenshot_recognition_dialog.dart`）

強項（revert 後基線確實穩）：

- 引用卡防護完整：「quoted card 名字不改變外層氣泡 speaker」prompt 明文 + `only_left` pattern 強制全 `isFromMe: false`
- 系統列（已讀/時間戳/收回/banner）strip 邏輯 + 測試
- 非聊天圖（自拍/profile/群聊/social feed）分類 → `importPolicy: reject`

## 風險清單（精選，依嚴重度）

| # | 風險 | 證據 | 級別 |
|---|------|------|------|
| 1 | 中線氣泡（42-58%）→ unknown，heuristic 修復成功率從未量化 | `index.ts:2958-2961` | P1 |
| 2 | 精確度基準無實測：98% 是目標非量測，無 telemetry / golden set | `ocr-analysis-maturity-benchmark.md:34` | P1 |
| 3 | 中文 SYSTEM_PROMPT 無「逐字保留錯字/注音/口語」對等指令（英文 OCR prompt 有 "Preserve... exactly; do not guess"）；分析層可能好心修字，零測試 | `index.ts:947` vs 中文 SYSTEM_PROMPT | P1 |
| 4 | 重疊截圖 dedup 完全相等判定、無 fuzzy；兩張無關截圖可無聲併合（contactName/時間連續性未驗） | `index.ts:2892-2936`、`conversation_hash.ts` | P1 |
| 5 | 暗模式零專屬指令、零測試 | `layout_parser_test.ts` 無用例 | P2 |
| 6 | 群聊誤判被 reject 後用戶可手動覆蓋、無強警告 | `screenshot_recognition_dialog.dart:789-844` | P2 |
| 7 | 引用卡內含 nested screenshot 的內層對話不被捕捉（建議文件化為已知限制） | prompt 無指引 | P2 |
| 8 | 繁中形似字（住/佳）無回退機制 | `index.ts:1089-1091` | P3 |

## 各情境矩陣

| 情境 | 防護 | 備註 |
|------|------|------|
| 圖中圖 | ✅ prompt「外層氣泡決定 side、忽略內層內容」 | 無對抗測試 |
| 圖中影片 | ✅ `[video...]` 佔位符 | 影片內字幕可能被抄成訊息 |
| Emoji/貼圖 | ✅ `[sticker]` 佔位符、逐字保留 | OK |
| 錯字/注音/口語 | ⚠️ 英文 prompt 有、中文 prompt 無、零測試 | 風險 #3 |
| 重疊/亂序截圖 | ⚠️ 有 dedup + anchor_drift，但無 fuzzy | 風險 #4 |
| 非聊天圖 | ✅ 分類 + reject | 手動覆蓋無強警告 |
| 暗模式 | ❌ 無 | 風險 #5 |

## 效能 / 成本

- 限制：3 張、單張 900KB（client 6 階壓縮 960→640px / quality 78→30）、總 2.7MB、超限 400 不截斷——合理
- Timeout：有圖 90s（recognizeOnly）/ 120s（`index.ts:5740-5741`）vs 實際 18-25s，餘裕過大但無害
- **有圖 = 禁 model fallback**（`index.ts:5743`，已驗證）：Sonnet 失敗用戶吃硬錯誤，無「改貼文字重試」引導
- **同圖重分析 server 全額重跑**：client OCR cache 條件嚴（high confidence + 0 uncertain 才存，`ocr_recognition_cache_service.dart:63-76`）、server 無 vision cache
- 成本：圖片不另計費但強制 Sonnet（input 費率 3.75× Haiku）；開場模式固定 3 則/請求與張數無關；無 vision 成本監控指標
- quick/full 二階模式明確拒圖（400），僅 legacy 路徑收圖——by design（build 213）

## 建議（依 rollback note 教訓：一次一變數、絕不 batch）

1. **【已拍板開案】Golden set 量測先行（零風險，不動 code path）**：10-20 張涵蓋中線/暗模式/引用卡/重疊/錯字情境，離線跑分把 98% 從願望變數字；加 telemetry 記 unknown 率/修復次數分佈
2. 中文 SYSTEM_PROMPT 補「逐字保留錯字」：單變數 prompt 改動，須 Codex 雙審（高風險區）
3. 圖片失敗 UX 引導「改貼文字」：client-only，不碰 OCR
4. Fuzzy dedup / server vision cache：真正 code 改動，**現階段不動**——golden set 有數字之後再評估

## 結論

當初 revert 是對的，現基線值得守。Codex 提油救火的根因正是缺量測——沒有 golden set 之前，任何「優化」都無法驗證沒變壞。回饋迴路先建，code 後動。
