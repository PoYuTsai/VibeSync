# VibeSync Architecture Decision Records

> 歷史決策記錄。新決策遇到時在這裡新增，**不寫進 CLAUDE.md**。
>
> 已被新決策取代的舊決策保留原文，並在頂部標示 **🔁 SUPERSEDED**。

---

## Index

| # | 決策 | 狀態 |
|---|------|------|
| 1 | 對話資料不上雲 | ✅ Active |
| 2 | 混合 AI 模型策略（70% Haiku + 30% Sonnet） | 🔁 SUPERSEDED by #11 |
| 3 | 訊息制訂閱 — 3 方案 | 🔁 SUPERSEDED by #10 |
| 4 | 五種回覆類型 + MK 框架 | ✅ Active |
| 5 | 對話記憶 — 15 輪完整 + 自動摘要 | ✅ Active |
| 6 | GAME 框架整合（v1.1） | 🔁 SUPERSEDED by rename（改為「對話進度」） |
| 7 | 實作計畫 v2.0 — 訊息制 + 5 回覆 | 🔁 部分過時（訂閱方案已換） |
| 8 | Admin Dashboard + 沙盒雙軌（v1.3） | ⏸️ 暫停 |
| 9 | System Prompt 優化 + 個人化 + 反饋機制 | ✅ Active |
| 10 | 訂閱方案更新（2026-04-22）— NT$590/NT$1,290 + 4 產品 | ✅ Active |
| 11 | AI 模型策略更新（2026-04-22）— Starter 升 Sonnet | ✅ Active |
| 12 | UI 重構 — 溫暖粉紫漸層毛玻璃 | ✅ Active |
| 13 | 截圖上傳 — Claude Vision | ✅ Active |
| 14 | 開場救星 feature（2026-04） | ✅ Active |

---

## ADR #1 — [2026-02-26] 對話資料不上雲
**狀態**: ✅ Active

**決定**: 對話歷史只存本地，伺服器不保留

**原因**:
1. 隱私風險最小化
2. GDPR 合規簡化
3. App Store 審核友善
4. 用戶信任度提升

---

## ADR #2 — [2026-02-26] 混合 AI 模型策略（70/30）
**狀態**: 🔁 SUPERSEDED by ADR #11（2026-04-22 Starter 升 Sonnet）

**原決定**: 70% Haiku + 30% Sonnet 混合

**原因**:
1. 成本降低 60-70%
2. 簡單情境不需要大模型
3. 複雜情境保持品質

**為何取代**: 2026-04-22 定價調升後，Starter 升級使用 Sonnet，成本結構改變。見 ADR #11。

---

## ADR #3 — [2026-02-26] 訊息制訂閱模型（3 方案）
**狀態**: 🔁 SUPERSEDED by ADR #10

**原決定**: Free / Starter NT$149 / Essential $29 USD，訊息制

**為何取代**: 2026-04-22 重訂價，見 ADR #10。

---

## ADR #4 — [2026-02-26] 五種回覆類型 + MK 框架
**狀態**: ✅ Active

**決定**: 從 3 種擴充到 5 種回覆風格
- 🔄 延展（細緻化深挖）
- 💬 共鳴（情感連結）
- 😏 調情（推拉反差）
- 🎭 幽默（曲解/誇大）
- 🔮 冷讀（假設代替問句）

**新增功能**:
- 話題深度階梯（Event → Personal → Intimate）
- 對話健檢（Essential 專屬）
- 70/30 法則（聆聽 vs 說話）
- 面試式提問警告

---

## ADR #5 — [2026-02-26] 對話記憶設計
**狀態**: ✅ Active

**決定**: 一人一對話，永久持續，背景自動摘要

**策略**:
- 最近 15 輪：完整保留
- 更早輪次：自動摘要
- 用戶無感：對話一直連貫

**選擇追蹤**: AI 從對方回覆反推，90% 自動推測，10% 輕量確認

---

## ADR #6 — [2026-02-27] 設計規格 v1.1 — GAME 框架整合
**狀態**: 🔁 SUPERSEDED（GAME 字樣已移除，改為「對話進度」）

**原決定**: 整合完整 GAME 框架到 AI 分析引擎（打開 → 前提 → 評估 → 敘事 → 收尾）

