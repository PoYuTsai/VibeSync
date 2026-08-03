# 「關於我」批3：AI 指令風格反轉 — 設計定案

> **狀態**：設計已與 Eric 逐段確認，尚未實作。屬高風險區（動 AI prompt、影響 token/cost、會刻意打破 `effective_style_prompt_builder` 既有的「主-only 輸出 byte-for-byte 不變」鎖測試），實作完成後必須雙審才可部署。
> **上游報告**：附檔報告第177–188行「第三批」；依 Eric 拍板，8/9/10 三項合併一次做、一次審、一次部署，不拆階段出。
> **前置依賴**：批2（欄位重新設計）落地後，`effective_style_prompt_builder.dart` 讀的欄位形狀會先變（`practiceGoals` → 新的「我想達成什麼」），這是批2實作的機械性調整，不影響本批設計。

## 一、指令反轉（項目8）

`lib/features/user_profile/domain/services/effective_style_prompt_builder.dart` 的 `_voiceLine`：

現在（送進 analyze-chat/opener 的文字）：
```
- Preferred voice: 穩重；回覆乾淨穩定，不急著推進，也不要過度解釋
```

改成舒適區框架：
```
- 使用者目前的舒適區：穩重。這不是你要模仿的模板，是他現在寫得出來的範圍。
- 五種回覆風格請照常全力發揮，不要因為舒適區而收斂任何一種；至少一種要明顯超出他的舒適區。
```

主＋副風格並存時，兩行比照現有主/副架構各自擴寫（副風格維持點綴、不蓋過主基調的既有規則不變）。

適用範圍：analyze-chat 分析、opener、new topic 三處注入點皆同步改（`buildForAnalysis`／`buildForOpener`／`buildForNewTopic` 共用 `_voiceLine`）。

## 二、AI 自判延伸程度（項目10）

現況：`analyze-chat` 的 `openers` schema 是 `{extend/resonate/tease/humor/coldRead: 純字串}`；批1的 `ReplyStretchClassifier` 是純 client 端本地對照表（只看主風格，準確度有限，`lib/.../reply_stretch_classifier.dart` 裡已註記「之後由批3 #10 改成 AI 自己判斷取代」）。

**決定**：不改動 `openers` 既有形狀（改了要動全部呼叫端與既有測試）。新增一個平行欄位：

```
"stretchLevels": {
  "extend": "within" | "stretch" | "far",
  "resonate": "within" | "stretch" | "far",
  "tease": "within" | "stretch" | "far",
  "humor": "within" | "stretch" | "far",
  "coldRead": "within" | "stretch" | "far"
}
```

AI 跟五則開場白／回覆一起產出，寫進 prompt 的 schema 說明裡（連同"至少一則要 stretch"的要求）。client 端 `ReplyStretchClassifier.classifyByTypeString` 停用（保留檔案當歷史對照或直接刪除，實作階段再定），改讀這個新欄位。repair prompt（`OPENER_REPAIR_PROMPT`）也要同步補上 `stretchLevels` 的 schema 說明，否則修復流程會遺漏這個欄位。

## 三、Coach 1:1 補讀處境與邊界（項目9）

`buildForCoachFollowUp`（`coachFollowUpMaxChars = 500`）目前故意排除 notes/topics，只給風格＋目標，理由是原本怕教練被拖去做長期人格判斷。這批要加回：

- 「我現在卡在哪」（批2新增的 A1，取代原本被排除的內容）
- 「想讓 AI 知道的事」（邊界，批2改問法後這欄專門講邊界）
- 常聊話題／自訂話題仍不需要（教練不需要素材，只需要處境）

**連帶調整**：內容變多，後端 `supabase/functions/coach-chat/schemas.ts` 的 `effectiveStyleContext: z.string().max(500)` 上限要放寬到 900（對齊分析/開場白的 `analysisMaxChars`/`openerMaxChars`），Dart 端 `EffectiveStylePromptBuilder.coachFollowUpMaxChars` 同步從 500 改 900。

## 四、順手清理：兩行死指令

`supabase/functions/analyze-chat/index.ts` 裡兩處舊 `sessionContext` 欄位（`userStyle`／`userInterests`，行號約 6796-6797、7441-7442）永遠是「未提供」／"not provided"，跟同一次請求裡真正生效的 `effectiveStyleContext` 打架，直接砍掉。低風險，同批一起做。

## 五、不在本批範圍

- 不動練習檢討評分依據、AI 鍵盤傳遞邊界、資料上雲（批4，各自獨立評估）
- 不動練習對象個性、不動提示守門機制
- 不擴充自述 100 字上限本身（批2已拍板不動；本批只放寬的是後端 `effectiveStyleContext` 組合後的總長度上限，不是使用者輸入欄位的字數上限）

## 六、驗證與部署要求

- 既有「主-only 輸出 byte-for-byte 不變」快照測試會被本批**刻意打破**——這是預期行為，需要對照新舊輸出明確記錄差異，不能順手改掉測試了事
- `OPENER_REPAIR_PROMPT` 與主 schema 兩處都要同步更新並各自跑過修復流程的測試
- 實作完成後走 Codex 雙審（AI prompt/token/cost 屬 Critical Gotchas 高風險區），至少一輪對抗式審查
- 部署後留 Eric 真機 dogfood：分析結果能不能看到 stretch 標記、Coach 1:1 能不能接住「我常聊到一半冷掉」這類處境
