# System Prompt 優化實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 優化 System Prompt（70/30 法則、英文話題深度）、新增個人化資料收集、建立反饋機制（Telegram 通知）

**Architecture:** 擴展現有 SessionContext 加入個人化欄位，修改 Edge Function 處理新欄位，新增 feedback Edge Function 處理反饋並發送 Telegram 通知

**Tech Stack:** Flutter/Dart, Hive, Supabase Edge Functions (Deno), Telegram Bot API

**Design Doc:** `docs/plans/2026-03-04-system-prompt-optimization-design.md`

---

## Task 1: System Prompt 名詞修改

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:49-95`

**Step 1: 修改 82/18 → 70/30**

```typescript
// 找到這段 (約 L66-70)
### 2. 82/18 原則
好的對話是 82% 聆聽 + 18% 說話

// 改成
### 2. 70/30 法則
好的對話是 70% 聆聽 + 30% 說話
```

**Step 2: 修改話題深度階梯為英文**

```typescript
// 找到這段 (約 L78-82)
### 5. 話題深度階梯
- Level 1: 事件導向 (Facts) - 剛認識
- Level 2: 個人導向 (Personal) - 有基本認識
- Level 3: 曖昧導向 (Intimate) - 熱度 > 60

// 改成
### 5. Topic Depth Ladder
- Level 1: Event-oriented (Events) - 剛認識
- Level 2: Personal-oriented (Personal) - 有基本認識
- Level 3: Intimate-oriented (Intimate) - 熱度 > 60
```

**Step 3: 修改 JSON 輸出格式中的 topicDepth**

```typescript
// 找到 JSON 輸出格式範例中的 topicDepth (約 L131)
"topicDepth": { "current": "personal", ...

// 改成
"topicDepth": { "current": "Personal-oriented", ...
```

**Step 4: 部署並測試**

Run: `SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN npx supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg`
Expected: Function deployed successfully

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "[fix] System Prompt 名詞修改 - 70/30 法則 + 英文話題深度"
git push
```

---

## Task 2: 新增 UserStyle Enum

**Files:**
- Modify: `lib/features/conversation/domain/entities/session_context.dart`

**Step 1: 新增 UserStyle enum**

在檔案最上方（`MeetingContext` enum 之前）新增：

```dart
/// 用戶說話風格
@HiveType(typeId: 7)
enum UserStyle {
  @HiveField(0)
  humorous, // 幽默型
  @HiveField(1)
  steady, // 穩重型
  @HiveField(2)
  direct, // 直球型
  @HiveField(3)
  gentle, // 溫柔型
  @HiveField(4)
  playful; // 調皮型

  String get label {
    switch (this) {
      case humorous:
        return '幽默型';
      case steady:
        return '穩重型';
      case direct:
        return '直球型';
      case gentle:
        return '溫柔型';
      case playful:
        return '調皮型';
    }
  }
}
```

**Step 2: 擴展 SessionContext class**

在 `SessionContext` class 中新增三個欄位：

```dart
@HiveType(typeId: 6)
class SessionContext extends HiveObject {
  @HiveField(0)
  final MeetingContext meetingContext;

  @HiveField(1)
  final AcquaintanceDuration duration;

  @HiveField(2)
  final UserGoal goal;

  @HiveField(3)
  final UserStyle? userStyle; // 新增

  @HiveField(4)
  final String? userInterests; // 新增

  @HiveField(5)
  final String? targetDescription; // 新增

  SessionContext({
    required this.meetingContext,
    required this.duration,
    this.goal = UserGoal.dateInvite,
    this.userStyle, // 新增
    this.userInterests, // 新增
    this.targetDescription, // 新增
  });

  Map<String, dynamic> toJson() => {
        'meetingContext': meetingContext.label,
        'duration': duration.label,
        'goal': goal.label,
        'userStyle': userStyle?.label, // 新增
        'userInterests': userInterests, // 新增
        'targetDescription': targetDescription, // 新增
      };
}
```

**Step 3: 重新生成 Hive adapter**

Run: `cd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: 生成 `session_context.g.dart`

**Step 4: 註冊新的 Hive adapter**

檢查 `lib/core/services/storage_service.dart`，確認 `UserStyleAdapter` 有被註冊：

```dart
// 在 initialize() 中確認有：
Hive.registerAdapter(UserStyleAdapter());
```

**Step 5: Commit**

```bash
git add lib/features/conversation/domain/entities/session_context.dart
git add lib/features/conversation/domain/entities/session_context.g.dart
git add lib/core/services/storage_service.dart
git commit -m "[feat] 新增 UserStyle enum + SessionContext 個人化欄位"
git push
```

---

## Task 3: 新建對話 UI - 個人化設定區塊

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 新增 state 變數**

在 `_NewConversationScreenState` class 中新增：

```dart
// Session Context (情境收集) - 現有
MeetingContext _meetingContext = MeetingContext.datingApp;
AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
UserGoal _goal = UserGoal.dateInvite;

// 個人化設定 - 新增
UserStyle? _userStyle;
final _userInterestsController = TextEditingController();
final _targetDescriptionController = TextEditingController();
bool _showPersonalization = false; // 控制展開/收合
```

**Step 2: dispose 新的 controller**

```dart
@override
void dispose() {
  _nameController.dispose();
  _herMessageController.dispose();
  _myMessageController.dispose();
  _userInterestsController.dispose(); // 新增
  _targetDescriptionController.dispose(); // 新增
  super.dispose();
}
```

**Step 3: 在「你的目標」後方新增個人化設定區塊**

在 `build()` 方法中，找到 `SegmentedButton<UserGoal>` 後方，新增：

```dart
// === 個人化設定區塊（可折疊）===
const SizedBox(height: 24),
InkWell(
  onTap: () => setState(() => _showPersonalization = !_showPersonalization),
  child: Row(
    children: [
      Icon(
        _showPersonalization ? Icons.expand_less : Icons.expand_more,
        color: AppColors.textSecondary,
      ),
      const SizedBox(width: 8),
      Text(
        '個人化設定（選填）',
        style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
      ),
    ],
  ),
),
if (_showPersonalization) ...[
  const SizedBox(height: 16),
  Text('你的風格', style: AppTypography.bodyMedium),
  const SizedBox(height: 8),
  Wrap(
    spacing: 8,
    children: UserStyle.values.map((style) {
      final isSelected = _userStyle == style;
      return ChoiceChip(
        label: Text(style.label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _userStyle = selected ? style : null);
        },
      );
    }).toList(),
  ),
  const SizedBox(height: 16),
  Text('你的興趣', style: AppTypography.bodyMedium),
  const SizedBox(height: 8),
  TextField(
    controller: _userInterestsController,
    decoration: const InputDecoration(
      hintText: '例如：咖啡、攝影、露營',
      isDense: true,
    ),
  ),
  const SizedBox(height: 16),
  Text('對方特質', style: AppTypography.bodyMedium),
  const SizedBox(height: 8),
  TextField(
    controller: _targetDescriptionController,
    decoration: const InputDecoration(
      hintText: '例如：慢熱、喜歡旅行',
      isDense: true,
    ),
  ),
],
```

**Step 4: 修改 _analyze() 帶入新欄位**

```dart
// Update session context - 修改這段
conversation.sessionContext = SessionContext(
  meetingContext: _meetingContext,
  duration: _duration,
  goal: _goal,
  userStyle: _userStyle, // 新增
  userInterests: _userInterestsController.text.trim().isEmpty
      ? null
      : _userInterestsController.text.trim(), // 新增
  targetDescription: _targetDescriptionController.text.trim().isEmpty
      ? null
      : _targetDescriptionController.text.trim(), // 新增
);
```

**Step 5: 測試 UI**

Run: `flutter run -d chrome`
Expected: 新建對話頁面有可折疊的「個人化設定」區塊

**Step 6: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "[feat] 新建對話 UI 新增個人化設定區塊"
git push
```

---

## Task 4: Edge Function 處理個人化資料

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:331-339`

**Step 1: 擴展 contextInfo 組裝**

找到 `contextInfo` 的組裝邏輯（約 L331-339），修改為：

```typescript
// Format session context for Claude
let contextInfo = "";
if (sessionContext) {
  contextInfo = `
## 情境資訊
- 認識場景：${sessionContext.meetingContext || "未知"}
- 認識時長：${sessionContext.duration || "未知"}
- 用戶目標：${sessionContext.goal || "約出來"}
- 用戶風格：${sessionContext.userStyle || "未提供"}
- 用戶興趣：${sessionContext.userInterests || "未提供"}
- 對方特質：${sessionContext.targetDescription || "未提供"}
`;
}
```

**Step 2: 在 SYSTEM_PROMPT 新增個人化原則**

在 `SYSTEM_PROMPT` 的 `## 冰點特殊處理` 之前，新增：

```typescript
## 個人化原則
如果有提供用戶風格，回覆建議要符合該風格的說話方式：
- 幽默型：多用輕鬆俏皮的語氣
- 穩重型：沉穩內斂，不輕浮
- 直球型：簡單直接，不繞圈子
- 溫柔型：細膩體貼，照顧對方感受
- 調皮型：帶點挑逗，製造小驚喜

如果有提供對方特質，策略要考慮對方的個性。
```

**Step 3: 部署並測試**

Run: `SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN npx supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg`
Expected: Function deployed successfully

**Step 4: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "[feat] Edge Function 支援個人化資料"
git push
```

---

## Task 5: 建立 feedback 資料表

**Files:**
- Create: `supabase/migrations/20260304000000_create_feedback_table.sql`

**Step 1: 建立 migration 檔案**

```sql
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
```

**Step 2: 推送 migration**

Run: `SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN npx supabase db push --project-ref fcmwrmwdoqiqdnbisdpg`
Expected: Migration applied

**Step 3: Commit**

```bash
git add supabase/migrations/20260304000000_create_feedback_table.sql
git commit -m "[feat] 建立 feedback 資料表"
git push
```

---

## Task 6: 建立 submit-feedback Edge Function

**Files:**
- Create: `supabase/functions/submit-feedback/index.ts`

**Step 1: 建立 Edge Function**

```typescript
// supabase/functions/submit-feedback/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, x-client-info, apikey",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

async function sendTelegramNotification(feedback: {
  userEmail: string;
  userTier: string;
  rating: string;
  category?: string;
  comment?: string;
  conversationSnippet?: string;
  aiResponse?: Record<string, unknown>;
  modelUsed?: string;
}) {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.warn("Telegram credentials not configured");
    return;
  }

  // 只有負面反饋才發通知
  if (feedback.rating !== "negative") return;

  const categoryLabels: Record<string, string> = {
    too_direct: "太直接/不自然",
    too_long: "回覆太長",
    unnatural: "聽起來像機器人",
    wrong_style: "不符合我的風格",
    other: "其他",
  };

  // 遮蔽 email
  const maskedEmail = feedback.userEmail.replace(/(.{2})(.*)(@.*)/, "$1***$3");

  let message = `🔴 新的負面反饋\n\n`;
  message += `用戶：${maskedEmail} (${feedback.userTier})\n`;
  message += `問題類型：${categoryLabels[feedback.category || "other"] || feedback.category}\n`;

  if (feedback.comment) {
    message += `補充：「${feedback.comment}」\n`;
  }

  if (feedback.conversationSnippet) {
    message += `\n📝 對話片段：\n${feedback.conversationSnippet}\n`;
  }

  if (feedback.aiResponse?.finalRecommendation) {
    const rec = feedback.aiResponse.finalRecommendation as Record<string, string>;
    message += `\n🤖 AI 推薦回覆：\n${rec.pick}: 「${rec.content}」\n`;
  }

  message += `\nModel: ${feedback.modelUsed || "unknown"}`;
  message += `\nTime: ${new Date().toISOString()}`;

  try {
    await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: TELEGRAM_CHAT_ID,
        text: message,
        parse_mode: "HTML",
      }),
    });
  } catch (error) {
    console.error("Failed to send Telegram notification:", error);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    // Parse request
    const body = await req.json();
    const {
      rating,
      category,
      comment,
      conversationSnippet,
      aiResponse,
      userTier,
      modelUsed,
    } = body;

    if (!rating || !["positive", "negative"].includes(rating)) {
      return jsonResponse({ error: "Invalid rating" }, 400);
    }

    // Insert feedback
    const { error: insertError } = await supabase.from("feedback").insert({
      user_id: user.id,
      rating,
      category,
      comment,
      conversation_snippet: conversationSnippet,
      ai_response: aiResponse,
      user_tier: userTier,
      model_used: modelUsed,
    });

    if (insertError) {
      console.error("Insert error:", insertError);
      return jsonResponse({ error: "Failed to save feedback" }, 500);
    }

    // Send Telegram notification for negative feedback
    await sendTelegramNotification({
      userEmail: user.email || "unknown",
      userTier: userTier || "unknown",
      rating,
      category,
      comment,
      conversationSnippet,
      aiResponse,
      modelUsed,
    });

    return jsonResponse({ success: true });
  } catch (error) {
    console.error("Error:", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
```

**Step 2: 部署 Edge Function**

Run: `SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN npx supabase functions deploy submit-feedback --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg`
Expected: Function deployed successfully

**Step 3: Commit**

```bash
git add supabase/functions/submit-feedback/index.ts
git commit -m "[feat] 建立 submit-feedback Edge Function + Telegram 通知"
git push
```

---

## Task 7: 分析結果頁面新增反饋 UI

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`

**Step 1: 新增 state 變數**

在 State class 中新增：

```dart
// 反饋相關
bool _feedbackSubmitted = false;
bool _showFeedbackForm = false;
String? _feedbackCategory;
final _feedbackCommentController = TextEditingController();
```

**Step 2: dispose controller**

```dart
@override
void dispose() {
  _feedbackCommentController.dispose();
  super.dispose();
}
```

**Step 3: 新增 _submitFeedback 方法**

```dart
Future<void> _submitFeedback(String rating) async {
  if (_feedbackSubmitted) return;

  final analysisState = ref.read(analysisProvider);
  final conversation = // 取得當前對話

  try {
    final response = await Supabase.instance.client.functions.invoke(
      'submit-feedback',
      body: {
        'rating': rating,
        'category': _feedbackCategory,
        'comment': _feedbackCommentController.text.trim().isEmpty
            ? null
            : _feedbackCommentController.text.trim(),
        'conversationSnippet': _buildConversationSnippet(),
        'aiResponse': analysisState.result,
        'userTier': // 取得用戶 tier,
        'modelUsed': analysisState.result?['usage']?['model'],
      },
    );

    if (response.status == 200) {
      setState(() {
        _feedbackSubmitted = true;
        _showFeedbackForm = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(rating == 'positive'
                ? '謝謝回饋！'
                : '感謝你的回饋，我們會持續改進！'),
          ),
        );
      }
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反饋送出失敗，請稍後再試')),
      );
    }
  }
}

String _buildConversationSnippet() {
  // 取最後 3 輪對話
  final messages = // 取得對話訊息
  final lastMessages = messages.length > 6
      ? messages.sublist(messages.length - 6)
      : messages;
  return lastMessages.map((m) => '${m.isFromMe ? "我" : "她"}: ${m.content}').join('\n');
}
```

**Step 4: 在分析結果區塊底部新增反饋 UI**

```dart
// 反饋區塊
if (!_feedbackSubmitted) ...[
  const SizedBox(height: 24),
  const Divider(),
  const SizedBox(height: 16),
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text('這個建議有幫助嗎？', style: AppTypography.bodyMedium),
      const SizedBox(width: 16),
      IconButton(
        icon: const Icon(Icons.thumb_up_outlined),
        onPressed: () => _submitFeedback('positive'),
        tooltip: '有幫助',
      ),
      IconButton(
        icon: const Icon(Icons.thumb_down_outlined),
        onPressed: () => setState(() => _showFeedbackForm = true),
        tooltip: '需要改進',
      ),
    ],
  ),
  if (_showFeedbackForm) ...[
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('哪裡需要改進？', style: AppTypography.bodyLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCategoryChip('too_direct', '太直接/不自然'),
              _buildCategoryChip('too_long', '回覆太長'),
              _buildCategoryChip('wrong_style', '不符合我的風格'),
              _buildCategoryChip('other', '其他'),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _feedbackCommentController,
            decoration: const InputDecoration(
              hintText: '補充說明（選填）',
              isDense: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _feedbackCategory != null
                  ? () => _submitFeedback('negative')
                  : null,
              child: const Text('送出反饋'),
            ),
          ),
        ],
      ),
    ),
  ],
] else ...[
  const SizedBox(height: 24),
  Center(
    child: Text(
      '✓ 已收到你的回饋',
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
    ),
  ),
],
```

**Step 5: 新增 _buildCategoryChip helper**

```dart
Widget _buildCategoryChip(String value, String label) {
  final isSelected = _feedbackCategory == value;
  return ChoiceChip(
    label: Text(label),
    selected: isSelected,
    onSelected: (selected) {
      setState(() => _feedbackCategory = selected ? value : null);
    },
  );
}
```

**Step 6: 測試 UI**

Run: `flutter run -d chrome`
Expected: 分析結果底部有 👍👎 按鈕，按 👎 展開表單

**Step 7: Commit**

```bash
git add lib/features/analysis/presentation/screens/analysis_screen.dart
git commit -m "[feat] 分析結果頁面新增反饋 UI"
git push
```

---

## Task 8: 設定 Telegram Bot（手動）

**這個任務需要手動操作，不是程式碼**

**Step 1: 創建 Telegram Bot**

1. 在 Telegram 搜尋 `@BotFather`
2. 發送 `/newbot`
3. 輸入 bot 名稱（例如：VibeSync Feedback）
4. 輸入 bot username（例如：vibesync_feedback_bot）
5. 記下回傳的 **Bot Token**

**Step 2: 創建群組並加入 bot**

1. 創建新的 Telegram 群組（例如：VibeSync 反饋通知）
2. 將剛創建的 bot 加入群組
3. 在群組中發送任意訊息
4. 訪問 `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates`
5. 找到 `chat.id`（通常是負數，例如 `-123456789`）

**Step 3: 設定 Supabase 環境變數**

Run:
```bash
npx supabase secrets set TELEGRAM_BOT_TOKEN=<your_bot_token> --project-ref fcmwrmwdoqiqdnbisdpg
npx supabase secrets set TELEGRAM_CHAT_ID=<your_chat_id> --project-ref fcmwrmwdoqiqdnbisdpg
```

**Step 4: 測試通知**

在 app 中提交一個負面反饋，確認 Telegram 群組收到通知

---

## Task 9: 端對端測試

**Step 1: 測試 System Prompt 修改**

1. 開啟 web app
2. 新建對話，輸入測試訊息
3. 確認 AI 回傳的 `topicDepth.current` 是英文格式（如 `Personal-oriented`）

**Step 2: 測試個人化資料**

1. 新建對話
2. 展開「個人化設定」
3. 選擇「幽默型」風格，填寫興趣
4. 分析對話
5. 確認 AI 回覆風格有符合「幽默型」

**Step 3: 測試反饋機制**

1. 在分析結果頁按 👎
2. 選擇分類，填寫補充
3. 送出反饋
4. 確認 Telegram 群組收到通知
5. 確認 Supabase feedback 表有新記錄

**Step 4: 更新 CLAUDE.md**

記錄此次優化完成

```bash
git add CLAUDE.md
git commit -m "[docs] 更新開發進度 - System Prompt 優化完成"
git push
```
