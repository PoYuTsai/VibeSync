# VibeSync MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Flutter-based chat analysis app that provides enthusiasm scoring and reply suggestions using Claude API.

**Architecture:** Clean Architecture with feature-based modules. Local-first data storage with Hive, cloud auth via Supabase, AI processing through Edge Functions calling Claude API.

**Tech Stack:** Flutter 3.x, Riverpod, Hive, Supabase, Claude API, RevenueCat

---

## Phase 1: Project Foundation

### Task 1.1: Create Flutter Project

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `analysis_options.yaml`

**Step 1: Create Flutter project**

Run:
```bash
flutter create --org com.vibesync --project-name vibesync .
```

Expected: Flutter project scaffolded with default files

**Step 2: Verify project creation**

Run:
```bash
flutter doctor && flutter pub get
```

Expected: No critical issues, dependencies resolved

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: 建立 Flutter 專案基礎架構"
```

---

### Task 1.2: Configure Dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Update pubspec.yaml with all dependencies**

```yaml
name: vibesync
description: 社交溝通技巧教練 App
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.4.9
  riverpod_annotation: ^2.3.3

  # Routing
  go_router: ^13.0.0

  # Local Storage
  hive: ^2.2.3
  hive_flutter: ^1.1.0

  # Backend
  supabase_flutter: ^2.3.0

  # Subscription
  purchases_flutter: ^6.17.0

  # Utils
  uuid: ^4.2.1
  intl: ^0.18.1
  flutter_secure_storage: ^9.0.0

  # UI
  flutter_svg: ^2.0.9
  shimmer: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  build_runner: ^2.4.7
  hive_generator: ^2.0.1
  riverpod_generator: ^2.3.9

flutter:
  uses-material-design: true
```

**Step 2: Install dependencies**

Run:
```bash
flutter pub get
```

Expected: All packages resolved successfully

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: 新增專案依賴 (Riverpod, Hive, Supabase, RevenueCat)"
```

---

### Task 1.3: Setup Project Structure

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/routes.dart`
- Create: `lib/core/constants/app_constants.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/core/theme/app_colors.dart`
- Create: `lib/core/theme/app_typography.dart`
- Modify: `lib/main.dart`

**Step 1: Create directory structure**

Run:
```bash
mkdir -p lib/app lib/core/{constants,theme,utils,extensions} lib/features/{auth,conversation,analysis,subscription}/{data,domain,presentation} lib/shared/widgets
```

Expected: Directory structure created

**Step 2: Create app_colors.dart**

```dart
// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary - Deep Purple
  static const primary = Color(0xFF6B4EE6);
  static const primaryLight = Color(0xFF9D8DF7);
  static const primaryDark = Color(0xFF4527A0);

  // Enthusiasm Levels
  static const cold = Color(0xFF64B5F6);
  static const warm = Color(0xFFFFD54F);
  static const hot = Color(0xFFFF8A65);
  static const veryHot = Color(0xFFFF6B9D);

  // Neutral (Dark Mode)
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceVariant = Color(0xFF2D2D2D);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const divider = Color(0xFF3D3D3D);

  // Semantic
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE57373);
  static const warning = Color(0xFFFFB74D);
}
```

**Step 3: Create app_typography.dart**

```dart
// lib/core/theme/app_typography.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static const headlineLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const headlineMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
```

**Step 4: Create app_theme.dart**

```dart
// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.primaryLight,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}
```

**Step 5: Create app_constants.dart**

```dart
// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const appName = 'VibeSync';
  static const appVersion = '1.0.0';

  // Enthusiasm Levels
  static const coldMax = 30;
  static const warmMax = 60;
  static const hotMax = 80;
  // veryHot: 81-100

  // Golden Rule
  static const goldenRuleMultiplier = 1.8;

  // Subscription Tiers (訊息制)
  static const freeMonthlyLimit = 30;
  static const starterMonthlyLimit = 300;
  static const essentialMonthlyLimit = 1000;

  // Daily Limits (每日上限)
  static const freeDailyLimit = 15;
  static const starterDailyLimit = 50;
  static const essentialDailyLimit = 150;

  // Conversation Limits (對話數量)
  static const freeConversationLimit = 3;
  static const starterConversationLimit = 15;
  static const essentialConversationLimit = 50;

  // Memory Limits (對話記憶輪數)
  static const freeMemoryRounds = 5;
  static const paidMemoryRounds = 15;

  // Message Calculation (訊息計算)
  static const maxCharsPerMessage = 200;  // 單則上限 200 字
  static const maxTotalChars = 5000;       // 單次分析上限 5000 字

  // Local Storage
  static const conversationsBox = 'conversations';
  static const settingsBox = 'settings';
  static const usageBox = 'usage';
}
```

**Step 6: Create routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('VibeSync')),
      ),
    ),
  ],
);
```

**Step 7: Create app.dart**

```dart
// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'routes.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'VibeSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
```

**Step 8: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 9: Verify app runs**

Run:
```bash
flutter run -d chrome
```

Expected: App launches showing "VibeSync" text in dark mode

**Step 10: Commit**

```bash
git add lib/
git commit -m "feat: 建立 Clean Architecture 專案結構與主題系統"
```

---

## Phase 2: Local Data Layer (Hive)

### Task 2.1: Create Domain Entities

**Files:**
- Create: `lib/features/conversation/domain/entities/message.dart`
- Create: `lib/features/conversation/domain/entities/conversation.dart`
- Create: `lib/features/analysis/domain/entities/enthusiasm_level.dart`

**Step 1: Create enthusiasm_level.dart**

```dart
// lib/features/analysis/domain/entities/enthusiasm_level.dart
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum EnthusiasmLevel {
  cold,
  warm,
  hot,
  veryHot;

  static EnthusiasmLevel fromScore(int score) {
    if (score <= AppConstants.coldMax) return cold;
    if (score <= AppConstants.warmMax) return warm;
    if (score <= AppConstants.hotMax) return hot;
    return veryHot;
  }

  String get label {
    switch (this) {
      case cold:
        return '冰點';
      case warm:
        return '溫和';
      case hot:
        return '熱情';
      case veryHot:
        return '高熱';
    }
  }

  String get emoji {
    switch (this) {
      case cold:
        return '❄️';
      case warm:
        return '🌤️';
      case hot:
        return '🔥';
      case veryHot:
        return '💖';
    }
  }

  Color get color {
    switch (this) {
      case cold:
        return AppColors.cold;
      case warm:
        return AppColors.warm;
      case hot:
        return AppColors.hot;
      case veryHot:
        return AppColors.veryHot;
    }
  }
}
```

