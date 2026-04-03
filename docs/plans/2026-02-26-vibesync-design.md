# VibeSync 設計規格書

**專案名稱**: VibeSync 頻率調校師
**版本**: 1.4
**日期**: 2026-02-27
**狀態**: 設計完成，待實作

---

## 核心定位

| 項目 | 內容 |
|------|------|
| **產品名稱** | VibeSync 頻率調校師 |
| **一句話定位** | 社交溝通教練 App |
| **目標用戶** | 20-35 歲，願意投資自我提升的個人用戶 |
| **核心目標** | 幫助用戶成功邀約（預設），可自訂其他目標 |
| **哲學** | 框架策略為輔 → 最終回歸「個人化 + 真誠流」 |
| **服務範圍** | 文字對話輔助 → 確認邀約（約會當天不在範圍內） |

### 產品理念

> **我們的 Know-How**：不是教用戶變成另一個人，而是用專業框架幫助他們更有效地展現真實自我。
>
> **最終目標**：輸出要像人說的話，不能太 AI 味。見面時用戶要能自然表現。

---

## 1. 系統架構 (System Architecture)

### 1.1 整體架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter App                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   UI Layer  │  │   Domain    │  │     Data Layer      │  │
│  │  (Riverpod) │  │   Layer     │  │  ┌───────────────┐  │  │
│  │             │  │             │  │  │  Hive (Local) │  │  │
│  │  - Screens  │  │  - UseCases │  │  │  AES-256加密   │  │  │
│  │  - Widgets  │  │  - Entities │  │  └───────────────┘  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Supabase                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │     Auth     │  │  PostgreSQL  │  │  Edge Functions  │   │
│  │              │  │              │  │                  │   │
│  │ Google/Apple │  │ - users      │  │ - analyze-chat   │   │
│  │ Email OTP    │  │ - subs       │  │ - generate-reply │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌──────────┐    ┌──────────┐    ┌──────────────┐
       │  Claude  │    │ RevenueCat│   │  Sentry      │
       │   API    │    │           │   │ (Monitoring) │
       └──────────┘    └──────────┘    └──────────────┘
```

### 1.2 核心元件

| 元件 | 技術 | 職責 |
|------|------|------|
| Mobile App | Flutter 3.x + Riverpod | UI、本地儲存、狀態管理 |
| Auth | Supabase Auth | 身份驗證 (Google/Apple/Email OTP) |
| Database | PostgreSQL | 用戶資料、訂閱狀態 |
| AI Gateway | Edge Functions | 請求路由、模型選擇、安全驗證 |
| AI Engine | Claude API | 熱度分析、回覆生成 |
| Subscription | RevenueCat | 訂閱管理、收據驗證 |

### 1.3 技術選型理由

- **Flutter**: 一套程式碼支援 iOS/Android，開發效率高
- **Supabase**: 開源 Firebase 替代方案，PostgreSQL 底層更靈活
- **Edge Functions**: Serverless，按使用量計費，自動擴展
- **RevenueCat**: App Store/Play Store 訂閱整合標準方案
- **Hive**: Flutter 原生 NoSQL，效能優於 SQLite

---

## 2. 資料模型 (Data Model)

### 2.1 本地儲存 (Hive)

```dart
@HiveType(typeId: 0)
class Conversation extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;          // 對話對象名稱

  @HiveField(2)
  late String? avatarPath;   // 本地圖片路徑

  @HiveField(3)
  late List<Message> messages;

  @HiveField(4)
  late DateTime createdAt;

  @HiveField(5)
  late DateTime updatedAt;
}

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String content;       // 訊息內容

  @HiveField(2)
  late bool isFromMe;        // 是否為用戶發送

  @HiveField(3)
  late DateTime timestamp;

  @HiveField(4)
  late int? enthusiasmScore; // 熱度分數 (0-100)

  @HiveField(5)
  late List<String>? suggestedReplies; // AI 建議回覆
}
```

### 2.2 雲端儲存 (PostgreSQL)

```sql
-- 用戶資料表
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,

  -- 統計資料
  total_analyses INTEGER DEFAULT 0,
  total_conversations INTEGER DEFAULT 0
);

-- 訂閱狀態表
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('free', 'starter', 'essential')),
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'cancelled')),

  -- RevenueCat 整合
  rc_customer_id TEXT,
  rc_entitlement_id TEXT,

  -- 使用量追蹤
  monthly_analyses_used INTEGER DEFAULT 0,
  monthly_reset_at TIMESTAMPTZ,

  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,

  UNIQUE(user_id)
);

-- RLS 政策：用戶只能存取自己的資料
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own data" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can view own subscription" ON subscriptions
  FOR SELECT USING (auth.uid() = user_id);
```

### 2.3 資料流向

```
用戶輸入對話 → 本地加密儲存 (Hive)
                    ↓
            發送至 Edge Function
                    ↓
            Claude API 分析 (不儲存)
                    ↓
            返回結果給 App
                    ↓
            結果存入本地 Hive
```

**關鍵原則**: 對話內容 **永不** 儲存於伺服器

---

## 3. GAME 框架 (Core Know-How)

> **這是我們的核心競爭力**，所有 AI 分析都基於這個框架。

### 3.1 GAME 流程五階段

```
┌─────────────────────────────────────────────────────────┐
│  GAME 流程                                              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 打開 (Opening)      → 破冰                          │
│          ↓                                              │
│  2. 前提 (Premise)      → 進入男女框架                  │
│          ↓                                              │
│  3. 評估 (Qualification) → 她證明自己配得上你           │
│          ↓                                              │
│  4. 敘事 (Narrative)    → 個性樣本、說故事              │
│          ↓                                              │
│  5. 收尾 (Close)        → 模糊邀約 → 確立邀約 ✓         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.2 各階段詳解

#### 階段 1: 打開 (Opening)
- **文字**：破冰，開啟對話
- **搭訕**：1 分鐘破防
- **重點**：90% 是態度，內容不重要

#### 階段 2: 前提 (Premise)
- **目的**：進入「男女框架」，建立張力
- **問題**：太閒聊 = 朋友框 = 沒有機會
- **時機**：太早突兀，太晚變朋友

#### 階段 3: 評估 (Qualification)
- **核心**：你在篩選她，不是她在篩選你
- **心理學**：她要證明自己配得上你
- **前提**：你的框架要先穩住
- **常見問題**：缺乏「配得感」，遇到正妹就忽略她的缺點

#### 階段 4: 敘事 (Narrative)
- **目的**：傳達「個性樣本」
- **內容**：生活模式、框架、看世界的角度、明確喜好
- **方式**：簡單帶過，不大作文章，不說教
- **例外**：她很熱情時，可以多拋鉤子

#### 階段 5: 收尾 (Close)
- **模糊邀約**：「改天一起喝咖啡」
- **確立邀約**：「週六下午，信義區那間？」
- **常見錯誤**：到最後一步扭扭捏捏
- **正確做法**：時間敲定、地點敲定，不要猶豫

### 3.3 核心技巧

#### 隱性價值展示 (Subtle DHV)

```
❌ 直接說：「我很常出國」
✅ 淺帶過：「剛從北京出差回來」

一句話傳達：
├─ 常飛 (頻率)
├─ 出差 (有事業)
├─ 北京首都 (重要業務)
└─ 平鋪直敘 (這對我很正常，沒什麼)
```

#### 框架控制 (Frame)

```
你的框架 = 你的人設
├─ 不因對方攻擊/挑釁/廢測而改變
├─ 不用點對點回答她的問題
├─ 可以跳出她問題的框架思考
└─ 維持一致性 = 高價值證明
```

