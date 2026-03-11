# 截圖上傳功能實作計畫

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓用戶上傳聊天截圖，AI 使用 Claude Vision 識別並分析對話內容

**Architecture:** 前端新增 ImagePickerWidget 處理圖片選擇/壓縮/預覽，透過 base64 傳給 Edge Function，Edge Function 組合成 Claude Vision API 格式呼叫 Sonnet

**Tech Stack:** Flutter (image_picker, flutter_image_compress, pasteboard), Supabase Edge Function, Claude Vision API

**Spec:** `docs/plans/2026-03-12-screenshot-upload-design.md`

---

## 檔案結構

| 操作 | 檔案 | 說明 |
|------|------|------|
| Create | `lib/shared/widgets/image_picker_widget.dart` | 圖片選擇/壓縮/預覽元件 |
| Create | `lib/shared/services/image_compress_service.dart` | 圖片壓縮服務 |
| Modify | `lib/features/analysis/domain/entities/analysis_models.dart` | 新增 RecognizedConversation |
| Modify | `lib/features/analysis/data/services/analysis_service.dart` | 新增 images 參數 |
| Modify | `lib/features/analysis/presentation/screens/analysis_screen.dart` | 整合截圖上傳 UI |
| Modify | `supabase/functions/analyze-chat/index.ts` | 新增圖片處理 + Vision API |

---

## Chunk 1: 前端基礎建設

### Task 1: 新增依賴套件

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 新增圖片相關套件**

```yaml
# 在 dependencies: 區塊新增
dependencies:
  # ... 現有依賴
  image_picker: ^1.0.7
  flutter_image_compress: ^2.1.0
  pasteboard: ^0.2.0
```

- [ ] **Step 2: 執行 flutter pub get**

Run: `flutter pub get`
Expected: 套件安裝成功

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: 新增圖片處理相關套件"
git push
```

---

### Task 2: 建立圖片壓縮服務

**Files:**
- Create: `lib/shared/services/image_compress_service.dart`

- [ ] **Step 1: 建立 ImageCompressService**

```dart
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

class ImageCompressService {
  static const int maxWidth = 1024;
  static const int quality = 85;
  static const int maxSizeBytes = 500 * 1024; // 500KB

