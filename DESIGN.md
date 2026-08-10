# VibeSync 設計憲法（DESIGN.md）

> 單一事實來源。改任何 presentation 程式碼前先讀這份；`lib/shared/widgets/brand/brand_kit.dart` 的註解只是指標，內容以這裡為準。
> 來源：2026-08-10 由 brand_kit 註解憲法搬出，並併入 anti-AI-slop 稽核（impeccable.style 清單）的拍板結果。

## 1. 品牌色彩身分（不動）

- **暗紫底＋橘色重點**。這是色彩身分，去 slop 動作不得改變它。
- 背景：`brandInk #150C24 → brandSurface #1F1330 → brandSurface2 #2A1840` 垂直漸層，stops `0 / .58 / 1`。
- 重點色：`ctaStart #FF6A2B → ctaEnd`（brandFlame/brandFlameDark）橘——CTA、焦點、icon badge。
- coach tone（Analyze Chat / Opener 洞察層）：紫 `coachAccent #9D78F5` 只負責選取與資訊；主要動作仍是橘。
- 粉 `coachRecommendation #FF5DA8` 保留給 AI 推薦。

## 2. 卡片與表面

- 卡片：brandSurface 系漸層 @ ~.9、圓角 22–24、`white@.10` 邊框、**黑色柔陰影**。
- 陰影一律中性（黑色系）表達高程；彩色發光只允許出現在「刻意保留」清單（§7）。
- 同款卡片不得當頁面結構平鋪堆疊——區塊分層優先用字級、間距、分隔線（S9，待修）。

## 3. 字級

現行 `AppTypography`（B5 批 2026-08-10 上線）：**12 / 15 / 19 / 24 / 30 / 38**，相鄰級距 ≥1.25。
內文統一 15、caption/label 12、titleLarge 19、headline 24/30、display 38（hero 數字與儀式時刻專用）。
底線：內文 ≥12px（繁中筆劃密、10px 實機吃力；B6 已修，全庫 <12 清零）；圖表空間不夠時減刻度，不縮字。

字級登記例外（尺度外但保留）：
- emoji 當 icon 用的 `fontSize`（⭐🧠🎯 等裝飾字符）＝icon 尺寸不是字級，不貼尺度。
- hero 數字 56：`partner_heat_hero_card.dart`（熱度）與 `analysis_record_detail_screen.dart`（分數，由 58 統一為 56）。
- 頭像字母 72：`practice_girl_photo.dart`，隨 220px 相框縮放的功能性字形。
- `fontSize: 0` 透明文字：`dimension_radar_chart.dart` 隱藏刻度的功能性 hack。
- `analysis_screen.dart` 尺度外殘值（13/14/18/20）＝拍板只修 B6 不動版面，留給重構案。

## 4. 圓角

憲法值：**22–24（卡片）／18（次級容器）／999（pill）**；bottom sheet 頂圓角統一 24。
B7 批 2026-08-10 收斂：8–16→18、20→22、28/30→24（234 處）。

圓角登記例外（保留）：
- ≤7 的功能性微圓角：聊天泡泡「尾巴」5、進度條/指示條圓端 2–4、小徽章 6–7。
- `analysis_screen.dart` 的 47 處出格值＝拍板不動版面，留給重構案（棘輪基準內）。

## 5. 間距

主尺度：**4 / 8 / 16 / 32**。節奏規則：群組內收緊、群組間放寬、標題上方留白 > 下方。
B8 批 2026-08-10 收斂（547 處）：噪音值貼齊（5→4、7/9/10→8、11/13→12、14/15→16、
EdgeInsets 20→16、childless SizedBox 20→24、22/26→24、28/30→32）。

間距登記保留：
- 中繼值 **12 / 24**：密集卡內距與區塊間距的半階，全下 8/16/32 會失衡，判定保留。
- micro 間隙 **2 / 6**：hairline 與 icon-label 間隙。
- `brand_kit.dart` 整檔（卡 padding 18、pill 9/12/14 等）＝拍板過的母版值，不貼尺度。
- `analysis_screen.dart` 不動（重構案）。

## 6. 動效

單一來源 `AppMotion`：press 120ms / enter 200ms / state 240ms / celebrate 320ms；easeOut `Cubic(.23,1,.32,1)`；easeOutBack 只准 celebrate 檔。原則：一個被設計過的瞬間，而非散落的效果。

## 7. 刻意保留（登記制——在此列出的「slop 樣式」是品牌決策，稽核工具再標也不拆）

