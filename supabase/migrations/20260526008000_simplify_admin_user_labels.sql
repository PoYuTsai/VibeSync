-- Keep user audience labels simple for Eric/Bruce operations.

UPDATE public.admin_user_labels
SET audience_type = 'prelaunch_sandbox'
WHERE audience_type IN ('unknown', 'internal');

ALTER TABLE public.admin_user_labels
  ALTER COLUMN audience_type SET DEFAULT 'prelaunch_sandbox';

ALTER TABLE public.admin_user_labels
  DROP CONSTRAINT IF EXISTS admin_user_labels_audience_type_check;

ALTER TABLE public.admin_user_labels
  ADD CONSTRAINT admin_user_labels_audience_type_check
  CHECK (audience_type IN ('prelaunch_sandbox', 'friend_test', 'production'));

NOTIFY pgrst, 'reload schema';
