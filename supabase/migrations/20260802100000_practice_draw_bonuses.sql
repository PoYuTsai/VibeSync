-- 起步清單一次性贈抽（2026-08-02，批 3 抽卡獎勵改造 A 案）。
--
-- 產品規則（docs/plans/2026-08-01-remove-guest-checklist-draw-reward.md）：
--   free 每日免費翻牌 1→0（starter 3／essential 5 保留）；改為「起步清單全部
--   完成 → 送一次性免費抽卡」，全 tier 皆可領一次。
--
-- 設計：
--   一人一列（user_id PK）＝終身最多一次；grant 走 INSERT ON CONFLICT DO NOTHING
--   天然冪等（client best-effort 重呼無害）。消耗採懶標記：Edge 在算免費額度時
--   對未消耗者 +1，抽出 cost=0 且本窗免費數「超過 tier 額度」那次才標 consumed_at
--   ——tier 額度夠用時不動贈抽（對用戶最有利）。標記失敗（crash）只是下窗再 +1，
--   自癒且風險封頂一抽。
--
-- 濫用面：grant 由 client 宣稱清單完成觸發（清單訊號在本機，server 無從驗證），
-- 最大暴露＝每帳號一次免費抽，接受（拍板見計畫檔）。
--
-- service_role only：RLS 開啟且零 policy，client 摸不到，僅 Edge service client
-- 與（如未來需要）SECURITY DEFINER RPC 可讀寫。

CREATE TABLE IF NOT EXISTS public.practice_draw_bonuses (
  user_id     UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  source      TEXT        NOT NULL DEFAULT 'getting_started'
              CHECK (length(source) BETWEEN 1 AND 32),
  granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  consumed_at TIMESTAMPTZ
);

ALTER TABLE public.practice_draw_bonuses ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.practice_draw_bonuses IS
  '起步清單一次性贈抽帳本：一人一列、grant 冪等、消耗懶標記（超過 tier 額度的 cost=0 抽才消耗）。';
