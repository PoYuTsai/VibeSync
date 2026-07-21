# 教練統一 Phase E Task 8 Step 2：live e2e 證據（2026-07-22）

環境：prod Edge（Phase E 10 commits 未動 `supabase/`，prod 即正確標的）。
帳號：vibesync.test@gmail.com（uid `8aa6e41c-f175-497b-8503-5f6a86dfa5d8`，essential/active）。
方法：curl 模擬 client wire（NDJSON 串流，body 依 `coach_chat_api_service.dart` 合約）；PAT 查 `coach_requests`／`subscriptions` 對帳。

## Scope 1：conversation（分析頁）

| 發 | 內容 | 結果 |
|---|---|---|
| 1 | 模糊問題（無 forceAnswer） | `clarifyingQuestion`，costDeducted=0，串流事件 request→generating→validating→finalizing→done 完整 |
| 2 | 釐清輪補充（activeSessionTurns 帶 question/clarification，新 requestId） | `coachAnswer`（狀態校準卡） |
| 3 | `forceAnswer:true` 續問邀約 | `coachAnswer` 含 suggestedLine |

## Scope 2：partner（對象頁）

| 發 | 內容 | 結果 |
|---|---|---|
| 4 | chip 實際 prefill 文案「我想約她出來，該怎麼開口比較自然？」＋`lifecyclePhase:"prepareInvite"`＋partnerHint | `clarifyingQuestion`，costDeducted=0 |
| 5 | 釐清補充（同 session turns，新 requestId） | `coachAnswer` 含具體邀約 suggestedLine |

## 帳本對帳（PAT 直查）

- `coach_requests` 恰 5 row，`request_id` 與 client 端 uuidgen 產出的 5 個**逐一相符**、順序一致，全部 `state='done'`。
- 兩則釐清 row `quota_charged=false` ✅（計畫要求）。
- Replay：同 requestId＋同 body 重送 → 直接回 `coach.done`（無 generating 階段）、卡 byte-for-byte 一致、**帳本無新增 row** ✅。
- 竄改 body 同 requestId → `409`（REPLAY_MISMATCH）✅。

## 已知偏離（非缺陷）

1. **「正式建議扣 1」在測試帳號結構上不可觀測**：`index.ts:465` `TEST_EMAILS` 含此帳號 → `generation.ts:251` `shouldCharge = shouldDeduct && !accountIsTest` 恆 false，所以 5 row 全 `quota_charged=false`、subscriptions 計數維持 0/0。此為 App Review 測試帳號既有設計（Phase E 未動 Edge）；扣費路徑由 Phase C Deno 測試覆蓋。
2. **read-bridge（對象頁歷史含舊 follow-up 卡）為純 client 本地 Hive 讀取**（typeId 16 經 `UnifiedCoachResult.fromFollowUpResult` 唯讀映射），curl 打不到；由 Phase D/E repo 與 widget 測試覆蓋，真機即時性留 Eric dogfood＋Codex 審查觀察點。
3. 發 2（未 force）回 `coachAnswer` 但 server 判 no-charge 卡（repair 保守路徑）——與計費不變式「扣 1 ⇔ AI 真生成」一致，非異常。