#### 廢物測試 (Shit Test)

| 關鍵 | 說明 |
|------|------|
| **態度** | 廢測是好事，代表她在評估你 |
| **橡膠球理論** | 讓它彈開，不用認真回應 |
| **回應方式** | 幽默曲解 / 直球但維持框架 / 忽略 |
| **沒有正確答案** | 重點是態度，不是內容 |

#### 淺溝通解讀

```
女生文字背後的意思 > 字面意思
├─ 一致性測試藏在文字裡
├─ AI 要幫忙解讀這層
└─ 告訴用戶：她可能在測試你
```

### 3.4 回覆優先順序

```
1. 有圖片先回圖片 → 對圖片的感受
2. 對圖片提出疑問
3. 無關緊要的陳述句
4. 回應重點訊息
5. 陳述句優於問句（朋友間直接問句比較少，對話更自然）
```

### 3.5 冰點策略

```
當熱度 0-30 且 AI 判斷機會渺茫：
├─ 不硬回
├─ 可建議「已讀不回」
├─ 鼓勵：「開新對話，聊聊其他對象吧」
└─ 解釋：為什麼這樣判斷
```

---

## 4. AI 分析引擎 (AI Analysis Engine)

### 4.1 核心哲學

#### 1.8x 黃金法則 (The Golden Rule)

```
回覆字數 ≤ 對方最後一則訊息字數 × 1.8
```

這是最高指導原則，所有建議回覆都必須遵守。

**理由**:
- 維持對話平衡感
- 避免過度投入 (Over-investing)
- 展現從容不迫的態度
- 符合「高價值」對話模式

### 4.2 熱度量表 (Enthusiasm Gauge)

| 分數範圍 | 等級名稱 | 視覺標示 | 建議策略 |
|----------|----------|----------|----------|
| 0-30 | 冰點 | ❄️ 藍色 | 鏡像冷處理、適度抽離、等待時機 |
| 31-60 | 溫和 | 🌤️ 黃色 | 引導式提問、拋出有趣話題、DHV |
| 61-80 | 熱情 | 🔥 橘色 | 80% 鏡像、保持沉穩、適度推進 |
| 81-100 | 高熱 | 💖 粉紅 | 推拉技巧、適度挑戰、建立框架 |

### 4.3 熱度分析指標

```typescript
interface EnthusiasmAnalysis {
  score: number;           // 0-100
  level: 'cold' | 'warm' | 'hot' | 'very_hot';

  indicators: {
    responseSpeed: number;      // 回覆速度 (已移除，用戶反饋主觀)
    messageLength: number;      // 訊息長度比例
    questionAsking: boolean;    // 是否主動提問
    emojiUsage: number;         // emoji 使用頻率
    initiationRatio: number;    // 主動發訊比例
    topicEngagement: number;    // 話題參與度
  };

  warnings: NeedyWarning[];     // Needy 警示
}

interface NeedyWarning {
  type: 'double_text' | 'over_invest' | 'seeking_validation' | 'too_available';
  message: string;
  suggestion: string;
}
```

### 4.4 五種回覆類型

| 類型 | 中文名 | 技巧 | 用途 | 範例 |
|------|--------|------|------|------|
| Extend | 🔄 延展 | 細緻化深挖 | 延續話題、挖掘深度 | 「哪種辣？為什麼喜歡被電到的感覺？」 |
| Resonate | 💬 共鳴 | 情感連結 | 同理心、讓對方覺得被懂 | 「我懂那種累到只想躺著的感覺」 |
| Tease | 😏 調情 | 推拉反差 | 輕鬆玩笑、建立張力 | 「你體力也太差了吧...不過辛苦了」 |
| Humor | 🎭 幽默 | 曲解/誇大 | 打破僵局、增加趣味 | 「加班到這麼晚，是在拯救地球嗎？」 |
| ColdRead | 🔮 冷讀 | 假設代替問句 | 避免面試感、展現洞察 | 「你一定是那種週末會去爬山的人」 |

### 4.5 話題深度階梯

```
Level 1: 事件導向 (Facts)
├─ 聊發生的事、客觀資訊
├─ 例：「今天吃了什麼」「去哪玩」
└─ 適合：剛認識、破冰階段

Level 2: 個人導向 (Personal)
├─ 聊想法、感受、價值觀
├─ 例：「為什麼喜歡這個」「什麼時候最開心」
└─ 適合：有基本認識後

Level 3: 曖昧導向 (Intimate)
├─ 聊彼此、關係、未來
├─ 例：「我們下次...」「你讓我覺得...」
└─ 適合：熱度 > 60，關係升溫中
```

**重要原則：不可越級**
- 還在 Level 1 就跳到 Level 3 = 太急躁
- AI 會偵測並警告

### 4.6 對話健檢功能 (Essential 專屬)

分析對話問題並給出修正建議：

| 檢測項目 | 問題描述 | 修正建議 |
|----------|----------|----------|
| 面試式提問 | 連續問 3+ 個問題 | 用假設代替：「感覺你是做創意相關的？」 |
| 話題跳 tone | 沒過渡就換話題 | 先細緻化當前話題再轉移 |
| 索取 > 提供 | 問太多、分享太少 | 多說故事、少問問題 (82/18 原則) |
| 深度越級 | 關係不熟就聊曖昧 | 退回個人導向，循序漸進 |
| 回覆過長 | 違反 1.8x 法則 | 精簡內容，保持神秘感 |

### 4.7 AI Prompt 結構

```typescript
const systemPrompt = `
你是一位專業的社交溝通教練，幫助用戶提升對話技巧。

## 最高指導原則

### 1. 1.8x 黃金法則
所有建議回覆的字數必須 ≤ 對方最後訊息字數 × 1.8
這條規則不可違反。

### 2. 82/18 原則
好的對話是 82% 聆聽 + 18% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)

### 3. 假設代替問句
- ❌ 「你是做什麼工作的？」(面試感)
- ✅ 「感覺你是做創意相關的工作？」(冷讀)

