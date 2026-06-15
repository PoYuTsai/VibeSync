# Pixel-X Side Detector — 獨立研究 spec ＋ Gate-2 門檻

> 狀態：DRAFT / research-only。**未接 prod、未接 pipeline。**
> 前置：Phase1 已 PASS（2026-06-15，handoff `pixel_x_anchor_phase1`）。本檔定義 Gate-2（＝原 handoff 的 Phase1b Gate）的**可量化**門檻與量測方法。
> 鐵律來源：`project_ocr_side_flip_2026-06-13`、handoff_latest、本輪 detector 第二輪結案結論。

---

## 1. 定位（不可變）

- pixel-x 只當「**單側幾何 anchor**」，**絕不取代 LLM**。
- 輸出僅 `left | right | mixed | unknown` ＋ `confidence`。**不讀文字、不處理引用、不碰語意、不碰名字。**
- **只有高信度單側**才用來 deterministic 統一 speaker；`mixed / unknown / 低信度` 一律 **fail-open 完全回 LLM**，不改原 OCR 任何一個 byte。
- 絕不自動翻側、不碰 `recognized side / isFromMe`、不再 prompt-whacking。
- 引用 / 圖中圖 leakage＝**另案**，本 detector 不負責、不能期待它解。

## 2. 為何要這個（一句話）

暗色單側對話 vision side acc ~19%、recall 4/8，「snap 到模型主側」已六輪證偽（死路）。純幾何（泡泡左緣 x 分布）在 Phase1 三張上確定性分出單/雙側，值得擴樣驗證它**不是只對 3 張有效**。沒過 Gate-2＝停在現有 client 兜底（一鍵「全部改成對方說」）。

## 3. Phase1 recap（已 PASS，不重做）

- 離線 prototype：deno + `npm:jpeg-js`（系統無 cv2/numpy）。解圖→mode-agnostic bubble mask→4-鄰 BFS 連通元件→濾（寬>0.18W & area>1500 & fill>0.55）→取泡泡 bbox 左緣 x 分布→判單/雙側。
- 暗單側 `S__42237983`：7 泡、7L/0R、左緣 spread 24px(3%W)＝SINGLE-LEFT✓
- 淺雙側 `S__42246174`(11泡 5L/6R spread522px) / `S__42246176`(8泡 4L/4R)＝MIXED✓
- 結論：非 trivial「永遠左」，x 分布真能分單/雙側；確定性、重跑同值。

---

## 4. Gate-2 門檻（**全過**才准接 pipeline）

> 分兩類：**安全門檻**（G2-1/G2-3/G2-4，任一破＝絕不接）＋**有用性門檻**（G2-6，過安全但沒用＝也不接）。
> **UNKNOWN/fail-open 既不算誤判、也不算成功**——它只是「沒出手」。報表必須把「出手了多少」與「沒判錯多少」分開列，避免用 fail-open 灌水成功率。

### G2-1 高信度單側 activated subset：**零誤判（安全門檻，硬性）**
- 定義 activated subset＝detector 輸出 `single-left|single-right` 且 `confidence ≥ τ`（τ 見 §6）。
- **此子集任一張側別判錯＝Gate-2 直接 FAIL**，不接 pipeline。無容忍。
- 理由：activated subset 就是會 deterministic override 的集合，誤判＝釘死誤讀（side-flip 紅線）。

### G2-2 整體單側 side accuracy ≥ 95%
- 全部單側樣本（含未達 τ 而 fail-open 的）side acc ≥ 95%。
- 未達 τ → unknown/fail-open，**算「未啟用」不算錯**（不污染 G2-2 分母？見下）。
  - 計法：G2-2 分母＝所有「真實單側」樣本；分子＝detector 未把它判成相反側（含 unknown/mixed→fail-open 視為「沒判錯」，但**會吃 recall**，記錄但不擋 G2-2）。
  - 真正的「判錯」＝把 single-left 判成 single-right 或反向。

### G2-3 mixed → single 誤判率：**0（安全門檻，P0 gate fail）**
- 任一張正常雙側 mixed 被判成 single-*（不論信度）＝**P0 FAIL**。
- 理由：會把正常雙側對話整段統一成單一 speaker，污染最廣、最難被用戶察覺。
- 反向（single 被判 mixed）＝吃 recall、不算 P0（fail-open 安全側）。

### G2-4 fail-open 完備性：**100%（安全門檻，硬性）**
- detector 找不到泡泡 / 信度不足 / 任一例外 → 回 `unknown`，**原 OCR 輸出零變動**（byte-for-byte）。
- 以「故意餵壞圖／空圖／非聊天截圖」測試集驗證：必須 100% 走 fail-open，0 次 override。

### G2-5 純幾何（安全門檻，硬性，自動驗）
- detector 程式碼路徑**不得** import 任何文字/OCR/名字/語意訊號。靜態檢查＋review 雙保。

