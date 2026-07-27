# Review Packet — VibeSync UI 優化計畫（設計審查，實作前）

> 2026-07-27。示意圖：`docs/ui-optimization-mockup.html`
> 本 packet 為 **plan-only 設計審查**，非 code review。尚無 commit、`lib/` 未變更一行。
> 審查標的＝設計方向、階段切分、與風險假設，而非實作忠實度。

---

## 1. Scope 與類型

| 欄位 | 值 |
|---|---|
| 類型 | 設計審查（pre-implementation） |
| Branch | `claude/vibesync-ui-optimization-c39l6i` |
| BASE_SHA | `8f30e5e`（`修正報告投入度資料流與成長動效`） |
| HEAD_SHA | 同上 — **本輪無 code commit** |
| Changed files | 僅 2 個新增文件：<br>`docs/ui-optimization-mockup.html`<br>`docs/reviews/2026-07-27-ui-optimization-plan-review-packet.md`（本檔） |
| Migration | 無 |
| Edge deploy | 無 |
| Secrets | 無新增 |

**要求 reviewer 做的事**：評估下方第 5 節提案的六階段是否方向正確、切分合理、風險已被辨識；特別攻擊第 6 節點名的四個假設。**不需要**審程式碼，因為還沒有。

---

## 2. 背景與已鎖定決策

### 起點
Eric 要求研究 repo 並建構優化 VibeSync UI 的整體計畫，參考 `https://github.com/Nutlope/hallmark`。

### 關於 hallmark 的定位澄清（重要）
`Nutlope/hallmark` **不是一個 App，是一套設計規則集** — 自述為 "A design skill for Claude Code, Cursor, and Codex that refuses to look AI-generated"（Together AI，MIT，18.4k stars）。輸出目標是 HTML/CSS 落地頁，內含反模式清單（Critical/Major/Minor 三級）、token 尺度、57 道 slop gate。

因此本計畫**不是抄它的長相**，而是把它可移植的紀律當作品質標準。約 6 成規則可移植到 Flutter：8 態檢查表、motion token、間距/字級尺度、單一陰影、無純黑純白、深色以亮度表達層級、tabular figures、空狀態三件套、silent success、spinner 150ms delay-show / 300ms min-duration。**不可移植**：macrostructure、nav、footer、hover 處理、command palette（皆針對桌面落地頁）。此界線已在計畫中明列，避免後續 session 誤套。

### Eric 本輪拍板（三項，不在審查範圍）

1. **保留暖紫橘品牌**，只在品牌內部套紀律。等同正式關閉 `docs/reviews/ui-design-audit-2026-06-09.md` 卡住的 Decision #1（色彩系統方向）與 #2（AI-slop 尺度）。
2. **範圍＝地基 + 一致性掃除**。不含 `analysis_screen.dart` 拆解、不含完整 BrandKit 遷移。
3. **安裝 hallmark skill**，每階段收尾跑 `hallmark audit` 當客觀關卡。

### 既有約束（reviewer 需知，皆非本輪可推翻）

- **專案階段**：TestFlight dogfood / App Review readiness 穩定化（`docs/snapshot.md`）。任一階段結束都必須是可發版狀態。
- **Bruce 2026-06-10 指示**，記載於 `test/visual_proof/density_proof_test.dart` 檔頭：
  > "keep the EXACT warm theme — same gradient bg, same bokeh, same glass surfaces, same AppColors. Do NOT adopt the v3 dark/calm look."
  → **品牌長相不在審查範圍**。若 reviewer 認為某階段逾越此界線，請以 `NEEDS_ERIC` 標記，而非逕自建議改色。
- **既有 audit**：`docs/reviews/ui-design-audit-2026-06-09.md`（940 行、73 findings、0 P0 / 29 P1 / 30 P2 / 14 Polish）。本計畫與其相容但不繼承其未驗證結論（見第 7 節 Open concerns）。

---

## 3. 研究證據（全部可獨立複驗）

`lib/` 306 檔 / 92,490 行，presentation 層 105 檔 / 49,609 行（54%）。
Flutter 3.6+、Riverpod、go_router 14.6、Material 3、dark-only。

### 3.1 已經做對的（提案明確保留，不重造）

