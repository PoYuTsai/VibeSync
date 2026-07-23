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

**窄例外（2026-07-16，ADR #22）**: Essential「我幫你修」為避免回應中斷後重複扣額度，伺服器提供 7 天的 AI 生成潤飾句／理由重播，並由每小時排程清除逾期 live-table 列（最晚約 7 天 + 1 小時）；備份／PITR 副本依 Supabase 供應商週期處理。ledger 不另存原始草稿或完整對話輸入，但生成文字仍可能重述或反映草稿、姓名與對話內容；這是對「伺服器不保留對話歷史」的限時、結果型窄例外，不得擴張成對話歷史庫。

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
**狀態**: 🟡 Partially superseded（Starter / Essential 仍有效；Free analyze-chat 由 ADR #23 取代）

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
- 2026-06-11 PM **r3 = 夥伴新需求修訂（見下方 🔴 r3 區塊，覆寫部分 r2 規格）**。線數計費案否決、改字數參數 + 區間報價 UX；屬參數修訂非架構重寫，仍須 Codex 把關後實作
- 2026-06-11 晚 **r3 定案 = Eric 拍板 OPEN 三條 + 4 條邊界規則（見 🟢 r3 定案區塊），規格凍結**。待 Codex r3 設計把關 → 新 session 實作 → 實作雙審

**🔴 r3 修訂（2026-06-11 PM · 夥伴 dogfood 新需求 · 本區塊覆寫下方 r1/r2 衝突處，實作以此為準）**

**起因**: 夥伴回饋「200 字/則太便宜、單位與感知脫鉤」；並要求預覽**只報區間、不報精確值**（精確報價費工且易生爭議）。**線數計費（對象丟幾條線扣幾則）經討論否決** —— LLM 切「線」非確定性、無法 pre-charge 預覽、且會重蹈「逐則計費」的比例原則問題。結論：**維持字數制，只改參數 + 預覽 UX**。

**新公式（覆寫 r2 規格 #2 的 200 與 floor）**:

```
則數 = clamp( ceil(計費字數 / 40), floor = 1, soft_cap = 10 )

1~40 字      → 1 則
41~400 字    → ceil(字數/40) = 2~10 則
401~2000 字  → 一律 10 則（緩衝帶，免費送，不額外扣）
2001~4000 字 → 一律固定 20 則，需用戶確認後才扣（r3 定案 #1：乙案，固定值非第二段斜率）
4001+ 字     → 拒絕分析「內容過長，請分批分析」，不扣費（夥伴 2026-06-11 終確認補的硬上限）

（整數閉區間，Codex r3-P2 修訂：原 40/400 邊界重疊已消除；0 字輸入沿用既有「空白不扣費」規則）

**4000 字硬上限（夥伴終確認 · 補洞）**：`pricing-final.md` 原寫「超過 5000 字提示分批」但**從未實作**（code 已 grep 驗證無此限制）——原 r3 緩衝帶等於上不封頂：貼 5 萬字仍只扣 20 則、AI 成本無上限。定 4000（= 2×2000，「最多等於兩次滿額分析」）：server 守門 reject + client 本地預警，同兩層模式；**對新舊 client 一視同仁 reject、不扣費**（user-safe，legacy cap 10 路徑僅適用 2001~4000）。實作 commit 同步把 pricing-final 的 5000 改 4000。屬風險收斂（關成本洞、無新計費路徑），不重開設計輪，**實作雙審一併驗收**。
```

**預覽 UX（覆寫 r2「分析前即時精確數字」）**:
- 分析前**不算精確值**，顯示固定區間文案：「依對話複雜度使用 1–10 **則**」（r3 定案 #3：單位沿用「則」，夥伴原文「枚 Token」否決——避免與 AI token 成本混淆）。→ 免 client pre-flight 字數計算、免兩端預覽 mirror 爭議。
- 分析後顯示 server 算出的**實際消耗則數**。
- 「絕不驚訝」原則改由「區間上限 = soft_cap 10」保證：正常分析實扣必 ≤ 10、落在告知區間內；唯一例外 >2000 字必先跳通知才可超 10。