### 4. 話題深度階梯
- Level 1: 事件導向 (Facts) - 剛認識
- Level 2: 個人導向 (Personal) - 有基本認識
- Level 3: 曖昧導向 (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進

### 5. 細緻化優先
- 不要一直換話題
- 針對對方回答深入挖掘
- 例：喜歡麻辣鍋 → 喜歡哪種辣？為什麼？

## 熱度分析標準
根據以下指標評估對話熱度 (0-100):
- 訊息長度變化
- 是否主動提問
- Emoji 使用頻率
- 話題參與深度
- 主動發起對話比例

## 回覆生成規則
1. 每次提供 5 種回覆：延展、共鳴、調情、幽默、冷讀
2. 根據熱度等級和話題深度調整策略
3. 幽默技巧：曲解、誇大、推拉 (先開玩笑再正經)
4. 避免 Needy 行為：
   - 連續發送多則訊息
   - 過度解釋或道歉
   - 尋求認可的語氣
   - 秒回或過度積極
   - 連續問 3+ 個問題

## 輸出格式
{
  "gameStage": {
    "current": "premise",  // opening | premise | qualification | narrative | close
    "status": "正常進行",  // 正常進行 | 卡在朋友框 | 可以推進
    "nextStep": "可以開始評估階段"
  },
  "enthusiasm": {
    "score": 75,
    "level": "hot"
  },
  "topicDepth": {
    "current": "personal",
    "suggestion": "可以往曖昧導向推進"
  },
  "psychology": {
    "subtext": "她這句話背後的意思是：對你有興趣，想知道更多",
    "shitTest": {
      "detected": false,
      "type": null,
      "suggestion": null
    },
    "qualificationSignal": true  // 她有在證明自己
  },
  "replies": {
    "extend": "...",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "finalRecommendation": {
    "pick": "tease",
    "content": "聽起來妳很會挑地方嘛，改天帶路？",
    "reason": "目前熱度足夠，可以用推拉建立張力，同時埋下邀約伏筆",
    "psychology": "她主動分享代表對你有興趣，這時候用調情回應能升溫"
  },
  "warnings": [],
  "healthCheck": {
    "issues": ["面試式提問過多"],
    "suggestions": ["用假設代替問句"]
  },
  "strategy": "簡短策略說明",
  "reminder": "記得用你的方式說，見面才自然"
}
`;
```

### 4.8 俚語/時事梗處理

```
處理策略：90% AI 反推 + 10% 問用戶

情況 1: AI 能理解
├─ 正常分析
└─ 不打擾用戶

情況 2: AI 不確定
├─ 嘗試從上下文推測
├─ 給出分析但標註「不確定」
└─ 提供「點擊說明」選項

情況 3: 完全不懂
├─ 詢問用戶：「這句話的意思是...？」
└─ 用戶解釋後更新理解
```

### 4.9 混合模型策略

```typescript
function selectModel(context: AnalysisContext): 'haiku' | 'sonnet' {
  // 使用 Sonnet 的情況 (30%)
  if (
    context.conversationLength > 20 ||      // 長對話
    context.enthusiasmLevel === 'cold' ||   // 冷淡需要策略
    context.hasComplexEmotions ||           // 複雜情緒
    context.isFirstAnalysis                 // 首次分析建立基準
  ) {
    return 'sonnet';
  }

  // 預設使用 Haiku (70%)
  return 'haiku';
}
```

---

## 5. UI/UX 設計 (User Interface)

### 5.0 設計風格：高端極簡

> **核心理念**：大量留白、精緻動畫、字體層次明確（類似 Apple 官網風格）

| 元素 | 設計原則 |
|------|----------|
| **留白** | 元素間保持足夠呼吸空間，不擁擠 |
| **動畫** | 微交互、過場動畫流暢自然 |
| **字體** | 層次分明：標題/正文/說明 大小對比 |
| **色彩** | 深色底 + 重點色點綴，不花俏 |
| **卡片** | 圓角、輕微陰影、懸浮感 |

### 5.1 核心畫面

#### 畫面 1: 對話列表 (Home)
```
┌─────────────────────────────┐
│  VibeSync          [+新增]  │
├─────────────────────────────┤
│  🔍 搜尋對話...              │
├─────────────────────────────┤
│  ┌───┐                      │
│  │ 👤│ 小美        昨天 23:14│
│  └───┘ 熱度: 🔥 72          │
│        最後：哈哈好啊～      │
├─────────────────────────────┤
│  ┌───┐                      │
│  │ 👤│ Amy         前天     │
│  └───┘ 熱度: ❄️ 28          │
│        最後：嗯              │
├─────────────────────────────┤
│                             │
│      [ 升級方案解鎖更多 ]    │
│                             │
└─────────────────────────────┘
```

#### 畫面 2: 對話分析 (Analysis)
```
┌─────────────────────────────┐
│  ← 小美           [分析中...]│
├─────────────────────────────┤
│                             │
│  ┌─────────────────────────┐│
│  │ 她: 週末有什麼計畫嗎？   ││
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│
│  │ 我: 可能去爬山，妳呢？   ││
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│
│  │ 她: 哇塞我也超愛爬山的！ ││
│  │     最近去了抹茶山超美～ ││
│  └─────────────────────────┘│
│                             │
├─────────────────────────────┤
│  熱度分析                    │
│  ┌─────────────────────────┐│
│  │  🔥 72/100  熱情        ││
│  │  ████████████░░░░       ││
│  └─────────────────────────┘│
│                             │
│  💡 策略：她有興趣且主動分享 │
│     保持沉穩，80%鏡像即可   │
│                             │
├─────────────────────────────┤
│  建議回覆 (字數上限: 32字)   │
│                             │
│  [延展] 抹茶山不錯欸，        │
│        下次可以挑戰更難的    │
│                     [複製]  │
│                             │
│  [共鳴] 抹茶山超讚！         │
│        照片一定很美吧       │
│                     [複製]  │
│                             │
│  [調情] 聽起來妳很會挑地方嘛 │
│        改天帶路？           │
│                     [複製]  │
└─────────────────────────────┘
```

#### 畫面 3: 新增對話 (New Session)

> **重要**：一個對話 = 一位聊天對象（像 ChatGPT 的 session）

```
┌─────────────────────────────┐
│  ← 新增對話                  │
├─────────────────────────────┤
│                             │
│  對話對象暱稱                │
│  ┌─────────────────────────┐│
│  │ 小美                     ││
│  └─────────────────────────┘│
│                             │
│  認識場景                    │
│  ┌─────────────────────────┐│
│  │ [交友軟體 ▼]             ││
│  │  ├─ 交友軟體             ││
│  │  ├─ 現場搭訕             ││
│  │  ├─ 朋友介紹             ││
│  │  └─ 其他                 ││
│  └─────────────────────────┘│
│                             │
│  認識多久                    │
│  ┌─────────────────────────┐│
│  │ [剛認識 ▼]               ││
│  │  ├─ 剛認識               ││
│  │  ├─ 幾天                 ││
│  │  ├─ 幾週                 ││
│  │  └─ 一個月+              ││
│  └─────────────────────────┘│
│                             │
│  你的目標                    │
│  ┌─────────────────────────┐│
│  │ [約出來 ▼] (預設)        ││
│  │  ├─ 約出來               ││
│  │  ├─ 維持熱度             ││
│  │  └─ 純聊天               ││
│  └─────────────────────────┘│
│                             │
│         [ 下一步 ]           │
│                             │
└─────────────────────────────┘
```

#### 畫面 4: 貼上對話 (Input)
```
┌─────────────────────────────┐
│  ← 與小美的對話              │
├─────────────────────────────┤
│                             │
│  貼上對話內容                │
│  ┌─────────────────────────┐│
│  │ 她: 你好                 ││
│  │ 我: 嗨                   ││
│  │ 她: 在幹嘛               ││
│  │ 我: 工作中，妳呢         ││
│  │ 她: 週末有什麼計畫嗎？   ││
│  │ ...                      ││
│  └─────────────────────────┘│
│                             │
│  ℹ️ 格式：每行一則訊息       │
│     以「她:」或「我:」開頭   │
│                             │
│         [ 開始分析 ]         │
│                             │
└─────────────────────────────┘
```

#### 畫面 5: 設定 (Settings)
```
┌─────────────────────────────┐
│  設定                        │
├─────────────────────────────┤
│                             │
│  帳戶                        │
│  ├─ 訂閱方案     Essential ✓ │
│  ├─ 本月用量     47/200     │
│  └─ 帳號         user@...   │
│                             │
│  偏好設定                    │
│  ├─ 語言         繁體中文   │
│  ├─ 深色模式     開啟       │
│  └─ 通知         關閉       │
│                             │
│  隱私與安全                  │
│  ├─ 清除所有對話資料         │
│  ├─ 匯出我的資料             │
│  └─ 隱私權政策               │
│                             │
│  關於                        │
│  ├─ 版本         1.0.0      │
│  ├─ 使用條款                 │
│  └─ 意見回饋                 │
│                             │
│        [ 登出 ]              │
└─────────────────────────────┘
```

### 5.2 對話記憶 UX 設計

#### 核心概念：一人一對話 (永久持續)

```
用戶視角：
┌─────────────────────────────────────────┐
│  與小美的對話                    [...]  │
├─────────────────────────────────────────┤
│                                         │
│  📊 第 23 輪 ｜ 認識 14 天              │
│  🔥 熱度趨勢：穩定上升 (45→72)          │
│                                         │
│  ┌─ 她 ──────────────────────────────┐  │
│  │ 哇健身！你練多久了？              │  │
│  └───────────────────────────────────┘  │
│                                         │
│  💡 建議回覆                            │
│  ┌───────────────────────────────────┐  │
│  │ 🔄 延展：三個月了，越練越上癮...  │  │
│  │ 💬 共鳴：你也有運動習慣嗎？       │  │
│  │ 😏 調情：練到可以單手抱你...      │  │
│  │ 🎭 幽默：練到可以參加奧運了       │  │
│  │ 🔮 冷讀：感覺你也是運動型的人？   │  │
│  └───────────────────────────────────┘  │
│                                         │
│  📝 貼上她的新回覆...                   │
│  [分析] ← 消耗 1 則訊息額度             │
│                                         │
└─────────────────────────────────────────┘
```

#### 記憶策略 (用戶無感)

```
技術實作：
├─ 最近 15 輪：完整保留
├─ 更早的輪次：自動摘要
└─ 用戶感知：對話一直連貫，無中斷

摘要範例 (系統內部，用戶看不到)：
「第 1-15 輪摘要：
- 認識管道：交友軟體
- 共同興趣：健身、咖啡
- 熱度變化：40→55→65
- 關係進展：已約過一次咖啡
- 她的特徵：回覆快、愛用表情符號」
```

#### 智能推測用戶選擇

```
90% 情況：AI 從對方回覆反推用戶說了什麼
例：對方說「哇健身！」→ 推測用戶選了健身相關建議

10% 情況：推測不出來時輕量確認
┌─────────────────────────────────────────┐
│  🤔 快速確認 (可跳過)                   │
│                                         │
│  對方回覆好像跟我的建議不太相關，       │
│  你實際回覆了什麼呢？                   │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ 輸入你的實際回覆（可選）          │  │
│  └───────────────────────────────────┘  │
│                                         │
│  [跳過]              [確認]             │
└─────────────────────────────────────────┘
```

#### 封存與新對話 (特殊情況)

```
點擊 [...] 選單：
┌─────────────────────┐
│ 📊 查看熱度歷史     │
│ 📝 編輯對象資訊     │
│ ────────────────── │
│ 📦 封存並開新對話   │  ← 特殊情況才用
│ 🗑️ 刪除此對話       │
└─────────────────────┘

使用時機：
- 關係重新開始 (分手後復合)
- 很久沒聊，想重新來過
```

### 5.3 設計系統

#### 色彩系統
```dart
class AppColors {
  // 主色調 - 深紫 (專業、神秘)
  static const primary = Color(0xFF6B4EE6);
  static const primaryLight = Color(0xFF9D8DF7);
  static const primaryDark = Color(0xFF4527A0);

  // 熱度等級色彩
  static const cold = Color(0xFF64B5F6);      // 藍
  static const warm = Color(0xFFFFD54F);      // 黃
  static const hot = Color(0xFFFF8A65);       // 橘
  static const veryHot = Color(0xFFFF6B9D);   // 粉紅

  // 中性色
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
}
```

#### 字型系統
```dart
class AppTypography {
  static const headlineLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );

  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.5,
  );

  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
```

---

## 6. 安全與合規 (Security & Compliance)

### 6.1 App Store 審核策略

#### 定位說明
- **App Store 分類**: Social Networking / Lifestyle
- **應用描述**: 社交溝通技巧教練，幫助用戶提升對話品質
- **避免用詞**: 把妹、搭訕、約會、戀愛技巧
- **採用用詞**: 社交技巧、溝通能力、人際關係、對話品質

#### 關鍵合規點
1. ✅ 不存儲他人對話於伺服器
2. ✅ 用戶完全控制本地資料
3. ✅ 提供資料刪除功能
4. ✅ 訂閱價格透明
5. ✅ 不使用「操控」相關用語

### 6.2 隱私保護

```dart
class PrivacyManager {
  /// 本地加密金鑰 (由 Hive 自動管理)
  static const encryptionCipher = HiveAesCipher(key);

  /// 資料保留政策
  static const dataRetentionDays = 90; // 90天未使用自動清理

  /// 匯出用戶資料 (GDPR 合規)
  Future<File> exportUserData() async {
    final conversations = await getLocalConversations();
    final json = jsonEncode(conversations);
    return saveToFile(json);
  }

  /// 完全刪除所有資料
  Future<void> deleteAllData() async {
    await Hive.deleteBoxFromDisk('conversations');
    await Hive.deleteBoxFromDisk('settings');
    await supabase.auth.signOut();
  }
}
```

### 6.3 API 安全

```typescript
// Edge Function 安全檢查
async function validateRequest(req: Request) {
  // 1. 驗證 JWT
  const token = req.headers.get('Authorization');
  const { user, error } = await supabase.auth.getUser(token);
  if (error) throw new UnauthorizedError();

  // 2. 檢查訂閱狀態
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('tier, monthly_analyses_used')
    .eq('user_id', user.id)
    .single();

  // 3. 檢查用量限制
  const limit = TIER_LIMITS[sub.tier];
  if (sub.monthly_analyses_used >= limit) {
    throw new QuotaExceededError();
  }

  // 4. Rate limiting (IP + User)
  await checkRateLimit(user.id, req.ip);
}
```

---

## 7. 訂閱策略 (Subscription Strategy)

### 7.1 定價方案 (訊息制) ✅ 最終版

> **計費邏輯：1 則訊息 = 1 訊息額度**
> **策略：合理定價，前期 6-14 付費用戶即可打平**
> **簡化為 2 個付費方案，專注個人用戶**

| 方案 | 月費 | USD | 訊息/月 | 每日上限 |
|------|------|-----|---------|----------|
| **Free** | NT$0 | $0 | 30 | 15 |
| **Starter** | NT$149 | ~$5 | 300 | 50 |
| **Essential** | NT$349 | ~$11 | 1,000 | 150 |

### 7.2 功能對照表

| 功能 | Free | Starter | Essential |
|------|------|---------|-----------|
| **額度** | | | |
| 訊息額度/月 | 30 | 300 | 1,000 |
| 每日上限 | 15 | 50 | 150 |
| 對話數量 | 3 | 15 | 50 |
| **分析功能** | | | |
| 熱度分析 | ✓ | ✓ | ✓ |
| 話題深度分析 | ✗ | ✓ | ✓ |
| 對話健檢 | ✗ | ✗ | ✓ |
| Needy 警示 | ✗ | ✓ | ✓ |
| **回覆建議** | | | |
| 🔄 延展回覆 | ✓ | ✓ | ✓ |
| 💬 共鳴回覆 | ✗ | ✓ | ✓ |
| 😏 調情回覆 | ✗ | ✓ | ✓ |
| 🎭 幽默回覆 | ✗ | ✓ | ✓ |
| 🔮 冷讀回覆 | ✗ | ✓ | ✓ |
| **其他** | | | |
| 對話記憶 | 5 輪 | 15 輪 | 15 輪 + 摘要 |
| AI 模型 | Haiku | 混合 | Sonnet 優先 |
| 免費試用 | - | 7天 | 7天 |

### 7.3 成本與損益

| 方案 | 月費 | 我們成本 | 毛利率 |
|------|------|----------|--------|
| Starter | NT$149 | ~NT$10 | 94% |
| Essential | NT$349 | ~NT$32 | 91% |

**前期損益平衡：6-14 個付費用戶**

### 7.4 加購訊息包

| 訊息包 | 價格 | 每則成本 |
|--------|------|----------|
| 50 則 | NT$39 | NT$0.78 |
| 150 則 | NT$99 | NT$0.66 |
| 300 則 | NT$179 | NT$0.60 |

### 7.5 免費試用
- 所有付費方案享 **7 天免費試用**
- 試用期間可隨時取消
- 試用結束自動扣款

### 7.6 客服管道
- 📧 Email: support@vibesync.app
- 💬 LINE 官方帳號: @vibesync
- 📝 App 內回饋表單

### 7.7 首發市場
- 台灣優先 (繁體中文)

### 7.8 RevenueCat 整合

```dart
class SubscriptionService {
  final _purchases = Purchases.instance;

  Future<void> initialize() async {
    await Purchases.setLogLevel(LogLevel.debug);

    PurchasesConfiguration config = PurchasesConfiguration(
      Platform.isIOS
        ? 'appl_xxxxxxxx'  // App Store key
        : 'goog_xxxxxxxx', // Play Store key
    );

    await Purchases.configure(config);
  }

  Future<SubscriptionTier> getCurrentTier() async {
    final customerInfo = await _purchases.getCustomerInfo();

    if (customerInfo.entitlements.active.containsKey('essential')) {
      return SubscriptionTier.essential;
    } else if (customerInfo.entitlements.active.containsKey('starter')) {
      return SubscriptionTier.starter;
    }
    return SubscriptionTier.free;
  }

  Future<void> purchaseStarter() async {
    final offerings = await _purchases.getOfferings();
    final package = offerings.current?.getPackage('starter_monthly');
    if (package != null) {
      await _purchases.purchasePackage(package);
    }
  }

  Future<void> purchaseEssential() async {
    final offerings = await _purchases.getOfferings();
    final package = offerings.current?.getPackage('essential_monthly');
    if (package != null) {
      await _purchases.purchasePackage(package);
    }
  }
}
```

---

## 8. 技術堆疊摘要 & MVP 範圍

### 8.1 技術堆疊總覽

| 層級 | 技術 | 用途 |
|------|------|------|
| **Frontend** | Flutter 3.x | 跨平台 UI |
| | Riverpod | 狀態管理 |
| | Hive | 本地加密儲存 |
| | go_router | 路由管理 |
| **Backend** | Supabase | BaaS 平台 |
| | PostgreSQL | 用戶/訂閱資料 |
| | Edge Functions | Serverless API |
| **AI** | Claude API | Haiku + Sonnet |
| **Payment** | RevenueCat | 訂閱管理 |
| **Monitoring** | Sentry | 錯誤追蹤 |

### 8.2 MVP 功能範圍

#### 包含 ✅
1. 用戶註冊/登入 (Google、Apple、Email OTP)
2. 對話複製貼上輸入 + 情境設定（認識場景/多久/目標）
3. 熱度分析 (0-100 + 四等級)
4. GAME 階段判斷（打開→前提→評估→敘事→收尾）
5. **五種回覆建議** (延展/共鳴/調情/幽默/冷讀)
6. **AI 最終建議 + 理由 + 心理學分析**
7. 1.8x 黃金法則字數限制
8. Needy 行為警示
9. 廢物測試偵測 + 淺溝通解讀
10. 本地加密儲存對話
11. 三級訂閱 (Free/Starter/Essential)
12. 高端極簡深色模式 UI
13. **一人一對話 Session 設計**
14. 對話記憶（15 輪 + 自動摘要）
15. **冰點放棄建議**（機會渺茫時建議開新對話）
16. **真人一致性提醒**（見面才自然）

#### 不包含 (V2) ❌
- Keyboard Extension
- Share Extension
- **圖片上傳分析**（交友軟體個人檔案照破冰用）
- **TTS 語音朗讀**（點擊念出建議回覆）
- 多語言支援
- 社群功能
- AI 個性化調整

### 8.3 專案結構

```
vibesync/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   └── routes.dart
│   ├── core/
│   │   ├── constants/
│   │   ├── theme/
│   │   ├── utils/
│   │   └── extensions/
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   ├── conversation/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   ├── analysis/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   └── subscription/
│   │       ├── data/
│   │       ├── domain/
│   │       └── presentation/
│   └── shared/
│       └── widgets/
├── supabase/
│   ├── functions/
│   │   ├── analyze-chat/
│   │   └── generate-reply/
│   └── migrations/
├── test/
├── docs/
│   └── plans/
├── pubspec.yaml
├── CLAUDE.md
└── README.md
```

---

## 附錄 A: GAME 框架完整整合

> 基於專業社交教練 Know-How，以下概念完整整合至 AI 提示

### A.1 GAME 五階段

| 階段 | 英文 | 目標 | AI 判斷依據 |
|------|------|------|-------------|
| 打開 | Opening | 破冰 | 對話剛開始，基本寒暄 |
| 前提 | Premise | 進入男女框架 | 是否有張力，還是純閒聊 |
| 評估 | Qualification | 她證明自己 | 她有沒有在展示自己的優點 |
| 敘事 | Narrative | 個性樣本 | 用戶是否在說故事/分享 |
| 收尾 | Close | 確立邀約 | 熱度穩定，可以約了 |

### A.2 核心技巧

| 技巧 | 說明 | AI 應用 |
|------|------|---------|
| **隱性 DHV** | 一句話帶過價值，不解釋 | 建議回覆時示範 |
| **框架控制** | 不因攻擊/廢測改變 | 偵測廢測，建議彈開 |
| **橡膠球理論** | 廢測讓它彈開 | 幽默/忽略回應 |
| **淺溝通解讀** | 讀懂文字背後意思 | 心理分析輸出 |
| **評估權反轉** | 你在篩選她 | 偵測她是否在證明自己 |
| **陳述優於問句** | 更自然 | 回覆建議多用陳述 |

### A.3 警示系統

| 警示 | 觸發條件 | 建議 |
|------|----------|------|
| **Needy** | 連發訊息/過度解釋/秒回 | 收斂，不要太急 |
| **面試感** | 連問 3+ 問題 | 用假設代替問句 |
| **朋友框** | 太閒聊，沒張力 | 該進入男女前提 |
| **深度越級** | 關係不熟就聊曖昧 | 退回上一層 |
| **冰點放棄** | 熱度 <30 且沒回應 | 建議開新對話 |

### A.4 邀約判斷

```
可以邀約的信號：
├─ 熱度穩定 60+
├─ 她有在「證明自己」
├─ 對話有來有往
├─ 有男女張力
└─ 她對你表現好奇

邀約方式：
├─ 模糊邀約：「改天一起喝咖啡」
└─ 確立邀約：「週六下午，信義區那間？」

常見錯誤：
└─ 到最後一步扭扭捏捏 → 直接敲定
```

---

## 附錄 B: 商業級 SaaS 補充設計

> **v1.2 新增**：補齊 AI 護欄、日誌審計、Fallback、Onboarding、Rate Limiting、Token 追蹤

### B.1 AI 護欄 (Guardrails)

#### B.1.1 System Prompt 安全約束

```typescript
const SAFETY_RULES = `
## 安全規則 (不可違反)

### 絕對禁止建議：
- 任何形式的騷擾、跟蹤、強迫行為
- 未經同意的身體接觸暗示
- 操控、威脅、情緒勒索的言語
- 持續聯繫已明確拒絕的對象
- 任何違法行為

### 冰點情境處理：
當熱度 < 30 且對方明顯不感興趣時：
- 建議用戶「尊重對方意願」
- 可建議「開新對話，認識其他人」
- 絕不建議「再試一次」或「換個方式追」

### 輸出原則：
- 所有建議必須基於「雙方舒適」
- 鼓勵真誠表達，而非操控技巧
`;
```

#### B.1.2 輸出驗證層

```typescript
const BLOCKED_PATTERNS = [
  /跟蹤|stalking/i,
  /不要放棄.*一直/i,
  /她說不要.*但其實/i,
  /強迫|逼.*答應/i,
  /騷擾|harassment/i,
  /威脅|勒索/i,
];

function validateOutput(response: AnalysisResult): AnalysisResult {
  const allReplies = Object.values(response.replies).join(' ');

  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(allReplies)) {
      return {
        ...response,
        replies: getSafeReplies(response.enthusiasm.level),
        warnings: [...response.warnings, {
          type: 'safety_filter',
          message: '部分建議因安全考量已調整'
        }]
      };
    }
  }

  return response;
}
```

#### B.1.3 免責聲明

- **位置**：Analysis Screen 底部固定顯示
- **內容**：「建議僅供參考，請以真誠、尊重為原則」

---

### B.2 AI Fallback 機制

#### B.2.1 重試與降級流程

```
請求 → Sonnet (首選)
         ↓ 失敗
      重試 Sonnet (1次)
         ↓ 仍失敗
      降級 Haiku
         ↓ 仍失敗
      重試 Haiku (1次)
         ↓ 仍失敗
      顯示錯誤 UI + 不扣額度
```

**超時設定**：每次請求 30 秒上限

#### B.2.2 錯誤類型與處理

| 錯誤類型 | 行為 | 扣額度？ |
|----------|------|----------|
| `TIMEOUT` | 重試 → 降級 → 顯示錯誤 | ❌ 不扣 |
| `API_ERROR` (500) | 重試 → 降級 → 顯示錯誤 | ❌ 不扣 |
| `RATE_LIMITED` (429) | 等待後重試 | ❌ 不扣 |
| `INVALID_RESPONSE` | 重試 → 降級 → 顯示錯誤 | ❌ 不扣 |
| `CONTENT_BLOCKED` | 回傳安全版本 | ✅ 扣 |
| `SUCCESS` | 正常回傳 | ✅ 扣 |

#### B.2.3 失敗 UI

```
┌─────────────────────────────┐
│                             │
│     😔 分析暫時無法完成      │
│                             │
│  AI 服務目前忙碌中，          │
│  請稍後再試                  │
│                             │
│  ✓ 此次不會扣除訊息額度      │
│                             │
│      [ 重新分析 ]           │
│                             │
└─────────────────────────────┘
```

---

### B.3 AI 日誌 (Audit Log)

#### B.3.1 資料表結構

```sql
CREATE TABLE ai_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  -- 請求資訊
  model TEXT NOT NULL,
  request_type TEXT NOT NULL,  -- 'analyze' | 'generate'

  -- Token 使用
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cost_usd DECIMAL(10, 6),

  -- 效能
  latency_ms INTEGER NOT NULL,

  -- 狀態
  status TEXT NOT NULL,  -- 'success' | 'failed' | 'filtered'
  error_code TEXT,

  -- 失敗時才記錄的完整內容
  request_body JSONB,
  response_body JSONB,
  error_message TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_ai_logs_user_id ON ai_logs(user_id);
CREATE INDEX idx_ai_logs_created_at ON ai_logs(created_at);
CREATE INDEX idx_ai_logs_status ON ai_logs(status);

-- 自動清理 30 天前的記錄
CREATE OR REPLACE FUNCTION cleanup_old_ai_logs()
RETURNS void AS $$
BEGIN
  DELETE FROM ai_logs WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
```

#### B.3.2 記錄策略

| 記錄項目 | 成功時 | 失敗時 |
|----------|--------|--------|
| timestamp, user_id, model | ✓ | ✓ |
| input_tokens, output_tokens | ✓ | ✓ |
| latency_ms, cost_usd | ✓ | ✓ |
| request_body, response_body | ✗ | ✓ |
| error_message | ✗ | ✓ |

**保留期限**：30 天

---

### B.4 Onboarding 流程

#### B.4.1 流程總覽

```
首次啟動 App
     │
     ▼
┌─────────────┐
│  歡迎頁     │  ← 品牌介紹
└─────────────┘
     │
     ▼
┌─────────────┐
│  功能介紹   │  ← 3 個核心功能 (可滑動)
└─────────────┘
     │
     ▼
┌─────────────┐
│  Demo 體驗  │  ← 內建範例對話分析
└─────────────┘
     │
     ▼
┌─────────────┐
│  首頁(空)   │  ← 引導開始第一次分析
└─────────────┘
```

#### B.4.2 Demo 對話

```typescript
const DEMO_CONVERSATION = {
  name: '範例對話',
  context: {
    meetingContext: 'dating_app',
    duration: 'few_days',
    goal: 'date',
  },
  messages: [
    { content: '欸你週末都在幹嘛', isFromMe: false },
    { content: '看情況欸 有時候爬山有時候耍廢', isFromMe: true },
    { content: '哇塞你也爬山！我最近去了抹茶山超美', isFromMe: false },
  ],
};

// Demo 分析結果 (預設，不呼叫 API，不扣額度)
const DEMO_RESULT = {
  enthusiasm: { score: 72, level: 'hot' },
  gameStage: { current: 'premise', status: '正常進行' },
  replies: {
    extend: '抹茶山不錯欸，你喜歡哪種路線？',
    resonate: '抹茶山超讚！雲海那段是不是很美',
    tease: '聽起來你很會挑地方嘛，改天帶路？',
    humor: '抹茶山...所以你是抹茶控？',
    coldRead: '感覺你是那種週末不會待在家的人',
  },
  finalRecommendation: {
    pick: 'tease',
    content: '聽起來你很會挑地方嘛，改天帶路？',
    reason: '熱度足夠，用調情建立張力並埋下邀約伏筆',
  },
};
```

#### B.4.3 空狀態設計

```
┌─────────────────────────────┐
│  VibeSync          [設定]   │
├─────────────────────────────┤
│                             │
│      💬                     │
│                             │
│   還沒有對話紀錄             │
│                             │
│   把聊天內容貼上來，         │
│   讓 VibeSync 幫你分析！     │
│                             │
│   [ ＋ 開始第一次分析 ]      │
│                             │
│  ─────────────────────────  │
│  💡 Free 方案每月 30 則訊息  │
│     足夠體驗核心功能         │
│                             │
└─────────────────────────────┘
```

---

### B.5 Rate Limiting

#### B.5.1 限制層級

| 層級 | 限制 | 重置時間 | 用途 |
|------|------|----------|------|
| **每分鐘** | 5 次請求 | 60 秒滾動 | 防止激進使用/腳本 |
| **每日** | 依方案 (15/50/150) | 每日 00:00 UTC+8 | 防止單日耗盡月額度 |
| **每月** | 依方案 (30/300/1000) | 每月 1 日 | 訂閱核心限制 |

#### B.5.2 資料表擴充

```sql
-- 在 subscriptions 表新增
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS
  daily_messages_used INTEGER DEFAULT 0,
  daily_reset_at TIMESTAMPTZ DEFAULT NOW();

-- Rate Limit 表
CREATE TABLE rate_limits (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  minute_count INTEGER DEFAULT 0,
  minute_window_start TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### B.5.3 錯誤 UI

| 觸發條件 | UI 訊息 | CTA |
|----------|---------|-----|
| 每分鐘超限 | 「請稍後再試」+ 倒數計時 | 等待 |
| 每日超限 | 「今日額度已用完，明天重置」 | 升級方案 |
| 每月超限 | 「本月額度已用完」 | 升級 / 加購 |

#### B.5.4 Response Headers

```typescript
res.setHeader('X-RateLimit-Remaining-Minute', remaining.minute);
res.setHeader('X-RateLimit-Remaining-Daily', remaining.daily);
res.setHeader('X-RateLimit-Remaining-Monthly', remaining.monthly);
res.setHeader('X-RateLimit-Reset', retryAfter);
```

---

### B.6 Token 精確追蹤

#### B.6.1 資料表結構

```sql
CREATE TABLE token_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
  cost_usd DECIMAL(10, 6) NOT NULL,

  conversation_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 月度彙總 View
CREATE VIEW user_monthly_token_summary AS
SELECT
  user_id,
  DATE_TRUNC('month', created_at) AS month,
  SUM(input_tokens) AS total_input_tokens,
  SUM(output_tokens) AS total_output_tokens,
  SUM(total_tokens) AS total_tokens,
  SUM(cost_usd) AS total_cost_usd,
  COUNT(*) AS request_count
FROM token_usage
GROUP BY user_id, DATE_TRUNC('month', created_at);
```

#### B.6.2 成本計算

```typescript
const MODEL_PRICING = {
  'claude-sonnet-4-20250514': {
    input: 3.00 / 1_000_000,
    output: 15.00 / 1_000_000,
  },
  'claude-3-5-haiku-20241022': {
    input: 0.25 / 1_000_000,
    output: 1.25 / 1_000_000,
  },
};

function calculateCost(model: string, inputTokens: number, outputTokens: number): number {
  const pricing = MODEL_PRICING[model];
  return (inputTokens * pricing.input) + (outputTokens * pricing.output);
}
```

#### B.6.3 從 API Response 擷取

```typescript
// Claude API Response
const { input_tokens, output_tokens } = response.usage;

await supabase.from('token_usage').insert({
  user_id: userId,
  model,
  input_tokens,
  output_tokens,
  cost_usd: calculateCost(model, input_tokens, output_tokens),
  conversation_id: request.conversationId,
});
```

---

## 附錄 C: Admin Dashboard

> **v1.3 新增**：自建管理後台，供營運團隊監控與分析

### C.1 技術架構

```
┌─────────────────────────────────────────────────────────────┐
│                   Admin Dashboard (Vercel)                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Next.js 14 (App Router) + Tailwind CSS + shadcn/ui    ││
│  │  Recharts (圖表) + Supabase Auth (認證)                 ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌──────────┐    ┌──────────┐    ┌──────────────┐
       │ Supabase │    │ RevenueCat│   │  ai_logs     │
       │   DB     │    │  Webhook  │   │ token_usage  │
       └──────────┘    └──────────┘    └──────────────┘
```

### C.2 報表模組 (8 項)

| # | 模組 | 主要指標 | 資料來源 |
|---|------|----------|----------|
| 1 | **用戶總覽** | 總用戶數、日/週新增、活躍率 | `users` |
| 2 | **訂閱分佈** | Free/Starter/Essential 佔比、轉換率 | `subscriptions` |
| 3 | **Token 成本** | 日/月消耗、Haiku vs Sonnet 分佈 | `token_usage` |
| 4 | **營收總額** | MRR、新訂閱、續訂、取消 | RevenueCat Webhook |
| 5 | **利潤分析** | 毛利 = 營收 - Token 成本、每用戶平均成本 | 計算欄位 |
| 6 | **AI 成功率** | 成功/失敗/過濾比例、趨勢 | `ai_logs` |
| 7 | **錯誤追蹤** | 錯誤類型分佈 (TIMEOUT/API_ERROR/...) | `ai_logs` |
| 8 | **用戶活躍度** | DAU/MAU、7日留存、30日留存 | Event tracking |

### C.3 資料庫擴充

```sql
-- Admin 用戶白名單
CREATE TABLE admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 營收事件 (RevenueCat Webhook 寫入)
CREATE TABLE revenue_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  event_type TEXT NOT NULL,  -- 'INITIAL_PURCHASE' | 'RENEWAL' | 'CANCELLATION'
  product_id TEXT NOT NULL,
  price_usd DECIMAL(10, 2) NOT NULL,
  currency TEXT DEFAULT 'TWD',
  transaction_id TEXT,
  event_timestamp TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 月度營收彙總 View
CREATE VIEW monthly_revenue AS
SELECT
  DATE_TRUNC('month', event_timestamp) AS month,
  SUM(CASE WHEN event_type IN ('INITIAL_PURCHASE', 'RENEWAL') THEN price_usd ELSE 0 END) AS revenue,
  COUNT(DISTINCT user_id) AS paying_users
FROM revenue_events
GROUP BY DATE_TRUNC('month', event_timestamp);

-- 月度利潤 View
CREATE VIEW monthly_profit AS
SELECT
  r.month,
  r.revenue,
  COALESCE(t.total_cost_usd, 0) AS cost,
  r.revenue - COALESCE(t.total_cost_usd, 0) AS profit,
  CASE WHEN r.revenue > 0
    THEN ((r.revenue - COALESCE(t.total_cost_usd, 0)) / r.revenue * 100)::DECIMAL(5,2)
    ELSE 0
  END AS margin_percent
FROM monthly_revenue r
LEFT JOIN (
  SELECT DATE_TRUNC('month', created_at) AS month, SUM(cost_usd) AS total_cost_usd
  FROM token_usage
  GROUP BY DATE_TRUNC('month', created_at)
) t ON r.month = t.month;
```

### C.4 Dashboard 頁面結構

```
/admin
├── /dashboard          # 總覽儀表板 (關鍵指標卡片 + 趨勢圖)
├── /users              # 用戶列表 + 搜尋 + 詳細
├── /subscriptions      # 訂閱分佈 + 轉換漏斗
├── /revenue            # 營收報表 + MRR 趨勢
├── /costs              # Token 成本 + 利潤分析
├── /ai-health          # AI 成功率 + 錯誤追蹤
└── /settings           # Admin 白名單管理
```

### C.5 認證流程

```typescript
// middleware.ts
export async function middleware(req: NextRequest) {
  const session = await getSession(req);

  if (!session) {
    return NextResponse.redirect('/login');
  }

  // 檢查是否在 admin_users 白名單
  const { data } = await supabase
    .from('admin_users')
    .select('id')
    .eq('email', session.user.email)
    .single();

  if (!data) {
    return NextResponse.redirect('/403');
  }

  return NextResponse.next();
}
```

---

## 附錄 D: 沙盒測試環境

> **v1.3 新增**：內測與上架前測試的雙軌策略

### D.1 環境配置

| 環境 | 用途 | 配置 |
|------|------|------|
| **DEV** | 本地開發 | 本地 Supabase + Claude API (測試 key) |
| **STAGING** | 內部測試 | 雲端 Supabase (獨立 Project) + Claude API |
| **PROD** | 正式上線 | 雲端 Supabase (正式) + Claude API |

```dart
// lib/core/config/environment.dart
enum Environment { dev, staging, prod }

class AppConfig {
  static Environment get environment {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    return Environment.values.firstWhere(
      (e) => e.name == env,
      orElse: () => Environment.dev,
    );
  }

  static String get supabaseUrl {
    switch (environment) {
      case Environment.dev:
        return 'http://localhost:54321';
      case Environment.staging:
        return 'https://xxxx-staging.supabase.co';
      case Environment.prod:
        return 'https://xxxx-prod.supabase.co';
    }
  }
}
```

### D.2 雙軌測試策略

| 階段 | 工具 | 適用情境 |
|------|------|----------|
| **快速迭代** | Firebase App Distribution | 每日 build、功能驗證 |
| **正式測試** | TestFlight (iOS) + Internal Testing (Android) | 上架前、訂閱測試 |

### D.3 Firebase App Distribution 設定

```yaml
# .github/workflows/distribute.yml
name: Distribute to Testers

on:
  push:
    branches: [main]

jobs:
  build-and-distribute:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'

      - name: Build APK
        run: flutter build apk --dart-define=ENV=staging

      - name: Upload to Firebase
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_APP_ID }}
          token: ${{ secrets.FIREBASE_TOKEN }}
          groups: testers
          file: build/app/outputs/flutter-apk/app-release.apk
