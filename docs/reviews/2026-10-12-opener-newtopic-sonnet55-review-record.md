# 開場救星與新話題：上線前修正與換 Sonnet 5.5 準備（ADR #54）審查紀錄

- 本機分支 `claude/opener-newtopic-55`，base 是 main `38ab7dbb`。程式由 Claude（Anthropic）撰寫。
- Eric 交辦原話（2026-10-12）：對唯讀評估的三項決定回「照建議」——這一輪先修 bug、介面問題和換 5.5 的卡點（不花錢），Codex 主審後再跑付費黑箱，過關才開開關。
- R2：開場救星與新話題的扣費與失敗路徑（拒答整次不扣）、模型開關、Edge 錯誤碼與 App 顯示、去識別化漏斗事件。不動 DB、migration、提示詞、帳本格式；共用模型呼叫程式依分工不在本分支。
- **主審（關卡）**：Codex（OpenAI）唯讀，`codex exec --sandbox read-only -m gpt-6-astra`（reasoning high），預設兩輪（全範圍一輪＋修正後差異複核一輪）。送審封包是純檔案樹＋format-patch＋背景說明＋測試證據，`SHA256SUMS.txt` 的 sha256 記在下表；封包與回覆原文留在 Claude 暫存區，回覆全文另抄在本文。

| 輪 | 範圍（base → head） | 審查 tree | packet manifest sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|---|
| 主審 1 | `38ab7dbb` → `6e330cd44c5dd49546dfbc3ef346a34d92b145d3` | `d8e2409262b010066fa3d0cc784c9832072f82ee` | `da0e7d06297924e73b3a494f281acecf7f73e3a0f1a2e0afadb078148f43efb6` | `a4d0cce0d67aab66c61b2e32c7b1c38fa6c1f52bd6737d78e8b3ca228b86535d` | BLOCKED |

## 主審 1 的發現與處置

| # | 等級 | 發現 | 處置 |
|---|---|---|---|
| 1 | P1 | 結構刀的改寫被拒答時，程式吞掉錯誤、拿掉那張卡照交付並扣額度，違反「拒答整次不扣」。 | 同一個請求裡任何一步被拒答都整次失敗：結構刀的修格式、改寫，舊路徑的修格式與內容修正，第一段的修格式，新話題的修格式。回 422、不扣、不結算。測試在修正前會失敗。 |
| 2 | P2 | 被拒答的草稿重新打開時，App 會用同一筆內容自動重送，再花一次模型費用；第一段分析的草稿也一樣。 | App 認得 `OPENER_CONTENT_REFUSED`：生成被拒答時清掉送出快照、草稿退出「生成中」；分析被拒答時不留「分析中」的紀錄。重開草稿不會自動重送。測試在修正前會失敗。 |
| 3 | P3 | 兩段「捲到看得到進度」的動畫重疊時，第一段的完成回呼會提早清掉旗標，結果到時定格又被跳過。 | 旗標加編號，只有最新那段動畫可以清掉；補交錯情境測試（修正前會失敗）。 |

- 主審 1 列的殘餘風險：用戶給的原文含「人間失格」時，說明欄出現「先讓她失格」也會被放行。這是既有子字串豁免的限制，本分支把豁免範圍擴大到對象作戰板摘要與關於我，一併繼承。接受為殘餘風險，不另加字串規則。

### 主審 1 回覆全文

```
本輪發現 **1 項 P1、1 項 P2、1 項 P3**；拒答後仍可能扣額度，需先修正。

審查範圍：`38ab7dbb` 至 `6e330cd44c5dd49546dfbc3ef346a34d92b145d3`。以下行號均指 head。

1. **P1 — 改寫拒答仍可能成功結算。**  
   `supabase/functions/analyze-chat/opener_plan_write.ts:278` 新增的拒答判斷未涵蓋第 405 行的改寫 catch。具體情境：寫手產出一張違反限制的卡，改寫呼叫被拒答；程式吞掉錯誤、移除該卡，再交付其他卡。唯讀本機診斷已重現 `plan → write → rewrite` 後仍回傳 `kind: "ok"`；handler 第 951 行因此進入結算，首次生成仍扣額度，違反「拒答整次不扣」。應讓修格式與改寫也回傳 `fail("refusal", ...)`，並驗證釋放 claim、完全不呼叫 settle。

2. **P2 — 拒答草稿重新開啟會自動重送。**  
   `supabase/functions/analyze-chat/opener_flow_handler.ts:940` 新增 `OPENER_CONTENT_REFUSED`，但 App 未將它處理為已終止請求。`opener_flow_controller.dart:640` 未清除其 pending 與持久化的 `generating` 狀態。使用者重新開啟草稿時，`opening_rescue_screen.dart:745` 會自動重送相同內容，再次產生模型費用；文字分析草稿亦有相同問題。應辨識拒答碼，保留可編輯素材，但清除 pending 並保存非執行中狀態。

3. **P3 — 重疊進度動畫仍會漏掉結果定位。**  
   `lib/features/new_topic/presentation/widgets/new_topic_view.dart:179`：開始生成及首個串流事件各會觸發捲動。第二次動畫取消第一次後，第一次的 `whenComplete` 會清掉 `_revealingProgress`，此時第二次仍在捲動。若結果隨即抵達，第 153 行會略過定位，之後沒有補做。已核對 Flutter 取消動畫時確實完成舊 Future。應用遞增識別碼，僅允許最新動畫清除旗標，並補上交錯情境測試。

其餘指定範圍未發現具體新增阻擋問題。殘餘風險：既有子字串豁免會讓「人間失格」同時放行說明中的「先讓她失格」；本次擴大適用欄位，也繼承此限制。

全程唯讀，未使用網路、付費 API 或 Flutter。已閱讀測試證據，未重跑全套；P1 另以禁止網路的本機診斷重現。`changes.patch` SHA-256：`b13bcda154209fddc33b2f6e94b3a2d710dc74e64179a1f6a6f812dba9b7204f`。

VERDICT: BLOCKED
```