**字數來源（簡化）**:
- 手動輸入文字 + 對話截圖 OCR 文字，**統一同一條 `ceil(字數/40)`**。
- **刪除「純圖片 = 1 則」特例**：純圖片（食物照/貼圖/迷因）在 server OCR 分類即被判 `gallery_album`/`social_feed` → `importPolicy: reject` 擋下，根本不進計費（`index.ts:2452-2474`）。「用戶傳純圖片沒意義、要截圖才有分析」已由現有分類驗證落實。
- recognizeOnly 免費識別階段不變（0 則，`quota_usage.ts:27-78`）；只有付費分析套新公式。

**實作影響（相對 r2 已寫的 `billing.ts`）**:
- `CHARS_PER_MESSAGE_UNIT` 200 → 40。
- `billedUnitsForChars` 加 `soft_cap = 10`。
- 新增 >2000 字額外計費通知路徑（行為見 OPEN-1）。
- r2 三層 compat fallback / char baseline 機制**保留**（增量仍走字數差）。
- client 預覽改靜態區間文案 → 放寬規格 #8「預覽走同一 helper」的**預覽**部分；但 **baseline char helper 仍兩端共用 + mirror test 不變**。
- 風險等級不變（高風險：quota/計費），仍須 Codex 把關 + 雙審。

**🟢 r3 定案（2026-06-11 晚 · Eric 全數拍板 · OPEN 清零 · 規格凍結）**:

原 OPEN 三條結案：

1. **>2000 字 = 乙案，一律固定 20 則**。`ceil(字數/40)` 在 >2000 起跳即 50、必超 cap 20，故第二段實效為固定值——確認框可顯示精確「本次將扣 20 則」，無區間無驚訝。用戶側帳算得攏：拆兩批（各 ≤2000）= 10+10 = 20，一次過也是 20，怎麼選都不吃虧；分批引導純屬品質建議（超長輸入分析品質下降），非省錢套路。
2. **月額度 30/300/800 不調**。「燒快 5 倍」係只看除數（200→40）、忽略 soft_cap 10 的誤導結論。實際：截圖 OCR 為主流型態（多行）在新制更便宜（舊制逐行無上限、12 行=12 則 vs 新制 ≤10）；僅手打單段長文路徑變貴。各層保證分析次數**（以正常 ≤2000 字分析計，Codex r3-P2 修訂）**：Free 30→至少 3 次/月（舊制 12 行截圖只夠 2 次）、Starter 300→至少 30 次、Essential 800→至少 80 次，全部高於舊制。若全做 >2000 confirmed 分析則為 Starter 15 次 / Essential 40 次——**pricing 文案與 App Review 說法不得引用保證次數而不帶 ≤2000 前提**。**部署門檻（原 OPEN-2）解除**。上線後觀察真實分佈再議。
3. **單位沿用「則」**，不引入「枚」「Token」。預覽文案：「依對話複雜度使用 1–10 則」。

同日補拍的 4 條邊界規則：

4. **額度檢查先於 >2000 確認框**。順序：算出本次需要則數 → 既有額度/每日上限檢查 → 不足走既有額度不足 UI（不出確認框）→ 足夠才跳「本次將扣 20 則」確認。推論：Free 日上限 15 < 20 → Free 永遠無法單次做 >2000 分析，自然引導分批（跨日）或升級——不加新機制，屬漏斗設計意圖。
5. **>2000 確認 = client 預警 + server 守門兩層，確認旗標必綁 payload + idempotent**（Codex r3-P1-3 修訂）。recognizeOnly（免費）後 client 已持有全部 OCR 文字 → 本地算字數、>2000 先跳確認再送（零額外往返）。server 為 authoritative：>2000 且請求無有效確認 → 不分析不扣費，回 `confirmation_required` + 實際則數 + `billableChars`。**確認綁定**：client 重送時帶 `confirmedOvercharge: { billableChars }`（或 payload hash）；server 重算後不符（確認後內容又改過）→ 視同未確認，回新的 `confirmation_required`，絕不拿舊確認扣新內容。**Idempotency**：confirmed >2000 請求帶 idempotency key，同一確認重送/雙送絕不重扣 20。扣費只發生在有效確認的呼叫，無「先扣再退」髒狀態。（Codex 終審實作建議：綁定**優先用 payload hash**，`billableChars` 留作顯示/比對——只綁字數偵測不到「同字數不同內容」。）
6. **新舊 client 以 capability 訊號硬區分；legacy cap 10 有明確 precedence**（Codex r3-P1-1/P1-2 修訂）。
   - **Capability contract**：新 client 所有 analyze 請求**必送 `billingProtocolVersion: 3`**（不依賴 baseline 欄位推斷——首次分析本來就沒有 `previousAnalyzedCharCount`，不得因此被誤判為舊 client 而繞過 20 則確認）。「舊 client」定義 = **無 capability 訊號**的請求，僅此類才允許走 legacy 路徑。新 client 無確認送 >2000 → 一律 `confirmation_required`，無例外。
   - **Legacy 計算順序（precedence，先到先擋）**：(a) 先 resolve r2 三層 fallback；(b) clipped 分支（N>payload.length + summary/clipped 訊號）**永遠 floor 1 + log `legacy_count_exceeds_payload_clipped`，不被任何 cap 覆蓋**——cap 10 是上限不是下限，不得把 1 抬成 10；(c) 只有可計算 diff/全額、且結果 >10 的 legacy 路徑，才以 soft_cap 10 收 + log `legacy_over2000_capped`。與 r2 user-safe 哲學一致：舊 client 永遠往便宜方向錯。log 歸零後可拔 legacy 路徑。
