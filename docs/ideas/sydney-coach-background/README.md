# Sydney 教練頁：進場人物與長文閱讀

2026-09-06：Eric 看過六狀態互動原型後確認閱讀優先 UX，並在比較完整表演 V3 後決定「可以，用這版吧」。同一張 PR 現在包含 Flutter 閱讀版與選定影片的入口接線。

## 選定的 V3 動態素材

- 入口人物循環播放完整 10 秒表演；固定 9:16、最多 240 邏輯像素高，大字體時縮小，保留頭部及手勢。
- 開始輸入即卸載人物播放器，等待、釐清及長文都沿用標題列靜態頭像；影片不控制 AI 請求或答案完成時機。
- 提供暫停／播放按鈕。切到背景、頁面被覆蓋或 TickerMode 停用時停止播放；手動暫停不因回到前景而解除。
- 系統「減少動態效果」使用同一支影片的首幀靜態圖；載入或播放失敗也使用靜態圖，不阻擋提問。
- 影片為 APP 內附資產，無額外下載 URL、生成費用或自動重試生成。原始輸出約 14.18 MB，包內衍生版約 1.90 MB。
- 保留使用者選定的原表演與自然循環：最後回托腮較快、首尾笑容與角度不同，沒有做淡接或宣稱無縫。

包內影片 `assets/videos/coach/sydney_performance_v3.mp4`：540×960、H.264 Baseline／8-bit／BT.709、24 fps、241 幀、10.041667 秒、無音軌、faststart。SHA-256：`795fe45dcffdfc16c2d7b4f009fb91df8515e6f30f96919f07f9d73c8fe22ade`。靜態圖 `assets/images/coach/sydney_performance_v3_poster.jpg` 是原輸出首幀擷取，SHA-256：`9113b99474bca933ec0a3312a45c04ec0e9dd6582d3726f5e9539ec2c2c872a5`。

