# 截圖上傳功能設計規格

> 版本：1.0
> 日期：2026-03-12
> 狀態：待實作

## 概述

讓用戶上傳聊天截圖，AI 使用 Claude Vision 識別並分析對話內容。此功能作為手動輸入的補充，兩者並存。

## 需求摘要

| 項目 | 決定 |
|------|------|
| 定位 | 補充手動輸入，兩者並存 |
| 數量限制 | 最多 3 張/次 |
| 與文字混合 | 截圖 + 既有對話一起分析 |
| 入口位置 | 獨立按鈕，對話列表上方 |
| 上傳後流程 | 直接分析（不需確認識別內容） |
| 圖片處理 | 前端自動壓縮到 ~1024px 寬 |
| AI 模型 | 統一用 Sonnet (Vision) |
| 來源方式 | 相簿 + 剪貼簿貼上 |
| 順序 | 按上傳順序 + 提示用戶 |
| 失敗處理 | 顯示錯誤，不扣額度 |
| 儲存方式 | 用完即丟，不保留截圖 |
| 計費方案 | **上線前決定**（選項：1截圖=N訊息 / 獨立額度 / 僅付費可用） |

## 整體架構

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter App                          │
├─────────────────────────────────────────────────────────────┤
│  AnalysisScreen                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [📷 上傳截圖]              [🔍 開始分析]             │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ 💡 請按對話時間順序上傳，先傳較早的                    │   │
│  │ ┌──────┐ ┌──────┐ ┌──────┐                         │   │
│  │ │ img1 │ │ img2 │ │  +   │  ← ImagePickerWidget    │   │
│  │ └──────┘ └──────┘ └──────┘                         │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ [她說 | 我說]  ← 現有輸入區（不變）                    │   │
│  │ ┌─────────────────────────────────────────────────┐ │   │
│  │ │ 輸入訊息...                                     │ │   │
│  │ └─────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Edge Function (analyze-chat)             │
├─────────────────────────────────────────────────────────────┤
│  1. 接收 messages[] + images[] (base64)                     │
│  2. 組合成 Claude Vision API 格式                            │
│  3. 呼叫 Sonnet (Vision)                                    │
│  4. 解析結果 + 護欄檢查                                      │
│  5. 回傳分析結果                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Claude Vision API                        │
│  model: claude-sonnet-4-20250514                            │
│  content: [image, image, image, text]                       │
└─────────────────────────────────────────────────────────────┘
```

## 技術方案

採用 **Base64 直傳** 方案：

- 前端壓縮圖片 → Base64 編碼 → JSON payload 傳給 Edge Function → Claude Vision API
- 優點：架構簡單、隱私最佳、不需額外儲存
- Payload 估算：3 張截圖約 1-2 MB，遠低於 6MB 限制

## 前端設計

### 新增元件

```dart
// lib/shared/widgets/image_picker_widget.dart
class ImagePickerWidget extends StatefulWidget {
  final int maxImages;           // 最多 3 張
  final Function(List<Uint8List>) onImagesChanged;

  // 功能：
  // - 顯示已選圖片縮圖
  // - 點擊「+」從相簿選圖 / 剪貼簿貼上
  // - 點擊縮圖可刪除
  // - 自動壓縮到 1024px 寬
}
```

### 修改檔案

| 檔案 | 修改內容 |
|------|----------|
| `analysis_screen.dart` | 新增 ImagePickerWidget、images state、修改 _runAnalysis() |
| `analysis_service.dart` | 新增 images 參數，轉 base64 |
| `analysis_models.dart` | 新增 `recognizedConversation` 欄位 |

### 圖片壓縮邏輯

```dart
// 使用 flutter_image_compress 套件
Future<Uint8List> compressImage(Uint8List imageBytes) async {
  // 1. 解碼取得尺寸
  // 2. 若寬度 > 1024，縮放到 1024
  // 3. 壓縮品質 85%
  // 4. 輸出 JPEG
}
```

### 剪貼簿支援（Web）

```dart
// 監聽 Ctrl+V
RawKeyboardListener(
  onKey: (event) {
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteFromClipboard();
    }
  },
)
```

## API 設計

### 請求格式

```json
{
  "messages": [
    { "isFromMe": false, "content": "你週末有空嗎？" },
    { "isFromMe": true, "content": "要看是什麼事" }
  ],
  "images": [
    {
      "data": "base64_encoded_image_data...",
      "mediaType": "image/jpeg",
      "order": 1
    },
    {
      "data": "base64_encoded_image_data...",
      "mediaType": "image/jpeg",
      "order": 2
    }
  ],
  "sessionContext": { ... },
  "analyzeMode": "normal"
}
```

### 回應格式

```json
{
  "enthusiasm": { "score": 75, "level": "hot" },
  "gameStage": { ... },
  "recognizedConversation": {
    "messageCount": 8,
    "summary": "從截圖識別到 8 則對話",
    "messages": [
      { "isFromMe": false, "content": "嗨～在幹嘛" },
      { "isFromMe": true, "content": "剛下班" }
    ]
  },
  "replies": { ... },
  "usage": {
    "messagesUsed": 2,
    "imagesUsed": 2,
    "model": "claude-sonnet-4-20250514"
  }
}
```

## Edge Function 修改

### 圖片處理函數

```typescript
function buildVisionContent(
  messages: Message[],
  images: ImageData[]
): ClaudeContent[] {
  const content: ClaudeContent[] = [];

  // 先加入截圖（按 order 排序）
  for (const img of images.sort((a, b) => a.order - b.order)) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: img.mediaType,
        data: img.data
      }
    });
  }

  // 再加入文字訊息
  content.push({
    type: "text",
    text: formatMessagesForPrompt(messages)
  });

  return content;
}
```

### 模型選擇邏輯

```typescript
function selectModel(messages, images, tier) {
  // 有圖片 → 強制 Sonnet
  if (images && images.length > 0) {
    return "claude-sonnet-4-20250514";
  }

  // 無圖片 → 維持現有 70/30 邏輯
  return existingModelSelection(messages, tier);
}
```

### 識別失敗處理

```typescript
if (result.recognizedConversation?.messageCount === 0) {
  return jsonResponse({
    error: "RECOGNITION_FAILED",
    message: "無法識別截圖中的對話內容，請確保截圖清晰且為聊天畫面",
    shouldChargeQuota: false
  }, 400);
}
```

## System Prompt 更新

### 新增截圖識別指引

```
## 截圖識別規則