  /// 壓縮圖片到適合上傳的大小
  /// 返回壓縮後的 JPEG bytes，或 null 如果壓縮失敗
  static Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    try {
      // 解碼圖片取得尺寸
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // 計算目標尺寸
      int targetWidth = image.width;
      int targetHeight = image.height;

      if (image.width > maxWidth) {
        targetWidth = maxWidth;
        targetHeight = (image.height * maxWidth / image.width).round();
      }

      // 壓縮
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      // 檢查大小
      if (result.length > maxSizeBytes) {
        // 再次壓縮，降低品質
        return await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: 60,
          format: CompressFormat.jpeg,
        );
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  /// 檢查圖片格式是否支援
  static bool isSupportedFormat(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png';
  }

  /// 將 bytes 轉成 base64
  static String toBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}
```

- [ ] **Step 2: 新增 import**

在檔案頂部確認有：
```dart
import 'dart:convert';
```

- [ ] **Step 3: Commit**

```bash
git add lib/shared/services/image_compress_service.dart
git commit -m "feat: 新增圖片壓縮服務"
git push
```

---

### Task 3: 建立 ImagePickerWidget

**Files:**
- Create: `lib/shared/widgets/image_picker_widget.dart`

- [ ] **Step 1: 建立 Widget 結構**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import '../services/image_compress_service.dart';
import '../../core/theme/app_colors.dart';
import 'glassmorphic_container.dart';

class ImagePickerWidget extends StatefulWidget {
  final int maxImages;
  final Function(List<Uint8List>) onImagesChanged;

  const ImagePickerWidget({
    super.key,
    this.maxImages = 3,
    required this.onImagesChanged,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final List<Uint8List> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  Future<void> _pickImage() async {
    if (_images.length >= widget.maxImages) {
      _showError('最多上傳 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      await _processImage(await file.readAsBytes(), file.mimeType);
    } catch (e) {
      _showError('選取圖片失敗');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_images.length >= widget.maxImages) {
      _showError('最多上傳 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null) {
        _showError('剪貼簿中沒有圖片');
        return;
      }
      await _processImage(imageBytes, 'image/png');
    } catch (e) {
      _showError('貼上圖片失敗');
    }
  }

  Future<void> _processImage(Uint8List bytes, String? mimeType) async {
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('僅支援 JPG、PNG 格式');
      return;
    }

    setState(() => _isProcessing = true);

    final compressed = await ImageCompressService.compressImage(bytes);

    setState(() => _isProcessing = false);

    if (compressed == null) {
      _showError('圖片處理失敗');
      return;
    }

    if (compressed.length > 500 * 1024) {
      _showError('圖片太大，請選擇較小的截圖');
      return;
    }

    setState(() {
      _images.add(compressed);
    });
    widget.onImagesChanged(_images);
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
    widget.onImagesChanged(_images);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 提示文字
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '💡 請按對話時間順序上傳，先傳較早的',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warmTextSecondary,
              ),
            ),
          ),

        // 圖片預覽區
        SizedBox(
          height: 80,
          child: Row(
            children: [
              // 已選圖片
              ..._images.asMap().entries.map((entry) => _buildImageThumbnail(
                    entry.value,
                    entry.key,
                  )),

              // 新增按鈕
              if (_images.length < widget.maxImages) _buildAddButton(),

              // 處理中指示器
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageThumbnail(Uint8List imageBytes, int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          GlassmorphicContainer(
            width: 70,
            height: 70,
            borderRadius: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                width: 70,
                height: 70,
              ),
            ),
          ),
          // 刪除按鈕
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // 順序標籤
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _pickImage,
      onLongPress: _pasteFromClipboard,
      child: GlassmorphicContainer(
        width: 70,
        height: 70,
        borderRadius: 12,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.warmTextSecondary,
              size: 28,
            ),
            const SizedBox(height: 2),
            Text(
              '截圖',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.warmTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/shared/widgets/image_picker_widget.dart
git commit -m "feat: 新增 ImagePickerWidget 元件"
git push
```

---

### Task 4: 匯出新元件

**Files:**
- Modify: `lib/shared/widgets/warm_theme_widgets.dart`

- [ ] **Step 1: 新增 export**

在檔案中新增：
```dart
export 'image_picker_widget.dart';
```

- [ ] **Step 2: Commit**

```bash
git add lib/shared/widgets/warm_theme_widgets.dart
git commit -m "chore: 匯出 ImagePickerWidget"
git push
```

---

## Chunk 2: 資料模型與服務層

### Task 5: 更新 AnalysisModels

**Files:**
- Modify: `lib/features/analysis/domain/entities/analysis_models.dart`

- [ ] **Step 1: 新增 RecognizedConversation 類別**

在檔案中新增：
```dart
class RecognizedConversation {
  final int messageCount;
  final String summary;
  final List<RecognizedMessage>? messages;

  RecognizedConversation({
    required this.messageCount,
    required this.summary,
    this.messages,
  });

  factory RecognizedConversation.fromJson(Map<String, dynamic> json) {
    return RecognizedConversation(
      messageCount: json['messageCount'] ?? 0,
      summary: json['summary'] ?? '',
      messages: json['messages'] != null
          ? (json['messages'] as List)
              .map((m) => RecognizedMessage.fromJson(m))
              .toList()
          : null,
    );
  }
}

class RecognizedMessage {
  final bool isFromMe;
  final String content;

  RecognizedMessage({
    required this.isFromMe,
    required this.content,
  });

  factory RecognizedMessage.fromJson(Map<String, dynamic> json) {
    return RecognizedMessage(
      isFromMe: json['isFromMe'] ?? false,
      content: json['content'] ?? '',
    );
  }
}
```

- [ ] **Step 2: 更新 AnalysisResult 類別**

在 AnalysisResult 類別中新增欄位：
```dart
class AnalysisResult {
  // ... 現有欄位
  final RecognizedConversation? recognizedConversation;
  final int? imagesUsed;

  // 更新 constructor 和 fromJson
}
```

- [ ] **Step 3: 更新 fromJson**

```dart
factory AnalysisResult.fromJson(Map<String, dynamic> json) {
  return AnalysisResult(
    // ... 現有欄位
    recognizedConversation: json['recognizedConversation'] != null
        ? RecognizedConversation.fromJson(json['recognizedConversation'])
        : null,
    imagesUsed: json['usage']?['imagesUsed'],
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/analysis/domain/entities/analysis_models.dart
git commit -m "feat: 新增 RecognizedConversation 模型"
git push
```

---

### Task 6: 更新 AnalysisService

**Files:**
- Modify: `lib/features/analysis/data/services/analysis_service.dart`

- [ ] **Step 1: 新增 ImageData 類別**

在檔案頂部新增：
```dart
class ImageData {
  final String data; // base64
  final String mediaType;
  final int order;

  ImageData({
    required this.data,
    required this.mediaType,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'data': data,
        'mediaType': mediaType,
        'order': order,
      };
}
```

- [ ] **Step 2: 更新 analyzeConversation 方法簽名**

```dart
static Future<AnalysisResult> analyzeConversation({
  required List<Message> messages,
  List<Uint8List>? images, // 新增
  SessionContext? sessionContext,
  String? userDraft,
  String analyzeMode = 'normal',
}) async {
```

- [ ] **Step 3: 處理圖片轉換**

在方法內部新增：
```dart
// 處理圖片
List<ImageData>? imageDataList;
if (images != null && images.isNotEmpty) {
  imageDataList = images.asMap().entries.map((entry) {
    return ImageData(
      data: base64Encode(entry.value),
      mediaType: 'image/jpeg',
      order: entry.key + 1,
    );
  }).toList();
}
```

- [ ] **Step 4: 更新 API payload**

```dart
final body = {
  'messages': messages.map((m) => m.toJson()).toList(),
  if (imageDataList != null) 'images': imageDataList.map((i) => i.toJson()).toList(),
  if (sessionContext != null) 'sessionContext': sessionContext.toJson(),
  if (userDraft != null) 'userDraft': userDraft,
  'analyzeMode': analyzeMode,
};
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/analysis/data/services/analysis_service.dart
git commit -m "feat: AnalysisService 支援圖片上傳"
git push
```

---

## Chunk 3: UI 整合

### Task 7: 更新 AnalysisScreen

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`

- [ ] **Step 1: 新增 state 變數**

在 State 類別中新增：
```dart
List<Uint8List> _selectedImages = [];
```

- [ ] **Step 2: 新增 ImagePickerWidget**

在 UI 中「開始分析」按鈕上方新增：
```dart
// 截圖上傳區
if (_messages.isEmpty || !_hasAnalyzed)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: ImagePickerWidget(
      maxImages: 3,
      onImagesChanged: (images) {
        setState(() {
          _selectedImages = images;
        });
      },
    ),
  ),