7. **soft_cap 每次分析各自算（非整段對話累計）**。follow-up 增量走字數差，通常 1~3 則；增量罕見 >2000 同走確認路徑，規則統一。否決累計制理由：扣滿 10 後永久免費 = 收入與 AI 成本脫鉤，且多一個跨端同步狀態。
8. **範圍與字數定義鎖定**：ADR #19 只動 analyze-chat；開場救星維持一律 3 則（ADR #18）、Coach 1:1 計費不動（釐清不扣、正式建議 1 則）。「計費字數」定義沿用 r2 已過終審版本（UTF-16 code units、不 normalize、`quotedReplyPreview` 不計費），本輪只改除數 200→40 + 加 cap，不重開定義。

**衍生獨立立項（不在 ADR #19 範圍）**：夥伴「分段格式」回饋 = AI 推薦回覆改「一球一回」結構（對方丟 N 條線 → N 則對應回覆、各自複製鈕、用戶自選引用哪條）。屬 Edge schema 變更 + UI 改版，**與本 ADR 分批、各自過 Codex 把關**，已記入測試期候選清單 #12。注意其與 style-pair 主 prompt byte-for-byte 鎖的衝突須屆時重審。


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

## ADR #20 — [2026-07-15] analyze-chat 採獨立分析紀錄，不再用長逐字稿收納

**狀態**: 🟢 Active decision／2026-07-16 修訂實作終審通過 — Eric 拍板

**背景**: Sam 指出一般使用者不會用「一段一段的邏輯」整理聊天，且同一對象可能從交友軟體轉到 LINE、IG 或 Threads；Bruce 指出既有長 OCR／長逐字稿會越疊越亂，收納盒真正要解的是疊加與找回問題。Eric 拍板融合兩者：保留目前片段的即時感，舊分析改成可按對象與平台找回的獨立案例。

**決定**:

1. 一次成功分析保存一筆 self-contained record，包含當時訊息 deep copy、AI snapshot、分析邊界、完成 key、內容 revision、熱度／階段與來源平台。
2. 一次分析請求就是一個獨立 fragment／Conversation。使用者一次選取 1–3 張截圖形成一批；第一次分析前若重新選圖，必須整批取代目前草稿，不得逐則追加或把零散內容拼成逐字稿。成功後立即關閉並收進右上分析紀錄，之後的新輸入必須建立新的 Conversation id（同一 partner），不得接回上一筆。
3. 成功 fragment 的聊天內容唯讀。同內容、同邊界的付費回覆刷新可明確覆寫該 archived record；completion replay 只重放，不製造重複案例。任何內容 revision 改變、邊界延伸或已刪除 record 都不得用刷新路徑復活。
4. `metVia` 存在 partner scope；`sourcePlatform` 在每筆成功分析時 snapshot。平台由使用者選擇，OCR 不推測。
5. owner scope 進入 key 與 record body，使用既有 AES 加密 `settingsBox`；每筆獨立 key、無 FIFO、無自動 pruning。刪除對話以 cleanup marker＋tombstone 防止中斷或延遲寫入復活資料。
6. 完整覆蓋單一 Conversation 的唯一 record 被刪除時，走 Conversation 的 owner-scoped 安全刪除與 records/state/source cascade；舊制同一 Conversation 多筆或 partial records 只刪指定 record，避免誤刪其他歷史。partner `metVia` 不因刪一條 conversation 而消失，並跟隨 partner merge／delete lifecycle。
7. 原有整段 conversation archive 保留並改稱「已收起的對話」，只承接無法安全視為單一完整 record 的舊制資料；已由完整獨立 record 承接的 Conversation 必須從該入口排除，避免重複顯示或刪除後看似復活。
8. OCR `recognizeOnly` request 不帶目前或歷史訊息，只保留必要的 canonical Partner name 做身份核對；舊批次摘要在整批取代時一併清除。正式分析仍只使用這次 fragment 的內容，封存紀錄不回流成模型輸入。本案不改 Edge schema、quota 或 billing。
9. 對象頁右上封存圖示是分析紀錄的主要入口；分析頁保留同一入口作捷徑。「已收起的對話」降為封存抽屜內的次入口，不再佔用對象頁主內容。
10. `sourcePlatform == null` 的紀錄保留在「全部」，但 UI 不顯示「未分類」badge／filter，也不得由 `metVia` 或 OCR 猜測。只有至少兩種已知平台時才顯示平台篩選。
11. 清單不常駐顯示刪除；點入唯讀快照後才可從右上管理選單刪除。詳情必須讀 frozen messages／AI snapshot，不重新分析，並保留回覆引用脈絡。
12. 舊版已疊加資料不自動猜測或切割；它可以保守留在舊入口，但不得再顯示「分析新增內容」或逐則輸入入口。任何已有完成證據的 Conversation 都不得再追加或重跑，後續內容一律另建獨立 fragment。
13. 48 小時跟進提醒以 partner 為單位。刪除單一 fragment／Conversation 時，只有該 partner 已無其他 Conversation 才取消提醒；刪除舊片段或放棄空白新片段不得誤取消其他片段排定的提醒。

**後果**:

- 優點：避免逐字稿越疊越亂；跨平台仍能以同一對象找回；完成後唯讀使畫面、AI snapshot 與封存內容維持一致；刪除與 owner 隔離可被單元測試鎖定。
- 代價：本地紀錄沒有自動上限，容量交給使用者手動管理；更換裝置不會自動同步這批 local-only record。
- 舊 `2026-07-14-analyze-chat-round-archive-*` 文件只保留歷史／程式地圖，產品與資料設計均已 superseded。

**詳細實作與驗收**: `docs/plans/2026-07-15-analyze-chat-independent-records-implementation.md`

**審查證據**: `docs/reviews/2026-07-15-analyze-chat-independent-records-codex-review.md`；`flutter analyze` 0 issue，148 項 targeted unit／widget tests 全數通過。

## ADR #21 — [2026-07-16] 分數只描述對方在當次互動的文字投入

**狀態**: 🟡 Partially superseded — 語意仍有效；分數校準由 ADR #26 更新

**背景**: Dogfood 將 4 則友善回覆得到 65 分解讀成「關係健康快速升溫」，因而質疑缺少樣本量約束。現有 AI 規則實際只根據回覆長度、emoji、主動提問與話題延伸，評估對方在這次對話中的投入訊號；它不知道雙方熟識程度，也不是在估計整段關係進度。

**決定**:

1. （2026-07-17 由 ADR #26 局部取代）仍不加入樣本量降權；但完成回應的顯示分數改為原分九折後向上取整。短對話的分數仍只描述這一輪可觀察到的投入。
2. 使用者可見名稱統一為「對方這次的投入度」，短名為「本次投入」；四檔為「投入偏低／有在回應／投入明顯／高度投入」。
3. 顯示分數時明示「只反映這次互動中的文字訊號，不代表關係進度。」不得再由分數直接宣告關係升溫、建議見面或其他關係結論。
4. 歷次分數可以畫成每次互動投入度的變化，但每個點仍只代表當次互動；GameStage、使用者目標中的「維持熱度」與練習室溫度計是不同概念，不在此決策範圍。

**不動（除 ADR #26 的完成分數校準外）**: AI prompt、模型原始評分規則、門檻、quota、既有分析資料與歷史分數。

