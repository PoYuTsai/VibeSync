# OCR 暗色 side 誤讀 — 填色補強訊號設計（第③軌）

> 狀態：DESIGN（brainstorming 收斂，2026-06-14，Eric 拍板方向＋三層 gate）。
> 範圍：第③軌「暗色 vision 誤讀」獨立 track。延續 [[project_ocr_side_flip_2026-06-13]] / `docs/plans/2026-06-13-ocr-geometry-lock-design.md`。
> ⚠️ 這份只到 Phase 1（量測）。Phase 2（確定性覆蓋）必須通過 Phase 1 hard gate 才動。

## 問題（已重現、已建檔）

- 真機 dogfood：暗色長截圖 `S__5480452`（Candy 單側、全 left＝她說），live OCR 把 **7/10 翻成「我說」**。
- 人工標註真值（`tools/ocr-golden/labels/real/S__5480452.json`）＝10 則全 `left`，Eric 真機回報一致。
- `S__5480452` 早被 side-flip 案列為 dark/quoted 風險群、幾何閘救不了的單元。

## 根因（已定案，非新查）

- side-flip probe 實證：模型自報 `horizontalPosition`（側別唯一錨）在**暗色只有 78.3% 可信**，會自信地把左泡泡讀成右。
- 現行 prompt（`index.ts:957-1026`）**已**明確教「只看外層泡泡位置」「Bruce 引用卡名字不准翻側」，還附 `only_left`+Bruce worked example——模型被教對了規則**仍翻**。
- ∴ 這是**感知失敗、非指令失敗**。再加位置類指令無用。
- 關鍵缺口：整套側別判讀全錨在**位置**（暗色唯一會壞的訊號），且 `index.ts:1022` 反而叫模型**忽略**主題色差——而**泡泡填色**在暗色仍是強訊號（全灰接收→全她說），完全沒被用。

## 鐵教訓（決定設計順序）

side-flip 否決「全幾何決定性閘」的唯一理由：**對沒驗證可信度的模型自報訊號做 deterministic override，會把誤讀釘死。** 填色也是模型自報訊號。**同樣陷阱。** 所以：先量測證明暗色填色比位置可信，才准建覆蓋閘。**先量再信。**

## Phase 1 — 只插樁＋量測（不改判讀邏輯）

1. vision 每泡泡多吐 `bubbleFillColor`（具名：green／gray／white／blue／…）。
2. vision 整圖多吐 `myBubbleColor` ＋ `myBubbleColorEvidence`，evidence 三態：
   - `right_anchor`（畫面有右側泡泡可錨「我發的色」）
   - `app_convention`（無右錨，靠 app 慣例推；LINE 無綠＝全接收＝對方）
   - `unknown`（推不出）
3. harness 新指標：**fill-only side accuracy**（純用 `bubbleFillColor` vs `myBubbleColor` 推側別）對真值，在暗色 gated subset 上跟 **position-only** 對打。
4. 記錄 evidence source 分佈（多少 right_anchor / app_convention / unknown）。

**不改 isFromMe 判讀路徑。Phase 1 純觀測。**

## Phase 1 Hard Gate（三層，全過才准進 Phase 2）

1. 暗色 LINE gated subset：**fill-only accuracy ≥95% 且比 position-only 高 +10pp**。
2. **95% Wilson lower bound ≥90%**（擋小樣本假漂亮）。
3. Anchor：`S__5480452` 的 Candy 全 left **明顯改善**；同時淺色標準＋交友 app golden **零回退**。Phase 2 gate 理論上不觸發的路徑，也要用 harness 證明 **non-triggered path unchanged**。

> 預判：以目前可信暗色單元數，第 2 層幾乎一定 FAIL。⟹ **現實第一步＝擴暗色標註集（label 校對／多輪取樣），不准硬進 Phase 2。**

## Phase 2 —（條件達成才做）確定性補強閘

- 觸發條件（gated，Eric 定）：① 暗色 LINE ② 全同色單側 ③ `horizontalPosition` 落中段(42–58) 或 sideConfidence 不穩 ④ quoted-card／name-card 干擾側別。
- 邏輯：`side = (bubbleFillColor == myBubbleColor) ? me : her`，覆蓋位置判讀。
- **`myBubbleColorEvidence == unknown` 不准覆蓋**——只能降 confidence／`importPolicy: confirm`。
- 🔧 開放旋鈕：`app_convention`-only 能否覆蓋、還是只能降信心？（`S__5480452` 全左無右錨＝這顆旋鈕的壓力測試點。）
- 淺色標準／交友 app **完全走原路徑**（gate 不觸發）＝結構保證不回退。
- TDD＋Codex 雙審（OCR＝高風險區）。

## 驗收

暗色 `S__5480452` 改善、淺色標準＋交友 app golden 零回退、non-triggered path 證明 unchanged。

## 下一步（新 session）

1. 擴暗色標註集到足以算 CI（label 校對＋多輪取樣）。
2. Phase 1 插樁（`bubbleFillColor` / `myBubbleColor` / evidence）＋ harness fill-only 指標。
3. 跑 Phase 1 三層 gate → 過才開 Phase 2。