**原核心變更**:
- GAME 五階段 + 隱性 DHV + 框架控制 + 廢測處理 + 淺溝通解讀
- AI 輸出：GAME 階段 + 心理分析 + 5 回覆 + 最終建議 + 理由
- Session 設計：情境收集（認識場景/多久/目標）
- UI 風格：高端極簡
- 冰點策略：可建議已讀不回 + 放棄
- 真人一致性提醒：見面才自然

**為何改名**: commit `0286ae6`（2026-04-xx）移除 GAME 字樣，改為「對話進度」五階段（破冰/升溫/深入/連結/邀約）。內核邏輯保留，僅命名調整。

---

## ADR #7 — [2026-02-26] 實作計畫 v2.0 更新
**狀態**: 🔁 部分過時（訂閱部分已被 ADR #10 取代）

**原決定**: 實作計畫與設計規格書同步
1. 訂閱系統改訊息制（30/300/1000）
2. 每日上限（15/50/150）+ 訊息計算
3. 回覆類型：3 → 5 種
4. 功能分層：Free 只有延展，Starter/Essential 完整
5. 新增 Phase 7-9：訊息計算、對話記憶、Paywall
6. 總任務：15 → 19

**原因**: 避免實作與設計不一致造成返工

---

## ADR #8 — [2026-02-27] 設計規格 v1.3 — 運營補充
**狀態**: ⏸️ 暫停（Admin Dashboard 延後）

**原決定**: 新增 Admin Dashboard 與沙盒測試環境

**Admin Dashboard**:
- 技術棧：Next.js 14 + Tailwind + Recharts + Vercel
- 8 項報表：用戶總覽、訂閱分佈、Token 成本、營收、利潤、AI 成功率、錯誤追蹤、活躍度
- 權限：單一 Admin（Email Allowlist）+ Supabase Auth

**沙盒環境**:
- 雙軌：Firebase App Distribution + TestFlight/Internal Testing
- 環境：dev / staging / prod
- 排除測試帳號的報表 View
- CI/CD：GitHub Actions 自動 build + 分發

**當前狀態**: Admin Dashboard 部分已建（`admin-dashboard/`），上架後再完善。

---

## ADR #9 — [2026-03-04] System Prompt 優化 + 個人化 + 反饋機制
**狀態**: ✅ Active

**決定**: 三項優化

### 1. 名詞修改（規避著作權）
- 82/18 原則 → 70/30 法則
- 話題深度階梯改英文（Event-oriented / Personal-oriented / Intimate-oriented）

### 2. 個人化資料收集
- 用戶風格（幽默/穩重/直球/溫柔/調皮）
- 用戶興趣（自由填寫）
- 對方特質（選填）
- AI 依資料調整回覆風格

### 3. 反饋機制
- 分析結果頁底部 👍👎 按鈕
- 負面反饋展開表單（分類 + 補充說明）
- 反饋存 Supabase `feedback` 表
- 負面反饋自動發送 Telegram 通知

**相關文件**:
- 設計: `docs/plans/2026-03-04-system-prompt-optimization-design.md`
- 實作: `docs/plans/2026-03-04-system-prompt-optimization-impl.md`

---

## ADR #10 — [2026-04-22] 訂閱方案大改版（4 產品）
**狀態**: ✅ Active（取代 ADR #3）

**決定**: 從「訊息制，3 方案（月繳）」改為「訊息制，5 方案（4 個付費產品）」

**新方案**:
| Tier | 月繳 | 季繳 Product ID | 訊息/月 | 每日 |
|------|------|-----------------|---------|------|
| Free | NT$0 | — | 30 | 15 |
| Starter | NT$590 | `starter_quarterly` | 300 | 50 |
| Essential | NT$1,290 | `essential_quarterly` | 800 | 120 |

**功能分層調整**:
- Starter 升級為 **Sonnet AI** + 全 5 種回覆風格（見 ADR #11）
- 雷達圖限 Starter/Essential 可見（Free 隱藏）
- Essential 額度調減：月 1000→800、日 150→120

**相關 commit**: `6fe4567`

---

## ADR #11 — [2026-04-22] AI 模型策略更新（Starter 升 Sonnet）
**狀態**: ✅ Active（取代 ADR #2）

**決定**: Starter 層從 Haiku 升級為 Sonnet

