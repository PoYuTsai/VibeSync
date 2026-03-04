# System Prompt 優化設計規格

> **版本**: 1.0
> **日期**: 2026-03-04
> **狀態**: 已確認

## 概述

根據測試夥伴反饋，優化 System Prompt 並新增個人化資料收集與反饋機制。

### 目標

1. 規避著作權爭議（名詞修改）
2. 提升 AI 回覆的個人化程度
3. 建立反饋收集機制以持續優化 prompt

## 設計決策

| 項目 | 決定 | 理由 |
|------|------|------|
| 個人資料範圍 | 中等版（風格 + 興趣） | 平衡 UX 與資料量 |
| 對方資料 | 選填 | 用戶可能不清楚對方特質 |
| 反饋目的 | 收集案例給團隊優化 | MVP 先專注 prompt 優化 |
| 通知管道 | Telegram Bot | 免費、簡單、穩定 |
| 反饋觸發 | 分析結果下方 | 最自然的時機點 |

---

## Part 1: System Prompt 修改

### 1.1 名詞修改

**82/18 → 70/30 法則**

```
### 2. 70/30 法則
好的對話是 70% 聆聽 + 30% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)
```

**話題深度階梯 → 英文**

```
### 5. Topic Depth Ladder
- Level 1: Event-oriented (Events) - 剛認識
- Level 2: Personal-oriented (Personal) - 有基本認識
- Level 3: Intimate-oriented (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進
```

### 1.2 JSON 輸出格式同步

```json
{
  "topicDepth": {
    "current": "Personal-oriented",
    "suggestion": "..."
  }
}
```

### 1.3 新增個人化區塊

```
## 情境資訊
- 認識場景：${meetingContext}
- 認識時長：${duration}
- 用戶目標：${goal}
- 用戶風格：${userStyle || "未提供"}
- 用戶興趣：${userInterests || "未提供"}
- 對方特質：${targetDescription || "未提供"}

## 個人化原則
如果有提供用戶風格，回覆建議要符合該風格的說話方式。
如果有提供對方特質，策略要考慮對方的個性。
```

---

## Part 2: 資料模型

### 2.1 UserStyle Enum

```dart
/// 用戶說話風格
@HiveType(typeId: 7)
enum UserStyle {
  @HiveField(0) humorous,    // 幽默型
  @HiveField(1) steady,      // 穩重型
  @HiveField(2) direct,      // 直球型
  @HiveField(3) gentle,      // 溫柔型
  @HiveField(4) playful;     // 調皮型

  String get label => switch (this) {
    humorous => '幽默型',
    steady => '穩重型',
    direct => '直球型',
    gentle => '溫柔型',
    playful => '調皮型',
  };
}
```

### 2.2 SessionContext 擴展

新增欄位：

| 欄位 | 類型 | 說明 |
|------|------|------|
| `userStyle` | `UserStyle?` | 用戶風格（選填） |
| `userInterests` | `String?` | 用戶興趣關鍵字，逗號分隔（選填） |
| `targetDescription` | `String?` | 對方特質描述，自由文字（選填） |

### 2.3 UI 呈現

位置：`NewConversationScreen` 情境收集區塊下方

```
┌─────────────────────────────────┐
│ 📝 個人化設定（選填）        [▼] │  ← 可折疊，預設收合
├─────────────────────────────────┤
│ 你的風格                        │
│ [幽默] [穩重] [直球] [溫柔] [調皮] │  ← SegmentedButton
│                                 │
│ 你的興趣                        │
│ [咖啡、攝影、露營____________]   │  ← TextField
│                                 │
│ 對方特質                        │
│ [慢熱、喜歡旅行______________]   │  ← TextField
└─────────────────────────────────┘
```

---

## Part 3: 反饋機制

### 3.1 資料表設計

```sql
CREATE TABLE feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),

  -- 反饋內容
  rating TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
  category TEXT,  -- 'too_direct', 'too_long', 'unnatural', 'wrong_style', 'other'
  comment TEXT,   -- 用戶自由填寫

  -- 上下文
  conversation_snippet TEXT,  -- 最後 3 輪對話
  ai_response JSONB,          -- 當時的 AI 回覆
  user_tier TEXT,
  model_used TEXT
);

-- 索引
CREATE INDEX idx_feedback_created_at ON feedback(created_at DESC);
CREATE INDEX idx_feedback_rating ON feedback(rating);
```