| 項目 | 證據 |
|---|---|
| BrandKit 已是實質設計系統 | `lib/shared/widgets/brand/brand_kit.dart`（737 行），檔頭 9–16 行已寫中文「設計憲法」；`BrandSurfaceCard` 已 29 檔採用 |
| 字體紀律良好 | `AppTypography.*` 871 次 vs inline `TextStyle(` 173 次 |
| reduced-motion 覆蓋佳 | 18 處檢查 `MediaQuery.disableAnimations`；`liquid_motion_frame.dart:69-83` 同時檢查 `TickerMode` + reduced-motion，是全 repo 最正確的動效樣板 |
| 無頭視覺驗證框架已存在 | `test/visual_proof/`（19 檔），真 CJK 字型、390×844、3x PNG，`proof_support.dart:103` `pumpAndCapture()` |
| 測試安全網 | 283 測試檔、127 含 `testWidgets`；基線 2265 passed / 4 skipped / 0 failed |

### 3.2 地基缺口（提案主體）

| 項目 | 實測 |
|---|---|
| 間距 token | **0**（546 個 `EdgeInsets` 字面值，7 種卡片內距並存） |
| 圓角 token | **0**（**20 種**圓角值：999/12/14/8/16/18/20/10/24/22/11/4/99/7/6/28/9/2/15/13） |
| 動效 token | **0**（25+ 種 duration 字面值） |
| focus state | **0** |
| pressed state | **2** |
| tabular figures | **0** |
| 共用 Empty / Error / Loading | **0**（Empty 在 8 檔手刻；Error 僅 `analysis_error_widget.dart` 一個且 analysis 專用） |
| skeleton | `skeletonizer: ^2.1.3` 已是付費依賴，**只用 1 處**（`about_me_card.dart:55`）；並存 **30 個裸 `CircularProgressIndicator`** |

### 3.3 hallmark 反模式實測命中

| 反模式 | 分級 | VibeSync 現況 |
|---|---|---|
| shadow-glow on dark | Major | 62 個 `BoxShadow`，其中 **28 個**是橘/粉發光；54 處 `boxShadow:` 多為堆疊 |
| aurora-blob / floating orbs | Critical | `gradient_background.dart` 3 顆 bokeh + **3 個永久 `repeat()` AnimationController**，常駐 login 與 main shell |
| purposeless glassmorphism | Major | `GlassmorphicContainer` 14 檔 |
| gradient headline | Critical | `ShaderMask` 於 `splash_screen.dart`、`practice_collection_screen.dart` |
| missing tabular-nums | Major | 0 處 |

> **動效有前例**：commit `718aa81`「修正流光動畫造成的發版測試逾時」。動效紀律在本專案不是美學問題，是發版問題。

### 3.4 被架空的 ThemeData（最高槓桿，單檔）

`AppTheme.darkTheme`（`lib/core/theme/app_theme.dart`）綁定：
- `scaffoldBackgroundColor: AppColors.background` = `#121212`
- `colorScheme.primary: AppColors.primary` = `#6B4EE6`（紫）

**兩者都不是品牌色**。品牌是 `brandInk #150C24` + `ctaStart #FF6A2B`（橘）。

全 `lib/` 僅 **18 次** `Theme.of(context)`。後果：所有未被 Brand 元件包住的 Material fallback 路徑 —— **230 個裸 `SnackBar`**、dialog、bottom sheet、text selection、Cupertino sheet —— 都以錯誤色票渲染。

`app_colors.dart` 實際上並存四套色系：flat-Material（唯一被 `ThemeData` 綁的）、warm brand（畫面實際用的）、glass（淺表面用）、coach tone（後加）。

### 3.5 色彩問題的精確二分（比 2026-06-09 audit 的敘述更準確）

audit §1 稱「對比崩潰」。實測後應區分為**兩種性質不同的情況**：

- **(a) 合法的淺色島 —— 不是 bug，不要改。**
  `BrandAlertDialog`（`brand_dialog.dart:24,73`）**刻意**用 `glassWhite` 當 `AlertDialog` 表面，再配 `glassTextPrimary` 文字。深底上浮一張淺色卡，自洽且對比合格。`GlassmorphicContainer` 預設 `color: AppColors.glassWhite`（`glassmorphic_container.dart:44`）同理，所以用它的檔案多半自洽。

