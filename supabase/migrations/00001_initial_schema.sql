-- supabase/migrations/00001_initial_schema.sql
-- VibeSync Initial Schema

-- Users table (synced with auth.users)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  total_analyses INTEGER DEFAULT 0,
  total_conversations INTEGER DEFAULT 0
);

-- Subscriptions table (訊息制)
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'starter', 'essential')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
  rc_customer_id TEXT,
  rc_entitlement_id TEXT,
  -- 訊息用量追蹤
  monthly_messages_used INTEGER DEFAULT 0,
  daily_messages_used INTEGER DEFAULT 0,
  monthly_reset_at TIMESTAMPTZ DEFAULT NOW(),
  daily_reset_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own data" ON public.users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own data" ON public.users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own subscription" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);

-- Function to create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email);

  INSERT INTO public.subscriptions (user_id)
  VALUES (NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to check and reset daily/monthly usage
CREATE OR REPLACE FUNCTION public.check_and_reset_usage(p_user_id UUID)
RETURNS TABLE(
  can_use BOOLEAN,
  messages_remaining INTEGER,
  daily_remaining INTEGER
) AS $$
DECLARE
  v_sub RECORD;
  v_monthly_limit INTEGER;
  v_daily_limit INTEGER;
BEGIN
  -- Get subscription
  SELECT * INTO v_sub FROM public.subscriptions WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 0, 0;
    RETURN;
  END IF;

  -- Set limits based on tier
  CASE v_sub.tier
    WHEN 'free' THEN
      v_monthly_limit := 30;
      v_daily_limit := 15;
    WHEN 'starter' THEN
      v_monthly_limit := 300;
      v_daily_limit := 50;
    WHEN 'essential' THEN
      v_monthly_limit := 1000;
      v_daily_limit := 150;
    ELSE
      v_monthly_limit := 30;
      v_daily_limit := 15;
  END CASE;

  -- Reset monthly if needed
  IF v_sub.monthly_reset_at < DATE_TRUNC('month', NOW()) THEN
    UPDATE public.subscriptions
    SET monthly_messages_used = 0,
        monthly_reset_at = DATE_TRUNC('month', NOW())
    WHERE user_id = p_user_id;
    v_sub.monthly_messages_used := 0;
  END IF;

  -- Reset daily if needed
  IF v_sub.daily_reset_at < DATE_TRUNC('day', NOW()) THEN
    UPDATE public.subscriptions
    SET daily_messages_used = 0,
        daily_reset_at = DATE_TRUNC('day', NOW())
    WHERE user_id = p_user_id;
    v_sub.daily_messages_used := 0;
  END IF;

  -- Return usage info
  RETURN QUERY SELECT
    (v_sub.monthly_messages_used < v_monthly_limit AND v_sub.daily_messages_used < v_daily_limit),
    (v_monthly_limit - v_sub.monthly_messages_used),
    (v_daily_limit - v_sub.daily_messages_used);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment usage
CREATE OR REPLACE FUNCTION public.increment_usage(p_user_id UUID, p_messages INTEGER DEFAULT 1)
RETURNS VOID AS $$
BEGIN
  UPDATE public.subscriptions
  SET monthly_messages_used = monthly_messages_used + p_messages,
      daily_messages_used = daily_messages_used + p_messages
  WHERE user_id = p_user_id;

  -- Also update user's total analyses
  UPDATE public.users
  SET total_analyses = total_analyses + 1
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Index for faster lookups
CREATE INDEX idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX idx_users_email ON public.users(email);
