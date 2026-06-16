# Per-Bubble Pixel-Colour Census — 結果＝FAIL（color lever 死）

> 狀態：CLOSED / research-only。**未接 prod、未接 pipeline、未碰 OCR/LLM/prompt。**
> 與 `2026-06-16-pixel-side-detector-gate2-spec.md`（pixel-X **幾何** detector，已 Gate-2 FAIL）**不同案**。
> 本案測的是 memory `project_ocr_dark_only_left_explore_2026-06-16` 的「剩 1 條活槓桿」＝**逐泡實測像素填色**，量「模型判右但 raster 實際灰」能不能當獨立訊號。
> 工具：`tools/pixel-census/census.ts`（deno + `npm:jpeg-js`，無 cv2/PIL）。連通元件抓泡→取每泡內部 median RGB→greenness = G−(R+B)/2。

## 樣本（18 張，分母先 ls 確認）
暗 only_left 7 ／暗 only_right 2 ／暗 both_sides 4 ／淺 only_right 3 ／淺雙側 2。

## Eric 寫死的 GATE 判定（任一 FAIL → 回 product-UX 一鍵確認，不再追 pixel）

| Gate | 條件 | 結果 | 證據 |
|------|------|------|------|
| ① | 真右綠泡 0 次讀灰 | **FAIL** | `暗 both S__42319882`：右側「我方」訊息**渲染成灰泡（非綠）**，census nGreen=0＝色彩偵不到右側 |
| ② | 真左灰泡 0 次讀綠 | **FAIL** | `暗 only_left S__42237983`：唯一被判綠的 blob ＝**黃色貼圖（哭笑雞）** greenness 37，非泡泡 |
| ③ | gray/green cluster 可分 | **FAIL** | 「我方」綠泡 greenness 跨 0(灰渲染)→14→139；貼圖/噪聲落在 17~37＝**重疊、無全域門檻可切** |
| ④ | overall ≥95% | **FAIL** | 上述任一即破 |
| ⑤ | 任一 mixed·both 會被錯翻 | **FAIL** | `S__42319882`(both) 色彩偵不到綠→會把整段右側統一翻成「對方」 |

**全條 FAIL。**

## 三條根因（眼睛覆核過原圖，非單純 script artifact）
1. **「我方／右」泡泡不一定是綠**：`S__42319882` 用戶自己的右側泡渲染成灰（自訂主題／某些訊息型態）。色彩前提在根部就破。
2. **暖色貼圖/emoji 觸發綠偵測**：黃雞貼圖 greenness 37，落進綠帶。LINE 聊天貼圖滿天飛＝穩定誤觸。
3. **暗色「對方」灰泡 ≈ 近黑背景**：dist<30，7 顆全漏框；灰側在暗色幾乎與背景零對比。

## 誠實標注（被折抵的 artifact，不計入失敗證據）
- `淺 only_right S__5652524`：整張是一顆超大綠泡（meta 截圖），mode 背景偵測把**綠當成背景**減掉→nBub=1/nGreen=0。此列是我 script 的 bg 估計 bug，**不**當 pixel-separability 證據。即使折抵，①②③⑤ 仍由非-artifact 證據獨立判 FAIL。

## 結論 & 下一步
- **color/fill 訊號＝DEAD**（與已證偽的 dark-fill Phase1、自報泡色一致；本案是「逐泡 raster 實測」版本，也死）。
- **不進 gated TDD+Codex**（spec §10-5：任一 FAIL＝停）。
- 與已 committed 的 pixel-X 幾何 Gate-2 FAIL 合流：**整條 pixel side detector（幾何＋色彩兩臂）皆 FAIL**。
- 回 **product-UX 一鍵「全部改成對方說」兜底**（覆蓋 100%、零智慧但安全），不再追 pixel。
- Open loop（本案未碰，獨立 track）：nested-screenshot / image-in-image leakage guard。
