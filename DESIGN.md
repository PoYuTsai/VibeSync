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
- 首頁對象卡燈號狀態字 13：`partner_list_card.dart` 第二行燈號標籤（Bruce 2026-10-21 規格、Eric 同日拍板）。配 16 高的信號機，行高 1.2；只用在這一列，不進 `AppTypography`。

## 4. 圓角

憲法值：**22–24（卡片）／18（次級容器）／999（pill）**；bottom sheet 頂圓角統一 24。
B7 批 2026-08-10 收斂：8–16→18、20→22、28/30→24（234 處）。

圓角登記例外（保留）：
- ≤7 的功能性微圓角：共用聊天泡泡（`chat_bubble.dart`）組首上角尾巴 5、Sydney 開場泡泡尾巴 5、進度條/指示條圓端 2–4、小徽章 6–7、分析片段引用小卡 6。
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
| LiquidBeam 入口光暈 | `practice_room_entry_card.dart`（練習室入口用 1.6 / 10 / .5 微光）＋建立對象卡（維持 `LiquidBeamEntryPreset` 2.4 / 18 / 1） | Eric 2026-08-12 拍板：Hero 退成貼邊微光，建立對象卡不跟著弱化；兩者速度維持 6800ms |
| 首頁頭像 flow | 首頁對象卡頭像流光 | 同上，角速度已對齊 beam |
| 抽卡儀式 glow | `practice_collection_screen.dart` 抽卡/翻牌 `brandFlame` 呼吸光暈 | 儀式性場景，慶祝時刻 |
| 抽卡揭曉 V3 光效 | `practice_draw_ceremony.dart`、`practice_reveal_card.dart`、`practice_reveal_painters.dart`：卡背依稀有度染色光（銀→藍→金）、卡面外光、全息掃光、光刃、星塵、收卡光球；圖鑑那一格的落位光（`practice_collection_screen.dart`，和收卡光球同色）。色值集中在 `lib/core/theme/practice_reveal_palette.dart` | 揭曉是儀式時刻，稀有度靠光色分級；規格 `docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md` §6–§7（2026-10-15 D1–D9 由 PR 作者照建議先定，待 Eric 確認） |
| 抽卡揭曉 V3.1 光效（第一刀） | 同上三檔＋`practice_reveal_theme.dart`：卡片前後兩層泛光、徽記白光、整張卡染色（線路遮罩跟外框、徽記一起發光）、升階光點、衝擊波光環、加強的光刃與 SR 橫跨螢幕的十字光、星星點亮的四芒星光與小光點、收卡細線發光與弧線光尾、落位四芒星爆光與兩圈光環；六角金屬稀有度牌（銀色金屬漸層＋一道反光，SR 倒角帶金）與卡片厚度邊是金屬面、不發光。光暈一律用預先模糊好的貼圖（`tools/practice-reveal-sprites/`）或漸層畫，不做逐幀模糊；色值仍集中在 `practice_reveal_palette.dart` | 規格 `docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md` §5（K1–K7 Eric 2026-10-18 照建議定案）；粒子量照 §9 檔位（目前中檔）；停住時全部結束，畫面靜止 |
| 抽卡卡片典藏材質（卡面，P2） | `practice_reveal_card.dart`、`practice_card_material.dart`：2 pt 拋光金屬外框（管狀明暗＋跟著卡片姿態走的受光點；SR 右側全息邊）、六角牌拉絲銀面＋拋光倒角（SR 金）收進卡片內、煙燻玻璃資訊欄（中性炭灰、上緣受光、斜向反光、斜邊、底部厚度陰影）、十面切面金屬星與星後光暈。光暈與反光都是漸層，不做模糊；色值集中在 `practice_reveal_palette.dart` | 示意圖「SR 正反面質感示意」的卡面（實體典藏卡的金屬、玻璃材質，只在揭曉卡內）；規格 `docs/plans/2026-10-28-card-collectible-material-spec.md` §7（M1–M10 由 PR 作者照建議先定，待 Eric 確認）；光由卡片姿態算出，停住時靜止 |
| 抽卡卡片典藏材質（卡背，P3） | `practice_card_material.dart`、`practice_reveal_card.dart`、`practice_draw_ceremony.dart`：卡背改用 repo 內工具（`tools/practice-card-material/`）離線渲染的三階成品圖（N 鉑銀霧面、R 電光鈦藍、SR 香檳金全息），執行時只做轉化擴散（下一階從徽記往外長出來、前緣一圈細光）、跟著卡片姿態走的高光帶與浮雕補光、SR 全息（`color` 混色只換色相）與超出靜止值的額外發光；泛光全是預先模糊好的貼圖，painter 裡不做模糊；色值集中在 `practice_reveal_palette.dart` | 示意圖「卡背三階」；規格 `docs/plans/2026-10-28-card-collectible-material-spec.md` §5、§6；稀有度靠材質分級、只升到真實稀有度；卡背只在翻牌前出現，光由卡片姿態算出，姿態不動光就不動 |
| shimmer 掃光 | `splash_screen.dart`、`ebook_shelf_section.dart`（白色掃光，非漸層文字） | 品牌 wordmark 儀式 |
| 動畫 bokeh 背景 | `gradient_background.dart`——只掛首頁（MainShell）與登入頁 | 品牌記憶點＋入場儀式（S12 拍板）；其他頁一律靜態 `BrandPageBackground` |
| splash 開屏儀式 | wordmark 紫暈（2 層）＋環境光＋暗角＋載入圓點脈光 | 開屏儀式時刻；浮動光球已拆（S12） |
| 作戰板背景 | `partner_mind_map_screen.dart`（brandInk→partnerDetailBgTop 延續漸層） | 與對象詳情頁的視覺連續性 |
| 分析紀錄 sheet | `partner_analysis_records_screen.dart` 手刻 coach tone | 值已逐項對齊憲法，不強制遷移共用元件 |
| 邊緣淡出遮罩 | `home_coach_presence.dart` ShaderMask（dstIn） | 功能性遮罩，稽核誤報 |
| OCR 確認格單發閃光 | `screenshot_recognition_dialog.dart`（ctaStart 脈衝） | 2026-08-09 拍板的注意力提示，功能性 |
| 練習室輸入框聚焦光 | `practice_chat_screen.dart`（聚焦時 ctaStart@.22，失焦即收） | 瞬態 focus 回饋，功能性非裝飾 |
| Sydney 視窗輸入列聚焦光 | `coach_surface.dart`（同練習室配方：聚焦 ctaStart@.22，失焦中性黑陰影） | 2026-08-15 Eric 拍板兩個聊天介面輸入列一致；同上瞬態 focus 回饋 |
| 草稿潤飾面板輸入框聚焦光 | `draft_polish_sheet.dart`（同練習室配方） | 2026-08-16 Bruce 回饋「參照練習室窗」；同上瞬態 focus 回饋 |
| Collection 漸層大標 | `practice_collection_screen.dart` hero「Collection」金→橘→粉 ShaderMask | Eric 2026-08-10 翻案保留：抽卡儀式頁的華麗感 |
| 共用聊天泡泡尾巴圓角 5 | `chat_bubble.dart`（分析片段與練習室共用，每組第一顆朝說話者的上角，見 §4） | PR #87：沿用分析片段的 LINE 熟悉感，練習室同組後續分段不重複尾巴；白名單＝`kAllowedRadiiByFile`，只開共用元件這一個值 |
| Sydney 視窗開場泡泡尾巴圓角 5 | `global_coach_screen.dart`（開場泡泡朝頭像的貼合角） | 同上：沿用分則氣泡的尾巴語彙；白名單＝`kAllowedRadiiByFile`，只開這一檔這一個值 |
| 分析片段引用小卡 6 | `message_bubble.dart`（泡泡內引用小卡；尾巴由共用 `chat_bubble.dart` 提供） | 2026-10-02 A 案「LINE 熟悉感」：引用小卡取外圓角 18 的 1/3，用 18 會變 pill；白名單＝`kAllowedRadiiByFile`，此檔只保留 6 |
| 首頁對象卡燈號霓虹字與信號機亮燈 | `partner_list_card.dart` 第二行燈號標籤＋`japanese_led_signal.dart`：「燈色 狀態」整句同色，兩層文字光（.45／blur 2、.20／blur 5）；信號機亮的那顆用一層同色漸層光，不做逐顆模糊。外殼是 42 × 16 畫布上的切角金屬，不是新的容器圓角。色值集中在 `lib/core/theme/partner_signal_palette.dart` | Bruce 2026-10-21 燈號標籤規格、Eric 同日拍板：只限首頁對象卡這一列、靜態不動；光貼著燈具與筆畫，不出那一列；報告頁等其他燈號不跟著變 |

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
| B3 | 彩色陰影改中性（S1，排除 §7） | 本批；2026-08-12 補漏網一處：`BrandSegmentedButton` 選中 pill 的橘色發光陰影拆除，選中底同時由 `ctaStart→ctaEnd` 漸層改**實色 ctaStart**（pill 只有 ~80pt 寬，漸層看不出來，右半 `ctaEnd #E85A1E` 反而讓小色塊顯髒；整寬漸層留給主 CTA 維持層級）|
| B4 | Collection 漸層文字改實色（S3） | Eric 翻案：保留漸層（見 §7） |
| B5–B8 | 字級/小字/圓角/間距尺度重整（S4–S8） | ✅ 2026-08-10 上線（B6 全庫 <12 清零；例外登記見 §3/§4/§5；analysis_screen 留給重構案） |
| B9 | paywall 等卡片堆疊改分層（S9） | ✅ 2026-08-10：額度總覽與扣款資訊拆卡改字級＋hairline 分層；功能比較表判定為頁面唯一結構卡（回答「哪檔才有」的 FAQ 角色）；狀態通知卡（同步異常/降級待生效）與可點選方案卡屬功能元件保留；文案價格未動 |
| C | 7 個未遷移 screen 上 Brand Kit | ✅ 2026-08-10 全數處理（C-1~C-7；records/mindmap 判定部分保留見 §7） |
| — | S11 自訂繁中字體 | 拍板暫緩（App 體積），上架穩定後再議 |
| — | S12 放射光暈減密度 | ✅ 2026-08-10：splash 拆光球、三工作頁改靜態背景；保留清單見 §7 |

