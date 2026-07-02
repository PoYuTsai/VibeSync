-- practice-chat 殘留 RPC 清理（2026-07-03）
--
-- ⚠️⚠️⚠️ 部署順序鐵則 ⚠️⚠️⚠️
-- 必須在新版 practice-chat Edge 部署完成後才可套用！
-- 生產現在部署的舊版 Edge 仍在呼叫 4-arg commit_practice_chat_turn；
-- 先套本檔會把舊 Edge 的 chat 扣費打斷（function not found）。
--
-- 清理對象（全部已無新版呼叫點）：
--   1. update_practice_temperature(UUID, TEXT, INTEGER)
--      —— 20260628130000 起由 update_practice_learning_state 取代，生產已不呼叫。
--   2. commit_practice_chat_turn 4-arg 舊 overload（20260624120000 起、DEFAULT 10）
--      —— 新版 handler 只用 7-arg（dual-axis）簽名。
--   3. commit_practice_chat_turn 6-arg 舊 overload（20260628120000 起）
--      —— 同上，已被 7-arg 取代。
--
-- 7-arg（UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER）為現役簽名，
-- 絕不在此清理。整檔可重放（DROP IF EXISTS）。

DROP FUNCTION IF EXISTS public.update_practice_temperature(UUID, TEXT, INTEGER);

DROP FUNCTION IF EXISTS public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER);

DROP FUNCTION IF EXISTS public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER);

-- 移除 overload 後刷新 PostgREST schema cache，named-arg 解析立即收斂到 7-arg。
NOTIFY pgrst, 'reload schema';