當收到聊天截圖時：

1. **識別對話內容**
   - 讀取截圖中的所有訊息
   - 根據氣泡位置判斷「她說」（左/白）vs「我說」（右/藍或綠）
   - 保留表情符號、貼圖描述
   - 若有時間戳，注意對話間隔

2. **處理多張截圖**
   - 截圖按時間順序排列（第一張最早）
   - 合併所有截圖中的對話
   - 自動去除重複訊息

3. **與文字訊息整合**
   - 截圖內容視為較早的對話
   - 用戶手動輸入的文字視為較新的對話
   - 整體分析時考慮完整脈絡

4. **輸出識別結果**
   - 在 recognizedConversation 欄位回報識別到的對話
   - 包含 messageCount 和 messages 陣列

5. **識別失敗處理**
   - 若截圖模糊、非聊天畫面、無法判斷誰說的
   - 設 recognizedConversation.messageCount = 0
   - 不要猜測或編造內容
```

## 錯誤處理

### 前端錯誤

| 錯誤情境 | 處理方式 | 用戶提示 |
|----------|----------|----------|
| 圖片太大（壓縮後仍 > 500KB） | 阻止上傳 | 「圖片太大，請選擇較小的截圖」 |
| 圖片格式不支援 | 阻止上傳 | 「僅支援 JPG、PNG 格式」 |
| 超過 3 張 | 阻止新增 | 「最多上傳 3 張截圖」 |
| 網路錯誤 | 顯示錯誤 | 「網路連線失敗，請稍後再試」 |

### 後端錯誤

| 錯誤情境 | HTTP Code | 扣額度 | 回應 |
|----------|-----------|--------|------|
| 圖片 base64 無效 | 400 | ❌ | `INVALID_IMAGE` |
| 截圖識別失敗 | 400 | ❌ | `RECOGNITION_FAILED` |
| Claude API 錯誤 | 500 | ❌ | `AI_ERROR` |
| 分析成功 | 200 | ✅ | 正常結果 |

### Fallback 策略

```
截圖分析 (Sonnet) 失敗
    │
    ├─ 429/5xx → 重試 2 次
    │
    └─ 仍失敗 → 回傳錯誤，不扣額度
                （不降級到 Haiku，因為需要 Vision）
```

## 成本估算

| 項目 | Token 數 | Sonnet 成本 |
|------|----------|-------------|
| 1 張壓縮後截圖 | ~1,500-2,000 | ~$0.005-0.006 |
| 3 張截圖 | ~5,000-6,000 | ~$0.015-0.018 |
| 文字 System Prompt | ~2,000 | ~$0.006 |
| 輸出 | ~800 | ~$0.012 |
| **單次 3 張截圖分析** | **~8,000** | **~$0.03-0.04** |

## 上線前待決定

- [ ] **計費方案選擇**
  - A) 1 截圖 = N 訊息額度（建議 N=2 或 3）
  - B) 截圖獨立額度
  - C) 僅付費用戶可用
- [ ] **定價最終 Review** - 根據所有功能成本重新審視定價

## 相關檔案

| 功能 | 檔案路徑 |
|------|---------|
| Edge Function | `supabase/functions/analyze-chat/index.ts` |
| 前端 Service | `lib/features/analysis/data/services/analysis_service.dart` |
| 數據模型 | `lib/features/analysis/domain/entities/analysis_models.dart` |
| UI 頁面 | `lib/features/analysis/presentation/screens/analysis_screen.dart` |
| 新增元件 | `lib/shared/widgets/image_picker_widget.dart` |
