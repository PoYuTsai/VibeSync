# 開場救星（Opening Rescue）設計規格

> **功能定位**：在新增對話選單加入第三個入口，幫用戶在交友軟體上生成個人化開場白
> **品牌一致性**：維持 VibeSync 5 種回覆風格框架（延展/共鳴/調情/幽默/冷讀）
> **計費**：算 1 則訊息額度
> **確認日期**：2026-04-23

---

## 用戶流程

```
首頁 → 點「+」→ 底部選單
  ├── 手動輸入（現有）
  ├── 截圖開始（現有）
  └── 🎯 開場救星（新）→ OpeningRescueScreen
       ├── 上傳自介截圖（Vision 分析）
       ├── 手動輸入對方資訊
       └── 不提供資料 → 隨機生成
```

## 頁面設計

### OpeningRescueScreen

**頂部區域：**
- 標題：「開場救星」
- 副標題：「上傳對方的自介截圖，或手動輸入資料，AI 幫你量身打造開場白」

**輸入區域（二選一 tab）：**

Tab 1 — 截圖自介：
- ImagePickerWidget（複用現有元件，最多 3 張）
- 提示文字：「上傳交友軟體的個人檔案截圖」
- 計費：每張截圖算 1 則額度（3 張 = 3 則）

Tab 2 — 手動輸入：
- 對方名字（選填）
- Bio / 自我介紹（選填，多行文字框）
- 興趣標籤（選填）
- 認識場景下拉（交友軟體 / IG / 現實認識 / 其他）

**生成按鈕：**
- GradientButton「生成開場白」
- 有截圖或有文字 → 客製化生成
- 都沒填 → 隨機通用開場白

**結果區域：**
- 5 張水平滑動卡片（複用 _buildHorizontalReplyCard 風格）
- 每張：風格標籤 + 開場白內容 + 複製按鈕
- 第一張有「AI 推薦」badge
- 底部「重新生成」按鈕

## AI Prompt 設計

### 知識庫（融入 System Prompt）

從研究報告提取的可用框架：
1. **穿搭風格 → 性格推斷**（Gorpcore = 實用/冒險、Y2K = 外向/自信等）
2. **Big Five 照片特徵映射**（笑容、色彩、構圖 → 性格）
3. **擺拍 vs 自然照 → 真誠度/語氣調整**
4. **背景環境 → 話題切入點**

### 不使用的部分
- ❌ 黑暗三角分析（冒犯用戶）
- ❌ OSINT 真實性驗證（不是調查工具）

### Prompt 結構

```
你是 VibeSync 的開場白生成教練。

根據用戶提供的對方資訊（自介截圖或文字描述），生成 5 種不同風格的開場白。

## 分析框架
[穿搭風格分析 + Big Five 映射 + 背景環境分析]

## 5 種開場白風格
- extend（延展）：觀察對方照片/bio 中的細節，用好奇心切入
- resonate（共鳴）：找到共同點或共鳴，建立連結感
- tease（調情）：輕鬆俏皮的推拉，製造張力
- humor（幽默）：用幽默或自嘲開場，降低防備
- coldRead（冷讀）：猜測對方的特質，製造驚喜

## 輸出 JSON
{
  "profileAnalysis": {
    "style": "推斷的風格類型",
    "personality": "推斷的性格特質",
    "talkingPoints": ["可聊的話題1", "話題2"]
  },
  "openers": {
    "extend": "開場白內容",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "recommendation": {
    "pick": "推薦的風格",
    "reason": "為什麼推薦這個"
  }
}
```

## 技術架構

### 新增檔案
- `lib/features/opener/presentation/screens/opening_rescue_screen.dart` — 主頁面
- `lib/features/opener/data/services/opener_service.dart` — API 呼叫

### 修改檔案
- `lib/app/main_shell.dart` — 底部選單加第三個選項
- `lib/app/routes.dart` — 加 `/opener` 路由
- `supabase/functions/analyze-chat/index.ts` — 加開場白生成 prompt + 路由

### Edge Function 路由

在現有 `analyze-chat` function 中加入 `mode: "opener"` 判斷：
- `mode: "analyze"` → 現有分析流程
- `mode: "opener"` → 開場白生成流程

共用 CORS、auth、額度檢查邏輯，只換 prompt。

### AI 模型選擇
- 有截圖（Vision）：Sonnet（付費用戶）/ Haiku（Free）
- 純文字/隨機：Haiku（所有用戶，省成本）

### 計費
- 基本生成 = 3 則訊息額度
- 每多 1 張截圖多 2 則額度（1 張 = 5 則，2 張 = 7 則，3 張 = 9 則）
- 複用現有 `countMessages` + 額度檢查邏輯

## 功能分層

| 功能 | Free | Starter | Essential |
|---|---|---|---|
| 開場白生成 | ✅ | ✅ | ✅ |
| 回覆風格 | 延展 only | 全 5 種 | 全 5 種 |
| 截圖自介 | ✅ | ✅ | ✅ |
| AI 模型 | Haiku | Sonnet | Sonnet |

Free 用戶只看到延展風格的開場白，要看其他 4 種需升級。