```

- [ ] **Step 3: 更新分析按鈕文字**

```dart
// 根據是否有圖片調整按鈕文字
Text(
  _selectedImages.isNotEmpty
      ? '分析截圖 (${_selectedImages.length}張)'
      : '開始分析',
)
```

- [ ] **Step 4: 更新 _runAnalysis 呼叫**

```dart
final result = await AnalysisService.analyzeConversation(
  messages: _messages,
  images: _selectedImages.isNotEmpty ? _selectedImages : null,
  sessionContext: _sessionContext,
  analyzeMode: 'normal',
);
```

- [ ] **Step 5: 分析完成後清除圖片**

```dart
// 分析成功後
setState(() {
  _selectedImages = [];
  // ... 其他狀態更新
});
```

- [ ] **Step 6: 顯示識別結果**

在結果區新增：
```dart
if (_analysisResult?.recognizedConversation != null)
  _buildRecognizedConversationCard(),
```

```dart
Widget _buildRecognizedConversationCard() {
  final recognized = _analysisResult!.recognizedConversation!;
  return GlassmorphicContainer(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library, size: 18),
            const SizedBox(width: 8),
            Text(
              recognized.summary,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (recognized.messages != null && recognized.messages!.isNotEmpty)
          ExpansionTile(
            title: const Text('查看識別內容'),
            children: recognized.messages!.map((m) => ListTile(
              leading: Icon(m.isFromMe ? Icons.person : Icons.person_outline),
              title: Text(m.content),
              dense: true,
            )).toList(),
          ),
      ],
    ),
  );
}
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/analysis/presentation/screens/analysis_screen.dart
git commit -m "feat: AnalysisScreen 整合截圖上傳功能"
git push
```

---

## Chunk 4: Edge Function 更新

### Task 8: 更新 Edge Function - 圖片處理

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`

- [ ] **Step 1: 新增 ImageData 型別**

在檔案頂部新增：
```typescript
interface ImageData {
  data: string; // base64
  mediaType: string;
  order: number;
}
```

- [ ] **Step 2: 新增 buildVisionContent 函數**

```typescript
function buildVisionContent(
  messages: Message[],
  images: ImageData[]
): any[] {
  const content: any[] = [];

  // 先加入截圖（按 order 排序）
  const sortedImages = [...images].sort((a, b) => a.order - b.order);
  for (const img of sortedImages) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: img.mediaType,
        data: img.data,
      },
    });
  }

  // 再加入文字訊息
  content.push({
    type: "text",
    text: formatMessagesForPrompt(messages),
  });

  return content;
}
```

- [ ] **Step 3: 更新模型選擇邏輯**

```typescript
function selectModel(
  messages: Message[],
  images: ImageData[] | undefined,
  tier: string
): string {
  // 有圖片 → 強制 Sonnet（Vision 需要）
  if (images && images.length > 0) {
    return "claude-sonnet-4-20250514";
  }

  // 無圖片 → 維持現有邏輯
  return existingSelectModel(messages, tier);
}
```