## ADR #22 — [2026-07-16] Essential「我幫你修」成功固定扣 1 則

**狀態**: 🟢 Active — Eric 拍板

**背景**: 草稿潤飾原本共用 analyze-chat 的全對話字數計費。即使使用者只是修一句草稿，也可能因帶入聊天脈絡而扣 10 則、要求確認 20 則，與「幫我修一句」的產品感受不一致。

**決定**:

1. `optimize_message` 只限 Essential；每次伺服器成功產生非空、可用的 `optimizedMessage.optimized`，固定扣 1 則。
2. 脈絡長度不提高扣費，也不進入 2001–4000 字的 20 則確認；既有 4000 計費字元上限、單則訊息、草稿長度與 request body hard cap 全部保留。
3. AI、解析、格式驗證、額度 settlement 或網路前置失敗皆不扣；日／月額度仍在模型前預檢，並在原子扣費時再次檢查競態。
4. 新 App 每次 logical request 傳 UUID。伺服器把第一個成功結果與 `increment_usage(..., 1)` 放在同一交易；相同 user／request／input 重送直接回第一次結果且不重扣，不同 input 重用 request id 則拒絕。
5. 測試帳號仍免扣，但可寫入同一結果 ledger 以保持重送結果一致。舊 App 未帶 request id 時維持相容並固定扣 1，但不具新 ledger 的重送保證。
6. 一般分析、圖片分析、Opener、Coach 與 `my_message` 的既有計費不變。
7. 相同請求只在 7 天內可免費重播；Edge 查詢逾期即視為新請求。`pg_cron` 每小時清除逾期 live-table 列（最晚約 7 天 + 1 小時）；備份／PITR 副本依 Supabase 供應商週期處理。migration 若無法啟用排程則 fail closed，不接受 live table 無界保留。
8. ledger 只允許 AI 產生的 `optimized` 與 `reason` 欄位，DB constraint 拒絕另存原始草稿、完整對話輸入、usage、telemetry 或任何額外欄位；生成文字仍可能重述輸入內容。App 用同一 hash 綁定請求內的草稿重建 `original`。功能獨立同意、App 內 AI 隱私頁與 repo 隱私政策來源已更新；**部署前仍須把新版政策發佈到 `https://vibesyncai.app/privacy` 並核對 App Store Connect 揭露，否則不得上線本功能。**

**部署要求**: 必須先套用 `20260716170000_optimize_message_fixed_charge.sql`，再部署 `analyze-chat`，最後發佈含 request id wire contract 的 App build。這是 quota／Edge 高風險變更，Codex `APPROVED` 前不得宣稱可供 dogfood。

## ADR #23 — [2026-07-16] Free analyze-chat 固定使用 Sonnet 5

**狀態**: 🟡 Partially superseded — Free 固定 Sonnet 5 仍有效；付費路由由 ADR #24 更新

**決定**:

1. Free `analyze-chat` 不再依首次、長度、冷淡或複雜情緒分流，所有分析固定使用 `claude-sonnet-5`。
2. （2026-07-17 由 ADR #24 取代）Starter / Essential 與其他既有 Sonnet 主路徑已升級為 Sonnet 5；其他 Free AI endpoint 仍以各自實碼路由為準。
3. 品質優先於舊的 70% Haiku 成本假設，但月/日額度、per-user rate limit 與請求 hard cap 仍是強制上限。
4. logger 以 Sonnet 5 launch price 計價：input $2 / 1M tokens、output $10 / 1M tokens，同 token mix 為 Haiku 4.5 的 2.5 倍。此價格只到 2026-08-31，到期前必須重新核價。
5. 放量前以 `ai_logs` 監看 Free 每次成功成本、每日總成本、cache hit 與 Sonnet 5 → 4.6 fallback 比例；不再沿用「Free 100% Haiku」的毛利預估。

**驗證**: `analyze-chat/index_test.ts` 鎖定 Free 路由；`logger_test.ts` 鎖定當前 launch price 與 2.5 倍成本比。

## ADR #24 — [2026-07-17] 既有 Sonnet 主路徑統一升級 Sonnet 5

**狀態**: 🟡 Partially superseded — 第 1／2／4 點仍為歷史基線；第 3 點由 ADR #28 取代

