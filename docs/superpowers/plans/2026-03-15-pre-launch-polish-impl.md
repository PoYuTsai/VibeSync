# 上架前準備 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 優化登入頁和設定頁，移除測試資訊，完善法律聲明連結，準備正式上架。

**Architecture:** 修改兩個現有畫面（login_screen.dart, settings_screen.dart），新增一個依賴（package_info_plus）。所有改動都是 UI 層，無需修改後端或資料模型。

**Tech Stack:** Flutter, url_launcher, package_info_plus

**Spec:** `docs/superpowers/specs/2026-03-15-pre-launch-polish-design.md`

---

## File Structure

| 檔案 | 動作 | 說明 |
|------|------|------|
| `pubspec.yaml` | Modify | 新增 package_info_plus 依賴 |
| `lib/features/auth/presentation/screens/login_screen.dart` | Modify | 調整按鈕順序、移除測試帳號、新增法律聲明 |
| `lib/features/subscription/presentation/screens/settings_screen.dart` | Modify | 帳號顯示、刪除匯出、法律連結、Telegram、版本號 |

---

## Chunk 1: Dependencies and Login Screen

### Task 1: 新增 package_info_plus 依賴

**Files:**
- Modify: `pubspec.yaml:56-57`

- [ ] **Step 1: 新增依賴**

在 `pubspec.yaml` 的 `url_launcher` 後面新增：

```yaml
  url_launcher: ^6.2.5
  flutter_web_auth_2: ^4.0.1
  package_info_plus: ^8.0.0
```

- [ ] **Step 2: 執行 flutter pub get**

Run: `flutter pub get`

Expected: Dependencies resolved successfully

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: 新增 package_info_plus 依賴"
```

---

### Task 2: 登入頁 - 調整按鈕順序（Google → Apple）

**Files:**
- Modify: `lib/features/auth/presentation/screens/login_screen.dart:174-182`

- [ ] **Step 1: 調整按鈕順序**

找到 lines 174-182，將：

```dart
                    // Third-party Sign In Buttons (iOS only, login mode)
                    if (_isIOS && !_isSignUp) ...[
                      _buildAppleSignInButton(),
                      const SizedBox(height: 12),
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 24),
                    ],
```

改成：

```dart
                    // Third-party Sign In Buttons (iOS only, login mode)
                    if (_isIOS && !_isSignUp) ...[
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 12),
                      _buildAppleSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 24),
                    ],
```

- [ ] **Step 2: 驗證編譯**

Run: `flutter analyze lib/features/auth/presentation/screens/login_screen.dart`

Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/presentation/screens/login_screen.dart
git commit -m "feat: 登入頁按鈕順序改為 Google → Apple"
```

---

### Task 3: 登入頁 - 移除沙盒測試帳號區塊

**Files:**
- Modify: `lib/features/auth/presentation/screens/login_screen.dart:247-268`

- [ ] **Step 1: 刪除測試帳號區塊**

找到 lines 247-268，刪除整個區塊：

```dart
                    const SizedBox(height: 32),
                    GlassmorphicContainer(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧪 沙盒測試帳號',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.glassTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Email: vibesync.test@gmail.com\n密碼: test123456',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.glassTextHint,
                            ),
                          ),
                        ],
                      ),
                    ),
```

- [ ] **Step 2: 驗證編譯**

