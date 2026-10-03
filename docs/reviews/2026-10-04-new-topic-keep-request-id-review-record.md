# 新話題離開畫面不重扣（D2）：主審紀錄（2026-10-04）

分支 `claude/new-topic-keep-request-id`，base `d28167a1`。程式由 Codex（OpenAI）撰寫，主審 Claude（Anthropic）。Eric 授權原話：「先專心處理D2」「這輪乾淨把D2處理完成，推上去」。

| 輪 | 審查 head | 封包 sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 1 | f760bd2d | 673ffa6c2b5dbd620d93d832c109bfd3037cd8beeb65b961ebc6eecfc35dd15e | 5be0da7401c535202e077368ecc9835d043a9bdb5d4039d7296fdf504bc8c0f5 | APPROVED |

## 第 1 輪回覆

````text
主審（Claude，非實作家族；實作者 Codex）— 對 f760bd2dc80f4bc4f554bc86ecdc2f8d61db487e 的補丁（packet sha256 673ffa6c2b5dbd620d93d832c109bfd3037cd8beeb65b961ebc6eecfc35dd15e）
- 正確性：NewTopicRequestSession 由 widget State 移到非 autoDispose 的 Provider.family，key＝(ownerId, partnerId)；beginAttempt／markSuccess／pendingFor 語意不變。成功、素材被擋、伺服器佔號拒絕時 markSuccess 照舊；對象被刪除時改成清掉該對象 session。換帳號走不同 key，不會帶到他人編號。不寫儲存、不改畫面文案。
- 扣費：只改 App 端請求編號保留範圍；伺服器以 requestId 重播 24 小時內已付費結果的既有語意不變，同答案重送不會產生新扣費；答案改變照常換號。
- 測試：新增 5 個 provider 單元測試、2 個畫面卸載重建測試；本機 flutter test new_topic 126 passed、flutter analyze 0 issue；把 lib 改回舊版時「生成中離開並重建畫面，同答案送出相同 requestId」失敗，套回通過。
- P3：未登入（owner 為 null）時按生成改成靜默不動作（新話題本來就需要登入）；session 只活在 App 執行期間，App 重開不保留（刻意）。
VERDICT: APPROVED
````
