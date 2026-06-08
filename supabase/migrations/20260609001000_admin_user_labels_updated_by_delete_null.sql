-- Allow account deletion to preserve admin labels while dropping the deleted user's audit pointer.

ALTER TABLE public.admin_user_labels
  DROP CONSTRAINT IF EXISTS admin_user_labels_updated_by_fkey;

ALTER TABLE public.admin_user_labels
  ADD CONSTRAINT admin_user_labels_updated_by_fkey
  FOREIGN KEY (updated_by)
  REFERENCES auth.users(id)
  ON DELETE SET NULL;

NOTIFY pgrst, 'reload schema';
