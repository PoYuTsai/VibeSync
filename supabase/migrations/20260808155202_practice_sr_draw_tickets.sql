-- 訂閱送 SR 限定翻牌：券表＋抽卡事件 bonus_source 標記（2026-08-08 拍板，
-- docs/plans/2026-08-08-subscription-sr-draw-and-game-intro-design.md）。
--
-- 為何另開表而非 practice_draw_bonuses 加 source：主 claim RPC
-- （20260802120000）對 bonuses 以 user_id 單列 FOR UPDATE＋懶消耗，「一人一列」
-- 是其加固語意前提；塞第二種券會讓 SELECT..INTO 取列不定、懶消耗 UPDATE 誤吃
-- SR 券。獨立表＝零接觸既有加固路徑。
--
-- 語意：一人一列＝終身一次；grant 由 Edge 以 server 讀到的 tier 把關（不信
-- client 宣稱）且冪等（INSERT ON CONFLICT DO NOTHING）；消耗走顯式 claim RPC
-- （券強制 rarity=sr，抽卡請求必須知道自己是券抽，不能懶標記）；退訂不回收。
--
-- 部署順序（DB Migration Deploy Rule）：本檔必須先於 practice-chat Edge 新碼
-- 上線。舊 Edge 不讀新表/新欄，先套用無影響。套用走目標式 migration，
-- **不要** supabase db push。

CREATE TABLE IF NOT EXISTS public.practice_sr_draw_tickets (
  user_id             UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tier_at_grant       TEXT        NOT NULL CHECK (tier_at_grant IN ('starter', 'essential')),
  granted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  consumed_at         TIMESTAMPTZ,
  consumed_request_id TEXT        CHECK (consumed_request_id IS NULL OR length(consumed_request_id) BETWEEN 1 AND 64)
);

-- service_role only（與 practice_profile_draw_events 同策略）：RLS 開啟且零
-- policy，client 永遠摸不到；只有 service client 與 SECURITY DEFINER RPC 可碰。
ALTER TABLE public.practice_sr_draw_tickets ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.practice_sr_draw_tickets IS
  '訂閱一次性 SR 限定翻牌券：一人一列、server 驗 tier 後 grant、顯式 claim 消耗、退訂不回收。';

-- 券抽事件標記：主 RPC 的 free_used 計數（本窗 cost=0 事件數）必須排除券抽
-- （見 20260808 後續 claim_draw_exclude_sr_ticket migration），否則券會偷吃
-- tier 每日免費額度。NULL＝一般抽（含起步贈抽，語意不變）。
ALTER TABLE public.practice_profile_draw_events
  ADD COLUMN IF NOT EXISTS bonus_source TEXT
  CHECK (bonus_source IS NULL OR bonus_source IN ('subscription_sr'));
