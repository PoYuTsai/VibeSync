# 「關於我」批4：三項各自獨立評估 — 設計定案

> **狀態**：11／12 設計已與 Eric 確認，尚未實作；13 拍板暫不做。三項各自獨立，不綁同批實作/部署。
> **上游報告**：附檔報告第190–199行「第四批」。

## 11. 練習檢討用「我想達成什麼」當評分依據

**現況查證**：`practice-chat` 完全不讀 `UserProfile`（與報告表格一致：練習室在對話分析/開場白/Coach/鍵盤四張表裡全部是 ❌）。debrief prompt（`supabase/functions/practice-chat/prompt.ts`）純粹依對話內容、溫度、親密度產拆解卡，不知道用戶目標。

**決定**：只傳批2的 A2「我想達成什麼」進 debrief prompt，讓拆解卡評語多呼應一句用戶目標（例如用戶選「想約得出來」，評語點出這次對話有沒有往那個方向推進）。

**明確界線**（沿用報告原文）：
- 不傳 A1「我現在卡在哪」——那是 Coach 1:1 的處境資訊，debrief 評的是這次對話表現本身
- 不傳邊界（notes）——不是評分依據
- 不影響練習對象個性（那是抽卡決定的既定機制）
- 不動 hint 提示那一塊（守門機制密度高，報告已明講風險不成比例，不值得為這項牽動）

**風險**：中——新的 AI prompt 注入點，需雙審；範圍窄（只加一行 context 影響評語措辭，不動 schema、不動任何守門邏輯）。

## 12. AI 鍵盤只送邊界

**現況查證**（比報告原文更具體，實際讀過程式碼）：鍵盤**現在其實已經在送風格**——`ios/SharedKeyboard/KeyboardContextEnvelope.swift` 的 `globalVoice: KeyboardVoice`（primary/secondary 風格）會被寫進 App Group 共享儲存，並在 `KeyboardAssistPendingReplay.swift`／`KeyboardScreenshotAssistCoordinator.swift` 讀出、送進 AI 請求。這正是報告要推翻的「鍵盤送風格＝純模仿」情境，而且 envelope 目前完全沒有邊界／notes 欄位。

**決定要做的三件事**：
1. `KeyboardContextEnvelope` 新增邊界欄位（例如 `boundaryNote: String?`），App 端從 `UserProfile.notes`（批2改問法後即為邊界文字）寫入
2. 移除 `globalVoice` 在 AI 請求 payload 裡的實際使用——envelope 型別本身要不要整個拿掉 `globalVoice`、或保留欄位但不再讀取，留給實作階段依測試影響範圍決定
3. `schemaVersion` 需要 bump（現為 1），連帶要更新 `KeyboardAssistArchitectureTests.swift` 等既有原生測試

**風險**：中高——跨 App／Keyboard Extension 兩個 process 的原生 Swift 改動，Eric 沒有本地 Mac，只能靠 GitHub Actions 的 iOS build 驗證，肉眼難以直接 debug，出錯只能重新出 build 排查。

## 13. 資料上雲

**拍板**：暫不做。這項本質是產品／隱私決策，不是技術問題——新增伺服器上的個人資料會牽動隱私政策揭露與 App Review 隱私問卷，而 VibeSync 目前仍在 TestFlight dogfood 穩定期，不是加這類變動的好時機。

**重新評估時機**：等 App 正式送審通過、進入常態迭代後，如果「換手機歸零」「鍵盤讀不到 App 端設定」「看不到真實填寫率」這幾個現有痛點真的變成用戶明確抱怨的熱點，再重新拿出來評估要不要做。目前不排進任何實作計畫。

## 三項的獨立性

11／12／13 彼此沒有實作依賴，也不依賴批2／批3是否已出貨（11 只需要批2的 A2 欄位存在；12 不依賴批2/3 的任何 App 端改動，是純鍵盤邊的獨立工程；13 現在不做）。可以任選其一單獨排入實作，不需要湊批次。
