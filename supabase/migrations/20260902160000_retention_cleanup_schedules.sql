-- 資料保留期限排程（2026-09-02 隱私政策對齊）。
--
-- 背景：cleanup_expired_analysis_stream_runs() 與 cleanup_old_ai_logs() 早就存在，
-- 但從來沒有被 pg_cron 排程，等於已扣費的分析結果（含 AI 產生的 recommendation_json／
-- final_result_json）與 ai_logs 技術紀錄都保留到帳號刪除。本檔：
--   1. analysis_stream_runs：未扣費且過期者維持 1 小時後清除；已扣費者改為扣費後 30 天清除
--      （30 天而非 7 天：Analyze v2 dogfood 的 telemetry 黑箱要回看近一個月的 run）。
--   2. ai_logs：沿用既有 30 天函式，但補上 SECURITY DEFINER／固定 search_path，
--      並收回 anon／authenticated 的 EXECUTE（原檔用預設授權，任何登入者都能呼叫清理）。
--   3. 兩支函式各排一個 pg_cron job（每小時／每日 04:10 UTC），重跑冪等：先 unschedule 同名。
-- 沒有 pg_cron 就不能有「保留期限」這回事，所以正式環境缺 pg_cron 直接讓 migration 失敗
--（沿用 20260716170000 的慣例）；只有 PGlite 契約測試透過 GUC app.allow_missing_pg_cron=on 放行，
-- 測試只驗函式本體與權限。

CREATE OR REPLACE FUNCTION public.cleanup_expired_analysis_stream_runs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.analysis_stream_runs
  WHERE (charged_at IS NULL AND expires_at < now() - interval '1 hour')
     OR (charged_at IS NOT NULL AND charged_at < now() - interval '30 days');

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- 已扣費列的清理走 charged_at；既有索引只有 (user_id, expires_at) 與 (expires_at)
CREATE INDEX IF NOT EXISTS analysis_stream_runs_charged_at_idx
  ON public.analysis_stream_runs (charged_at)
  WHERE charged_at IS NOT NULL;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() TO service_role;

-- 原函式（00003_ai_logs.sql）RETURNS void；CREATE OR REPLACE 不能改回傳型別，先 DROP。
-- 沒有任何物件依賴它（未曾被排程或呼叫），DROP 安全。
DROP FUNCTION IF EXISTS public.cleanup_old_ai_logs();

CREATE FUNCTION public.cleanup_old_ai_logs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.ai_logs
  WHERE created_at < now() - interval '30 days';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_old_ai_logs() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_old_ai_logs() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_ai_logs() TO service_role;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    IF current_setting('app.allow_missing_pg_cron', true) = 'on' THEN
      RAISE NOTICE 'pg_cron not available; retention jobs skipped (test mode)';
      RETURN;
    END IF;
    RAISE EXCEPTION 'pg_cron is required to schedule retention cleanup jobs';
  END IF;

  CREATE EXTENSION IF NOT EXISTS pg_cron;

  FOR v_job_id IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('cleanup-expired-analysis-stream-runs', 'cleanup-old-ai-logs')
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-analysis-stream-runs',
    '17 * * * *',
    'SELECT public.cleanup_expired_analysis_stream_runs();'
  );
  PERFORM cron.schedule(
    'cleanup-old-ai-logs',
    '10 4 * * *',
    'SELECT public.cleanup_old_ai_logs();'
  );
END
$schedule$;
