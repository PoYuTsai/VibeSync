-- Codex P2（2026-07-23）：ai_logs.response_body 自單發 v2 觀測補強起會含
-- 被 gate 打回的候選原文——產品層拒絕顯示的內容不得讓已登入用戶自查。
-- client（lib/）從不讀 ai_logs，移除用戶 SELECT policy 無功能影響；
-- RLS 維持開啟，無 SELECT policy ＝ authenticated 查回零列。
-- 服務端寫入（service role insert）與 PAT/Management API 查詢不受影響。
DROP POLICY IF EXISTS "Users can view own logs" ON ai_logs;