**決定**:

1. 所有原本以 `claude-sonnet-4-6` 為主模型的 production 路徑改用 `claude-sonnet-5`：Starter／Essential `analyze-chat`、付費或圖片 Opener、圖片分析與 repair、付費 Coach／Follow-up，以及 Practice 的付費 Claude failover。
2. `analyze-chat` 降級鏈維持 `sonnet-5 → sonnet-4-6 → haiku`；4.6 仍可供 test account 強制模型與歷史成本計算使用，不得誤刪。
3. 這不是「所有請求一律用 Sonnet 5」：Coach／Follow-up／Practice 的 Free Claude 路徑與 Keyboard 仍維持 Haiku；Practice 的第一供應商仍是 DeepSeek。這些路徑若要升級，必須另案評估成本、延遲與 fallback 預算。
4. 不修改 prompt、quota、扣費時機、response schema 或 rate limit。Sonnet 5 launch price 只到 2026-08-31，屆期前依 `ai_logs` 的實際 token、cache hit、fallback 與每日總成本重新決定模型策略。

**驗證**: `analyze-chat/index_test.ts` 鎖主路由與降級鏈；Coach／Follow-up／Practice 測試鎖 tier 路由；Edge 全套與 Flutter analyze/test 在提交前執行。

## ADR #25 — [2026-07-17] Free analyze-chat 固定提供延展＋調情雙風格

**狀態**: 🟢 Active — Eric 拍板作為 1.0.1 Build 333 起的產品基線（Build 332 誤由舊 main 建置）

**決定**:

1. Free `analyze-chat` 每次回傳 `extend`（延展）與 `tease`（調情）兩種可比較回覆；共鳴、幽默、冷讀仍為 Starter／Essential 完整五種的升級差異。
2. 串流 prompt 只要求這兩種，server 後處理也只允許這兩種；不靠 client 隱藏來實現權益。
3. 分析結果下方繼續顯示完整五種的升級入口，Paywall 對照表明示 Free 有 2 種。
4. 這個調整不擴大 Free Opener；Opener 仍僅 `extend`，避免把 analyze-chat 的轉換實驗誤帶到另一個產品契約。

## ADR #26 — [2026-07-17] 投入度完成分數統一九折並向上取整

**狀態**: 🟢 Active — Eric 拍板作為 1.0.1 Build 333 起的校準基線（Build 332 誤由舊 main 建置）

**決定**:

1. 對方這次的投入度完成分數改為 `ceil(AI 原分 × 0.9)`，並限制在 0–100；例如 82 轉為 74、100 轉為 90。
2. 校準只在 server 完成回應後處理執行，不改 prompt、AI 原始推理、風格選擇、安全 fallback 或 quota。
3. 新分析顯示與存檔都使用校準後分數；既有本地歷史不批次重寫，避免無法還原的資料遷移。

**驗證**: 純函式測試鎖定 82 → 74、65 → 59、1 → 1、0 → 0、100 → 90；三條 analyze 完成路徑共用 `postProcessAnalysisResult`。

## ADR #27 — [2026-07-17] OCR 每次開啟重播滑動教學，長等待顯示狀態串流

**狀態**: 🟢 Active — Eric 拍板作為 1.0.1 Build 333 起的 OCR 等待體驗（Build 332 誤由舊 main 建置）

**決定**:

1. OCR 確認視窗每次開啟 350ms 後，都自動播放一次「右滑→我說、左滑→她說」示範；不再因 device-level seen flag 變成只有首次可見。使用者開始滑動／編輯時立即取消，reduce-motion 維持靜態圖例。
2. OCR request 仍是單一 `recognizeOnly` HTTP 請求，不傳回中間文字或分析結果。Client progress stream 在長等待時依序切換「AI 讀取圖片」、「辨識訊息內容」、「校對說話者」、「整理辨識結果」，response 到達後取消所有後續 timer。
3. 這是等待狀態，不是偽造的精確百分比；不改 Edge schema、OCR prompt、quota、timeout 或解析結果。

**根因**: commit `774ff49f` 將原本每次開啟的動畫改為 device first-run only，所以不是動畫程式被刪除，而是看過一次後被永久抑制。

## ADR #28 — [2026-07-18] 除 Practice 外的客戶可見 Claude 主路徑統一 Sonnet 5

