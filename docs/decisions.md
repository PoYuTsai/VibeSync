# VibeSync Architecture Decision Records

> 歷史決策記錄。新決策遇到時在這裡新增，**不寫進 CLAUDE.md**。
>
> 已被新決策取代的舊決策保留原文，並在頂部標示 **🔁 SUPERSEDED**。

---

## ADR #18 - [2026-06-07] Analyze quick/full compatibility retention
**Status**: Active

**Decision**: Do not remove backend `responseMode: quick/full`, `analysis_runs`, `quickResult`, or related rollback-compatible code yet. The official user-visible analyze path is full streaming analyze; quick/full remains hidden compatibility and rollback surface only.

**Removal criteria**: Revisit only after Eric approves a build cutoff, all active builds use streaming analyze, logs show no recent quick/full requests, streaming analyze is stable, and a high-risk cleanup PR includes focused Edge/quota/auth/schema review.

**Owner**: Eric.

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
| 15 | Partner Entity Refactor（2026-04-25） — A1 schema-only ship + A2 UI/AI deferred | ✅ Active（v2 Shipped 2026-04-28，含 D-P4-1~5） |
| 16 | Spec 4 Phase 1 — Coach Action Card 取代 ScoreActionHint（2026-05-01） | ✅ Active（Shipped + cleanup complete 2026-05-02 HEAD `0d7ff06`） |
| 17 | Coach Action Hint v2 — analyze-chat 回傳可接球點（2026-05-08） | ✅ Active |

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
- 負面反饋自動發送 Discord 通知

**相關文件**:
- 設計: `docs/archive/plans/2026-03-04-system-prompt-optimization-design.md`
- 實作: `docs/archive/plans/2026-03-04-system-prompt-optimization-impl.md`

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
- 設計: `docs/archive/plans/2026-03-10-ui-redesign-design.md`
- 實作: `docs/archive/plans/2026-03-10-ui-redesign-impl.md`

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
- 設計: `docs/archive/plans/2026-03-12-screenshot-upload-design.md`
- 實作: `docs/archive/plans/2026-03-12-screenshot-upload-impl.md`

---

## ADR #14 — [2026-04] 開場救星 Feature
**狀態**: ✅ Active

**決定**: 新增「開場救星」— 無/有截圖都能用的開場白生成工具

**設計**:
- 獨立頁面（`lib/features/opener/`）
- Edge Function `analyze-chat` 新增 opener 模式
- 最多 3 張截圖輔助（選填）
- 計費：基本 **3 則** + 每張截圖 **+2 則**（最多 3 張 = 最多 9 則）— 已於 2026-05-16 改為一律 3 則，詳見 ADR #18
- 文章學習頁「實戰練習」按鈕導向開場救星

**技術重點**:
- 環境變數用 `CLAUDE_API_KEY`（不是 `ANTHROPIC_API_KEY`）
- 截圖傳 `ImageData` 物件，不是純 base64 字串
- 使用 `callClaudeWithFallback` 統一 API 呼叫格式

**相關 commits**: `491b634`, `cfbf04a`, `21154bf`, `d9f7d9e`, `43b591a`

**相關文件**:
- 設計: `docs/archive/plans/*opener*design.md`
- 實作: `docs/archive/plans/*opener*impl.md`

---