來源輸出 SHA-256：`faa942024bf13429339ad00be7c62e435079221ada81cb4894ad09491d0a3d41`。只縮放與編碼，完整保留幀數、比例與速度，未裁切、去背、補幀或重繪。使用 [Flutter 官方 video_player](https://pub.dev/packages/video_player/versions/2.14.0)，鎖定 2.14.0；native iPhone 播放、背景返回與 Reduce Motion 仍須 TestFlight 真機驗收。

本輪 WSL Flutter 3.47.0：既有 10 檔 85 項回歸、13 項播放器生命週期測試及 1 項實際入口釋放測試通過，四態視覺擷取 1 項通過，8 檔靜態分析無問題。新增設計 token 檢查曾指出圓角及色碼不合規，改用既有圓角與品牌色後單獨重跑通過。另以隔離示範資料、實際 GlobalCoachScreen 編譯 JavaScript Web 預覽成功；這些證據不代表 iOS native 建置或 TestFlight 已完成。

## 先操作這一版

[show-me：進場、鍵盤、等待、釐清、摘要、完整分析](show-me-reading-first.html)

開啟方式：保留完整 repository 的目錄結構，用瀏覽器開啟此 HTML；圖片引用既有的 assets/images/coach/，只下載本資料夾會缺少人物圖。HTML 不呼叫服務、不讀取對象資料、不扣額度，問題、答案、額度與鍵盤均為固定示意。

建議操作：
1. 進場點引導問句，查看鍵盤升起後的閱讀區。
2. 切「釐清」後點輸入、補充、送出，檢查釐清仍保留，沒有變成已扣額度的正式答案。
3. 切「完整分析」，捲到中段再點輸入、送出，檢查全文與原段落的保留。
4. 回「建議摘要」，操作展開、收起、繼續深挖。

這次 show-me 的差別是能操作完整閱讀過程，包含人物退場、追問與長文。HTML 是先確認操作的原型；Flutter 的真實非同步流程由下列回歸測試驗證。

## 提案的核心判斷

**Sydney 在進場時迎接使用者；開始輸入、等待或閱讀後，收進既有標題列。高價值文字拿回完整閱讀區。**

| 使用階段 | 人物與空間 | 內容／操作 |
| --- | --- | --- |
| 進場，尚未開始提問 | 適量半身主視覺，不固定佔半屏；短螢幕、大字體時優先縮人物 | 一句開場、三個精簡引導、額度說明與輸入列 |
| 鍵盤升起 | 立即收成標題列 32 邏輯像素頭像 | 隱藏已用完的開場引導；保留草稿、前文及鍵盤上方輸入列 |
| 首次等待 | 小頭像與單一進度提示 | 依真實 request 狀態呈現；不以角色動作假裝已收到回覆 |
| 閱讀中追問、等待 | 維持小頭像，不重新回到大人物 | 前一份釐清／正式答案原樣保留，含全文展開狀態；不清空時間軸 |
| 免費釐清 | 小頭像靜止 | 先呈現需要補充的問題；保留免費次數、補充說明與「直接看建議」確認 |
| 正式建議／完整分析 | 小頭像靜止，不額外保留頭肩橫幅 | 單一較寬閱讀底面，摘要、行動、回覆或不用回覆、界線提醒、全文與前輪都可讀 |

保留既有的意義：免費釐清不是正式扣額度；「不用回訊息」不是遺漏回覆；從指定對象／對話進入時仍鎖定正確範圍。自由入口的對象選擇可收成緊湊選單，但切換草稿與來源依現有流程處理。**本 HTML 只示範一般模式，未實作對象切換。**

## 為什麼現有畫面需要先調空間

依 2026-09-06 main `f403ce01dc8c70160cd2bfc9ab80af2ec8b197ac` 及 Eric 提供的八張實機截圖：

- 開場介紹、三個引導與來源仍在回答上方；長文出現後，它們已不是當下主要任務。
- 外層滾動區、外卡、內卡、完整分析各有內距。以 390 寬畫布示意，完整分析左右約各 60，正文只剩約 270；若用單一底面、左右各 20，可到 350，增加約 30%。這是程式內距推算，非實機點數量測。
- 名稱雖是 GlassmorphicContainer，目前這裡是實色淺底。直接在後面加人物會被擋住；為露出人物而讓長文透明，會引入額外閱讀干擾。
- 目前是「最新分析在上、前輪收在下」，並非一般聊天的最新訊息在底部。
- loading 分支會替換時間軸；對追問情境，保留前一份回答更連貫。

## 閱讀位置與資料規則

1. 第一份／新一輪答案預設從答案開頭讀，不能無條件捲到底。
2. 若使用者正在回看前文，新回答到達時保留其位置，顯示「新回覆已完成」入口，由使用者切過去。
3. 展開／收起全文，以原按鈕或目前段落為錨點，避免跳到頁首或頁尾。
4. 鍵盤開關與後續追問，保留已展開全文及正在讀的段落；前一份是釐清就保留釐清。
5. 追問失敗仍保留已取得的答案與草稿，沿用現有重試／扣額度責任。
6. 不以字數或動圖播完判斷後端已完成；不把不存在的串流事件當成現有介面。
7. 來源標示要對應當下問題或所屬回合；不可讓下一題的來源冒充舊答案依據。

Flutter 實作保留同一份回答元件及其展開狀態；追問期間不卸載它。開始追問時已在下方閱讀，或等待中主動捲動前文，新答案完成後先顯示「新回覆已完成，從開頭看」，點擊才切到最新回答。鍵盤、進度與失敗提示造成的高度變化，以閱讀區錨點補償。等待或新答案待查看時，輸入列仍可編輯，保留草稿與鍵盤，只暫停送出，避免仍顯示舊文卻把追問接到新答案。非同步狀態不搶焦點；使用者可按鍵盤「完成」主動收起，草稿仍保留，短內容也不必依賴捲動。開始互動後，「釐清免費 · 正式建議扣 1 則」持續顯示在輸入列上方。

## 延續 Bruce 的工作

[Bruce 的完整分支文件](https://github.com/PoYuTsai/VibeSync/blob/2b41872da58cf98637f744768ce84a5b4dcb7624/docs/ideas/sydney-interaction/README.md) 已提出 A／B／C：開場約 55% 人物、長文收為約 22% 頭肩、鍵盤時約 44pt 頭像，並考慮減少動態與停止背景播放。不能把素材附件沒提到 UX，解讀成他沒有想過。

本提案沿用「角色退讓」方向，調整三點：
- 輸入／閱讀就退到標題列，不等到 6 行或可視區 40% 才改布局。
- 長文不再常駐 22% 頭肩，避免與標題、範圍、輸入列一起壓縮閱讀。
- 後續送出不自動回到 55% 大人物，補上追問與閱讀位置規則。

## 素材與提示詞結論

[詳細素材檢閱與 Seedance 小規模試片提示詞](asset-review.md)

素材檢閱保留當時的小動作試片建議作為歷史。後續 Eric 選定完整表演 V3，以上方「選定的 V3 動態素材」為準；閱讀區仍不放陪讀影片。

此 Flutter 實作加入選定 V3 的包內衍生影片與首幀靜態圖。夥伴原片、私人照片與實機截圖不放入 repository。

## 實作位置與邊界

| 程式 | 責任與候選調整 |
| --- | --- |
| [GlobalCoachScreen](../../../lib/features/coach_chat/presentation/screens/global_coach_screen.dart) | 開場顯示時機、緊湊範圍列；保留指定對象的鎖定 |
| [CoachSurface](../../../lib/features/coach_chat/presentation/widgets/coach_surface.dart) | 單一閱讀底面、前文 loading 保留、回答及展開錨點、固定輸入列 |
| [Coach controller](../../../lib/features/coach_chat/data/providers/coach_chat_providers.dart) | 沿用真實 loading、clarification、charged response、重試及 request identity；此單不更動模型、提示詞或扣費邏輯 |
| [HomeCoachPresence](../../../lib/features/partner/presentation/widgets/home_coach_presence.dart) | 參考現有姿勢對齊、淡切與下緣遮罩，先以原圖驗證布局 |
| [motionDisabled](../../../lib/core/animation/motion_preference.dart) | 沿用減少動態與 TickerMode，離頁／背景暫停；格式與播放器等實測後再定 |

播放器由 `SydneyWelcomePortrait` 獨立管理，既有 `CoachSurface` 的閱讀版行為不依賴播放器。此接入沒有追加素材生成；真機需確認循環、靜音、音樂不中斷、離頁釋放與 iPhone 流暢度。

## Flutter 實際畫面

以下是實際 Widget 與示範資料，非 TestFlight 真機截圖。進場保留 Sydney；展開長文後收成標題頭像。

| 進場 | 完整分析 |
| --- | --- |
| ![Flutter 進場](flutter-entry.png) | ![Flutter 完整分析](flutter-expanded.png) |

版本 12701fe 的本地驗證：下列 10 檔共 84 個互動／既有功能／設計棘輪測試通過；四態視覺測試 1 個通過；2 個 runtime 與 1 個測試 Dart 檔 analyze 無問題。後續完成鍵小修新增一個短內容回歸，僅重跑 coach_reading_layout 與 global_coach_screen 共 28 個測試、2 個變更 Dart 檔 analyze，皆通過；未重跑完整組合或截圖。實體 iPhone 與 PR CI 另行確認。

## 原始概念保留

![原始兩狀態概念圖板](sydney-preview-board.png)

[2026-09-05 的待機／思考 show-me](show-me-sydney.html) 為歷史發想，尚未處理完整長文使用流程。當時「交 Bruce 裁決」的交接已由本次 Eric／AI 接手取代；不表示那張圖是定稿。

本 PR 包含 Flutter 版面、入口動態、互動回歸測試與原型文件。未改 AI／額度／資料層，未合併 main 或發布。Widget 測試與截圖不能取代實體 iPhone 的鍵盤、捲動、播放器與觸控驗收。

## 驗證入口

本輪修正了放棄釐清後的失效回答 ID，並在 ID 已不存在時安全回到現有時間軸。回歸包含「正式 A → 深挖釐清 C → 放棄 C → 閱讀 A → 新回答到達」，以實際段落座標確認畫面沒有清空或跳動；失敗路徑也量測同一段落的位置。等待時的草稿、鍵盤、送出限制、費用說明與「新回覆」無障礙標籤皆有斷言。2.5 倍字體會縮小進場人物，正文與開場文字保留使用者字體大小。

前次完整驗證的 10 檔入口（當時 84 個測試；WSL，既有依賴，`--no-pub`）：

```sh
flutter test --no-pub \
  test/widget/coach_chat/coach_reading_layout_test.dart \
  test/widget/coach_chat/global_coach_screen_test.dart \
  test/widget/features/coach_chat/coach_surface_clean_session_test.dart \
  test/widget/features/coach_chat/coach_chat_result_view_compact_test.dart \
  test/widget/features/coach_chat/coach_chat_progress_notice_test.dart \
  test/unit/features/coach_chat/presentation/coach_surface_error_copy_test.dart \
  test/lint/slop_ratchet_test.dart \
  test/widget/features/partner/partner_detail_coach_focus_test.dart \
  test/widget/features/copy_sweep_snapshot_test.dart \
  test/widget/features/analysis/analysis_screen_hydration_test.dart \
  --reporter expanded
```

`test/visual_proof/sydney_reading_layout_capture_test.dart` 另外執行，輸出進場、摘要、完整分析與鍵盤高度四張實際 Widget 截圖；鍵盤圖只模擬可視高度，不是原生鍵盤截圖。

實機檢查：進場人物 → 點引導輸入 → 免費釐清 → 正式回答 → 展開中段追問 → 失敗重試／新答案到達 → 放棄釐清再追問 → 收起 → 切換對象並保留草稿。等待時繼續輸入草稿，確認鍵盤、文字與費用說明仍在，讀到的段落不被自動捲走；另以大字體檢查進場及長文。
