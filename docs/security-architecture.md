# VibeSync 資安架構

## 威脅模型

### 攻擊向量分析

| 威脅 | 風險等級 | 攻擊方式 | 防護措施 |
|------|----------|----------|----------|
| API Key 洩漏 | 🔴 高 | 反編譯 APK、GitHub 掃描 | Key 只存後端 |
| 用戶對話外洩 | 🔴 高 | 手機遺失、備份外洩 | 本地 AES-256 加密 |
| JWT Token 竊取 | 🟡 中 | 中間人攻擊、XSS | HTTPS + Token 短效期 |
| API 濫用 | 🟡 中 | 帳號分享、爬蟲 | Rate limit + 用量監控 |
| DDoS | 🟢 低 | 大量請求 | Supabase 內建防護 |

---

## 機密資料分層

```
┌─────────────────────────────────────────────────────────────┐
│                    SECRET LEVELS                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  🔴 Level 1: 絕不進入程式碼                                   │
│  ├── Claude API Key (CLAUDE_API_KEY)                        │
│  ├── Supabase Service Role Key                              │
│  └── Database Connection String                             │
│      → 只存在: Supabase Dashboard > Secrets                  │
│                                                              │
│  🟡 Level 2: 可進入 App 但不進 Git                            │
│  ├── Supabase Anon Key (公開但不 commit)                     │
│  ├── RevenueCat Public Key                                  │
│  └── Sentry DSN                                             │
│      → 存在: .env 檔案 (已在 .gitignore)                     │
│      → Build 時注入: --dart-define                          │
│                                                              │
│  🟢 Level 3: 可公開                                          │
│  ├── Supabase Project URL                                   │
│  └── App Bundle ID                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## API Key 保護策略

### 策略 1: Key 永不進入 Client

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Flutter    │ ──────▶ │   Supabase   │ ──────▶ │   Claude     │
│     App      │  JWT    │  Edge Func   │  API    │     API      │
└──────────────┘         └──────────────┘  Key    └──────────────┘
                               │
                               ▼
                    CLAUDE_API_KEY 只存這裡
                    (Supabase Secrets)
```

**關鍵：Flutter App 永遠不知道 Claude API Key**

### 策略 2: 環境變數注入

```bash
# 本地開發
flutter run --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx

# CI/CD Build
flutter build apk --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }} ...
```

```dart
// main.dart
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

### 策略 3: Git 防護

```bash
# .gitignore (已設定)
.env
.env.*
**/secrets/

# Git hooks (pre-commit)
# 掃描是否有 key 格式的字串
```

---

## 本地資料加密

### Hive + AES-256

```dart
class SecureStorageService {
  static late List<int> _encryptionKey;

  static Future<void> initialize() async {
    // 1. 從 Secure Storage 取得 key
    final secureStorage = FlutterSecureStorage();
    String? storedKey = await secureStorage.read(key: 'hive_key');

    if (storedKey == null) {
      // 2. 首次使用，生成新 key
      final newKey = Hive.generateSecureKey();
      await secureStorage.write(
        key: 'hive_key',
        value: base64Encode(newKey),
      );
      _encryptionKey = newKey;
    } else {
      _encryptionKey = base64Decode(storedKey);
    }

    // 3. 用加密 key 開啟 Hive Box
    await Hive.openBox<Conversation>(
      'conversations',
      encryptionCipher: HiveAesCipher(_encryptionKey),
    );
  }
}
```

### 加密 Key 儲存位置

| 平台 | 儲存位置 | 安全性 |
|------|----------|--------|
| iOS | Keychain | ✅ 硬體級加密 |
| Android | EncryptedSharedPreferences | ✅ Android Keystore |
| Web | LocalStorage | ⚠️ 較弱 (MVP 不支援 web) |

---

## JWT Token 安全

### Token 設計

```typescript
// Supabase 預設 JWT 設定
{
  "aud": "authenticated",
  "exp": 1234567890,  // 1 小時過期
  "sub": "user-uuid",
  "email": "user@example.com",
  "role": "authenticated"
}
```

### Token 重新整理

```dart
class AuthService {
  Timer? _refreshTimer;

  void startTokenRefresh() {
    // 每 50 分鐘刷新 (token 60 分鐘過期)
    _refreshTimer = Timer.periodic(
      Duration(minutes: 50),
      (_) => _refreshToken(),
    );
  }

  Future<void> _refreshToken() async {
    await SupabaseService.client.auth.refreshSession();
  }
}
```

---

## Edge Function 安全驗證

```typescript
// supabase/functions/analyze-chat/index.ts

async function validateRequest(req: Request): Promise<User> {
  // 1. 檢查 Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new Error('Missing auth token');
  }

  // 2. 驗證 JWT
  const token = authHeader.replace('Bearer ', '');
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    throw new Error('Invalid token');
  }

  // 3. 檢查用戶是否被封鎖
  const { data: profile } = await supabase
    .from('users')
    .select('is_banned')
    .eq('id', user.id)
    .single();

  if (profile?.is_banned) {
    throw new Error('User banned');
  }

  // 4. 檢查訂閱狀態和用量
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('tier, monthly_analyses_used')
    .eq('user_id', user.id)
    .single();

  const limits = { free: 5, pro: 200, unlimited: Infinity };
  if (sub.monthly_analyses_used >= limits[sub.tier]) {
    throw new Error('Quota exceeded');
  }

  return user;
}
```

---

## 安全監控

### Sentry 錯誤追蹤

```dart
// main.dart
await SentryFlutter.init(
  (options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.tracesSampleRate = 0.2;
    // 不要傳送 PII
    options.beforeSend = (event, {hint}) {
      // 移除敏感資料
      event.contexts.remove('device');
      return event;
    };
  },
  appRunner: () => runApp(const App()),
);
```

### 異常行為偵測

```sql
-- 在 Supabase 設定 Alert

-- 1. 單一用戶短時間大量請求
SELECT user_id, COUNT(*) as count
FROM api_logs
WHERE created_at > NOW() - INTERVAL '1 minute'
GROUP BY user_id
HAVING COUNT(*) > 10;  -- Alert threshold

-- 2. 異常付費行為
SELECT user_id
FROM subscriptions
WHERE tier = 'unlimited'
AND monthly_analyses_used > 1000;  -- 可疑大量使用
```