## 10. 驗證

### 開場救星局部變體（2026-09-21 完整 UI 規格）

僅開場白／新話題流程使用 `OpenerHomeStyle`：靜態 `#171121` 底、24 卡片及 CTA 圓角、18 輸入／模式／情境圓角、16 頁邊距；字級 12／15／19／24。CTA 陰影為黑色，入口照片／人物卡的漸層只表達實體斜角、高光與厚度，沒有光暈。照片入口圖示為 120、人物入口 128，窄版皆 104。`opener_entry_icon.dart` 的 3／6 微圓角只用於 64 單位畫布中的照片板與內嵌圖形，不是新增容器尺度。其他共用元件預設不變。

`flutter analyze` → 相關 `flutter test` → `test/visual_proof/` 出改前改後 PNG 對照 → 對比值重算 → 真機。
視覺改動一律先出改前/改後對照圖給 Eric 過目才 commit（2026-08-10 拍板鐵則）。

視覺設計（含示意圖、mockup）交出去前先做 AI-slop 自查，結果附在 PR 說明或交付訊息裡（2026-10-18 Bruce 提出）：

- 逐條對本文件：§1 色彩身分、§2／§7 彩色光暈與漸層（新的要先登記 §7）、§3 字級、§4 圓角、§5 間距、§6 動效（`AppMotion` 的檔位與曲線）、§8 對比。
- 再看常見的 AI-slop 樣式：裝飾用 emoji、漸層字、毛玻璃、彈跳過頭、沒有用途的光暈或外框、同款卡片平鋪堆疊、排版瑕疵（例如第二行只剩一兩個字）。
- 不合的值改回尺度上，或照 §7 登記理由。`slop_ratchet_test` 只抓四種機械可判定的 slop，不能取代這份自查。

## 11. 防回歸棘輪（階段 D，2026-08-10 上線）

`test/lint/slop_ratchet_test.dart` 隨測試套件跑，對 `lib/` 掃四種機械可判定
slop（<12px 字、出格圓角、白名單外彩色陰影、theme 外硬寫 Color(0x)），與
`slop_baseline.json` 逐檔比對：**超過基準＝紅（新 slop 進場）**；低於基準＝
綠＋提示重產基準鎖緊。既存 399 筆債（B5–B8 標的）已入基準；還債後現為 143 筆
（2026-08-11：分則氣泡的尾巴圓角 5 依 §4／§7 登記走 `kAllowedRadiiByFile` 白名單，
不是重產基準放行）。

- 還債後鎖緊：`dart test/lint/slop_baseline_generator.dart`
- 新的刻意保留：登記 §7 ＋ `slop_scan.dart` 白名單——**不得**用重產基準放行新 slop。