- **(b) 真正的失敗 —— `glassText*` 用在沒有淺色表面的地方。實測 11 檔命中：**
  ```
  shared/widgets/brand/brand_feedback_snack_bar.dart
  shared/widgets/coaching_outcome_capture_card.dart
  features/follow_up_notification/presentation/soft_opt_in_card.dart
  features/coach_chat/presentation/widgets/coach_chat_progress_notice.dart
  features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart
  features/partner/presentation/dialogs/partner_edit_dialog.dart
  features/partner/presentation/dialogs/partner_note_edit_dialog.dart
  features/partner/presentation/dialogs/partner_settings_dialog.dart
  features/conversation/presentation/widgets/conversation_tile.dart
  features/analysis/presentation/widgets/screenshot_recognition_dialog.dart
  features/analysis/presentation/widgets/screenshot_added_feedback_card.dart
  ```
  代表案例 `conversation_tile.dart:74,80,104` 是裸 `ListTile`（無自身表面），用 `glassTextPrimary` 標題 + `glassTextHint` 副標。

  **WCAG 實算（底色 `brandSurface #1F1330`）：**

  | Token | 值 | 對比 | 判定 |
  |---|---|---|---|
  | `glassTextPrimary` | `#4A3548` | **1.59:1** | ✗ 遠低於 4.5:1 |
  | `glassTextHint` | `#8B4557` | **2.58:1** | ✗ |
  | `glassTextSecondary` | `#6C5A6B` | **2.77:1** | ✗ |
  | `onBackgroundPrimary` | `#FFFFFF` | **17.59:1** | ✓ |
  | `onBackgroundSecondary` | `#E0D0E8` | **12.02:1** | ✓ |

  替代色票**已存在**於 `app_colors.dart:74,75`，不需新增顏色。

### 3.6 其他確認

- `_buildQuotaPill`（`paywall_screen.dart:710`）與 `_buildUsagePill`（`settings_screen.dart:447`）**逐字元相同**；`_buildPendingDowngradeCard` 亦重複於 `paywall_screen.dart:739` / `settings_screen.dart:479`。
- 無 l10n：0 個 `.arb`、無 `l10n.yaml`、無 `flutter_localizations`、無 `supportedLocales` → Flutter 內建元件（日期選擇器、文字選取選單）落回英文。約 4,547 條 CJK 字面值散於 256 檔。
- 無自訂字型：`pubspec.yaml` 無 `fonts:` 區塊，`AppTypography` 無 `fontFamily`（`proof_support.dart:115` 的註解「the app's family-less AppTypography styles」證實）。
- `analysis_screen.dart`：8,816 行、`build()` 2,053 行（6272–8325）、74 個 state 欄位、92 個 `setState`、75 個 `SnackBar`、檔首 `// ignore_for_file: dead_code, unchecked_use_of_nullable_value`。**本輪明確排除。**
- domain 層 UI 洩漏：`features/analysis/domain/services/game_stage_service.dart` 有 5 個 `Color(0x…)`。
- 響應式：1199 個固定 `height:`，僅 2 處處理 `textScaler`（皆在 `ebook_cover_badge.dart`）。

---

## 4. 示意圖

`docs/ui-optimization-mockup.html`（單檔自帶樣式，前例 `docs/splash-prototype.html`）。

畫布 390×844 對齊 `proof_support.dart:101` 的 `kPhone`，讓示意圖與未來 visual_proof 截圖可直接並排。

含 8 組 before/after 對照（圓角、間距、深色層級、文字對比、8 態、載入態、數字、三件套）＋ 1 組全頁對照（首頁對象列表）。**所有 After 使用與 Before 完全相同的色票**，用以佐證「只變乾淨、沒變品牌」。頁尾附 10 條複驗指令。

---

## 5. 提案的六階段

