# 一球一回：replySegments 分段回覆設計（候選 #12）

> 2026-06-11 · Eric 與 Claude 定案 → Codex 設計把關 r1 REVISE_REQUIRED（2 P1 / 2 P2）→ Claude 同日修訂 → Eric 拍板 **cap 3**。
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

1. **Cap 3 溢出行為**（Eric 拍板 2026-06-11，取代原 cap 4）：球清單 >3 顆時，AI 挑「互動價值最高」的 3 顆出段，其餘只留在球清單、不出段、UI 不另外提示。不做「還有其他線」提示——YAGNI。
   - 依據（Codex r1）：既有全鏈已是 cap 3——client parser `.take(3)`（`analysis_models.dart:241`）、server sanitizer `slice(0, 3)`（`post_process.ts:136`）、prompt 與測試鎖「最多 3 段」（`index.ts:1464`、`index_test.ts:257`）。cap 3 與現況對齊，client 完全不動；golden case 3 球已滿足驗收，cap 4 增益無真實案例（YAGNI）。
2. **N=1 不變**：只有一顆球時維持現狀單段 + 引用，已運作正常。
3. **Quick mode 本輪不動**：quick 定位是分析中的快速預覽，單句合理。等 Bruce 對 full mode 分段滿意後再評估（獨立候選）。
4. **舊 client fallback**：`content` 欄位仍填完整合併版，但 join 用**換行**不用逗點——未更新的 client 也擺脫逗點大句。新 client 有 `segments` 用 `segments`，`content` 只當備援。
5. **Prompt 目標式 audit 範圍**（Codex r1 擴充）：推薦回覆規則（index.ts ~1403-1404）、replySegments 規則（~1462-1476）、長度/格式約束、任何「回覆要精簡」類反向拉力指令；**加上 `post_process.ts` 的 `sanitizeReplySegments` 層**（:130 裁段、:443 清洗 source、:580 回填 finalRecommendation）——實際讓 cap/source 生效的是 sanitizer，不是 prompt，只審 prompt 會漏真正的行為決定層。修正原則：條件式改強制式、綁球清單、各段獨立成立。
6. **把關流程**：prompt 變更 = 破 style-pair byte-for-byte 鎖（2026-06-10 eebef91 立的鎖）+ 高風險區（analyze-chat）。走 Codex 設計把關 → 實作 → 實作雙審雙軌全跑。把關文件明寫「主風格 prompt 鎖已知情破鎖、重新驗證」，絕不聲稱 prompt 沒動。
7. **驗收標準**（Codex r1 擴充）：
   - **Golden case**：Bruce 2026-06-11 case——同樣輸入（行程球/電量球/吃飯球三球）應出 3 段，各段對應一顆球、各自有複製鈕、各段獨立成立不逗點串連。
   - **N=1 回歸**：單球行為不變。
   - **Cap overflow case**：球數 > cap 時恰出 cap 段，且挑的是互動價值最高的球。
   - **Schema validation case**：缺 `sourceMessage`/`sourceIndex` 的段被修復或 drop，絕不以空 source 流出 server（#13 接口前提）。
   - **Quick mode 不變**。
   - **Style-pair 重驗**：明列重新基準化 `test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart:124` 的主-only byte-for-byte 鎖測試（知情破鎖 → 以新 prompt 重立基準），不得砍測試了事。

## 下游接口預留（候選 #13「採用回填」，本案不實作）

#13 規劃：每段加「已送出」鈕 → 一鍵 append 成 `isFromMe: true` 的 `Message`，並以該段 `sourceMessage` 填 `quotedReplyPreview`（`Message` model 已有此欄位，`message.dart:1-41`），免費取得引用語意。

**本案唯一義務**：保證每段輸出穩定、非空的 `sourceMessage` 與 `sourceIndex`，schema 層面驗證。其餘 #13 自理。

**缺 source 處理規則**（Codex r1 P2 補定）：現況 sanitizer 只驗 `reply` 非空，`sourceIndex` 可省略、`sourceMessage` 可空（`post_process.ts:142/:147/:155`）。本案升級為三層：
1. `sourceIndex` 缺或越界 → 以 `sourceMessage` 文字回查球清單修復；
2. 兩者都缺/修不回 → **drop 該段**（不讓空 source 段流出 server）；
3. 全部段被 drop → 回退現狀單段行為（`content` 合併版），絕不回空 segments。
N=1 路徑不受影響。

## 風險

- Prompt 改動波及其他模式（quick / 主+副互動風格）→ 驗收須含 quick 不變、style-pair 重新驗證。
- 多段輸出 token 略增 → 屬 ADR #19 計費鏡像既有區間內，不另立規則。

## 不做清單

- 候選 #14（手動輸入 LINE 式引用 UI）：Eric 2026-06-11 拍板不考慮。
- Quick mode 分段、「還有其他線」提示、cap 數字可調設定。