**Step 2: Create message.dart**

```dart
// lib/features/conversation/domain/entities/message.dart
import 'package:hive/hive.dart';

part 'message.g.dart';

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final bool isFromMe;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  int? enthusiasmScore;

  Message({
    required this.id,
    required this.content,
    required this.isFromMe,
    required this.timestamp,
    this.enthusiasmScore,
  });

  int get wordCount => content.length;
}
```

**Step 3: Create conversation.dart**

```dart
// lib/features/conversation/domain/entities/conversation.dart
import 'package:hive/hive.dart';
import 'message.dart';

part 'conversation.g.dart';

@HiveType(typeId: 0)
class Conversation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  @HiveField(3)
  List<Message> messages;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  @HiveField(6)
  int? lastEnthusiasmScore;

  Conversation({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.lastEnthusiasmScore,
  });

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  List<Message> get theirMessages => messages.where((m) => !m.isFromMe).toList();
}
```

**Step 4: Generate Hive adapters**

Run:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Expected: Generated `message.g.dart` and `conversation.g.dart`

**Step 5: Commit**

```bash
git add lib/features/
git commit -m "feat: 建立 Message 和 Conversation 實體 (含 Hive 配置)"
```

---

### Task 2.2: Setup Hive Initialization

**Files:**
- Create: `lib/core/services/storage_service.dart`
- Modify: `lib/main.dart`

**Step 1: Create storage_service.dart**

```dart
// lib/core/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/conversation/domain/entities/conversation.dart';
import '../../features/conversation/domain/entities/message.dart';
import '../constants/app_constants.dart';

class StorageService {
  static const _encryptionKeyName = 'vibesync_encryption_key';
  static final _secureStorage = FlutterSecureStorage();

  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(ConversationAdapter());
    Hive.registerAdapter(MessageAdapter());

    // Get or create encryption key
    final encryptionKey = await _getEncryptionKey();

    // Open encrypted boxes
    await Hive.openBox<Conversation>(
      AppConstants.conversationsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox(
      AppConstants.settingsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<List<int>> _getEncryptionKey() async {
    final existingKey = await _secureStorage.read(key: _encryptionKeyName);

    if (existingKey != null) {
      return existingKey.codeUnits;
    }

    final newKey = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _encryptionKeyName,
      value: String.fromCharCodes(newKey),
    );
    return newKey;
  }

  static Box<Conversation> get conversationsBox =>
      Hive.box<Conversation>(AppConstants.conversationsBox);

  static Box get settingsBox => Hive.box(AppConstants.settingsBox);
}
```

**Step 2: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage
  await StorageService.initialize();

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 3: Verify app still runs**

Run:
```bash
flutter run -d chrome
```

Expected: App launches without errors (note: secure storage may not work on web, test on mobile emulator for full verification)

**Step 4: Commit**

```bash
git add lib/
git commit -m "feat: 設置 Hive 加密儲存服務"
```

---

### Task 2.3: Create Conversation Repository

**Files:**
- Create: `lib/features/conversation/data/repositories/conversation_repository.dart`
- Create: `lib/features/conversation/data/providers/conversation_providers.dart`

**Step 1: Create conversation_repository.dart**

```dart
// lib/features/conversation/data/repositories/conversation_repository.dart
import 'package:uuid/uuid.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

class ConversationRepository {
  final _uuid = const Uuid();

  List<Conversation> getAllConversations() {
    return StorageService.conversationsBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Conversation? getConversation(String id) {
    return StorageService.conversationsBox.get(id);
  }

  Future<Conversation> createConversation({
    required String name,
    required List<Message> messages,
  }) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      name: name,
      messages: messages,
      createdAt: now,
      updatedAt: now,
    );

    await StorageService.conversationsBox.put(conversation.id, conversation);
    return conversation;
  }

  Future<void> updateConversation(Conversation conversation) async {
    conversation.updatedAt = DateTime.now();
    await conversation.save();
  }

  Future<void> deleteConversation(String id) async {
    await StorageService.conversationsBox.delete(id);
  }

  Future<void> deleteAll() async {
    await StorageService.conversationsBox.clear();
  }

  List<Message> parseMessages(String rawText) {
    final lines = rawText.trim().split('\n');
    final messages = <Message>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final isFromMe = trimmed.startsWith('我:') || trimmed.startsWith('我：');
      final isFromThem = trimmed.startsWith('她:') ||
          trimmed.startsWith('她：') ||
          trimmed.startsWith('他:') ||
          trimmed.startsWith('他：');

      if (!isFromMe && !isFromThem) continue;

      final content = trimmed.substring(2).trim();
      if (content.isEmpty) continue;

      messages.add(Message(
        id: _uuid.v4(),
        content: content,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }
}
```

**Step 2: Create conversation_providers.dart**

```dart
// lib/features/conversation/data/providers/conversation_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository();
});

final conversationsProvider = Provider<List<Conversation>>((ref) {
  final repository = ref.watch(conversationRepositoryProvider);
  return repository.getAllConversations();
});
```

**Step 3: Write unit test for message parsing**

Create `test/conversation_repository_test.dart`:

```dart
// test/conversation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';

void main() {
  late ConversationRepository repository;

  setUp(() {
    repository = ConversationRepository();
  });

  group('parseMessages', () {
    test('parses messages correctly', () {
      const rawText = '''
她: 你好
我: 嗨
她: 在幹嘛
我: 工作中
''';

      final messages = repository.parseMessages(rawText);

      expect(messages.length, 4);
      expect(messages[0].isFromMe, false);
      expect(messages[0].content, '你好');
      expect(messages[1].isFromMe, true);
      expect(messages[1].content, '嗨');
    });

    test('handles empty lines', () {
      const rawText = '''
她: 你好

我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });

    test('ignores invalid lines', () {
      const rawText = '''
她: 你好
無效的行
我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });
  });
}
```

**Step 4: Run test**

Run:
```bash
flutter test test/conversation_repository_test.dart
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/features/conversation/ test/
git commit -m "feat: 建立 ConversationRepository 與訊息解析邏輯"
```

---

## Phase 3: UI Screens

### Task 3.1: Create Shared Widgets

**Files:**
- Create: `lib/shared/widgets/enthusiasm_gauge.dart`
- Create: `lib/shared/widgets/reply_card.dart`

**Step 1: Create enthusiasm_gauge.dart**

