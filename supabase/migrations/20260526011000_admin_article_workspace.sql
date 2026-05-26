-- Admin article workspace for Eric/Bruce editorial planning.
-- This table tracks draft and pending articles in the admin dashboard.
-- Existing in-app static articles remain in Flutter until a later publishing sync.

CREATE TABLE IF NOT EXISTS public.admin_articles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL CHECK (char_length(trim(title)) > 0),
  subtitle TEXT,
  category TEXT NOT NULL DEFAULT '未分類' CHECK (char_length(trim(category)) > 0),
  tags TEXT[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending_review' CHECK (
    status IN ('draft', 'pending_review', 'published_in_app', 'archived')
  ),
  source_format TEXT NOT NULL DEFAULT 'markdown' CHECK (
    source_format IN ('markdown', 'plain_text')
  ),
  content TEXT NOT NULL DEFAULT '',
  source_name TEXT,
  source_url TEXT,
  app_article_id TEXT,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by_email TEXT,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by_email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_articles_status
  ON public.admin_articles(status);

CREATE INDEX IF NOT EXISTS idx_admin_articles_category
  ON public.admin_articles(category);

CREATE INDEX IF NOT EXISTS idx_admin_articles_tags
  ON public.admin_articles USING GIN(tags);

CREATE OR REPLACE FUNCTION public.touch_admin_articles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS touch_admin_articles_updated_at
  ON public.admin_articles;
CREATE TRIGGER touch_admin_articles_updated_at
  BEFORE UPDATE ON public.admin_articles
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_admin_articles_updated_at();

ALTER TABLE public.admin_articles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage admin_articles"
  ON public.admin_articles;
CREATE POLICY "Admins can manage admin_articles"
  ON public.admin_articles
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

NOTIFY pgrst, 'reload schema';