### 3.2 反饋分類

| 分類 | 說明 |
|------|------|
| `too_direct` | 太直接/不自然 |
| `too_long` | 回覆太長 |
| `unnatural` | 聽起來像機器人 |
| `wrong_style` | 不符合我的風格 |
| `other` | 其他 |

### 3.3 UI 流程

**步驟 1：初始狀態**

```
┌─────────────────────────────────┐
│  這個建議有幫助嗎？  [👍] [👎]    │
└─────────────────────────────────┘
```

**步驟 2a：按 👍**

- 存入 feedback 表（rating: positive）
- 顯示「謝謝回饋！」toast
- 不發 Telegram 通知

**步驟 2b：按 👎**

- 展開反饋表單：

```
┌─────────────────────────────────┐
│  哪裡需要改進？                   │
│  ○ 太直接/不自然                 │
│  ○ 回覆太長                      │
│  ○ 不符合我的風格                 │
│  ○ 其他                         │
│                                 │
│  補充說明（選填）                 │
│  [________________________]     │
│                                 │
│           [送出反饋]             │
└─────────────────────────────────┘
```

**步驟 3：送出**

- 存入 feedback 表
- 發送 Telegram 通知
- 顯示「感謝你的回饋，我們會持續改進！」

### 3.4 Telegram 通知格式

```
🔴 新的負面反饋

用戶：***@gmail.com (Essential)
問題類型：太直接/不自然
補充：「這個回覆聽起來像機器人」

📝 對話片段：
她：週末有什麼計畫嗎
我：還沒想好欸
她：我想去看展覽

🤖 AI 建議的回覆：
tease: 「展覽？聽起來很文青，你該不會是...」

Model: claude-sonnet-4
Time: 2026-03-04 14:30:00
```

### 3.5 Edge Function

新建 `supabase/functions/submit-feedback/index.ts`：

```typescript
// 職責：
// 1. 驗證用戶身份
// 2. 存入 feedback 表
// 3. 如果是負面反饋，POST 到 Telegram Bot API

// 環境變數：
// - TELEGRAM_BOT_TOKEN
// - TELEGRAM_CHAT_ID
```

---

## 實作範圍

### 需修改的檔案

| 檔案 | 改動 |
|------|------|
| `supabase/functions/analyze-chat/index.ts` | System Prompt 修改 |
| `lib/features/conversation/domain/entities/session_context.dart` | 新增欄位 + UserStyle enum |
| `lib/features/conversation/domain/entities/session_context.g.dart` | 重新生成 |
| `lib/features/conversation/presentation/screens/new_conversation_screen.dart` | 個人化設定 UI |
| `lib/features/analysis/presentation/screens/analysis_screen.dart` | 反饋按鈕 UI |

### 需新建的檔案

| 檔案 | 說明 |
|------|------|
| `supabase/functions/submit-feedback/index.ts` | 反饋 Edge Function |
| `supabase/migrations/XXXXXX_create_feedback_table.sql` | feedback 表 migration |
| `lib/features/feedback/` | 反饋相關的 Flutter 代碼（可選，也可放 analysis feature） |

### 需手動設定

| 項目 | 步驟 |
|------|------|
| Telegram Bot | 1. @BotFather 創建 bot<br>2. 創建群組並加入 bot<br>3. 取得 chat_id |
| 環境變數 | 設定 `TELEGRAM_BOT_TOKEN`、`TELEGRAM_CHAT_ID` |

---

## 不在範圍內

- 現有對話流程
- 訂閱系統
- 額度計算邏輯
- 個人偏好學習（未來功能）

---

## 測試計畫

| 測試項目 | 驗證點 |
|------|------|
| System Prompt | 70/30、英文話題深度正確輸出 |
| 個人化資料 | 有填 vs 沒填，AI 回覆有差異 |
| 反饋存儲 | feedback 表正確寫入 |
| Telegram 通知 | 負面反饋正確發送到群組 |
| UI 折疊 | 個人化設定區塊可正常展開/收合 |
