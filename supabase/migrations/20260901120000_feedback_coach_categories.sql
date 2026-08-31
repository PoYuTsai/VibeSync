-- Batch E：擴充 Coach 1:1 可行動負評分類。舊分析頁分類完整保留；只改
-- category CHECK，不改欄位、資料或 RLS。
ALTER TABLE public.feedback
  DROP CONSTRAINT IF EXISTS feedback_category_check;

ALTER TABLE public.feedback
  ADD CONSTRAINT feedback_category_check CHECK (
    category IS NULL OR category IN (
      'too_direct',
      'too_long',
      'unnatural',
      'wrong_style',
      'other',
      'too_beta',
      'should_not_send',
      'too_generic',
      'invented_detail',
      'wrong_judgment',
      'too_many_questions',
      'missed_context'
    )
  );
