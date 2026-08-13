# VibeSync 去 AI 味 UI 收斂計畫（Grok 4.6 executor）

## 目標

把夥伴提供的 6 張示意稿轉成既有 App 可落地的視覺語法，降低「生成式 UI／AI SaaS 模板感」，但不改產品能力、資料、計費、quota、抽卡、路由與 AI 行為。

本輪由 Codex 擔任 PM／integration owner，Grok 4.6 擔任主要程式實作者；最終需有與 executor 獨立的 material R2 review。

## 輸入與基準

夥伴稿（只作視覺方向，不作功能規格）：

- `C:/Users/eric1/OneDrive/Desktop/S__44245029_0.jpg`：學習頁 Hero
- `C:/Users/eric1/OneDrive/Desktop/S__44245030_0.jpg`：首頁有內容態
- `C:/Users/eric1/OneDrive/Desktop/S__44245031_0.jpg`：首頁空態
- `C:/Users/eric1/OneDrive/Desktop/S__44245032_0.jpg`：練習室開場
- `C:/Users/eric1/OneDrive/Desktop/S__44245033_0.jpg`：新增對象
- `C:/Users/eric1/OneDrive/Desktop/S__44245034_0.jpg`：角色圖鑑

目前視覺 proof：

- `build/visual_proof/prod_partner_home.png`
- `build/visual_proof/prod_partner_home_empty.png`
- `build/visual_proof/prod_add_partner.png`
- `build/visual_proof/safe_batch_learning.png`

## 現況判斷

「不像生成式模板」初始分數：4/10。

問題不是單一紫色，而是下列語彙同時大量出現：

1. 大面積紫色 bokeh／漸層作為工作頁背景。
2. 卡中卡與等權重卡片堆疊，所有區塊都像 Hero。
3. 彩色 glow、gradient border、beam、sparkle／magic icon。
4. 選中狀態普遍使用大 pill 或整塊發光。
5. 文字、圖像與 CTA 同時搶主視覺，層級不安靜。

夥伴稿可採用的方向：近黑底、暗紫只留品牌底色、橘色只用於焦點／動作、左對齊 editorial typography、hairline 分隔、單一照片主視覺、原生 grouped form 語法、plain bottom navigation。

## 核心設計決策

### 採用

- 保留 `DESIGN.md` 的暗紫＋橘品牌身分，但工作頁改成近黑／低飽和暗紫，移除首頁動態 bokeh。
- active state 改為橘色 icon／文字或薄實色底；不用漸層膠囊和常駐彩色陰影。
- 同一區塊只保留一個真正有功能意義的 surface；其餘靠字級、間距、hairline 分層。
- 照片是學習 Hero、圖鑑卡、練習室開場的唯一主視覺。
- celebration／揭牌瞬間可保留短暫動畫；idle 狀態不常駐 glow。
- 既有 Traditional Chinese copy 與產品名可保留「AI」；去 AI 味指介面語彙，不是假裝沒有 AI。

### 不照抄

- 免費用戶不得顯示「每日登入解鎖新女孩」；沿用現行 tier-aware 文案。
- 不使用示意稿人物作正式素材，只用 repo 已授權 assets。
- 不新增示意稿中的功能、欄位、頁面或導覽。
- 新增對象仍維持「一頁完成」，不把三個選項拆成額外頁面。
- 不改 quota、翻牌、SR、練習模式、資料模型、埋點或 API。

## 實作切片與檔案

### A. App chrome 與 Home 第一印象

主要檔案：

- `lib/app/main_shell.dart`
- `lib/features/partner/presentation/screens/partner_list_screen.dart`
- `lib/features/partner/presentation/widgets/getting_started_checklist.dart`
- `lib/features/partner/presentation/widgets/home_feature_entries.dart`
- 視需要：`home_quota_strip.dart`、`partner_list_card.dart`

要求：

- MainShell 改用靜態品牌背景，不再掛動畫 bokeh。
- wordmark 左對齊；設定按鈕維持至少 44pt。
- bottom nav 三個 label 常駐，active 只用橘色，不用漸層 pill／陰影。
- Home FAB 改 solid orange，移除 gradient。
- quota 改成低層級 compact row／strip，不再像首要卡片。
- checklist 可保留單一 grouped surface，列間用 hairline；不可再卡中卡。
- 「開場救援／問教練」合成一個 divided surface，保留兩個 hit target 與既有 keys／埋點。
- 空態文案與兩條 CTA 行為不變；主 CTA solid orange、次 CTA quiet outline/text。