- [ ] **Step 4: 更新請求處理**

在主處理邏輯中：
```typescript
const { messages, images, sessionContext, userDraft, analyzeMode } = await req.json();

// 驗證圖片
if (images && images.length > 3) {
  return jsonResponse({ error: "TOO_MANY_IMAGES", message: "最多上傳 3 張截圖" }, 400);
}

// 選擇模型
const model = selectModel(messages, images, tier);

// 組建請求
const hasImages = images && images.length > 0;
const userContent = hasImages
  ? buildVisionContent(messages, images)
  : formatMessagesForPrompt(messages);

const request = {
  model,
  max_tokens: hasImages ? 1500 : 1024,
  system: hasImages ? SYSTEM_PROMPT_WITH_VISION : SYSTEM_PROMPT,
  messages: [{ role: "user", content: userContent }],
};
```

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "feat: Edge Function 支援圖片處理"
git push
```

---

### Task 9: 更新 System Prompt

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`

- [ ] **Step 1: 新增 VISION_INSTRUCTION**

```typescript
const VISION_INSTRUCTION = `
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
   - messageCount: 識別到的訊息數量
   - summary: "從截圖識別到 N 則對話"
   - messages: 識別到的對話陣列

5. **識別失敗處理**
   - 若截圖模糊、非聊天畫面、無法判斷誰說的
   - 設 recognizedConversation.messageCount = 0
   - 不要猜測或編造內容

`;

const SYSTEM_PROMPT_WITH_VISION = VISION_INSTRUCTION + SYSTEM_PROMPT;
```

- [ ] **Step 2: 更新 JSON 輸出格式**

在現有 OUTPUT_FORMAT 中新增：
```typescript
// 在 JSON 結構中新增
"recognizedConversation": {
  "messageCount": 8,
  "summary": "從截圖識別到 8 則對話",
  "messages": [
    { "isFromMe": false, "content": "訊息內容" }
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "feat: 新增截圖識別 System Prompt"
git push
```

---

### Task 10: 更新錯誤處理與額度邏輯

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`

- [ ] **Step 1: 新增識別失敗檢查**

```typescript
// 解析 AI 回應後
const result = JSON.parse(aiResponse);

// 檢查識別是否失敗
if (hasImages && (!result.recognizedConversation || result.recognizedConversation.messageCount === 0)) {
  return jsonResponse({
    error: "RECOGNITION_FAILED",
    message: "無法識別截圖中的對話內容，請確保截圖清晰且為聊天畫面",
    shouldChargeQuota: false,
  }, 400);
}
```

- [ ] **Step 2: 更新 usage 回應**

```typescript
// 在回應中新增 imagesUsed
const usage = {
  messagesUsed: messageCount,
  imagesUsed: images?.length || 0,
  model,
  // ... 其他欄位
};
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "feat: 新增截圖識別失敗處理"
git push
```

---

## Chunk 5: 測試與文件

### Task 11: 本地測試

- [ ] **Step 1: 啟動本地開發**

Run: `flutter run -d chrome`

- [ ] **Step 2: 測試截圖上傳 UI**

1. 進入對話頁面
2. 點擊「截圖」按鈕
3. 選擇圖片
4. 確認縮圖顯示
5. 確認可刪除
6. 確認最多 3 張限制

- [ ] **Step 3: 測試分析功能**

1. 上傳 1 張聊天截圖
2. 點擊「分析截圖」
3. 確認返回結果包含 recognizedConversation
4. 確認識別結果可展開查看

- [ ] **Step 4: 測試錯誤處理**

1. 上傳非聊天截圖（風景照）
2. 確認顯示識別失敗錯誤
3. 確認不扣額度

---

### Task 12: 更新 CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: 更新已完成功能**

```markdown
| **截圖上傳功能** | ✅ 完成 | 最多 3 張，Claude Vision 識別分析 |
```

- [ ] **Step 2: 移除待實作項目**

將「截圖上傳功能」從「待實作」移到「已完成」

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: 更新截圖上傳功能完成狀態"
git push
```

---

## 總結

| Chunk | Tasks | 預估 |
|-------|-------|------|
| 1. 前端基礎建設 | 1-4 | 套件、壓縮服務、元件 |
| 2. 資料模型與服務層 | 5-6 | Models、Service |
| 3. UI 整合 | 7 | AnalysisScreen |
| 4. Edge Function | 8-10 | 圖片處理、Prompt、錯誤 |
| 5. 測試與文件 | 11-12 | 測試、CLAUDE.md |

**總計：12 Tasks**
