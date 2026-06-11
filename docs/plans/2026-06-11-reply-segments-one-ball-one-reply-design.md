# 一球一回：replySegments 分段回覆設計（候選 #12）

> 2026-06-11 · Eric 與 Claude 定案，待 Codex 設計把關。
> 來源：Bruce TestFlight smoke feedback（golden case 見「驗收標準」）。

## 問題

對方一次丟出多顆球（多個獨立話題/提問）時，full mode 推薦回覆把多球答案用逗點串成一句大回覆。體感差、無法分開複製使用、不符合真實聊天「一球一回」的節奏。

## 語意定案

**一球一回**：每顆值得回的球出一段（segment），各段綁定它回應的那顆球（`sourceMessage`），各段獨立成立、各自有複製鈕。

## 現況事實（2026-06-11 程式碼探索）

- Client 端 **已具備全部基礎設施**，本案幾乎不動 client：
  - `ReplySegment` model：`lib/features/analysis/domain/entities/analysis_models.dart:156-217`（`sourceIndex` / `label` / `sourceMessage` / `reply` / `reason`）
  - 分段渲染 + 每段獨立複製鈕：`lib/features/analysis/presentation/screens/analysis_screen.dart:4299-4439`（`_buildStructuredRecommendationSegments`）
- 問題出在 **server prompt**：模型實際上常只輸出單段（或把多球合併進一段），client 有能力渲染 N 段但拿不到 N 段。
- **主戰場 = `supabase/functions/analyze-chat/index.ts` 的 prompt 與 schema**。

## 規格決策（七點，Eric 已同意）

1. **Cap 4 溢出行為**：球清單 >4 顆時，AI 挑「互動價值最高」的 4 顆出段，其餘只留在球清單、不出段、UI 不另外提示。不做「還有其他線」提示——YAGNI，等真實案例超過 4 球再說。
2. **N=1 不變**：只有一顆球時維持現狀單段 + 引用，已運作正常。
3. **Quick mode 本輪不動**：quick 定位是分析中的快速預覽，單句合理。等 Bruce 對 full mode 分段滿意後再評估（獨立候選）。
4. **舊 client fallback**：`content` 欄位仍填完整合併版，但 join 用**換行**不用逗點——未更新的 client 也擺脫逗點大句。新 client 有 `segments` 用 `segments`，`content` 只當備援。
5. **Prompt 目標式 audit 範圍**：推薦回覆規則（index.ts ~1403-1404）、replySegments 規則（~1462-1476）、長度/格式約束、任何「回覆要精簡」類反向拉力指令。修正原則：條件式改強制式、綁球清單、各段獨立成立。
6. **把關流程**：prompt 變更 = 破 style-pair byte-for-byte 鎖（2026-06-10 eebef91 立的鎖）+ 高風險區（analyze-chat）。走 Codex 設計把關 → 實作 → 實作雙審雙軌全跑。把關文件明寫「主風格 prompt 鎖已知情破鎖、重新驗證」，絕不聲稱 prompt 沒動。
7. **驗收標準（golden case）**：Bruce 2026-06-11 case——同樣輸入（行程球/電量球/吃飯球三球）應出 3 段，各段對應一顆球、各自有複製鈕、各段獨立成立不逗點串連。另須回歸：N=1 case 行為不變。

## 下游接口預留（候選 #13「採用回填」，本案不實作）

#13 規劃：每段加「已送出」鈕 → 一鍵 append 成 `isFromMe: true` 的 `Message`，並以該段 `sourceMessage` 填 `quotedReplyPreview`（`Message` model 已有此欄位，`message.dart:1-41`），免費取得引用語意。

**本案唯一義務**：保證每段輸出穩定、非空的 `sourceMessage` 與 `sourceIndex`，schema 層面驗證。其餘 #13 自理。

## 風險

- Prompt 改動波及其他模式（quick / 主+副互動風格）→ 驗收須含 quick 不變、style-pair 重新驗證。
- 多段輸出 token 略增 → 屬 ADR #19 計費鏡像既有區間內，不另立規則。

## 不做清單

- 候選 #14（手動輸入 LINE 式引用 UI）：Eric 2026-06-11 拍板不考慮。
- Quick mode 分段、「還有其他線」提示、cap 數字可調設定。