Run: `flutter analyze lib/features/auth/presentation/screens/login_screen.dart`

Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/presentation/screens/login_screen.dart
git commit -m "feat: 移除登入頁沙盒測試帳號區塊"
```

---

### Task 4: 登入頁 - 新增法律聲明

**Files:**
- Modify: `lib/features/auth/presentation/screens/login_screen.dart`

- [ ] **Step 1: 新增 url_launcher import**

在檔案頂部 imports 區塊新增：

```dart
import 'package:url_launcher/url_launcher.dart';
```

- [ ] **Step 2: 新增開啟網頁方法**

在 `_LoginScreenState` class 內，`_submit` 方法後面新增：

```dart
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
```

- [ ] **Step 3: 新增法律聲明 Widget**

在 `_buildDivider` 方法後面新增：

```dart
  Widget _buildLegalDisclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text.rich(
        TextSpan(
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
          children: [
            const TextSpan(text: '繼續即表示您同意 '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/terms'),
                child: Text(
                  '使用條款',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' 並確認已閱讀 '),
            WidgetSpan(
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/privacy'),
                child: Text(
                  '隱私權政策',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
```

- [ ] **Step 4: 在 build 方法中加入法律聲明**

在 TextButton（「沒有帳號？註冊」）後面，原本 `const SizedBox(height: 32)` 的位置改成：

```dart
                    const SizedBox(height: 24),
                    _buildLegalDisclaimer(),
```

- [ ] **Step 5: 驗證編譯**

Run: `flutter analyze lib/features/auth/presentation/screens/login_screen.dart`

Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/presentation/screens/login_screen.dart
git commit -m "feat: 登入頁新增法律聲明"
```

---

## Chunk 2: Settings Screen

### Task 5: 設定頁 - 改帳號顯示邏輯

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 新增 Supabase User import（已有）**

確認頂部已有 import：
```dart
import '../../../../core/services/supabase_service.dart';
```

- [ ] **Step 2: 新增帳號顯示方法**

在 `_getTierDisplayName` 方法後面新增：

```dart
  String _getAccountDisplay() {
    final user = SupabaseService.currentUser;
    if (user == null) return '未登入';

    // 檢查登入提供者
    final provider = user.appMetadata['provider'];

    if (provider == 'apple') {
      // Apple 用戶：優先顯示名稱，沒有則顯示「Apple 帳號」
      final fullName = user.userMetadata?['full_name'];
      final name = user.userMetadata?['name'];
      return fullName ?? name ?? 'Apple 帳號';
    }

    // Google / Email 用戶：顯示 email
    return user.email ?? '未知帳號';
  }
```

- [ ] **Step 3: 修改帳號顯示**

搜尋 `trailing: user?.email ?? '未登入'`，將整個 `_buildTile` 區塊：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.person,
                      title: '帳號',
                      trailing: user?.email ?? '未登入',
                    ),
```

改成：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.person,
                      title: '帳號',
                      trailing: _getAccountDisplay(),
                    ),
```

- [ ] **Step 4: 驗證編譯**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`

Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "feat: 設定頁帳號顯示優化（Apple 用戶不顯示 relay email）"
```

---

### Task 6: 設定頁 - 刪除「匯出我的資料」

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 刪除匯出資料項目**

搜尋 `title: '匯出我的資料'`，刪除整個 `_buildTile` 區塊：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.download,
                      title: '匯出我的資料',
                      onTap: () => _showComingSoonSnackBar(context, '匯出功能'),
                    ),
```

- [ ] **Step 2: 驗證編譯**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`

Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "feat: 移除設定頁「匯出我的資料」功能"
```

---

### Task 7: 設定頁 - 法律連結改開網頁

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 新增 url_launcher import**

在檔案頂部 imports 區塊新增：

```dart
import 'package:url_launcher/url_launcher.dart';
```

- [ ] **Step 2: 新增開啟網頁方法**

在 `_showComingSoonSnackBar` 方法後面新增：

```dart
  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法開啟連結')),
        );
      }
    }
  }
```

- [ ] **Step 3: 修改隱私權政策**

找到「隱私權政策」的 `_buildTile`，將：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.privacy_tip,
                      title: '隱私權政策',
                      onTap: () => _showComingSoonSnackBar(context, '隱私權政策'),
                    ),
```

改成：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.privacy_tip,
                      title: '隱私權政策',
                      onTap: () => _launchUrl(context, 'https://vibesyncai.app/privacy'),
                    ),
```

- [ ] **Step 4: 修改使用條款**

找到「使用條款」的 `_buildTile`，將：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.description,
                      title: '使用條款',
                      onTap: () => _showComingSoonSnackBar(context, '使用條款'),
                    ),
```