## ADR #15 — [2026-04-25] Partner Entity Refactor — 從 per-conversation 改為 per-partner data model
**狀態**: ✅ Accepted（2026-04-26：A1 已 merge `919e034` + TF soak 雙綠燈通過 [Eric build 139 + Bruce「Structure hasn't been changed, please proceed」]，A2 啟動）

**決定**: 引入 `Partner` Hive entity 作為對象的一級資料單位；`Conversation` 加 `partnerId` 掛在 Partner 下；跨對話的 trait/heat/count 透過 Partner aggregates 聚合（derived，not stored）；AI 分析時以「當前對話完整訊息 + Partner 摘要」雙層 context 餵入 prompt。

**動機**:
- Bruce 2026-04-25 測試期回報：同一個對方分兩次新對話建立 → 首頁顯示兩張獨立卡片，特質 / 熱度趨勢不聚合
- 根因：`Conversation` entity 只有 `name`（字串），無 `partnerId`，無 Partner 概念
- 上線後修 data model 風險 10×，趁 Bruce 測試期修補成本最低

**Brainstorm 決策**（鎖定）:
- 資訊架構：2 層（Home = Partner list → Partner detail）
- Migration：**B** 每 Conversation = 獨立 Partner + 手動合併 UI
- 聚合：**A Union** traits 聯集去重 / heat=latest / counts=sum / last=max
- AI context：**C Hybrid** 當前對話完整訊息 + Partner 摘要塞 prompt
- 我的報告 tab：**D** tab 不動，Partner 詳情頁加最新對話 5 維雷達摘要小卡
- 排程：Phase A Big Bang（內切 A1 schema 1.5 天 + A2 UI 7-8 天）

**送審影響**: 延 ~2 週。Eric 接受（trade-off：上線後修 data model 成本 10×）。

**相關文件**:
- 設計: `docs/archive/plans/2026-04-25-partner-entity-design.md`
- Live tracking: `docs/reviews/ai-arbitration-queue.md`

---

### ADR #15 v2 — Ship section（2026-04-28）

**狀態**: ✅ Shipped（A1 + A2 全集 merge to main，TF soak 進行中）

**Ship 範圍**: A1 schema (`919e034`) + A2 Phase 1-3 (`f053a9c` / `004388e` / `f2ab222` / `a38d46e`) + A2 Phase 4 polish + ship gate（branch `feature/partner-entity-A2-polish`）。

#### 主決策（D1-D4，A2 brainstorm 鎖定）

- **D1 — Partner detail 內 +新增對話 線性導向**：plan-default A，Partner detail page 提供 `+ 新增對話` CTA，建立後該 conversation 自動掛在當前 partner（`new_conversation_sheet.dart`）。對齊三大 Tab 既有層級，不引入額外 picker。
- **D2 — domain `Conversation` class 命名保留**：plan-default A，不 rename 為 `Session` 或其他。理由：A2 scope 只動 data model，避免 ripple 到 analysis / opener / OCR layers；UI 文案改走「對話」（partner-scoped 仍語意正確），class 名保留以縮 diff 面積。
- **D3 — conversation cell tap → analysis**：plan-default A，PartnerListCard 點擊進 partner detail，partner detail 內 conversation list cell 點擊直接進 analysis screen，不走中介 detail。
- **D4 — Same-name dedupe banner = 一次性 + per-account**：plan-default A，banner 永久可關（不每次冷啟提醒），dismissed flag per-account 隔離（D-P4-5 落地）。

#### Phase 4 新增決策（D-P4-1 ~ D-P4-5）

- **D-P4-1 — Partner delete cascade = block-when-conversations-exist**
  決定：Partner 對話數 ≥ 1 時禁止刪除，throw `PartnerHasConversationsException(conversationCount)`；用戶必須先 merge 或 reassign conversation。
  理由：資料安全 + 已有 path（merge / reassign）替代 + 教育用戶走正確 flow。
  實作位：`lib/features/partner/data/repositories/partner_repository.dart` `delete()` + `lib/features/partner/data/providers/partner_write_controller.dart` `delete()`；UI 切 informational vs confirm dialog。
  Reviewer guard：count 必用 `conversationsByPartnerProvider(p.id).length`，**不可**用 `aggregate.totalRounds`（0-round 對話會被誤判為空 → 誤刪）。

- **D-P4-2 — Banner pre-fill = newer-by-createdAt = source / older-by-createdAt = target**
  決定：merge picker route 加 `?target=` query param 帶較舊 partner 的 id；source = 當前列被合進去的 partner。
  理由：心智模型「先建的是正本」，對齊 Task 12 customNote `[from A]` tag 的 source/target 約定。
  實作位：`lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart` + merge picker route handler；無 `?target=` 時維持 PR-B 原行為（user 自選）。

- **D-P4-3 — PartnerListCard preview = interests/traits interleave 前 3 tag (keep ≥1 trait when both exist)**
  決定：preview 取 `[i0, t0, i1, t1, i2]` interleave 後 take(3)，不是 `(interests + traits).take(3)`。
  理由：產品定位（AI 拆解輪廓）+ 隱私（不曝對話原文）+ 0 行 aggregate 改動；Codex spec review 發現純 concat 會讓 traits 被 interests 餓死，改 interleave 保證至少 1 個 trait。
  實作位：`lib/features/partner/presentation/widgets/partner_list_card.dart` `_previewTags()`。

- **D-P4-4 — Heat fallback = 🌡️ 待分析 灰字（latestHeat == null）**
  決定：`latestHeat` 為 null 時 PartnerListCard 顯示「🌡️ 待分析」灰字，不顯示 0 / 空白 / hide 整塊。
  理由：5 件套視覺完整性 + 教學暗示（提示用戶跑分析）+ 語意正確（null ≠ 0）。
  實作位：`lib/features/partner/presentation/widgets/partner_list_card.dart` heat indicator block。

- **D-P4-5 — Banner dismissed flag scope = per-account uid-scoped SharedPreferences key**
  決定：dismissed key = `partner_dedupe_banner_dismissed_$uid`，uid 取自 `Supabase auth.currentUser?.id`。
  理由：多帳戶隔離一致性（A2 invariant）；A 帳戶「以後再說」不外洩到 B 帳戶。
  實作位：`lib/features/partner/data/services/partner_banner_service.dart` + `lib/features/partner/data/providers/partner_banner_providers.dart` (`FutureProvider.family<bool, String uid>`)。

#### A2 後續 follow-up（ship 後另排）

- HS1：Sentry SDK 整合（A2 ship 後再裝，避免污染 ship diff）
- HS2：重做升級覆蓋舊備份（接受 trade-off）
- 2 週後人工評估是否退役 `conversationsProvider` legacy global invalidation

#### 相關 commits（Phase 4，branch `feature/partner-entity-A2-polish`）

`28d0746` 18a delete API · `7585497` 18b 5 件套 + dialog · `6f73208` 14a banner service · `e9a7fcd` 14b banner widget · `e4bbc4f` banner dismiss guard · `782d73a` 15 copy sweep · `30a529d` 16a 砍 @Deprecated HomeContent

---

## ADR #16 — [2026-05-01] Spec 4 Phase 1 — Coach Action Card 取代 ScoreActionHint
**狀態**: ✅ Active（Shipped + cleanup complete 2026-05-02 HEAD `0d7ff06`）

**決定**: 把 `analysis_screen.dart` 上原本由 `ScoreActionHint` 提供的「下一步提示」升級成 `CoachActionCard`，由 app-side deterministic `CoachActionPolicy` 決定每回合練哪個互動能力。9 個 actionType（softInvite / lowerPressureReply / extendTopicStoryFrame / emotionalResonance / rightSizeReply / playfulReply / pausePursuit / preferenceSignal / fitCheck），10 條 top-down 優先序規則。Spec 3 flagged-partner 走 safe-set 子集。

**原因**:
1. 「下一步提示」太被動 — 用戶只看到一句話，不知道在練什麼。CoachActionCard 把「本回合練什麼」做成顯性焦點，每次分析後幫用戶選一個最值得練的互動能力。
2. 走 deterministic policy（非 AI generated）= 可測試、可仲裁、可離線 fallback。Phase 1 不動 analyze-chat schema、不動 prompt、不新增 Edge endpoint，全部在 app 端決定。
3. ScoreActionHint 的 13-keyword meeting-language suppression 是已驗證 product red line，policy 直接繼承並在所有 actionType 上一致地 enforce（不只 softInvite）。
4. Spec 3 dataQualityFlag 已就緒；flagged 時 policy 強制 safe-set + 完全忽略 practiceGoals，避免長期人格資料污染當下對話建議。

**Codex review 7 條 amendments 全納入**:
- 不假 category fallback（沒對到 article 就隱藏 CTA，無 `/` 假 deep link）
- ScoreActionHint 先保留 rollback 安全網；TF smoke 綠後已於 `0d7ff06` cleanup 移除
- 新 code 一律用 `challengeSignal`，不引入 `shitTest` 詞彙到 Spec 4 surface
- TF gate：等 Spec 3 smoke 綠才動 lib/test/
- 6-field card / feature-mirror test 路徑 / Q1-Q5 全鎖

**ship 範圍**:
- 新 lib：`coach_action_type.dart`, `coach_action_card_data.dart`, `coach_action_policy.dart`, `learning_link_resolver.dart`, `coach_action_card.dart`（5 檔）
- 新 test：35 個（31 unit + 4 widget）
- analysis_screen.dart 一處改動（line 3819 swap，加 5 個 import）
- regression sweep 零退化；cleanup 後 full-suite `+638 ~1 -76`，baseline `-76` 不變
- post-review fix `d918888`：補 softInvite meeting/close signal gate + 1.8x 最新回覆判斷
- cleanup `0d7ff06`：移除 legacy `ScoreActionHint` widget + 舊 widget tests + stale comment

**不在範圍**:
- 不改 analyze-chat schema / prompt / OCR
- 不新增 Edge endpoint，不做 AI practice generation
- 不重寫 20 篇 Learning 文章
- softInvite / pausePursuit 沒對應到現有文章 → CTA 隱藏（Phase 1.5 補文章或補 Learning route）
- `ScoreActionHint` cleanup 已完成；Phase 1.5 再評估 softInvite / pausePursuit 文章或 Learning tab 真實 route

**相關文件**:
- `docs/archive/plans/2026-05-01-spec4-phase1-coach-action-card-impl.md` — 實作計畫（Codex APPROVED-WITH-AMENDMENTS）
- `docs/plans/2026-04-30-memory-coach-spec4-coach-action-loop-draft.md` — 早期 brainstorm draft（已 superseded）

**相關 commits（main 線性）**:
`20722d4` Task 1 enum · `cdf3c9d` Task 2 view model · `dda2715` Task 3 resolver · `3294bfc` Task 4 drift guard · `41d9496` review fixes · `2854bcb` Task 5 policy 骨架 · `1ee1d81` Task 6 softInvite · `c96f9e0` Task 7 meeting suppression · `b257d90` flagged whyNow 強化 · `cd844da` Task 8 storyFrame · `bdd9216` Task 9 emotionalResonance · `954346b` Task 10 rightSizeReply · `6ded284` Task 11 tie-breakers + safe set · `7dd7318` cosmetic · `5cad69d` Task 12 widget · `2ca0257` Task 13 wiring

---

## ADR #17 — [2026-05-08] Coach Action Hint v2 — analyze-chat 回傳可接球點
**狀態**: ✅ Active

**決定**: `analyze-chat` 主分析回應新增 `coachActionHint`，由模型在同一次分析裡回傳聊天窗下方卡片需要的「可接球點」。Flutter `AnalysisResult` 解析此欄位，`CoachActionPolicy` 在安全優先序後優先使用 high/medium confidence hint；低信心或缺欄位則回到 deterministic fallback。

**欄位契約**:
- `catchablePoint`：引用或濃縮對方剛丟出的具體球點，必須能在聊天內容找到證據
- `read`：一句話說明這顆球代表什麼，不以 heat score 開頭
- `microMove`：這回合只做的一個小動作
- `avoid`：針對當下對話風險的「先不要」
- `actionType`：沿用 9 個 `CoachActionType.name`
- `confidence`：`high | medium | low`

**原因**:
1. App-side keyword fallback 已能止血，但遇到夜店局、短回、邀約、性張力、情緒測試等複雜情境時，不足以證明「真的看懂聊天」。
2. 這張卡貼在聊天窗下方，位置權重高，第一眼必須引用或濃縮上方對話的具體球點。
3. 不新增第二次模型呼叫，避免成本、延遲與分析判斷不一致；沿用 `analyze-chat` 已讀完整對話的上下文。
4. App 端仍保留安全排序：cold/低熱度邀約、過長回覆、情緒訊號、flagged partner safe-set 不交給模型直接覆蓋。

**不做**:
- 不新增 Edge endpoint。
- 不讓 AI 直接決定所有 action card；AI 只提供 catchable point，policy 仍做 guard 與 fallback。
- 不動 OCR parser / layout / cache。

**驗收**:
- 「在家追劇 看絕命毒師」這類對話，卡片應顯示「她丟出的球：在家追劇 / 絕命毒師」，而不是泛用「先別下定論」。
- 如果 AI 回 low confidence，app 不採用 hint，回 deterministic fallback。

---

## ADR #18 — [2026-05-16] 開場救星扣費改為一律 3 則（取代 per-image surcharge）

**狀態**: ✅ Active（取代 ADR #14 的計費條目）

**決定**: 開場救星扣費由「基本 3 則 + 每張截圖 +2 則（最多 9 則）」改為**一律 3 則**，不論上傳幾張截圖（仍上限 3 張）。

**Eric 拍板於**: 2026-05-16 Discord 對話（Bruce dogfood 反饋 + Codex r2 APPROVED 安全洞修補之後）。

**主要原因**:
1. **效果與張數不線性**：多附幾張圖 AI 看到的「新增線索」邊際遞減；2 張 5 則、3 張 7 則的價格相對品質提升偏貴，會勸退用戶上傳第 2、3 張。
2. **可預期 > 嚴格成本回收**：用戶不容易在送出前計算「3+2+2」這種公式；統一 3 則讓用戶心智簡單，反而更願意上傳截圖、提升 AI 輸入品質。
3. **使用頻率不高**：opener 是「遇到新對象才開」的低頻動作，per-image 收費省下的單次成本相對整體 quota 池微小，但對 UX 反而是負擔。
4. **與品質策略一致**：同步在 system prompt 強化「用戶手填文字 + 無圖」case 的指引（避開「比較喜歡 A 還是 B」式瞎猜），讓無圖路徑也保有最低品質基準。Eric 主動吸收圖片 Sonnet 成本，換取「附圖效果通常較好」可以變成柔性建議而非硬扣費懲罰。

**不做**:
- 不強制截圖（保留 Tab 切換結構：截圖 / 手動輸入）。
- 不改 Tier quota 上限（Free 30、Starter 300、Essential 800）。
- 不動 model 選擇（仍 imageCount>0 或 effectiveTier!=free → Sonnet）。

**實作 commit**: `e27ba03`（同 commit 動 Edge Function `openerCost = 3`、OPENER_PROMPT 新增「沒有截圖、只有用戶手填的文字」段落、Flutter `_estimatedCost` 常數化 + 無圖時柔性副文）。

**前置 commit**:
- `8356dab`（quota bypass 安全洞修補，Codex r2 APPROVED — 必須先收這個再改定價，否則攻擊路徑會搭定價變動順風車）
- `16f01a7`（扣帳決定改由 server-side 條件主導）

**相關文件**:
- `docs/pricing-final.md:166` 已同步
- `docs/cost-optimization.md:55` 已同步
- ADR #14 計費條目已加上「2026-05-16 改」註記指向本 ADR

## ADR #19 — [2026-06-11] analyze-chat 扣費改為全對話字數合併計費（取代逐則計費）

**狀態**: 🟡 Proposed — Eric 拍板 2026-06-11，待 Codex 把關後實作；實作 commit 落地後轉 Active
**修訂**:
- 2026-06-11 Codex r1 = REVISE_REQUIRED（P1: compat fallback 使 server-first 不安全）→ 修規格 #1/#4/#5，新增 #7/#8，強化 recognizeOnly 閘門
- 2026-06-11 Codex r2 = REVISE_REQUIRED（P1: summary/clipped payload 下 N>payload.length 是舊 client 合法路徑，不得當越界全額）→ 修規格 #1 fallback 加 clipped 分支（user-safe floor 1 + log）
- 2026-06-11 Codex 終審 @ `ee20949` = **設計把關通過，無剩餘 P0/P1，實作綠燈**。實作後仍須高風險雙審，APPROVED 前不得稱 dogfood/build safe

**決定**: analyze-chat（手動輸入 + OCR 截圖兩入口）扣費由「逐則 `max(1, ceil(字數/200))` 加總」改為**全對話字數加總 → `ceil(總字數/200)`，整次最少 1 則**。

**起因**: 夥伴 dogfood 抱怨「3 句短訊扣 3 則」違反比例原則——短訊息在現制退化成「1 句 = 1 則」，與實際 AI 成本（input tokens ∝ 總字數）脫鉤。flat-3（分析固定價）已否決：解不了比例原則，且對超長對話虧損。

**效果對比**:

| 場景 | 現制 | 新制 |
|------|------|------|
| 3 句廢話（各 <200 字） | 3 則 | 1 則 |
| 15 句截圖（總 ~300 字） | 15 則 | 2 則 |
| 對方連發 3 張貼圖（OCR 佔位 `[sticker]`） | 3 則 | 併入字數池，幾乎免費 |
| 450 字單一長文 | 3 則 | 3 則（不變） |

**規格定義（8 條，實作必遵守）**:

1. **增量計費改字數差 + 三層 compat fallback**（Codex r1 P1 修訂）：
   - 新 client：送 `previousAnalyzedCharCount`，**過渡期同時保留送 `previousAnalyzedCount`**。
   - 舊 client fallback（缺 char count 但有 `previousAnalyzedCount` = N），分兩種（Codex r2 P1 修訂）：
     - `0 <= N <= payload.length`：用**當次 payload 的前 N 則訊息**加總推回「已分析字數」，只扣後段字數差。
     - `N > payload.length` **且 payload 帶 `conversationSummary` 或 clipped context 訊號**：這是舊 client 長對話摘要壓縮的**合法路徑**（requestMessages 可能只剩最近 10 則但 N=30），不得當越界全額計費。採 user-safe fallback：baseline = 當次 payload 全部字數，本次只扣 floor 1 則，log `legacy_count_exceeds_payload_clipped`。
   - 只有**無 summary/clipped 訊號**、且 N 越界 / 非數字 / 缺失時，才整段全額計費並 **log 告警**。
   - 欄位職責分離：`lastAnalyzedMessageCount` 留給 stale/UI 判斷；新增 `lastAnalyzedCharCount` 專供 billing。**兩者不得混用**。
2. **餘字不結轉**：每次分析獨立 `ceil`、整次最少 1 則。不做跨次累積池。
3. **0 字輸入 → 400 拒絕**，不扣額度（與現行空白輸入提示一致）。
4. **字數 = UTF-16 length**（JS `String.length` ≡ Dart `String.length`），**禁止單端改 grapheme**。計算對象 = sanitized + trim 後的 payload content；**不做 NFC/NFD normalization、不移除 zero-width，零寬字元照算**。必補 JS/Dart mirror tests（同字串集兩端結果一致）。1 emoji ≈ 2 字（`pricing-final.md` 舊文案「1 emoji = 1 字」於實作 commit 一併修正）。
5. **部署順序 server 先、App 後**：安全前提是規格 #1 的推導式 fallback——舊 client 送舊欄位，server 推回 baseline 只扣字數差，與舊 client 的「只算新增訊息」預覽方向一致（預覽逐則高估、實扣字數制便宜）。⚠️ 若 fallback 做成「缺新欄位即整段全額」則 server-first **不安全**（舊 client 補 5 字可能被扣 11 則），此設計已於 r1 否決。
6. **測試矩陣**必含 `my_message` / `optimize_message` 路徑、retry 同 `analysisRunId` 不重複扣、fallback 各一案（新欄位 / 舊欄位推導 / **clipped+summary N 越界 floor 1** / 無訊號全缺失全額+log）。
7. **`quotedReplyPreview` 不計費**：billing 只看 `content`（維持現狀）；quoted preview 仍進 prompt 與 server total length limit，但**明確不入字數池**，兩端同此定義。
8. **單一字數 helper 兩端共用**：client/server 各自只有一個 char-count 函式，billing 與預覽都走它。persist 的 char baseline 必須對應**當次送出的 requestMessages**，不是分析完成時 repository 裡的最新 messages（避免分析中新進訊息造成 baseline 漂移）。

**同批修的 3 個既存 bug**:

1. **增量單位混用**：client 存「訊息數」（`analysis_screen.dart:817`），server 減「計費則數」（`index.ts:~5308`）→ 含長訊息的對話繼續分析會多扣。新制統一為字數差後修復——**前提是規格 #8**（兩端同一 helper + baseline 對應 requestMessages），否則只是把混用搬到字數層。
2. **空訊息分歧**：server 空白訊息 +1 則、Dart 跳過 → 預覽 < 實扣。新制合併計算後消除。
3. **`previousAnalyzedCount` 信任 client**（Hive 本地上報不可驗）→ 竄改可永扣 1 則。月額度封頂，標**已知接受**，不在本批修。

**UX 配套（與公式同批）**:

- 預覽改**即時數字**：分析按鈕顯示「本次將扣 X 則」，扣費前可見（計費 UX 原則：用戶能接受貴、不能接受驚訝）。
- 文案主角是「**每按一次分析，最少扣 1 則**」——follow-up 補一句再分析仍扣 1 是用戶真實痛點；「200 字 = 1 則」換算率次要。
- 引導 batch：「補充多句後一起分析較划算」。
- 對夥伴的說明直接用貼圖場景對比（3 則 → 幾乎免費）回應比例原則。

**已知接受（ADR 明寫，不再翻案）**:

- **vision 成本倒掛**：截圖走 Sonnet vision，input 成本高於純文字，但不加圖片附加費（與 ADR #18 同邏輯：可預期 > 嚴格成本回收）。
- **每次分析最少 1 則 floor**：有成本基礎——增量計費只少扣額度，server 每次仍整段重送 Claude。
- bug 3 的 client 信任問題（見上）。

**不做 / 不動**:

- Opener 不動（ADR #18 一律 3 則）。
- `recognizeOnly` 維持免費；上線前補兩道閘：①月餘額 >0 才可用 ②獨立日上限 ~30 次/日（現制零防護）。日上限必須是 **server-side atomic per-user/day gate，且在 Claude vision 呼叫前擋**；現有 `rate_limiter.ts` 尚未接入此路徑，**不得只靠 client 端限制**。
- 額度數字（Free 30 / Starter 300 / Essential 800）不動，等 dogfood 真實扣費分佈數據再校。
- 三 tier 共用同一扣費管線，改一處全 tier 同步。

**實作範圍**: server `countMessages`（`analyze-chat/index.ts:2325`）+ client 鏡像 `message_calculator.dart`，兩端同 commit。policy 變動同 commit 更新 `pricing-final.md` + `cost-optimization.md`。

**風險分級**: 高風險區（quota + Edge schema + AI cost）→ 實作後必過 Codex 雙審，APPROVED 前不得稱 dogfood/build safe。

**相關文件**:
- `docs/pricing-final.md` 訊息計算邏輯段（實作 commit 同步改寫）
- `docs/cost-optimization.md`（實作 commit 同步）
- ADR #18（opener flat-3，本 ADR 不動其範圍）
