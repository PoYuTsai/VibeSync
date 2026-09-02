# Migration 帳本

> 唯一權威是 remote：`supabase migration list --linked`（Windows 端 `supabase.exe` 已登入可直跑）。本檔是人讀的對照摘要，新 migration 上 production 後在此補一行；懷疑漂移時以 remote 為準重新對帳，不要憑本檔判定。

**最近一次全量對帳：2026-09-02** —— 本地 repo ↔ remote 一比一全對齊，無 pending。最新一支 `20260902150000`。

## 2026-08-22 → 2026-09-02（12 支）

| Migration | 用途 |
|---|---|
| `20260822120000_practice_moment_posts.sql` | 練習室 moment 貼文 |
| `20260824063344_practice_moment_reserve_usage_gate.sql` | moment 用量預留閘門 |
| `20260825120000_practice_moment_images.sql` | moment 圖片 |
| `20260825150000_practice_moment_image_expiry_guards.sql` | moment 圖片到期守門 |
| `20260826024500_practice_moment_image_orphan_ledger.sql` | moment 孤兒圖片帳本 |
| `20260827080000_practice_moment_slot_states.sql` | moment slot 狀態 |
| `20260831180000_coach_answer_v2_card_fields.sql` | 教練 Batch B2：CoachAnswerV2 card 欄位白名單 |
| `20260901120000_feedback_coach_categories.sql` | feedback 教練分類 |
| `20260902120000_analysis_stream_runs_decision_kind.sql` | Analyze Phase 1a：stream run 決策種類 |
| `20260902130000_admin_ops_v2_baseline.sql` | 後台 B0：admin_ops 契約表（原 20260831120000 改版號，2026-09-02 上線） |
| `20260902140000_admin_identity_v2_baseline.sql` | 後台 B1：管理員身分、session、append-only audit（原 20260831150000 改版號） |
| `20260902150000_admin_notify_feedback_breakglass_v2_baseline.sql` | 後台 B2：通知 outbox、metadata-only feedback、break-glass（原 20260831180000 改版號） |

## 2026-07-07 → 2026-08-13（build 311→473 窗口，31 支）

| Migration | 用途 |
|---|---|
| `20260707053000_practice_partner_state.sql` | 練習室對象關係狀態快照（BetterSimTracker 式） |
| `20260708120000_practice_game_mode.sql` | 練習室 Game Mode 加入 practice_mode allowlist |
| `20260708130000_practice_game_state_relationship_threads.sql` | Game 狀態＋關係線續接（additive，Edge fail-open 先行） |
| `20260708143000_practice_game_delta_clamp.sql` | Game Mode 分數 delta clamp（beginner 維持 ±12） |
| `20260710120000_practice_debrief_idempotency.sql` | 練習室 debrief requestId 冪等回放 |
| `20260711120000_practice_hint_prefetch.sql` | Hint 預取：bounded per-request ledger＋消耗時結算 |
| `20260711150000_practice_ai_no_canned_fallback.sql` | Hint/Debrief generated-only 契約（禁罐頭 fallback） |
| `20260712200532_practice_hint_quality_schema_version.sql` | DB 回放 predicate 對齊 Edge 品質守門 schema 版號 |
| `20260713120000_practice_debrief_semantic_owner_window.sql` | Debrief 語意複審先行；single-flight owner 存活窗延長 |
| `20260716170000_optimize_message_fixed_charge.sql` | 「我幫你修」成功固定扣 1 則＋同 requestId 只扣一次 |
| `20260717120000_keyboard_reply_exactly_once.sql` | AI 鍵盤文字回覆 exactly-once 帳本 |
| `20260719170000_practice_hint_review_schema_version.sql` | Hint 回放需雙獨立語意審核一致才認證 |
| `20260721120000_coach_exactly_once.sql` | Coach 1:1 exactly-once（ADR #22 模板） |
| `20260723120000_ai_logs_drop_user_select.sql` | ai_logs 撤銷已登入用戶 select（被 gate 打回的候選原文不得自查） |
| `20260724120000_new_topic_exactly_once.sql` | New Topic（破冰腦力）exactly-once（ADR #22 模板） |
| `20260724180000_new_topic_formula_topics.sql` | New Topic ledger 允許第四鍵 formulaTopics（0–2 則公式新話題） |
| `20260727130000_keyboard_assist_exactly_once.sql` | 鍵盤單張截圖輔助 exactly-once 帳本（不存影像/逐字稿） |
| `20260728060000_keyboard_assist_three_angles.sql` | 截圖輔助結算 validator 認得產品實出的三角度 |
| `20260728100000_keyboard_assist_score_words_not_percent.sql` | 結算改守分數字詞、不再見 % 就拒 |
| `20260729000000_refine_free_allowance.sql` | 「再調一下」每日免費額度 |
| `20260801000000_funnel_events.sql` | 去識別化漏斗埋點表（僅 submit-feedback service role 寫入） |
| `20260801120000_practice_prepare_guest_skip_reset.sql` | 訪客模式：匿名帳號跳過練習額度歸零（後由 150000 移除） |
| `20260801130000_users_email_nullable_for_guest.sql` | users.email 改 nullable（匿名帳號 NULL email 曾使 signup 整筆回滾） |
| `20260801150000_practice_prepare_remove_guest_skip.sql` | 訪客模式移除（ADR #34）：還原無條件歸零，撤 120000 分支 |
| `20260802100000_practice_draw_bonuses.sql` | 起步清單一次性贈抽（抽卡獎勵改造 A 案） |
| `20260802120000_claim_draw_bonus_atomic.sql` | 贈抽判定與消耗併入 claim RPC 同交易（修 Edge 先讀後傳雙花） |
| `20260808155202_practice_sr_draw_tickets.sql` | 訂閱送 SR 限定翻牌：券表＋bonus_source 標記 |
| `20260808155210_claim_draw_exclude_sr_ticket.sql` | 主 claim RPC 的 free_used 計數排除券抽 |
| `20260808155220_claim_sr_ticket_draw_rpc.sql` | SR 券消耗 RPC |
| `20260809120000_get_practice_draw_status.sql` | 圖鑑額度列 v2：唯讀翻牌額度狀態 RPC |
| `20260813003000_stream_analysis_retry_lease.sql` | 串流分析重試改 in-flight lease 預留 |

## 2026-07-07 之前（48 支）

未逐一回填；以 remote 對帳結果為準（2026-08-19 已核實全對齊）。需要細節時直接讀 `supabase/migrations/` 內各檔開頭註解。