```dart
// lib/shared/widgets/enthusiasm_gauge.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';

class EnthusiasmGauge extends StatelessWidget {
  final int score;

  const EnthusiasmGauge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                '$score/100',
                style: AppTypography.headlineMedium,
              ),
              const SizedBox(width: 8),
              Text(
                level.label,
                style: AppTypography.bodyLarge.copyWith(color: level.color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(level.color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Create reply_card.dart**

```dart
// lib/shared/widgets/reply_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum ReplyType { extend, resonate, tease, humor, coldRead }

class ReplyCard extends StatelessWidget {
  final ReplyType type;
  final String content;
  final bool isLocked;
  final VoidCallback? onTap;

  const ReplyCard({
    super.key,
    required this.type,
    required this.content,
    this.isLocked = false,
    this.onTap,
  });

  String get _label {
    switch (type) {
      case ReplyType.extend:
        return '🔄 延展';
      case ReplyType.resonate:
        return '💬 共鳴';
      case ReplyType.tease:
        return '😏 調情';
      case ReplyType.humor:
        return '🎭 幽默';
      case ReplyType.coldRead:
        return '🔮 冷讀';
    }
  }

  Color get _color {
    switch (type) {
      case ReplyType.extend:
        return AppColors.cold;
      case ReplyType.resonate:
        return AppColors.warm;
      case ReplyType.tease:
        return AppColors.veryHot;
      case ReplyType.humor:
        return AppColors.hot;
      case ReplyType.coldRead:
        return AppColors.primaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLocked ? onTap : () => _copyToClipboard(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _label,
                        style: AppTypography.caption.copyWith(color: _color),
                      ),
                    ),
                    const Spacer(),
                    if (isLocked)
                      const Icon(Icons.lock, size: 16, color: AppColors.textSecondary)
                    else
                      const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isLocked ? '升級 Pro 解鎖' : content,
                  style: isLocked
                      ? AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        )
                      : AppTypography.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製到剪貼簿'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
```

**Step 3: Commit**

```bash
git add lib/shared/
git commit -m "feat: 建立 EnthusiasmGauge 和 ReplyCard 共用元件"
```

---

### Task 3.2: Create Home Screen (Conversation List)

**Files:**
- Create: `lib/features/conversation/presentation/screens/home_screen.dart`
- Create: `lib/features/conversation/presentation/widgets/conversation_tile.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create conversation_tile.dart**

```dart
// lib/features/conversation/presentation/widgets/conversation_tile.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../domain/entities/conversation.dart';
import 'package:intl/intl.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    }
    return DateFormat('MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final level = conversation.lastEnthusiasmScore != null
        ? EnthusiasmLevel.fromScore(conversation.lastEnthusiasmScore!)
        : null;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceVariant,
        child: Text(
          conversation.name.isNotEmpty ? conversation.name[0] : '?',
          style: AppTypography.titleLarge,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.name,
              style: AppTypography.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(conversation.updatedAt),
            style: AppTypography.caption,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (level != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(level.emoji),
                const SizedBox(width: 4),
                Text(
                  '${conversation.lastEnthusiasmScore}',
                  style: AppTypography.caption.copyWith(color: level.color),
                ),
              ],
            ),
          ],
          if (conversation.lastMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              conversation.lastMessage!.content,
              style: AppTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
```

**Step 2: Create home_screen.dart**

```dart
// lib/features/conversation/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/conversation_providers.dart';
import '../widgets/conversation_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('VibeSync', style: AppTypography.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return ConversationTile(
                  conversation: conversation,
                  onTap: () => context.push('/conversation/${conversation.id}'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/new'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有對話',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '點擊右下角 + 開始新增',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 3: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/conversation/presentation/screens/home_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('新增對話')),
      ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('對話 ${state.pathParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 4: Verify app runs with home screen**

Run:
```bash
flutter run -d chrome
```

Expected: Home screen displays with empty state and FAB button

**Step 5: Commit**

```bash
git add lib/
git commit -m "feat: 建立首頁對話列表畫面"
```

---

### Task 3.3: Create New Conversation Screen

**Files:**
- Create: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create new_conversation_screen.dart**

```dart
// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/conversation_providers.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入對話對象暱稱')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請貼上對話內容')),
      );
      return;
    }

    final repository = ref.read(conversationRepositoryProvider);
    final messages = repository.parseMessages(content);

    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法解析對話，請確認格式正確')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final conversation = await repository.createConversation(
        name: name,
        messages: messages,
      );

      if (mounted) {
        context.go('/conversation/${conversation.id}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('新增對話', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('對話對象暱稱', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例如：小美',
              ),
            ),
            const SizedBox(height: 24),
            Text('貼上對話內容', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '她: 你好\n我: 嗨\n她: 在幹嘛\n...',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '格式：每行一則訊息，以「她:」或「我:」開頭',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _analyze,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('開始分析'),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('對話 ${state.pathParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 3: Verify new conversation flow**

Run:
```bash
flutter run -d chrome
```

Test: Click FAB → Enter name and paste conversation → Click analyze

Expected: Navigates to conversation detail (placeholder)

**Step 4: Commit**

```bash
git add lib/
git commit -m "feat: 建立新增對話畫面與訊息輸入功能"
```

---

### Task 3.4: Create Analysis Screen

**Files:**
- Create: `lib/features/analysis/presentation/screens/analysis_screen.dart`
- Create: `lib/features/conversation/presentation/widgets/message_bubble.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create message_bubble.dart**

```dart
// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isFromMe ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: message.isFromMe ? const Radius.circular(4) : null,
            bottomLeft: !message.isFromMe ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          message.content,
          style: AppTypography.bodyMedium,
        ),
      ),
    );
  }
}
```

**Step 2: Create analysis_screen.dart**

```dart
// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/enthusiasm_gauge.dart';
import '../../../../shared/widgets/reply_card.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const AnalysisScreen({super.key, required this.conversationId});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _isAnalyzing = false;
  int? _enthusiasmScore;
  String? _strategy;
  Map<String, String>? _replies;
  TopicDepth? _topicDepth;
  HealthCheck? _healthCheck;
  bool _isFreeUser = true;  // TODO: Get from subscription provider

  void _showPaywall(BuildContext context) {
    // TODO: Navigate to paywall screen
    context.push('/paywall');
  }

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);

    // TODO: Replace with actual API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isAnalyzing = false;
      _enthusiasmScore = 72;
      _strategy = '她有興趣且主動分享，保持沉穩，80%鏡像即可';
      _topicDepth = TopicDepth(
        current: 'personal',
        suggestion: '可以往曖昧導向推進',
      );
      _healthCheck = HealthCheck(
        issues: [],
        suggestions: [],
      );
      _replies = {
        'extend': '抹茶山不錯欸，下次可以挑戰更難的',
        'resonate': '抹茶山超讚！照片一定很美吧',
        'tease': '聽起來妳很會挑地方嘛，改天帶路？',
        'humor': '爬完山是不是腿軟到需要人扶？',
        'coldRead': '感覺你是那種週末閒不下來的人',
      };
    });

    // Update conversation with score
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    if (conversation != null) {
      conversation.lastEnthusiasmScore = _enthusiasmScore;
      await repository.updateConversation(conversation);
    }
  }

  int _calculateMaxReplyLength(Conversation conversation) {
    final theirMessages = conversation.theirMessages;
    if (theirMessages.isEmpty) return 50;

    final lastTheirMessage = theirMessages.last;
    return (lastTheirMessage.wordCount * AppConstants.goldenRuleMultiplier).round();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('找不到對話')),
      );
    }

    final maxLength = _calculateMaxReplyLength(conversation);

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation.name, style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (_isAnalyzing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Messages preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ...conversation.messages
                      .take(5)
                      .map((m) => MessageBubble(message: m)),
                  if (conversation.messages.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '...還有 ${conversation.messages.length - 5} 則訊息',
                        style: AppTypography.caption,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Enthusiasm Gauge
            if (_enthusiasmScore != null) ...[
              Text('熱度分析', style: AppTypography.titleLarge),
              const SizedBox(height: 12),
              EnthusiasmGauge(score: _enthusiasmScore!),
            ] else if (_isAnalyzing) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('分析中...'),
                  ],
                ),
              ),
            ],

            // Strategy
            if (_strategy != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _strategy!,
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reply suggestions
            // Topic Depth (話題深度)
            if (_topicDepth != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('📊', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('話題深度: ${_topicDepth!.current}',
                              style: AppTypography.bodyMedium),
                          if (_topicDepth!.suggestion.isNotEmpty)
                            Text(_topicDepth!.suggestion,
                                style: AppTypography.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Health Check (對話健檢 - Essential 專屬)
            if (_healthCheck != null && _healthCheck!.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🩺', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('對話健檢', style: AppTypography.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._healthCheck!.issues.map((issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text(issue, style: AppTypography.bodyMedium)),
                        ],
                      ),
                    )),
                    if (_healthCheck!.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._healthCheck!.suggestions.map((suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(child: Text(suggestion, style: AppTypography.caption)),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ],

            // Reply suggestions (5 種回覆)
            if (_replies != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('建議回覆', style: AppTypography.titleLarge),
                  const Spacer(),
                  Text(
                    '字數上限: $maxLength字',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 延展回覆 (所有方案都有)
              ReplyCard(
                type: ReplyType.extend,
                content: _replies!['extend']!,
              ),
              // 以下回覆 Starter/Essential 才有
              ReplyCard(
                type: ReplyType.resonate,
                content: _replies!['resonate']!,
                isLocked: _isFreeUser, // Free 用戶鎖定
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.tease,
                content: _replies!['tease']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.humor,
                content: _replies!['humor']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.coldRead,
                content: _replies!['coldRead']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

**Step 3: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 4: Verify full flow**

Run:
```bash
flutter run -d chrome
```

Test: Create new conversation → View analysis with mock data

Expected: Shows messages, enthusiasm gauge, strategy, and reply cards

**Step 5: Commit**

```bash
git add lib/
git commit -m "feat: 建立對話分析畫面 (含熱度儀表與回覆建議)"
```

---

## Phase 4: Supabase Backend

### Task 4.1: Setup Supabase Project

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/00001_initial_schema.sql`

**Step 1: Initialize Supabase**

Run:
```bash
npx supabase init
```

Expected: Creates `supabase/` directory

**Step 2: Create initial migration**

```sql
-- supabase/migrations/00001_initial_schema.sql

-- Users table (synced with auth.users)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  total_analyses INTEGER DEFAULT 0,
  total_conversations INTEGER DEFAULT 0
);

-- Subscriptions table (訊息制)
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'starter', 'essential')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
  rc_customer_id TEXT,
  rc_entitlement_id TEXT,
  -- 訊息用量追蹤
  monthly_messages_used INTEGER DEFAULT 0,
  daily_messages_used INTEGER DEFAULT 0,
  monthly_reset_at TIMESTAMPTZ DEFAULT NOW(),
  daily_reset_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own data" ON public.users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own data" ON public.users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own subscription" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);

-- Function to create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email);

  INSERT INTO public.subscriptions (user_id)
  VALUES (NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to reset monthly usage
CREATE OR REPLACE FUNCTION public.reset_monthly_usage()
RETURNS void AS $$
BEGIN
  UPDATE public.subscriptions
  SET monthly_analyses_used = 0,
      monthly_reset_at = NOW()
  WHERE monthly_reset_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
```

**Step 3: Commit**

```bash
git add supabase/
git commit -m "feat: 建立 Supabase 初始資料庫結構"
```

---

### Task 4.2: Create Edge Function for Analysis

**Files:**
- Create: `supabase/functions/analyze-chat/index.ts`

**Step 1: Create Edge Function**

```typescript
// supabase/functions/analyze-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 訊息制額度
const TIER_MONTHLY_LIMITS: Record<string, number> = {
  free: 30,
  starter: 300,
  essential: 1000,
};

const TIER_DAILY_LIMITS: Record<string, number> = {
  free: 15,
  starter: 50,
  essential: 150,
};

// 功能權限
const TIER_FEATURES: Record<string, string[]> = {
  free: ['extend'],  // 只有延展回覆
  starter: ['extend', 'resonate', 'tease', 'humor', 'coldRead', 'needy_warning', 'topic_depth'],
  essential: ['extend', 'resonate', 'tease', 'humor', 'coldRead', 'needy_warning', 'topic_depth', 'health_check'],
};

const SYSTEM_PROMPT = `你是一位專業的社交溝通教練，幫助用戶提升對話技巧。

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

## 對話健檢項目
- 面試式提問：連續問 3+ 個問題
- 話題跳 tone：沒過渡就換話題
- 索取 > 提供：問太多、分享太少
- 深度越級：關係不熟就聊曖昧
- 回覆過長：違反 1.8x 法則

## 輸出格式 (JSON)
{
  "enthusiasm": { "score": 75, "level": "hot" },
  "topicDepth": { "current": "personal", "suggestion": "可以往曖昧導向推進" },
  "replies": {
    "extend": "...",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "warnings": [],
  "healthCheck": {
    "issues": ["面試式提問過多"],
    "suggestions": ["用假設代替問句"]
  },
  "strategy": "簡短策略說明"
}`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
      });
    }

    // Check subscription
    const { data: sub } = await supabase
      .from("subscriptions")
      .select("tier, monthly_messages_used, daily_messages_used, daily_reset_at")
      .eq("user_id", user.id)
      .single();

    if (!sub) {
      return new Response(JSON.stringify({ error: "No subscription found" }), {
        status: 403,
      });
    }

    // Check if daily reset needed
    const now = new Date();
    const dailyResetAt = new Date(sub.daily_reset_at);
    if (now.toDateString() !== dailyResetAt.toDateString()) {
      await supabase
        .from("subscriptions")
        .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
        .eq("user_id", user.id);
      sub.daily_messages_used = 0;
    }

    // Check monthly limit
    const monthlyLimit = TIER_MONTHLY_LIMITS[sub.tier];
    if (sub.monthly_messages_used >= monthlyLimit) {
      return new Response(
        JSON.stringify({ error: "Monthly limit exceeded", monthlyLimit }),
        { status: 429 }
      );
    }

    // Check daily limit
    const dailyLimit = TIER_DAILY_LIMITS[sub.tier];
    if (sub.daily_messages_used >= dailyLimit) {
      return new Response(
        JSON.stringify({ error: "Daily limit exceeded", dailyLimit, resetAt: "tomorrow" }),
        { status: 429 }
      );
    }

    // Parse request
    const { messages } = await req.json();
    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Invalid messages" }), {
        status: 400,
      });
    }

    // Format messages for Claude
    const conversationText = messages
      .map((m: { isFromMe: boolean; content: string }) =>
        `${m.isFromMe ? "我" : "她"}: ${m.content}`
      )
      .join("\n");

    // Select model based on complexity
    const model = messages.length > 20 ? "claude-3-5-sonnet-20241022" : "claude-3-5-haiku-20241022";

    // Call Claude API
    const claudeResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: `分析以下對話並提供建議：\n\n${conversationText}`,
          },
        ],
      }),
    });

    const claudeData = await claudeResponse.json();
    const content = claudeData.content[0]?.text;

    // Parse Claude's response
    let result;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      result = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      result = {
        enthusiasm: { score: 50, level: "warm" },
        replies: {
          extend: "無法生成建議",
          resonate: "無法生成建議",
          tease: "無法生成建議",
        },
        warnings: [],
        strategy: "請重試",
      };
    }

    // Calculate message count (訊息計算邏輯)
    const messageCount = countMessages(messages);

    // Update usage count
    await supabase
      .from("subscriptions")
      .update({
        monthly_messages_used: sub.monthly_messages_used + messageCount,
        daily_messages_used: sub.daily_messages_used + messageCount,
      })
      .eq("user_id", user.id);

    // Update user stats
    await supabase
      .from("users")
      .update({ total_analyses: supabase.rpc("increment_analyses") })
      .eq("id", user.id);

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

    return new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500 }
    );
  }
});
```

**Step 2: Commit**

```bash
git add supabase/functions/
git commit -m "feat: 建立 analyze-chat Edge Function (Claude API 整合)"
```

---

## Phase 5: Connect Flutter to Supabase

### Task 5.1: Setup Supabase Client

**Files:**
- Create: `lib/core/services/supabase_service.dart`
- Create: `.env.example`
- Modify: `lib/main.dart`

**Step 1: Create .env.example**

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

**Step 2: Create supabase_service.dart**

```dart
// lib/core/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static late SupabaseClient _client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    _client = Supabase.instance.client;
  }

  static SupabaseClient get client => _client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isAuthenticated => currentUser != null;

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
```

**Step 3: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await StorageService.initialize();

  // TODO: Load from environment
  await SupabaseService.initialize(
    url: const String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'https://placeholder.supabase.co'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY',
        defaultValue: 'placeholder'),
  );

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 4: Commit**

```bash
git add lib/ .env.example
git commit -m "feat: 整合 Supabase 客戶端服務"
```

---

### Task 5.2: Create Analysis Service

**Files:**
- Create: `lib/features/analysis/data/services/analysis_service.dart`
- Create: `lib/features/analysis/data/providers/analysis_providers.dart`

**Step 1: Create analysis_service.dart**

```dart
// lib/features/analysis/data/services/analysis_service.dart
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';