### G2-6 有用性 / activation coverage（**有用性門檻**）
- **activation coverage**＝單側樣本中被 detector 以高信度（≥τ）接管的比例，**單獨報出**。
- 安全門檻全過、但 coverage 太低＝結論「**safe but not useful**」，**不接 pipeline**（解了像沒解，徒增複雜度）。
- coverage 的最低及格線本 spec **不拍死數字**（取決於量測後 activated subset 能多大仍守住 G2-1 零誤判）；但報表**必須**讓 Eric 看到「出手率 vs 安全率」一起判，禁止只報 side acc 蓋掉低 coverage。
- 對照基準：現有 client 兜底（一鍵全改對方說）覆蓋 100% 但零智慧；detector 要有意義，得在「暗單側這類 LLM 本來會錯」的子集拿到夠高的安全接管率。

---

## 5. 樣本集（Gate-2 跑這個才算數）

最少 **15 張**（目標 20），組成必含每類 ≥3。

> ⚠️ **這是「接 pipeline 前的 Gate-2 prototype 門檻」，不是 ship 門檻。** 15-20 張只夠判斷「值不值得接 pipeline 做下一步」。**真要上 prod，必須用擴大後的 golden set 重跑全部門檻**，prototype 過 ≠ 可發佈。

| 類別 | 目的 | 現況 |
|------|------|------|
| 暗色單側（左／右各有） | 主戰場、Phase1 只有 1 張左 | 缺 only_right、缺暗右單側 |
| 暗色雙側 mixed | G2-3 最關鍵 | 缺 |
| 淺色單側（左／右） | 對照 | 缺 |
| 淺色雙側 mixed | G2-3 | 有 2 張 |
| 含貼圖/emoji/圖片泡泡 | 量漏框率、確認不誤觸發 | 缺 |
| 故意壞圖/非聊天截圖 | G2-4 fail-open | 需合成 |

> **Gate-2 第一件事＝補圖**。only_right / 暗色雙側 / 裸貼圖樣本要請 Bruce/Eric 提供或合成。golden 目前 0 個 only_right。

## 6. confidence 定義（τ 門檻，spec 待量測校準）

幾何信度由三訊號組合（純幾何，無語意）：
1. **bubble recall floor**：偵到泡泡數 ≥ R_min（暫定 ≥4，低於即 unknown——泡泡太少分布不可靠）。
2. **單側性**：所有泡泡左緣落在單一窄帶（spread ≤ S_max%W，Phase1 暗單側=3%）**且**對側無顯著泡泡叢集。
3. **無雙叢集**：左緣 x 出現兩個分離 cluster（gap ≥ G_min%W）＝mixed，**不得**輸出 single。

- τ（activated 門檻）＝同時滿足 1+2 且明確非 3。
- **S_max / G_min / R_min 的實際數值＝Gate-2 量測產物**，不在本 spec 拍死；先用 Phase1 觀測值當起點（S_max≈8%、G_min≈15%、R_min=4），擴樣後校準到「activated subset 零誤判」為止（G2-1 倒推）。

## 7. 量測指標（每張都記，報表三類分開列）

**安全類**
- 左右欄判定正確 / 錯誤（G2-1/G2-2）
- mixed→single 誤判數（G2-3，必須 0）
- fail-open 觸發正確率（G2-4，壞圖測試集）

**有用性類（不可被安全率蓋掉）**
- **activation coverage**：單側樣本高信度接管比例（G2-6）
- **fail-open rate**：判成 unknown/mixed→回 LLM 的比例（高 coverage 的反面）

**支撐 / 成本類**
- 泡泡 recall（偵到/實際）、單/雙側分類正確、貼圖漏框率（含 emoji/圖片泡泡）
- **Edge 成本**：單張 latency（解圖+像素掃描）、peak memory。

## 8. Edge 可行性門檻（與 Gate-2 並行量，過不了也不接）

- latency：解圖+掃描 **p95 ≤ 800ms ＝ target / placeholder，不當硬 fail**。等 Supabase Edge 實測後校準成真門檻。
- memory：峰值 ≤ Edge function 限額安全邊際（待確認 Supabase Edge 上限後填）。
- 實測後若成本過高→再決定離線/client 端或放棄；本階段不因 placeholder 數字擋 Gate-2。

## 9. 不在範圍（YAGNI / 明確排除）

- 引用、圖中圖 leakage guard（另案）。
- 任何文字、名字、語意訊號。
- 取代 / 覆寫 LLM 的 side（只在 activated subset 統一 speaker）。
- Phase2 確定性覆蓋閘以外的填色/顏色訊號（dark-fill 已證偽，DEAD）。

## 10. 交付物 & 流程

1. 重建離線 prototype（/tmp 版 rotate 已失，從 memory 全 context 重寫）。
2. 補樣本集（§5）。
3. 跑量測→填 §6 數值→對 §4 五條 gate 判定。
4. 全過＝寫接 Edge 的實作 plan（另案，需 Codex 雙審，屬高風險 OCR/Edge 區）。
5. 任一條 FAIL＝停，停在現有 client 兜底，記錄死因進 memory。

> 本 spec 為 research scope、無 prod runtime import，撰寫階段免 Codex 雙審；**接 pipeline 的實作 plan 必雙審**。