| 項目 | 位置 | 理由 |
|---|---|---|
| 紫色系主色盤 | `primary #6B4EE6`、coach 系 | 已上線色彩身分（Tier 3） |
| LiquidBeam 入口光暈 | `practice_room_entry_card.dart`（練習室入口＋建立對象卡，`LiquidBeamEntryPreset`） | Eric 2026-08-09 逐格拍板的品牌記憶點 |
| 首頁頭像 flow | 首頁對象卡頭像流光 | 同上，角速度已對齊 beam |
| 抽卡儀式 glow | `practice_collection_screen.dart` 抽卡/翻牌 `brandFlame` 呼吸光暈 | 儀式性場景，慶祝時刻 |
| shimmer 掃光 | `splash_screen.dart`、`ebook_shelf_section.dart`（白色掃光，非漸層文字） | 品牌 wordmark 儀式 |
| 動畫 bokeh 背景 | `gradient_background.dart`——只掛首頁（MainShell）與登入頁 | 品牌記憶點＋入場儀式（S12 拍板）；其他頁一律靜態 `BrandPageBackground` |
| splash 開屏儀式 | wordmark 紫暈（2 層）＋環境光＋暗角＋載入圓點脈光 | 開屏儀式時刻；浮動光球已拆（S12） |
| 作戰板背景 | `partner_mind_map_screen.dart`（brandInk→partnerDetailBgTop 延續漸層） | 與對象詳情頁的視覺連續性 |
| 分析紀錄 sheet | `partner_analysis_records_screen.dart` 手刻 coach tone | 值已逐項對齊憲法，不強制遷移共用元件 |
| 邊緣淡出遮罩 | `home_coach_presence.dart` ShaderMask（dstIn） | 功能性遮罩，稽核誤報 |
| OCR 確認格單發閃光 | `screenshot_recognition_dialog.dart`（ctaStart 脈衝） | 2026-08-09 拍板的注意力提示，功能性 |
| 練習室輸入框聚焦光 | `practice_chat_screen.dart`（聚焦時 ctaStart@.22，失焦即收） | 瞬態 focus 回饋，功能性非裝飾 |
| Collection 漸層大標 | `practice_collection_screen.dart` hero「Collection」金→橘→粉 ShaderMask | Eric 2026-08-10 翻案保留：抽卡儀式頁的華麗感 |

規則：想把新的彩色光暈/漸層加進產品＝先加進這張表並說明理由，否則視為 slop。

## 8. 對比門檻

內文 ≥4.5:1、大字（≥18.66px bold 或 24px）≥3:1。
已驗合格：`textSecondary` on bg 8.93、`brandFlame` on `brandInk` 6.62、`glassTextSecondary` 5.65、`coachAccent` on `coachSurface` 5.49。
主 CTA 字色（決策 1，2026-08-10 Eric 拍板試行）：橘底深墨字 `AppColors.onCta`（=brandInk，6.62:1）。單一開關在 `app_colors.dart` 的 `onCta`——真機看了想回白字只改那一行。

## 9. 已知債清單（去 slop 批次進度）

| 批 | 項目 | 狀態 |
|---|---|---|
| B1 | CTA 字色對比（S10） | 試行深墨字（`onCta` 單一開關），等真機定案 |
| B2 | 4px 橘豎條收窄（S2） | 本批 |
| B3 | 彩色陰影改中性（S1，排除 §7） | 本批 |
| B4 | Collection 漸層文字改實色（S3） | Eric 翻案：保留漸層（見 §7） |
| B5–B8 | 字級/小字/圓角/間距尺度重整（S4–S8） | ✅ 2026-08-10 上線（B6 全庫 <12 清零；例外登記見 §3/§4/§5；analysis_screen 留給重構案） |
| B9 | paywall 等卡片堆疊改分層（S9） | ✅ 2026-08-10：額度總覽與扣款資訊拆卡改字級＋hairline 分層；功能比較表判定為頁面唯一結構卡（回答「哪檔才有」的 FAQ 角色）；狀態通知卡（同步異常/降級待生效）與可點選方案卡屬功能元件保留；文案價格未動 |
| C | 7 個未遷移 screen 上 Brand Kit | ✅ 2026-08-10 全數處理（C-1~C-7；records/mindmap 判定部分保留見 §7） |
| — | S11 自訂繁中字體 | 拍板暫緩（App 體積），上架穩定後再議 |
| — | S12 放射光暈減密度 | ✅ 2026-08-10：splash 拆光球、三工作頁改靜態背景；保留清單見 §7 |

## 10. 驗證

`flutter analyze` → 相關 `flutter test` → `test/visual_proof/` 出改前改後 PNG 對照 → 對比值重算 → 真機。
視覺改動一律先出改前/改後對照圖給 Eric 過目才 commit（2026-08-10 拍板鐵則）。

## 11. 防回歸棘輪（階段 D，2026-08-10 上線）

`test/lint/slop_ratchet_test.dart` 隨測試套件跑，對 `lib/` 掃四種機械可判定
slop（<12px 字、出格圓角、白名單外彩色陰影、theme 外硬寫 Color(0x)），與
`slop_baseline.json` 逐檔比對：**超過基準＝紅（新 slop 進場）**；低於基準＝
綠＋提示重產基準鎖緊。既存 399 筆債（B5–B8 標的）已入基準。

- 還債後鎖緊：`dart test/lint/slop_baseline_generator.dart`
- 新的刻意保留：登記 §7 ＋ `slop_scan.dart` 白名單——**不得**用重產基準放行新 slop。