| Phase | 內容 | 變更面 | 預期 diff | 回退 |
|---|---|---|---|---|
| **0** | 立憲＋裝表：`npx skills add nutlope/hallmark`；新增 `docs/design-system.md`（把 `brand_kit.dart:9-16` 既有中文憲法升格＋併入 hallmark 可移植規則＋明列不適用項）；跑 `hallmark audit` 取基線 | 僅 docs | 0 行 code | 刪檔 |
| **1** | 新增 token 層：`app_spacing.dart`（6 級 4pt）、`app_radius.dart`（20→4 種）、`app_motion.dart`（micro 120 / short 220 / long 420，enter `easeOutCubic`、exit 取 60–75%）、`app_elevation.dart`（每級 +3% lightness＋單一 hairline） | **純新增檔案，零畫面變更** | ~150 行新增 | 刪檔 |
| **2** | 修 `app_theme.dart`：色票改綁品牌；補 `snackBarTheme` / `dialogTheme` / `bottomSheetTheme` / `textSelectionTheme` / `chipTheme` / `progressIndicatorTheme`；`inputDecorationTheme` 對齊既有 `brandInputDecoration()`；舊 flat-Material 色標 `@Deprecated` 不刪 | 單檔，但影響 230 個裸 SnackBar 與全部 Material fallback | ~80 行 | 單檔還原 |
| **3** | 色彩收斂：逐一判定 11 檔屬 (a) 或 (b)，(b) 改 `onBackground*`；`app_colors.dart` glass 區塊加使用契約註解；`brand_kit.dart:64,68,72` 三個硬編碼 chip 態色收進 `AppColors`；`game_stage_service.dart` 5 個色移出 domain | 11 檔 + 2 檔 | ~120 行 | 逐檔 |
| **4** | 新增三件套於 `shared/widgets/brand/`：`brand_empty_state.dart`、`brand_error_state.dart`（以 `analysis_error_widget.dart` 為藍本泛化，**硬規則：永不渲染原始 exception**）、`brand_loading.dart`（包 skeletonizer，150ms delay-show / 300ms min-duration）。先建元件＋示範遷移 3–5 個呼叫點 | 新增 3 檔 + 少量遷移 | ~300 行 | 刪檔 |
| **5** | 8 態補完（`BrandPrimaryButton` / `BrandSecondaryButton` / `BrandChoiceChip` / `BrandSegmentedButton`）；`AppTypography` 新增 `numeric` 系列帶 `FontFeature.tabularFigures()`；動效改吃 token；28 處發光陰影改亮度層級；bokeh 收斂為僅首頁保留且靜態化 | BrandKit + 動效相關檔 | ~200 行 | 逐項 |
| **6** | 去重：抽 `BrandStatPill` 取代 `_buildQuotaPill`/`_buildUsagePill`，處理 `_buildPendingDowngradeCard`；11 處 `...` → `…` | paywall / settings（**高風險區**） | ~80 行 | 逐項 |

**排序理由**：Phase 1 純新增 → 零視覺風險，先落地讓後續 diff 乾淨。Phase 2 單檔但投報比最高。Phase 3 才動既有畫面，且已被前兩階段的 token 與 baseline 截圖保護。Phase 4–6 是增量採用，隨時可停。

---

## 6. Risk focus — 希望 reviewer 集中攻擊的四點

### R1 — Phase 2 的 blast radius
改 `AppTheme.darkTheme` 會一次影響 230 個裸 `SnackBar` 與所有 Material fallback 路徑。
**問**：是否存在依賴目前「錯誤」色票的畫面？例如某處刻意在深色 dialog 上依賴 `colorScheme.surface` = `#1E1E1E`？補 `snackBarTheme` 是否會與既有 `buildBrandFeedbackSnackBar()`（10 檔採用）衝突或雙重套用？

### R2 — Phase 3 的二分法是否成立
提案主張 `glassText*` 的使用可乾淨切成 (a) 合法淺色島 / (b) 真對比失敗，而 `BrandAlertDialog` 是 (a) 的反例證明。
**問**：這個二分是否有第三種情況？例如某檔的淺色表面由**呼叫端**提供（跨檔），靜態 grep 判不出來，逐檔人工判定會誤殺？11 檔清單是否有遺漏（我的偵測法是「同檔內無 `GlassmorphicContainer` 且無 `glassWhite`」，跨檔情況會漏）？

### R3 — Phase 5 的 bokeh 收斂是否逾越拍板界線
Eric 拍板「保留暖色品牌」，Bruce 明示「same bokeh」。提案卻要把 bokeh 收斂為僅首頁保留且靜態化。
提案的辯護是：理由不只 hallmark，還有 **3 個永久 `repeat()` controller 常駐 main shell 的電力與發版測試成本**（前例 commit `718aa81`），且 `brand_kit.dart:75` 註解顯示團隊已採用過「靜態 gradient，動態光球只留首頁」的方向。
**問**：這個辯護站得住嗎？還是應該標為 `NEEDS_ERIC`？

### R4 — Phase 6 觸及高風險區的宣稱
`paywall_screen.dart` / `settings_screen.dart` 屬 `AGENTS.md` 明列高風險區（subscription / paywall / quota / RevenueCat / 429）。
提案宣稱只動 presentation、不碰訂閱邏輯。
**問**：抽 `_buildQuotaPill` / `_buildPendingDowngradeCard` 成共用元件時，是否可能改變**呼叫時機**或**條件判斷**而非只是外觀？此階段是否應該直接移出本輪、獨立立項？