**狀態**: 🟢 Active — supersedes ADR #24 第 3 點；Practice 例外由 Eric 明確確認

**決定**:

1. Free／付費 Analyze、Opener、Coach／Follow-up、Keyboard、OCR／圖片分析，以及 quick／full 相容路徑的 production primary 全部使用 `claude-sonnet-5`。
2. Sonnet 5 request contract 必須同步處理：預設 thinking 明確關閉（或由特定 OCR contract 明確指定）、可見 text blocks 合併、`refusal`／`max_tokens`／`model_context_window_exceeded` fail closed，並以 request-level deadline 約束 repair／fallback 總等待。
3. `analyze-chat` 保留 `sonnet-5 → sonnet-4-6 → haiku`，但舊模型只處理 timeout、429、5xx 等真正上游中斷；模型已回覆但截斷、拒答或 context window 不足時不得藉 fallback 改變語意或誤扣額。
4. Practice 不改主路由，仍是 DeepSeek-first；依 tier 決定的 Claude failover／reviewer 維持既有行為。測試用 forced model、歷史 logger model id 與 OCR benchmark 註解不構成 production primary。
5. 沒有 durable requestId＋原子 result replay 的一般分析／OCR 不做 client 背景自動重送；只有具該能力的 optimize-message 可沿用同一 requestId 自動重試。
6. Keyboard 使用 24 秒 request-entry deadline、20 秒 generation budget（含一次 repair）、4 秒 settlement reserve、30 秒 iOS client timeout與 45 秒 DB lease；只有確定 settlement 尚未開始的 failure 才 owner-bound release claim。
7. Sonnet 5 launch price 只到 2026-08-31。現有 `ai_logs` 尚未涵蓋 Coach／Follow-up／Keyboard token usage，管理端總成本會低估；補齊前不得宣稱成本 dashboard 完整。

**已知邊界**: Coach／Follow-up 尚未具 durable requestId／結果 replay；扣額完成後若 response 遺失，手動重送可能再扣。這是獨立 exactly-once 專案，不以本輪模型切換假裝解決。

**驗證**: Production route source audit；Analyze、Coach／Follow-up、Keyboard、Practice Edge 全套；Flutter full test／analyze；iOS Keyboard 最終仍需 TestFlight 真機驗證 timeout 與 same-request replay。

## ADR #29 — [2026-07-21] Coach 1:1 exactly-once 帳本沿用 ADR #22 範本，lease 唯一偏離改 90 秒

**狀態**: 🟢 Active — 教練統一案 Phase C

**決定**:

1. `coach_requests` 帳本與 claim/settle/release/cleanup RPC 結構 1:1 照抄 keyboard（ADR #22）；唯一參數性偏離＝DB lease 45s→**90s**，因 coach 生成含最多 3 次 attempt 重試（75s generation budget），45s lease 會在正常生成中被併發請求奪走。
2. `result_json` 狀態一致性 CHECK 不用 keyboard 的 `jsonb_build_object` 精確等於（coach card 15 欄位不可行），改**白名單減鍵法**：envelope 五鍵＋card 欄位逐鍵減除後必須等於 `'{}'::jsonb`；同組條件在表 CHECK 與 settle RPC 前置驗證各出現一次。
3. `requestId` 缺席（null/undefined）＝完全不觸帳本、今日路徑 byte-for-byte 不變；generation 層以選填 `settleResult` dep 注入，未注入即舊 deductCredit 路徑。
4. settlement 失敗（帶 code 的回應）絕不 release claim——commit 結果可能曖昧；只有已知 settle 前失敗（生成失敗等 500）才 owner-bound release。

**已知邊界**: input_hash canonical 只含 userId/userQuestion/sessionId/activeSessionTurns/forceAnswer/scopeKey/lifecyclePhase；recentMessages 等上下文欄位變動不觸發 mismatch（同題重問視為同 identity，設計取捨）。

**坑**: Postgres `+ -` 優先級高於 `->` 等具名運算子，`x -> 'card' - 'key'` 會解析成 `'card' - 'key'`（42725）；jsonb 取鍵後減鍵必先括號。deno 字串測試抓不到，真 PG 才爆。