class TopicDepth {
  final String current;  // 'facts' | 'personal' | 'intimate'
  final String suggestion;

  TopicDepth({required this.current, required this.suggestion});

  factory TopicDepth.fromJson(Map<String, dynamic> json) {
    return TopicDepth(
      current: json['current'] as String? ?? 'facts',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }
}

class HealthCheck {
  final List<String> issues;
  final List<String> suggestions;

  HealthCheck({required this.issues, required this.suggestions});

  factory HealthCheck.fromJson(Map<String, dynamic>? json) {
    if (json == null) return HealthCheck(issues: [], suggestions: []);
    return HealthCheck(
      issues: (json['issues'] as List?)?.cast<String>() ?? [],
      suggestions: (json['suggestions'] as List?)?.cast<String>() ?? [],
    );
  }
}

class AnalysisResult {
  final int enthusiasmScore;
  final String level;
  final TopicDepth topicDepth;
  final Map<String, String> replies;  // extend, resonate, tease, humor, coldRead
  final List<String> warnings;
  final HealthCheck healthCheck;
  final String strategy;

  AnalysisResult({
    required this.enthusiasmScore,
    required this.level,
    required this.topicDepth,
    required this.replies,
    required this.warnings,
    required this.healthCheck,
    required this.strategy,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final enthusiasm = json['enthusiasm'] as Map<String, dynamic>;
    final replies = json['replies'] as Map<String, dynamic>;

    return AnalysisResult(
      enthusiasmScore: enthusiasm['score'] as int,
      level: enthusiasm['level'] as String,
      topicDepth: TopicDepth.fromJson(json['topicDepth'] as Map<String, dynamic>? ?? {}),
      replies: replies.map((k, v) => MapEntry(k, v.toString())),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      healthCheck: HealthCheck.fromJson(json['healthCheck'] as Map<String, dynamic>?),
      strategy: json['strategy'] as String? ?? '',
    );
  }
}

class AnalysisService {
  Future<AnalysisResult> analyzeConversation(List<Message> messages) async {
    final response = await SupabaseService.client.functions.invoke(
      'analyze-chat',
      body: {
        'messages': messages
            .map((m) => {
                  'isFromMe': m.isFromMe,
                  'content': m.content,
                })
            .toList(),
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Analysis failed');
    }

    return AnalysisResult.fromJson(response.data);
  }
}
```

**Step 2: Create analysis_providers.dart**

```dart
// lib/features/analysis/data/providers/analysis_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analysis_service.dart';

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService();
});
```

**Step 3: Commit**

```bash
git add lib/features/analysis/
git commit -m "feat: 建立 AnalysisService 連接 Edge Function"
```

---

## Phase 6: Settings & Subscription (Stub)

### Task 6.1: Create Settings Screen

**Files:**
- Create: `lib/features/subscription/presentation/screens/settings_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create settings_screen.dart**

```dart
// lib/features/subscription/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('設定', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          _buildSection(
            title: '帳戶',
            children: [
              _buildTile(
                icon: Icons.workspace_premium,
                title: '訂閱方案',
                trailing: 'Free',
                onTap: () {
                  // TODO: Open paywall
                },
              ),
              _buildTile(
                icon: Icons.analytics,
                title: '本月用量',
                trailing: '0/5',
              ),
              _buildTile(
                icon: Icons.person,
                title: '帳號',
                trailing: '未登入',
                onTap: () {
                  // TODO: Open login
                },
              ),
            ],
          ),
          _buildSection(
            title: '隱私與安全',
            children: [
              _buildTile(
                icon: Icons.delete_forever,
                title: '清除所有對話資料',
                titleColor: AppColors.error,
                onTap: () => _showDeleteDialog(context),
              ),
              _buildTile(
                icon: Icons.download,
                title: '匯出我的資料',
                onTap: () {
                  // TODO: Export data
                },
              ),
              _buildTile(
                icon: Icons.privacy_tip,
                title: '隱私權政策',
                onTap: () {
                  // TODO: Open privacy policy
                },
              ),
            ],
          ),
          _buildSection(
            title: '關於',
            children: [
              _buildTile(
                icon: Icons.info,
                title: '版本',
                trailing: '1.0.0',
              ),
              _buildTile(
                icon: Icons.description,
                title: '使用條款',
                onTap: () {
                  // TODO: Open terms
                },
              ),
              _buildTile(
                icon: Icons.feedback,
                title: '意見回饋',
                onTap: () {
                  // TODO: Open feedback
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(color: titleColor),
      ),
      trailing: trailing != null
          ? Text(trailing, style: AppTypography.bodyMedium)
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('確定要刪除所有對話？'),
        content: const Text('此操作無法復原'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await StorageService.conversationsBox.clear();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除所有對話')),
                );
              }
            },
            child: Text(
              '刪除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';
import '../features/subscription/presentation/screens/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
```

**Step 3: Commit**

```bash
git add lib/
git commit -m "feat: 建立設定畫面 (含清除資料功能)"
```

---

---

## Phase 7: Message Calculation & Usage Tracking

### Task 7.1: Create Message Calculation Service

**Files:**
- Create: `lib/core/services/message_calculator.dart`
- Create: `lib/core/services/usage_service.dart`

**Step 1: Create message_calculator.dart**

```dart
// lib/core/services/message_calculator.dart
import '../constants/app_constants.dart';

class MessageCalculator {
  /// 計算訊息數量
  /// 規則：換行分割 + 每 200 字 = 1 則
  static int countMessages(String text) {
    if (text.trim().isEmpty) return 0;

    // 用換行分割，過濾空行
    final lines = text.split(RegExp(r'\n+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    int total = 0;
    for (final line in lines) {
      final charCount = line.trim().length;
      total += (charCount / AppConstants.maxCharsPerMessage).ceil().clamp(1, 100);
    }

    return total.clamp(1, 1000);
  }

  /// 檢查是否超過單次分析上限
  static bool exceedsMaxLength(String text) {
    return text.length > AppConstants.maxTotalChars;
  }

  /// 預覽訊息計算結果
  static MessagePreview preview(String text) {
    final count = countMessages(text);
    final exceeds = exceedsMaxLength(text);

    return MessagePreview(
      messageCount: count,
      charCount: text.length,
      exceedsLimit: exceeds,
    );
  }
}

class MessagePreview {
  final int messageCount;
  final int charCount;
  final bool exceedsLimit;

  MessagePreview({
    required this.messageCount,
    required this.charCount,
    required this.exceedsLimit,
  });
}
```

**Step 2: Create usage_service.dart**

```dart
// lib/core/services/usage_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

class UsageData {
  final int monthlyUsed;
  final int monthlyLimit;
  final int dailyUsed;
  final int dailyLimit;
  final DateTime dailyResetAt;

  UsageData({
    required this.monthlyUsed,
    required this.monthlyLimit,
    required this.dailyUsed,
    required this.dailyLimit,
    required this.dailyResetAt,
  });

  bool get canAnalyze => monthlyUsed < monthlyLimit && dailyUsed < dailyLimit;
  int get monthlyRemaining => monthlyLimit - monthlyUsed;
  int get dailyRemaining => dailyLimit - dailyUsed;
  double get monthlyPercentage => monthlyUsed / monthlyLimit;
}

class UsageService {
  Future<UsageData> getUsage() async {
    // TODO: Fetch from Supabase
    return UsageData(
      monthlyUsed: 0,
      monthlyLimit: 30,
      dailyUsed: 0,
      dailyLimit: 15,
      dailyResetAt: DateTime.now().add(const Duration(hours: 6)),
    );
  }

  Future<bool> checkAndDeduct(int messageCount) async {
    final usage = await getUsage();
    if (usage.monthlyRemaining < messageCount) return false;
    if (usage.dailyRemaining < messageCount) return false;

    // TODO: Update usage in Supabase
    return true;
  }
}

final usageServiceProvider = Provider<UsageService>((ref) => UsageService());
```

**Step 3: Write unit tests**

Create `test/message_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';

void main() {
  group('MessageCalculator', () {
    test('counts single short message as 1', () {
      expect(MessageCalculator.countMessages('你好'), 1);
    });

    test('counts multiple lines correctly', () {
      expect(MessageCalculator.countMessages('你好\n在嗎\n吃飯了嗎'), 3);
    });

    test('counts long message by 200 char chunks', () {
      final longText = 'a' * 450; // 450 chars = ceil(450/200) = 3
      expect(MessageCalculator.countMessages(longText), 3);
    });

    test('handles empty lines', () {
      expect(MessageCalculator.countMessages('你好\n\n\n在嗎'), 2);
    });

    test('returns 0 for empty input', () {
      expect(MessageCalculator.countMessages(''), 0);
      expect(MessageCalculator.countMessages('   '), 0);
    });
  });
}
```

**Step 4: Commit**

```bash
git add lib/core/services/ test/
git commit -m "feat: 建立訊息計算服務與用量追蹤"
```

---

### Task 7.2: Create Analysis Preview Dialog

**Files:**
- Create: `lib/shared/widgets/analysis_preview_dialog.dart`
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: Create analysis_preview_dialog.dart**

```dart
// lib/shared/widgets/analysis_preview_dialog.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/services/message_calculator.dart';
import '../../core/services/usage_service.dart';

class AnalysisPreviewDialog extends StatelessWidget {
  final MessagePreview preview;
  final UsageData usage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const AnalysisPreviewDialog({
    super.key,
    required this.preview,
    required this.usage,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final canProceed = !preview.exceedsLimit &&
        usage.monthlyRemaining >= preview.messageCount &&
        usage.dailyRemaining >= preview.messageCount;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('確認分析', style: AppTypography.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message count
          _buildRow('本次分析', '${preview.messageCount} 則訊息'),
          const SizedBox(height: 12),

          // Monthly usage
          _buildRow('月額度', '${usage.monthlyRemaining} / ${usage.monthlyLimit} 則'),
          LinearProgressIndicator(
            value: usage.monthlyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              usage.monthlyPercentage > 0.8 ? AppColors.warning : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Daily usage
          _buildRow('今日額度', '${usage.dailyRemaining} / ${usage.dailyLimit} 則'),
          const SizedBox(height: 16),

          // Warnings
          if (preview.exceedsLimit)
            _buildWarning('內容過長，請分批分析 (上限 5000 字)')
          else if (usage.monthlyRemaining < preview.messageCount)
            _buildWarning('月額度不足，請升級方案或加購')
          else if (usage.dailyRemaining < preview.messageCount)
            _buildWarning('今日額度已用完，明天再試'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: canProceed ? onConfirm : null,
          child: const Text('確認分析'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(value, style: AppTypography.bodyLarge),
      ],
    );
  }

  Widget _buildWarning(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/shared/widgets/
git commit -m "feat: 建立分析前預覽確認對話框"
```

---

## Phase 8: Conversation Memory

### Task 8.1: Add Memory Fields to Entities

**Files:**
- Modify: `lib/features/conversation/domain/entities/conversation.dart`
- Create: `lib/features/conversation/domain/entities/conversation_summary.dart`

**Step 1: Create conversation_summary.dart**

```dart
// lib/features/conversation/domain/entities/conversation_summary.dart
import 'package:hive/hive.dart';

part 'conversation_summary.g.dart';

@HiveType(typeId: 2)
class ConversationSummary extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int roundsCovered;  // 摘要涵蓋的輪數範圍

  @HiveField(2)
  final String content;  // AI 生成的摘要

  @HiveField(3)
  final List<String> keyTopics;  // 關鍵話題

  @HiveField(4)
  final List<String> sharedInterests;  // 共同興趣

  @HiveField(5)
  final String relationshipStage;  // 關係階段

  @HiveField(6)
  final DateTime createdAt;

  ConversationSummary({
    required this.id,
    required this.roundsCovered,
    required this.content,
    required this.keyTopics,
    required this.sharedInterests,
    required this.relationshipStage,
    required this.createdAt,
  });
}
```

**Step 2: Update conversation.dart**

```dart
// 在 Conversation class 中添加以下欄位

  @HiveField(7)
  int currentRound;  // 當前輪數

  @HiveField(8)
  List<ConversationSummary>? summaries;  // 歷史摘要

  @HiveField(9)
  String? lastUserChoice;  // 用戶上次選擇的回覆類型 (用於選擇追蹤)

  /// 取得最近 N 輪訊息 (用於 AI context)
  List<Message> getRecentMessages(int rounds) {
    // 計算每輪約 2 則訊息 (用戶 + 對方)
    final messageCount = rounds * 2;
    if (messages.length <= messageCount) return messages;
    return messages.sublist(messages.length - messageCount);
  }

  /// 需要摘要嗎？(超過 15 輪且沒有摘要時)
  bool get needsSummary => currentRound > 15 && (summaries?.isEmpty ?? true);
```

**Step 3: Generate Hive adapters**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 4: Commit**

```bash
git add lib/features/conversation/domain/entities/
git commit -m "feat: 添加對話記憶實體與摘要結構"
```

---

### Task 8.2: Create Memory Service

**Files:**
- Create: `lib/features/conversation/data/services/memory_service.dart`

**Step 1: Create memory_service.dart**

```dart
// lib/features/conversation/data/services/memory_service.dart
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/message.dart';
import '../../../analysis/data/services/analysis_service.dart';

class MemoryService {
  final AnalysisService _analysisService;

  MemoryService(this._analysisService);

  /// 準備 AI 分析的 context
  /// 最近 15 輪完整 + 更早的摘要
  Future<String> prepareContext(Conversation conversation) async {
    final buffer = StringBuffer();

    // 添加歷史摘要 (如果有)
    if (conversation.summaries?.isNotEmpty ?? false) {
      buffer.writeln('【歷史摘要】');
      for (final summary in conversation.summaries!) {
        buffer.writeln(summary.content);
      }
      buffer.writeln('---');
    }

    // 添加最近 15 輪訊息
    final recentMessages = conversation.getRecentMessages(15);
    buffer.writeln('【最近對話】');
    for (final msg in recentMessages) {
      buffer.writeln('${msg.isFromMe ? "我" : "她"}: ${msg.content}');
    }

    return buffer.toString();
  }

  /// 智能推測用戶選擇
  /// 從對方回覆反推用戶說了什麼
  String? inferUserChoice(
    Message theirReply,
    Map<String, String> previousSuggestions,
  ) {
    final content = theirReply.content.toLowerCase();

    // 簡單的關鍵字匹配 (實際可用 AI)
    for (final entry in previousSuggestions.entries) {
      final keywords = _extractKeywords(entry.value);
      for (final keyword in keywords) {
        if (content.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return null;  // 無法推測，可能需要詢問用戶
  }

  List<String> _extractKeywords(String text) {
    // 提取關鍵詞 (簡化版本)
    return text
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ')
        .split(' ')
        .where((w) => w.length > 1)
        .toList();
  }

  /// 生成對話摘要 (背景執行)
  Future<ConversationSummary> generateSummary(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) async {
    // TODO: 呼叫 AI 生成摘要
    return ConversationSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roundsCovered: toRound - fromRound,
      content: '待實作：AI 生成的對話摘要',
      keyTopics: [],
      sharedInterests: [],
      relationshipStage: 'personal',
      createdAt: DateTime.now(),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/conversation/data/services/
git commit -m "feat: 建立對話記憶服務 (context 準備 + 選擇追蹤)"
```

---

## Phase 9: Paywall & Subscription UI

### Task 9.1: Create Paywall Screen

**Files:**
- Create: `lib/features/subscription/presentation/screens/paywall_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create paywall_screen.dart**

```dart
// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential';  // 預設選 Essential

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('升級方案', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              '解鎖完整功能',
              style: AppTypography.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '提升你的社交溝通能力',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Plan cards
            _buildPlanCard(
              tier: 'starter',
              name: 'Starter',
              price: 'NT\$149/月',
              features: [
                '300 則訊息/月',
                '每日 50 則上限',
                '5 種回覆建議',
                'Needy 警示',
                '話題深度分析',
              ],
              isSelected: _selectedTier == 'starter',
              onTap: () => setState(() => _selectedTier = 'starter'),
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              tier: 'essential',
              name: 'Essential',
              price: 'NT\$349/月',
              features: [
                '1,000 則訊息/月',
                '每日 150 則上限',
                '5 種回覆建議',
                'Needy 警示',
                '話題深度分析',
                '🩺 對話健檢 (獨家)',
                'Sonnet 優先模型',
              ],
              isSelected: _selectedTier == 'essential',
              isRecommended: true,
              onTap: () => setState(() => _selectedTier = 'essential'),
            ),
            const SizedBox(height: 32),

            // CTA button
            ElevatedButton(
              onPressed: _subscribe,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                '開始 7 天免費試用',
                style: AppTypography.titleLarge.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '試用結束後自動扣款，可隨時取消',
              style: AppTypography.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Terms
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {},
                  child: Text('使用條款', style: AppTypography.caption),
                ),
                Text(' | ', style: AppTypography.caption),
                TextButton(
                  onPressed: () {},
                  child: Text('隱私權政策', style: AppTypography.caption),
                ),
                Text(' | ', style: AppTypography.caption),
                TextButton(
                  onPressed: () {},
                  child: Text('恢復購買', style: AppTypography.caption),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required String price,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: AppTypography.titleLarge),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('推薦', style: AppTypography.caption.copyWith(color: Colors.white)),
                  ),
                ],
                const Spacer(),
                Radio<String>(
                  value: tier,
                  groupValue: _selectedTier,
                  onChanged: (v) => setState(() => _selectedTier = v!),
                ),
              ],
            ),
            Text(price, style: AppTypography.headlineMedium),
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: AppTypography.bodyMedium)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    // TODO: Integrate with RevenueCat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RevenueCat 整合待實作')),
    );
  }
}
```

**Step 2: Add paywall route**

```dart
// In lib/app/routes.dart, add:
GoRoute(
  path: '/paywall',
  builder: (context, state) => const PaywallScreen(),
),
```

**Step 3: Commit**

```bash
git add lib/
git commit -m "feat: 建立 Paywall 訂閱方案選擇畫面"
```

---

## Summary

**Total Tasks:** 19 tasks across 9 phases

**Phase Breakdown:**
1. Project Foundation (3 tasks) - Flutter setup, dependencies, structure
2. Local Data Layer (3 tasks) - Hive entities, storage, repository
3. UI Screens (4 tasks) - Widgets, home, new conversation, analysis
4. Supabase Backend (2 tasks) - Schema, Edge Function
5. Flutter-Supabase Integration (2 tasks) - Client, service
6. Settings (1 task) - Settings screen
7. Message Calculation & Usage (2 tasks) - 訊息計算、用量追蹤、預覽確認
8. Conversation Memory (2 tasks) - 對話記憶、摘要、選擇追蹤
9. Paywall & Subscription (1 task) - 訂閱方案選擇畫面

**Next Steps After MVP:**
- Authentication screens (Google/Apple Sign-in)
- RevenueCat integration for subscriptions
- Real device testing
- App Store / Play Store submission

---

## Risk Mitigation Checklist

### Before Launch
- [ ] Sentry 錯誤監控設定
- [ ] Firebase Analytics 埋點
- [ ] App Icon + Splash Screen
- [ ] 隱私權政策頁面 (實際 URL)
- [ ] 使用條款頁面
- [ ] TestFlight / Internal Testing 測試
- [ ] API 成本監控 Dashboard

### API Resilience
- [ ] 請求重試機制 (3 次 + exponential backoff)
- [ ] 離線模式提示 (無網路時)
- [ ] Rate limit 錯誤處理 (顯示友善訊息)
- [ ] Timeout 處理 (30 秒上限)

### Message Parsing Robustness
- [ ] 支援「我：」和「我:」(全形/半形)
- [ ] 支援「對方:」「她:」「他:」
- [ ] 支援時間戳記格式 (自動移除)
- [ ] 支援 LINE/IG 匯出格式 (V2)

### App Store Preparation
- [ ] 截圖 (6.5" + 5.5")
- [ ] App 描述 (強調「溝通教練」)
- [ ] 隱私權聲明 (強調不儲存對話)
- [ ] 年齡分級 (17+ 建議)
- [ ] 審核備註 (說明 app 用途)

---

## Appendix: Test Commands

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Build for release
flutter build apk --release
flutter build ios --release

# Deploy Supabase functions
supabase functions deploy analyze-chat
```