**新策略**:
- **Free**: Haiku（`claude-haiku-4-5-20251001`）
- **Starter**: Sonnet（`claude-sonnet-4-20250514`）
- **Essential**: Sonnet
- **有圖片時**: 強制 Sonnet（所有層）

**原因**:
1. 定價上調後毛利足夠覆蓋 Sonnet 成本
2. Starter 品質升級可降低退訂率
3. 簡化模型路由邏輯

**成本影響**: 記帳在 `docs/cost-optimization.md`

---

## ADR #12 — [2026-03-11] UI 重構 — 溫暖粉紫漸層毛玻璃
**狀態**: ✅ Active

**決定**: 從暗黑主題改為溫暖粉紫漸層 + 毛玻璃風格
**目標**: Gen Z 友善、約會 app 氛圍

**設計決策**:
| 項目 | 決定 |
|------|------|
| 背景風格 | B2 動態光球（呼吸縮放 + 多方向浮動） |
| 毛玻璃範圍 | 僅互動元件（輸入框、選項按鈕） |
| 發光效果 | BoxShadow |
| CTA 按鈕 | 珊瑚漸層，全 app 統一 |
| 頭像 | 漸層泡泡 |
| 實作 | 修改現有 Theme |
| 平台 | Web 優先，iOS 同步 |

**Phase 1 產出** (15 Tasks):
- AppColors 新增 Warm Theme
- 6 個共用元件：GradientBackground / GlassmorphicContainer / GradientButton / BubbleAvatar / GlassmorphicSegmentedButton / GlassmorphicTextField

**Phase 2/3**: HomeScreen / LoginScreen / SettingsScreen / AnalysisScreen / 動態光球動畫

**相關文件**:
- 設計: `docs/plans/2026-03-10-ui-redesign-design.md`
- 實作: `docs/plans/2026-03-10-ui-redesign-impl.md`

---

## ADR #13 — [2026-03-12] 截圖上傳 — Claude Vision
**狀態**: ✅ Active

**決定**: 新增截圖上傳，用 Claude Vision API 識別對話

**設計決策**:
| 項目 | 決定 |
|------|------|
| 定位 | 補充手動輸入（非取代） |
| 最大圖片 | 3 張/次 |
| 圖片+文字 | 一起分析（截圖為較早對話） |
| 進入點 | 對話列表上方獨立按鈕 |
| 上傳後 | 直接分析 |
| 壓縮 | 自動（~1024px、85% quality） |
| AI 模型 | 有圖片強制 Sonnet |
| 來源 | 相簿 + 剪貼簿（Web） |
| 失敗處理 | 顯示錯誤，不扣額度 |
| 儲存 | 用完即丟 |
| 傳輸 | Base64 直傳 |

**技術架構**:
- 前端: `ImagePickerWidget` + `ImageCompressService`
- 後端: Edge Function `buildVisionContent` + 識別指示
- API: Claude Vision (Sonnet)

**新增檔案**:
- `lib/shared/services/image_compress_service.dart`
- `lib/shared/widgets/image_picker_widget.dart`

**相關文件**:
- 設計: `docs/plans/2026-03-12-screenshot-upload-design.md`
- 實作: `docs/plans/2026-03-12-screenshot-upload-impl.md`

---

## ADR #14 — [2026-04] 開場救星 Feature
**狀態**: ✅ Active

**決定**: 新增「開場救星」— 無/有截圖都能用的開場白生成工具

**設計**:
- 獨立頁面（`lib/features/opener/`）
- Edge Function `analyze-chat` 新增 opener 模式
- 最多 3 張截圖輔助（選填）
- 計費：基本 **3 則** + 每張截圖 **+2 則**（最多 3 張 = 最多 9 則）
- 文章學習頁「實戰練習」按鈕導向開場救星

**技術重點**:
- 環境變數用 `CLAUDE_API_KEY`（不是 `ANTHROPIC_API_KEY`）
- 截圖傳 `ImageData` 物件，不是純 base64 字串
- 使用 `callClaudeWithFallback` 統一 API 呼叫格式

**相關 commits**: `491b634`, `cfbf04a`, `21154bf`, `d9f7d9e`, `43b591a`

**相關文件**:
- 設計: `docs/plans/*opener*design.md`
- 實作: `docs/plans/*opener*impl.md`
