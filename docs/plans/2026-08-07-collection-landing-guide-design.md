# 圖鑑落地引導（Sydney 泡泡）設計

**日期**：2026-08-07
**狀態**：已實作（本 branch）
**範圍**：純前端。不動 AI、額度、付費牆、Edge、資料庫、埋點字典。

## 問題

新用戶在 onboarding 分流頁按「還沒，先去練習」後直接落在角色圖鑑：0/100、
整片鎖卡「???」，沒有任何一句話說這是哪裡、下一步做什麼。上一頁 Sydney
還在說話，落地後教練憑空消失，onboarding 建立的陪伴感在最後一步斷鏈。

## 解法

落地那一次，在圖鑑上疊一層引導：淡 scrim＋右下角 Sydney（`sydney_greeting.png`，
高 160，比 Gemini 示意縮小靠右）＋白泡泡：

> 哈囉！這裡是角色圖鑑～先按右上角的『翻牌』，抽出你的第一位練習夥伴吧！

點畫面任何地方收掉（該次點擊被吸收，不觸發底下互動）。進場 200ms 淡入＋
微上移（`TweenAnimationBuilder`，單次收斂；`disableAnimations` 時零秒）。

## 觸發：query 參數，零持久化

分流頁 push `/practice-collection?guide=1`；路由 builder 讀 query 傳
`PracticeCollectionScreen(showOnboardingGuide: true)`。onboarding 一生只完成
一次（`OnboardingService.markCompleted` 擋重入），參數天然只出現那一次，
不需要本機旗標。其他入口進圖鑑行為零改變。

## 拍板紀錄

- 觸發只做「onboarding 分流進來的第一次」，不做「首次進圖鑑就出」、不做
  可複用引導系統（Eric 2026-08-07）。
- 不用 `HomeCoachPresence`（那是首頁大立繪：55% 螢幕高＋上下淡出 shader，
  與縮小靠右的引導需求不合），引導層用同素材輕量自建。
- 不做自動倒數消失：計時器在 widget test fake async 下不收斂（既有坑）。
- `pumpAndSettle` 禁用於 locked seed 圖鑑測試（翻牌鈕脈動 repeat 會 hang），
  引導測試一律顯式 pump。

## 已知的 worktree 坑

fresh worktree 跑測試前必先 `flutter pub get`＋
`dart run build_runner build`（`hive_registrar.g.dart` 等 46 個生成檔
gitignored，缺了整包 widget test 直接編譯失敗）。

## 驗證

- `flutter test test/widget/features/practice_chat/practice_collection_screen_test.dart test/widget/features/onboarding/` → 62 綠
  - 新增 3 條：預設不出引導層／`showOnboardingGuide` 出現且文案逐字對／
    點一下收掉且翻牌鈕恢復可點（首擊被吸收不觸發抽卡）
  - 升級 1 條：分流「還沒」斷言 push 帶 `guide=1`
- `flutter analyze` 全 repo 0 issue
- 真機（Eric）：走全新 onboarding →「還沒，先去練習」→ 圖鑑出 Sydney 泡泡，
  點一下收掉，翻牌可按；從首頁其他入口再進圖鑑不再出現。