**驗證**: deno coach-chat 132 綠；Phase B vs HEAD byte-identity（generation 六 fixture＋handler legacy 429）；prod live smoke 五態（fresh／replay 同 generatedAt／mismatch 409／legacy 200／streaming 恰一 done）；Codex adversarial 審查另記。

---

## ADR #30 — [2026-07-21] Release preflight 不再要求手動 bump pubspec build 號

**狀態**: 🟢 Active

**背景**: 「Release to App Stores」實際打包以 `--build-number=github.run_number` 蓋號，pubspec 的 `+N` 從未被 release 流程讀取；但舊 preflight 要求 pubspec 版本 byte-equal `APP_VERSION+run_number`，導致每次手動觸發前都得先 bump 一個 commit，忘了就紅（run #339 即此因）。Eric 的使用習慣是隨時手動觸發，此檢查只剩絆腳石。

**決定**: preflight 改為只驗 pubspec 版本**前段**（marketing version，如 `1.0.1`）等於 workflow `env.APP_VERSION`；build 號完全交給 run_number（單調遞增，不會倒退或撞號）。pubspec `+N` 自此與 release 無關，任何 main 上的 ref 隨按隨過。

**保留的守門**: 版本前段不一致仍紅——升版時 `release.yml` 的 `APP_VERSION` 與 pubspec 前段必須一起改，防止用舊 ref 誤發新版號（原「stale source」守門的真正價值所在）。

**影響**: TestFlight build 號中間會有空洞（失敗的 run 也吃編號），正常現象非事故。

---

## ADR #31 — [2026-07-24] Opener Free 解鎖三型（contract v2）＋新話題破冰腦力（固定 3 則、exactly-once）

**狀態**: 🟢 Active — 實作完成，待 Codex 審查與部署

**取代**: ADR #7 條目 4「Free 只有延展」的 Opener 部分（analyze 的 Free 兩型維持 2026-07-17 決定不變）。

**決定**:

1. **Opener contract v2**：新 App request 帶 `openerContractVersion: 2`，Free 恰好解鎖 `extend`／`humor`／`tease`、鎖 `resonate`／`coldRead`；缺席／`1` 視為 v1（舊 App Free 維持 legacy `extend` 單卡），非法型別在 rate limit／模型／扣費前 400。模型仍固定產五種，差異只在 server 權益投影；v2 成功前先過五種 completeness gate（一次既有 format repair，仍不全 502 不扣）。response 帶 server 權威 `access` metadata，client 不得只靠卡數猜 tier；舊 cache 讀取時依現行權益重投影，無 Hive migration。
2. **新話題（`mode: new_topic`）**：素材＝對象作戰板＋關於我＋情境 enum（`went_cold/after_date/stuck/warm_up`，無自由輸入），至少一類非空否則 422 不扣。模型恰好五題（direction/openingLine/whyItWorks/nextMove），恰一題推薦；成功固定扣 3 則。所有 tier 都生成五題，Free 由 server 投影只回最推薦一題（另四題文字不出 server、不入帳本）。限流 scope `new_topic`＝3/分、30/日。
3. **Exactly-once**：`new_topic_requests` 帳本沿用 ADR #22 範本（claim/lease/settle/replay、server-keyed HMAC `NEW_TOPIC_REPLAY_HMAC_KEY`、24h window）；參數性偏離＝lease 65 秒（45s generation deadline＋5s settlement reserve）、固定 cost 3。settle 同 transaction 扣額＋落結果；transport 結果不明絕不 release；handler 永遠回 settlement stored result。
4. **成本**: Opener Free 1→3 型不增模型 token 成本（本來就產五種）；New Topic Free 也產五題是為了推薦題真實且付費品質一致。

**坑**: contract version 不入 opener input hash（同輸入跨版本重試仍 dedup）；`MODEL_RATE_LIMITED` 429 永不帶 quota keys（防誤開 paywall）；Free v2 之後「任何 non-extend 內容＝paid」的 client 判定失效，legacy fallback 只能看 paid-only keys（`resonate`/`coldRead`）。

**驗證**: analyze-chat Deno 全套 710 綠＋new_topic payload/billing/prompt/source 41 綠；Flutter opener 97＋new_topic 44＋UI 契約測試綠；部署閘門＝Codex APPROVED 後 apply_migration→設 secret→單獨部署 analyze-chat。