```

### D.4 測試帳號管理

```sql
-- 測試帳號表
CREATE TABLE test_users (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  tester_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 報表時排除測試帳號
CREATE VIEW real_users AS
SELECT * FROM users
WHERE id NOT IN (SELECT user_id FROM test_users);
```

### D.5 RevenueCat Sandbox 測試

| 平台 | Sandbox 設定 | 測試方式 |
|------|--------------|----------|
| iOS | Xcode → StoreKit Configuration | Sandbox Apple ID |
| Android | Play Console → License Testing | 測試帳號 email |

```typescript
// RevenueCat 初始化時判斷環境
final configuration = PurchasesConfiguration(
  environment == Environment.prod
    ? REVENUECAT_API_KEY
    : REVENUECAT_API_KEY_SANDBOX
);
```

### D.6 分發流程

```
開發者 Push → GitHub Actions
                  │
                  ▼
        ┌─────────────────┐
        │  Build APK/IPA  │
        └─────────────────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
   Firebase App        TestFlight /
   Distribution       Internal Testing
        │                   │
        ▼                   ▼
   掃 QR Code 安裝      商店內測安裝
   (快速迭代)          (上架前驗證)
```

---

## 附錄 E: 免責聲明與行銷策略

> **v1.4 新增**：App 內免責聲明 + 雙軌行銷定位

### E.1 團隊核心定位（內部）

```
核心 Know-How：
├─ 搭訕大師全套心法
├─ Chris 技術流聊天模組
├─ GAME 框架 + MK 筆記
├─ 實戰技巧 + 心理學
└─ 最終濃縮：個人化 + 真誠流

哲學：
「不是教你戰勝對手，是讓你在任何情況下都立於不敗之地」
— 孫子兵法精神

訂閱會員專屬：
├─ 搭訕大師實戰/理論影片（Chris/梁叔/Ryan）
└─ MK 筆記講義
```

### E.2 App 內免責聲明 UI

**位置**：Analysis Screen 底部固定顯示

```
┌─────────────────────────────────────────────┐
│  ⚠️ 使用須知                                │
├─────────────────────────────────────────────┤
│                                             │
│  VibeSync 提供的建議僅供參考，               │
│  旨在幫助你更自然地表達自己。                 │
│                                             │
│  我們鼓勵：                                  │
│  ✓ 真誠溝通，展現真實的你                    │
│  ✓ 尊重對方的感受與意願                      │
│  ✓ 建立健康、平等的互動關係                  │
│                                             │
│  請記住：                                    │
│  • 每個人都是獨特的，建議需要適當調整        │
│  • 見面時用你自己的方式說，才會自然          │
│  • 真正的連結來自真誠，而非技巧              │
│                                             │
│  ─────────────────────────────────────────  │
│  本服務不保證任何特定結果，                   │
│  用戶需自行承擔使用建議的責任。               │
└─────────────────────────────────────────────┘
```

### E.3 雙軌行銷策略

| 管道 | 定位 | 用詞 |
|------|------|------|
| **App Store** | 社交溝通教練 | 溝通技巧、情商提升、對話品質、人際關係 |
| **LINE OA / 私域** | 搭訕實戰教練 | GAME 框架、搭訕大師、Chris 技術流、把妹心法 |

#### App Store 描述（審核友善版）

```
【一句話】
社交溝通教練 - 讓每次對話都更有默契

【描述】
VibeSync 幫助你提升社交溝通能力，讓對話更自然、更有效率。

✓ AI 即時分析對話熱度
✓ 五種回覆風格建議
✓ 減少聊天焦慮，不再詞窮
✓ 幫助你展現最好的自己

適合想要提升人際溝通技巧的你。
```

#### LINE OA 行銷文案（私域版）

```
🔥 VibeSync - 搭訕大師 AI 助手

整合 Chris 技術流 + MK 框架 + GAME 理論
由 Opus 頂級 AI 驅動

📚 訂閱即送：
• 搭訕大師實戰影片（Chris/梁叔/Ryan）
• MK 筆記講義完整版
• 兄弟會專屬群組

💡 不是教你戰勝對手，是讓你立於不敗之地
最終目標：個人化 + 真誠流
```

### E.4 敏感詞對照表

| App Store 禁用 ❌ | 替代用詞 ✅ |
|------------------|------------|
| 搭訕 | 社交、認識新朋友 |
| 把妹 | 提升魅力、建立連結 |
| 控制 | 引導、框架 |
| 追求 | 互動、溝通 |
| 約會技巧 | 社交技巧 |
| 戀愛攻略 | 溝通教練 |

---

## 變更記錄

| 日期 | 版本 | 變更內容 |
|------|------|----------|
| 2026-02-26 | 1.0 | 初始設計完成 |
| 2026-02-27 | 1.1 | 新增 GAME 框架、更新 AI 輸出格式、Session 設計、UI 風格 |
| 2026-02-27 | 1.2 | **商業級補充** - AI 護欄、日誌審計、Fallback、Onboarding、Rate Limiting、Token 追蹤 |
| 2026-02-27 | 1.3 | **運營補充** - Admin Dashboard (8 項報表)、沙盒測試環境 (雙軌策略) |
| 2026-02-27 | 1.4 | **行銷補充** - 免責聲明、雙軌行銷策略、敏感詞對照表 |

---

**文件結束**
> Historical Baseline
>
> 這份是 2026-02-27 的初版設計基線，保留當初產品定義與決策脈絡。
> 後續 scope 已明顯擴張，請不要把這份當成現在唯一的現況文件。
>
> 目前請優先搭配這些文件一起看：
> - `docs/current-test-status-2026-04-03.md`
> - `docs/app-review-final-checklist.md`
> - `docs/supabase-ops-guide.md`
> - `docs/revenuecat-ops-guide.md`
> - `docs/phases/phase-a-ios-launch-stabilization.md`
> - `docs/phases/phase-b-android-google-play-expansion.md`
> - `docs/phases/phase-c-growth-content-engine.md`
> - `docs/phases/phase-d-line-oa-automation.md`