### B. 新增對象

主要檔案：

- `lib/features/partner/presentation/screens/add_partner_screen.dart`

要求：

- 移除 `LiquidMotionFrame`、gradient beam、`BrandIconBadge`、sparkle／auto-awesome 裝飾。
- 名稱先出現；關係預設用一個低對比 grouped section，透過 label、spacing、hairline 分層。
- 保留現有全部欄位、預設值、字數限制、disabled／loading／auth 行為與一頁裝完守門。
- CTA 不帶 magic icon；enabled solid orange，disabled 中性灰。

### C. 學習頁 Hero

主要檔案：

- `lib/features/practice_chat/presentation/widgets/practice_room_entry_card.dart`
- 視需要：`lib/features/learning/presentation/screens/learning_screen.dart`

要求：

- 照片 full-bleed，僅保留可讀性 scrim；文案放底部左側。
- 移除中央 glass panel、beam、glowing sparkle mark、gradient reward pill。
- 保留整卡可點、tier-aware eyebrow、NEW、route 與 accessibility。
- Hero 下方既有內容不改順序與資料行為；只修跟新 Hero 直接衝突的 spacing。

### D. 角色圖鑑

主要檔案：

- `lib/features/practice_chat/presentation/screens/practice_collection_screen.dart`

要求：

- 頁首改為一個清楚的 collection summary：已收集數、總數、進度、翻牌 CTA、可信時才顯示 quota。
- 移除 idle 的漸層 `Collection` 大標、常駐 draw glow、卡片 rarity glow／彩色 shadow。
- rarity 仍可透過小 badge、stars 或細邊辨識；解鎖 highlight 與 reveal ceremony 可保留。
- filters 改 quiet segmented bar／tabs；保留既有 keys 與 filter 邏輯。
- SR ticket、locked/unlocked、paywall 分流與 onboarding guide 行為不變。

### E. 練習室開場

主要檔案：

- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`

要求：

- 開場前視覺採全深色一體化，不再把人物放在白色 workspace 卡中。
- 難度與學習模式保留，但選中狀態不用彩色 glow；摘要只留一層。
- 人物照片成為主視覺，名字／職業／tags／計費提示維持可讀。
- 聊天開始後可保留現有淺色 workspace，避免本輪擴張到所有 bubble／debrief 重構。
- Game lock、info sheet、Hint、輸入列、扣費與 session 行為不改。

## 狀態與 accessibility

- loading、disabled、empty、error、locked、premium/free、reduce-motion 都要維持。
- 所有 tap target 至少 44×44 logical px。
- 一般內文對比至少 4.5:1；大字至少 3:1。
- 不新增外部 dependency；不新增未登記彩色 glow／gradient。
- 保留現有 widget keys、semantics、路由和 funnel tracking。

## 視覺 proof 與驗證

先在 runtime UI 改動前建立／執行 deterministic visual proof，輸出：

- `build/visual_proof/anti_ai_ui/before/home_populated.png`
- `build/visual_proof/anti_ai_ui/before/home_empty.png`
- `build/visual_proof/anti_ai_ui/before/add_partner.png`
- `build/visual_proof/anti_ai_ui/before/learning_hero.png`
- `build/visual_proof/anti_ai_ui/before/collection.png`
- `build/visual_proof/anti_ai_ui/before/practice_opening.png`

完成後輸出同名 `after/` 圖，並提供 6 組 side-by-side。若既有 proof 可重用，允許複製目前 HEAD 產物，但 collection／practice opening 必須新增穩定 seed。

最小驗證：

1. `dart format`（只格式化 task-owned Dart files）。
2. 相關 widget tests：MainShell／Home／Add Partner／Learning／Collection／Practice style。
3. `flutter test --no-pub test/lint/slop_ratchet_test.dart`。
4. `flutter analyze --no-pub`。
5. `git diff --check`。

## 驗收標準

- 首屏不再以紫色 bokeh、卡中卡、漸層 pill 或 magic icon 為主要記憶點。
- orange accent 的使用範圍縮到 active／CTA／少量 status。
- 六張 after 圖在不看互動說明時，仍能清楚讀出第一、第二、第三層。
- 所有既有產品行為與測試契約維持。
- Eric 看過 before/after 並明確同意後，才可 commit／push。

## Not in scope

- 登入／onboarding／paywall／分析頁／報告頁的全面重設計。
- 新字體、品牌改名、新人像生成或素材授權。
- AI prompt、Edge Function、Supabase、RevenueCat、quota／pricing。
- App Store release。