---

## 變更記錄

| 日期 | 版本 | 變更內容 |
|------|------|----------|
| 2026-02-26 | 1.0 | 初始實作計畫 |
| 2026-02-26 | 2.0 | **重大更新** - 與設計規格書同步 |

### v2.0 變更明細

**訂閱/計費系統**
- ❌ 舊: free/pro/unlimited，分析次數 (5/200/∞)
- ✅ 新: Free/Starter/Essential，訊息制 (30/300/1000)
- ✅ 新增: 每日上限 (15/50/150)
- ✅ 新增: 訊息計算邏輯 (換行分割 + 200字上限)

**回覆類型**
- ❌ 舊: 3 種 (extend/resonate/tease)
- ✅ 新: 5 種 (+ humor/coldRead)

**功能分層 (付費牆)**
- ✅ 新增: Free 只有延展回覆
- ✅ 新增: Starter 有全部回覆 + Needy 警示 + 話題深度
- ✅ 新增: Essential 額外有對話健檢

**AI Prompt**
- ✅ 新增: topicDepth (話題深度階梯)
- ✅ 新增: healthCheck (對話健檢)
- ✅ 新增: 82/18 原則、假設代替問句

**新增 Phase**
- Phase 7: 訊息計算與用量追蹤 (2 tasks)
- Phase 8: 對話記憶 (2 tasks)
- Phase 9: Paywall 訂閱畫面 (1 task)

**總任務數**: 15 → 19 tasks
