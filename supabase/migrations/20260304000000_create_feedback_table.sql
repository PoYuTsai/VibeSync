-- 反饋資料表
CREATE TABLE IF NOT EXISTS feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),

  -- 反饋內容
  rating TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
  category TEXT CHECK (category IN ('too_direct', 'too_long', 'unnatural', 'wrong_style', 'other')),
  comment TEXT,

  -- 上下文
  conversation_snippet TEXT,
  ai_response JSONB,
  user_tier TEXT,
  model_used TEXT
);

-- 索引
CREATE INDEX idx_feedback_created_at ON feedback(created_at DESC);
CREATE INDEX idx_feedback_rating ON feedback(rating);
CREATE INDEX idx_feedback_user_id ON feedback(user_id);

-- RLS
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- 用戶只能新增自己的反饋
CREATE POLICY "Users can insert own feedback" ON feedback
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 用戶可以讀取自己的反饋
CREATE POLICY "Users can read own feedback" ON feedback
  FOR SELECT USING (auth.uid() = user_id);
