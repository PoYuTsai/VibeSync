# 對象卡互動階段閉環

## 一句規則

每次成功分析，都替該對象寫入一個「本次互動階段」快照；作戰板永遠顯示最新快照，從未成功分析才顯示問號，任何缺值或壞資料都不得假裝成破冰。

## 使用者要看到的六種狀態

| 畫面 | 內部值 | 本次互動的判讀 |
|---|---|---|
| 問號 | 無 stage snapshot | 對象卡已建立，但從未有成功且有效的 AnalyzeChat 階段結果 |
| 冰塊 | `opening` | 真正初次開場；或非伴侶關係在有明確長時間斷聯證據後重新接軌 |
| 火焰 | `premise` | 已超過普通朋友聊天，正在建立男女感、曖昧張力或彼此個人好奇 |
| 天秤 | `qualification` | 正在互相確認價值觀、界線、生活節奏、投入程度或關係期待是否合適 |
| 盔甲 | `narrative` | 正在透過個人故事、情緒、身份與生活樣本深化理解與連結 |
| 邀約物件 | `close` | 對話存在真實邀約窗口、提議、接受、改期或時間地點等可落地證據，適合推進下一個具體安排 |

`normal`、`stuckFriend`、`canAdvance`、`shouldRetreat` 是階段內狀態，不選 3D 圖。

## 判讀規則

1. 一次成功分析恰好產生一個有效 stage snapshot；判的是「這次互動現在最適合做什麼」，不是替整段關係永久升級。
2. 同一對象第 2、3、4 次分析可以換圖。階段不是單向解鎖，也不保留「歷史最高級」；最新成功分析才是作戰板真相。
3. 往前或往後移代表戰術焦點改變，不等於感情變好或變差。例如邀約被婉拒後，下一次可能回到建立男女感或互相評估。
4. `opening` 必須有正面證據：真正第一次接觸，或明確長時間斷聯後重新建立對話。短訊息、普通問候、模型缺欄位、未知字串都不能造成冰塊。
5. `已是伴侶` 永不判成 `opening`。伴侶重新聯絡、修復或生活分享，要依內容落在 premise／qualification／narrative／close；五階段沒有「假破冰」。
6. `close` 不由「已是伴侶」或使用者目標「邀約見面」直接觸發；必須從本次訊息看見可推進的邀約或安排證據。
7. `narrative` 不是中間預設值；只有真的存在故事、情緒、身份或生活樣本深化連結時才能選。
8. 前一次 stage、認識情境與對象歷史是連續性證據，但不能鎖死本次判讀；本次訊息仍是主要證據。
9. AI 缺少、寫錯或輸出無法映射的 stage 時，本次不得寫入新快照；保留上一個有效階段。若從未有有效階段，維持問號。

## 資料閉環

```text
一批截圖／訊息
  → AnalyzeChat 依本次內容＋認識情境＋對象歷史選一個 stage
  → 僅在完整分析成功且 stage 有效時寫入 stage snapshot
  → snapshot 綁定 partnerId 與分析完成時間
  → 作戰板按分析完成時間取該對象最新有效 snapshot
  → 映射成對應 3D 圖；完全沒有 snapshot 才映射問號
```

### 既有資料相容

- 新的 append-only `AnalysisHistoryEvent.analyze` 是最新階段的優先來源，使用 `createdAt` 排序。
- 舊資料若沒有 history event，可從 Conversation 的有效分析快照／`currentGameStage` 做 legacy fallback。
- legacy fallback 只接受五個合法值；未知值不准透過 `GameStage.fromString` 默認成 opening。
- 修改對象卡的認識情境後，新分析片段必須取得最新對象設定；既有非空 `SessionContext` 不得靜默擋住新的 `meetingContext`／`duration`／`goal`。

## 實作範圍

1. **分類契約**：強化 AnalyzeChat system/stream prompt 的五階段判準與 opening guard；不得呼叫付費模型做驗證。
2. **輸出守門**：缺少或非法 stage 不能變成 `opening`，也不能覆蓋上一筆有效 snapshot；不得改壞既有 quota／retry 的 exactly-once 語意。
3. **情境接線**：修正 partner-bound 新片段／截圖匯入，確保「已是伴侶」等最新設定真的送進下一次分析。
4. **作戰板真相**：優先用最新成功的 partner-scoped history event 取 stage，Conversation 僅作 legacy fallback；不得用普通 `updatedAt` 把舊分析誤當最新。
5. **無額度預覽**：提供不呼叫 AnalyzeChat 的六狀態預覽 seam，能一次看見問號與五張 stage 圖；不得把測試入口暴露成一般正式功能。
6. **領域文件**：實作不得違反根目錄 `CONTEXT.md` 的詞義。

## 已確認的測試 seams

這些 seams 由 Eric 的「照建議處理」承接前一輪提案，視為已確認：

1. **Edge 分類契約 seam**：給 prompt builder／stream reframer 固定輸入，驗證五階段判準存在、合法 stage 可通過、缺值／非法值不會成為 opening。
2. **Flutter 完成分析 seam**：用一個成功 `AnalysisResult` 經公開 persistence coordinator，驗證 partnerId、stage 與完成時間形成可讀的最新快照；失敗或非法結果不覆蓋舊值。
3. **報告作戰板 seam**：用多個 partner-scoped history events 與 legacy conversations，驗證每個對象只取最新有效分析、未知值顯示問號、一般 Conversation 更新不改寫階段順序。
4. **情境 seam**：從對象卡最新設定建立下一個分析片段，驗證 committedPartner 不被舊 Conversation context 吃掉，且 request payload 實際送出 `已是伴侶`。
5. **資產預覽 seam**：一個測試／開發入口一次渲染六個狀態，逐一斷言正確 asset path 與可見標籤，全程不呼叫 AI。

## TDD 與驗證要求

- 每個垂直切片先出會失敗的行為測試，再做最小修改轉綠；不要先一次寫完所有測試。
- 優先測公開 seam，不 mock 專案內部 class；外部 AI／資料庫邊界可用固定 fixture。
- 執行最小目標測試後，再依環境契約於 WSL 執行相關 analyze／較寬測試。
- 不呼叫真實 Anthropic／Supabase production，不 push、不部署、不開 PR。
- 最後精準 commit 任務檔案，回報 commit SHA、變更檔案、測試命令與任何未解風險，交由 Codex 主審。

## 驗收案例

1. 新對象卡、零成功分析 → 問號與「尚未分析」。
2. 同一對象依序得到 premise、qualification、close → 作戰板依序換成火焰、天秤、邀約圖，不保留歷史最高或第一張圖。
3. 同一對象最新分析從 close 回到 qualification → 顯示天秤；文案不得暗示關係退步。
4. 已是伴侶＋短生活訊息／個人分享 → 不得顯示冰塊；依證據可為 narrative 等其他階段。
5. 非伴侶且有明確長時間斷聯後重新開場 → 可以顯示冰塊，但語意是重新接軌，不是關係清零。
6. 已是伴侶＋「週六兩點去那間咖啡店？」「好」 → 可以顯示 close，因為有本次安排證據，不是因為伴侶標籤。
7. stage 缺失、`vibing hard` 或其他未知值 → 不得顯示冰塊；有舊快照就保留舊圖，沒有就問號。
8. 對 Conversation 只改名字或其他普通欄位 → 不得讓它超車較新的分析事件。
9. 在對象卡把認識情境改成已是伴侶後建立下一片段 → Edge request 收到 `meetingContext: 已是伴侶`。
10. 六狀態預覽 → 六張資產都能載入，且零網路／零模型呼叫。
