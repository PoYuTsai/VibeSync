# 開場救星（Opening Rescue）Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在新增對話選單加入「開場救星」功能，讓用戶上傳交友軟體自介截圖或手動輸入對方資訊，AI 生成 5 種風格的開場白。

**Architecture:** 新增 `OpeningRescueScreen` 頁面 + `OpenerService` API 呼叫。後端在 `analyze-chat` Edge Function 加入 `mode: "opener"` 分流，使用研究報告的照片分析框架作為 AI 知識庫。前端複用現有 ImagePickerWidget 和回覆卡片風格。

**Tech Stack:** Flutter, Riverpod, Supabase Edge Functions, Claude API (Sonnet Vision / Haiku)

**Design Spec:** `docs/plans/2026-04-23-opening-rescue-design.md`

---

### Task 1: Edge Function — 加入 opener 模式 prompt + 路由

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`

**做什麼：**

1. 新增 `OPENER_PROMPT` 常數，包含：
   - 角色：「你是 VibeSync 的開場白生成教練」
   - 照片分析框架（穿搭風格→性格、Big Five映射、擺拍vs自然、背景環境→話題）
   - 5 種風格定義（extend/resonate/tease/humor/coldRead）
   - JSON 輸出格式：`{ profileAnalysis, openers, recommendation }`
   - 台灣在地化提示（繁中、台灣交友軟體常見照片風格）

2. 在主請求處理邏輯中，檢查 `requestBody.mode === "opener"` 分流：
   - 使用 `OPENER_PROMPT` 替代 `SYSTEM_PROMPT`
   - 有圖片時用 Vision（buildVisionContent 複用現有邏輯）
   - 無圖片有文字時用純文字 prompt
   - 都沒有時生成隨機通用開場白
   - 額度扣除：基本 1 則 + 每多一張截圖多 1 則

3. 回應格式保持現有 CORS + JSON 結構

**Commit:** `[feat] Edge Function 加入 opener 模式：開場白生成 prompt + 路由`

---

### Task 2: Flutter — OpenerService API 呼叫

**Files:**
- Create: `lib/features/opener/data/services/opener_service.dart`

**做什麼：**

建立 `OpenerService`，封裝開場白生成的 API 呼叫：

```dart
class OpenerResult {
  final Map<String, dynamic>? profileAnalysis;
  final Map<String, String> openers; // {extend: "...", resonate: "...", ...}
  final String? recommendedPick;
  final String? recommendedReason;
}

class OpenerService {
  Future<OpenerResult> generateOpeners({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
  }) async {
    // 呼叫 Supabase Edge Function: analyze-chat
    // body: { mode: "opener", images?, profileInfo? }
    // 解析回傳 JSON
  }
}
```

- 圖片用 base64 編碼（複用現有 ImageCompressService 的壓縮邏輯）
- 處理錯誤（網路、timeout、額度不足）
- 回傳解析後的 OpenerResult

**Commit:** `[feat] 建立 OpenerService API 呼叫`

---

### Task 3: Flutter — OpeningRescueScreen 頁面

**Files:**
- Create: `lib/features/opener/presentation/screens/opening_rescue_screen.dart`

**做什麼：**

建立主頁面，包含：

1. **AppBar**：返回按鈕 + 標題「開場救星」

2. **輸入區域**：GlassmorphicSegmentedButton 切換兩種模式
   - Tab 1「截圖自介」：ImagePickerWidget（maxImages: 3）
   - Tab 2「手動輸入」：4 個欄位
     - 對方名字（GlassmorphicTextField，選填）
     - Bio / 自我介紹（多行 GlassmorphicTextField，選填）
     - 興趣（GlassmorphicTextField，選填）
     - 認識場景（GlassmorphicSegmentedButton：交友軟體/IG/現實/其他）

3. **生成按鈕**：GradientButton「生成開場白」
   - 顯示額度消耗提示：「將使用 N 則額度」
   - 點擊 → loading → 顯示結果

4. **結果區域**（生成後顯示）：
   - profileAnalysis 卡片（如果有截圖分析）
   - 5 張水平滑動開場白卡片（複用分析頁的卡片風格）
   - 每張：風格標籤 + 內容 + 複製按鈕 + AI 推薦 badge
   - 「重新生成」按鈕
   - Free 用戶只顯示 extend，其他 4 張顯示鎖定 + 升級提示

5. **空狀態提示**：「上傳截圖或輸入資料，效果更好。不提供資料也能生成通用開場白」

使用 GradientBackground 背景，整體風格跟分析頁一致。

**Commit:** `[feat] 建立開場救星頁面 UI`

---

### Task 4: 路由 + 底部選單整合

**Files:**
- Modify: `lib/app/routes.dart` — 加 `/opener` 路由
- Modify: `lib/app/main_shell.dart` — `_NewConversationSheet` 加第三個選項

**做什麼：**

1. routes.dart 加：
```dart
GoRoute(
  path: '/opener',
  builder: (context, state) => const OpeningRescueScreen(),
),
```

2. main_shell.dart 的 `_NewConversationSheet` 加第三個 ListTile：
```dart
ListTile(
  leading: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.bokehYellow.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.auto_awesome, color: AppColors.bokehYellow),
  ),
  title: Text('開場救星', style: TextStyle(color: AppColors.glassTextPrimary)),
  subtitle: Text(
    '交友軟體不知道怎麼開場？AI 幫你生成開場白',
    style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
  ),
  onTap: () {
    Navigator.pop(context);
    context.push('/opener');
  },
),
```

**Commit:** `[feat] 開場救星路由 + 底部選單第三個入口`

---

### Task 5: 額度檢查 + 整合測試

**做什麼：**

1. OpeningRescueScreen 加額度檢查：
   - 生成前檢查剩餘額度 ≥ 所需額度（1 + 截圖數）
   - 額度不足時顯示升級提示

2. 靜態分析：`flutter analyze`

3. 測試 checklist：
   - [ ] 底部選單顯示三個選項
   - [ ] 點「開場救星」進入頁面
   - [ ] 截圖上傳 + 生成開場白
   - [ ] 手動輸入 + 生成開場白
   - [ ] 不提供資料 + 生成通用開場白
   - [ ] Free 用戶只看到延展風格
   - [ ] 額度正確扣除
   - [ ] 複製按鈕正常

**Commit:** `[feat] 開場救星額度檢查 + 整合完成`

---

## 實作順序

| Task | 內容 | 依賴 |
|------|------|------|
| 1 | Edge Function opener prompt | 無 |
| 2 | OpenerService API | Task 1 |
| 3 | OpeningRescueScreen UI | Task 2 |
| 4 | 路由 + 底部選單 | Task 3 |
| 5 | 額度檢查 + 測試 | Task 4 |