---

## 7. Open concerns（主動揭露，不等 reviewer 發現）

1. **本容器沒有 Flutter**（`flutter: command not found`）。全部驗證需在 Eric 機器或 CI 執行；本輪**無法自證任何測試通過**。所有測試數字（2265 passed 等）引自 `docs/snapshot.md`，非本輪實跑。
2. **大字級是唯一可能引入新破版的地方**。全 repo 1199 個固定 `height:`、僅 2 處處理 `textScaler`。Phase 1 的間距 token 化本身不改值，但 Phase 3–5 動到版面時風險上升。已列入驗證計畫的真機走查。
3. **2026-06-09 audit 已 7 週**。其 73 findings 至少 A-01（onboarding 未接線）已修 —— `routes.dart:96-99` 現已有 `/onboarding` 路由。**本 packet 不繼承其未經重驗的結論**；引用時僅取根因分析（雙色系統），不取個別 finding 編號。
4. **hallmark 只有約 6 成可移植**，且它是 HTML/CSS 工具，`hallmark audit lib/` 對 Dart 的判讀能力未經驗證。提案把它當「客觀關卡」可能高估其效力，需人工判讀。
5. **`_buildQuotaPill` 逐字元相同的判定**基於視覺比對兩段程式碼，未做 AST 比對。若有肉眼漏掉的差異，Phase 6 抽共用會引入行為變更。
6. **l10n 未納入本輪**（4,547 條 CJK 字面值 / 256 檔，獨立立項）。但提案建議順手補 `flutter_localizations` + `supportedLocales: [zh-Hant]` —— 一行改動可修正內建元件落回英文。**此項未經 Eric 拍板，若 reviewer 認為屬範圍蔓延請指出。**

---

## 8. 不在範圍（各附理由）

| 項目 | 理由 |
|---|---|
| `analysis_screen.dart` 拆解（8,816 行 / build() 2,053 行 / 74 state / 92 setState） | Eric 拍板排除。全 App 最高風險檔且是核心付費流程，串流分析易出回歸，應獨立立項 |
| 完整 BrandKit 遷移（~30 畫面、14 個 `GlassmorphicContainer`） | Eric 拍板排除 |
| Coach 1:1 視覺改版（`coach_surface.dart` 1,428 行） | 其淺色卡屬 (a) 類自洽設計，非 bug；旗艦流程應獨立處理 |
| l10n / `.arb` 抽取 | 獨立且龐大的立項 |
| 換自訂字型 | 動到全 App 排版，TestFlight 階段不宜 |

---

## 9. 驗證計畫（每階段收尾依序執行）

1. `flutter analyze` — 須 0 issues（專案現行標準）
2. `flutter test` — 基線 2265 passed / 4 skipped / 0 failed
3. `flutter test test/visual_proof/` — 產出 `build/visual_proof/*.png`
   - **Phase 0 先跑一次存 baseline**
   - Phase 1 之後應**逐像素無變化**（純新增檔案）→ 有變化即代表誤觸
   - Phase 2–5 每階段截圖與前階段並排人眼比對，確認「只變乾淨、沒變品牌」
4. `hallmark audit lib/` — 與 Phase 0 基線比對，反模式命中數應單調下降（需人工判讀，見 Open concern #4）
5. 真機：SE 寬度（375）+ iOS 輔助使用大字級，各走一次核心四流程（Coach 1:1 / Opener / analyze-chat / Practice）

**紀律**：每階段一 commit、一個關注點、Traditional Chinese commit message。全程不碰 subscription/quota/RevenueCat 邏輯、`analyze-chat`、OCR、Edge schema —— 只動 presentation 層樣式。push / 部署 / TestFlight 送件需 Eric 明確授權。

---

## 10. 要求的 verdict

依 `docs/shared-agent-rules.md` §High-Risk Review：

- **`APPROVED`** — 方向與階段切分無材料級 P0/P1/P2，可進入實作。
- **`REVISE_REQUIRED`** — R1–R4 中有經證據支持的缺陷，需修正計畫後再審。
- **`NEEDS_ERIC`** — 存在產品／付費／資料／後果性取捨（例如 R3 bokeh 是否逾越品牌拍板、Open concern #6 的 l10n 範圍蔓延）。

請對 R1–R4 逐項給出結論與證據，並標明哪些 Open concern 你認為被低估。