改成：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.description,
                      title: '使用條款',
                      onTap: () => _launchUrl(context, 'https://vibesyncai.app/terms'),
                    ),
```

- [ ] **Step 5: 驗證編譯**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`

Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "feat: 設定頁隱私權政策和使用條款改開網頁"
```

---

### Task 8: 設定頁 - 意見回饋改開 Telegram

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 修改意見回饋**

找到「意見回饋」的 `_buildTile`，將：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.feedback,
                      title: '意見回饋',
                      onTap: () => _showComingSoonSnackBar(context, '意見回饋'),
                    ),
```

改成：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.feedback,
                      title: '意見回饋',
                      onTap: () => _launchUrl(context, 'https://t.me/vibesync_feedback_bot'),
                    ),
```

- [ ] **Step 2: 驗證編譯**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`

Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "feat: 設定頁意見回饋改開 Telegram"
```

---

### Task 9: 設定頁 - 版本號動態顯示

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 新增 package_info_plus import**

在檔案頂部 imports 區塊新增：

```dart
import 'package:package_info_plus/package_info_plus.dart';
```

- [ ] **Step 2: 將 ConsumerWidget 改為 ConsumerStatefulWidget**

找到 class 定義，將：

```dart
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

改成：

```dart
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
```

- [ ] **Step 3: 修改版本顯示**

找到「版本」的 `_buildTile`，將：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.info,
                      title: '版本',
                      trailing: '1.0.0',
                    ),
```

改成：

```dart
                    _buildTile(
                      context: context,
                      icon: Icons.info,
                      title: '版本',
                      trailing: _version.isEmpty ? '載入中...' : _version,
                    ),
```

- [ ] **Step 4: 驗證編譯**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`

Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "feat: 設定頁版本號動態顯示"
```

---

## Chunk 3: Final Verification

### Task 10: 完整測試驗證

- [ ] **Step 1: 執行全專案分析**

Run: `flutter analyze lib/`

Expected: No errors (warnings are acceptable)

- [ ] **Step 2: 登入頁視覺驗證**

Run: `flutter run` (選擇 iOS Simulator 或實機)

檢查：
- [ ] Google 登入按鈕在 Apple 按鈕上方
- [ ] 沙盒測試帳號區塊已移除
- [ ] 法律聲明顯示在底部
- [ ] 點擊「使用條款」可開啟網頁（或顯示 404 如果夥伴尚未建立頁面）
- [ ] 點擊「隱私權政策」可開啟網頁
- [ ] Email + 密碼登入仍正常運作（使用測試帳號驗證）

- [ ] **Step 3: 設定頁視覺驗證**

檢查：
- [ ] Apple 登入用戶顯示「Apple 帳號」
- [ ] Google 登入用戶顯示 email
- [ ] 「匯出我的資料」已移除
- [ ] 點擊「隱私權政策」可開啟網頁
- [ ] 點擊「使用條款」可開啟網頁
- [ ] 點擊「意見回饋」可開啟 Telegram
- [ ] 版本號顯示格式正確（如 1.0.0 (42)）

- [ ] **Step 4: 最終 Commit 並 Push**

```bash
git push origin main
```

- [ ] **Step 5: 觸發 TestFlight Build**

到 GitHub Actions 手動觸發 iOS release workflow。

---

## Summary

| Task | 說明 | 預估時間 |
|------|------|---------|
| 1 | 新增 package_info_plus 依賴 | 2 min |
| 2 | 登入頁按鈕順序 | 2 min |
| 3 | 移除測試帳號 | 2 min |
| 4 | 新增法律聲明 | 5 min |
| 5 | 帳號顯示邏輯 | 5 min |
| 6 | 刪除匯出功能 | 2 min |
| 7 | 法律連結開網頁 | 5 min |
| 8 | 意見回饋開 Telegram | 2 min |
| 9 | 版本號動態顯示 | 5 min |
| 10 | 完整測試驗證 | 10 min |
| **Total** | | **~40 min** |
