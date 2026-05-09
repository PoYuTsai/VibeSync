# 開場救星（Opening Rescue）設計規格

> **Superseded note（2026-05-09）**：本文件保留作為 feature 起源紀錄；AI prompt 與照片判讀規則已由 `2a59d96` 之後的 `OPENER_PROMPT` 取代。現行原則是「可見線索 → 可回覆開場」，不再使用 Big Five、穿搭推人格或深層人格診斷。若要改 prompt，請以 `supabase/functions/analyze-chat/index.ts` 的 `OPENER_PROMPT` 為準。
>
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
       └── 不提供資料 → 標示線索不足，生成低風險開場
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
- 都沒填 → 明確標示可見線索不足，生成低風險、不油、不假裝洞察的開場白

**結果區域：**
- 5 張水平滑動卡片（複用 _buildHorizontalReplyCard 風格）
- 每張：風格標籤 + 開場白內容 + 複製按鈕
- 第一張有「AI 推薦」badge
- 底部「重新生成」按鈕

## AI Prompt 設計（Superseded）

舊版曾考慮「穿搭風格 → 性格推斷」與 Big Five 照片映射；這些規則已停用，避免模型做過度人格臆測。

現行知識框架：
1. **可見線索優先**：只使用 bio、照片背景、物件、活動、地點、文字、用戶明確提供的資訊。
2. **開場白北極星**：低壓、具體、可回、像真人，讓對方覺得「你真的有看我的資料」。
3. **場景分流**：交友軟體 / IG 限動 / 現實認識 / 朋友介紹 / 資訊不足，語氣要不同。
4. **互動切入判斷**：`profileAnalysis.personality` 欄位保留相容性，但內容應寫成「適合怎麼切入」，不是人格診斷。
5. **資訊不足要明講**：不編造共同點、不假裝洞察，只給低風險開場。

### 現行 Prompt 方向

```
你是 VibeSync 的開場救星教練。

根據用戶提供的對方資訊，生成 5 種不同風格的開場白。

## 可見線索優先
只使用截圖、bio、照片背景、文字描述或用戶提供的明確資訊。
不要假裝看出很深的人格，不要做 Big Five、長期性格或身材價值判斷。

## 5 種開場白風格
- extend（延展）：抓可見細節，延伸成好回的問題
- resonate（共鳴）：真的有共同點或共同感受才用
- tease（調情）：輕微推拉、俏皮但不冒犯
- humor（幽默）：輕自嘲或場景幽默，不表演段子
- coldRead（冷讀）：只能做可被推翻的互動風格猜測

## 輸出 JSON
{
  "profileAnalysis": {
    "style": "可見風格 / 氛圍",
    "personality": "互動切入判斷，不是人格診斷",
    "talkingPoints": ["具體可聊線索1", "線索2"]
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
