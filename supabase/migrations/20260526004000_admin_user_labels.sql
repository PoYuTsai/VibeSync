-- Admin-only labels for distinguishing pre-launch sandbox accounts,
-- internal testers, friend testers, and production users.

CREATE TABLE IF NOT EXISTS public.admin_user_labels (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  audience_type TEXT NOT NULL DEFAULT 'unknown' CHECK (
    audience_type IN (
      'unknown',
      'prelaunch_sandbox',
      'internal',
      'friend_test',
      'production'
    )
  ),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_admin_user_labels_audience_type
  ON public.admin_user_labels(audience_type);

CREATE OR REPLACE FUNCTION public.touch_admin_user_labels_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS touch_admin_user_labels_updated_at
  ON public.admin_user_labels;
CREATE TRIGGER touch_admin_user_labels_updated_at
  BEFORE UPDATE ON public.admin_user_labels
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_admin_user_labels_updated_at();

ALTER TABLE public.admin_user_labels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage admin_user_labels"
  ON public.admin_user_labels;
CREATE POLICY "Admins can manage admin_user_labels"
  ON public.admin_user_labels
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

INSERT INTO public.admin_user_labels (user_id, audience_type, notes)
SELECT
  u.id,
  'prelaunch_sandbox',
  'Seeded from users that existed before launch cohort labeling.'
FROM public.users u
ON CONFLICT (user_id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
