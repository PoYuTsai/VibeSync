# 上架前準備 - 登入頁與設定頁優化設計

**建立日期：** 2026-03-15
**狀態：** 待實作
**TestFlight 版本：** v41

---

## 1. 背景與目標

### 1.1 背景
VibeSync 已完成核心功能開發，目前 TestFlight v41 正在進行伙伴測試。為了準備正式上架 App Store，需要進行以下優化：
- 移除開發階段的測試資訊
- 完善法律聲明與隱私權政策連結
- 優化設定頁面內容
- 參考 Claude app 的登入頁設計

### 1.2 目標
- 登入頁達到上架標準（移除測試帳號、加法律聲明）
- 設定頁功能完整（法律連結可用、版本號正確）
- 用戶體驗一致（參考 Claude app 風格）

### 1.3 非目標
- 不改變現有 Email + 密碼登入流程
- 不實作 Magic Link 登入
- 不進行大幅 UI 重構

---

## 2. 設計決策

### 2.1 登入頁社群登入順序
**決定：** Google → Apple（與 Claude app 一致）

**理由：**
- Google 帳號更通用（跨平台）
- 未來 Android 版也適用
- Apple 審核只要求提供 Apple Sign In，沒規定順序

### 2.2 Email 表單
**決定：** 保留現有 Email + 密碼表單

**理由：**
- 90% 用戶會選社群登入，Email 是備用選項
- 不需為備用選項大改架構
- 維持現有穩定流程

### 2.3 設定頁帳號顯示
**決定：** 組合顯示

| 登入方式 | 顯示內容 |
|---------|---------|
| Google | 用戶 email（如 `eric@gmail.com`）|
| Apple | 「Apple 帳號」或用戶名稱（如有）|
| Email | 用戶 email |

**理由：**
- Apple relay email 對用戶無意義
- 後台數據不受影響（仍存 relay email）
- 用戶能清楚識別登入方式

### 2.4 法律頁面
**決定：** 外部網頁（vibesyncai.app）

**網址：**
- 隱私權政策：`https://vibesyncai.app/privacy`
- 使用條款：`https://vibesyncai.app/terms`

**分工：**
- 夥伴負責在官網建立頁面
- 內容來源：`docs/legal/privacy-policy.md` 和 `terms-of-service.md`

### 2.5 匯出資料功能
**決定：** 刪除

**理由：**
- 對話資料本來就存在用戶手機本地
- MVP 不需要額外匯出功能

---

## 3. 登入頁設計

### 3.1 變更項目

| 變更 | 現狀 | 改成 |
|------|------|------|
| 社群登入順序 | Apple → Google | Google → Apple |
| 沙盒測試帳號區塊 | 顯示 | 移除 |
| 法律聲明 | 無 | 底部加上 |

### 3.2 法律聲明設計

**文字：**
```
繼續即表示您同意 使用條款 並確認已閱讀 隱私權政策
```

**規格：**
- 位置：註冊/登入切換按鈕下方
- 字體：`AppTypography.caption`
- 顏色：`AppColors.onBackgroundSecondary`
- 連結樣式：底線、可點擊
- 連結行為：用 `url_launcher` 開啟外部瀏覽器

### 3.3 檔案
`lib/features/auth/presentation/screens/login_screen.dart`

---

## 4. 設定頁設計

### 4.1 變更項目

| 區塊 | 項目 | 動作 |
|------|------|------|
| 帳戶 | 帳號 | 改顯示邏輯 |
| 隱私與安全 | 匯出我的資料 | 刪除 |
| 隱私與安全 | 隱私權政策 | 改成開網頁 |
| 關於 | 版本 | 動態顯示 |
| 關於 | 使用條款 | 改成開網頁 |
| 關於 | 意見回饋 | 改成開 Telegram |

### 4.2 帳號顯示邏輯

```dart
String getAccountDisplay(User? user) {
  if (user == null) return '未登入';

  // 檢查登入提供者
  final provider = user.appMetadata['provider'];

  if (provider == 'apple') {
    // Apple 用戶：優先顯示名稱，沒有則顯示「Apple 帳號」
    final name = user.userMetadata?['full_name'] ??
                 user.userMetadata?['name'];
    return name ?? 'Apple 帳號';
  }

  // Google / Email 用戶：顯示 email
  return user.email ?? '未知帳號';
}
```

### 4.3 連結網址

| 項目 | 網址 |
|------|------|
| 隱私權政策 | `https://vibesyncai.app/privacy` |
| 使用條款 | `https://vibesyncai.app/terms` |
| 意見回饋 | `https://t.me/vibesync_feedback_bot` |

### 4.4 動態版本號

**套件：** `package_info_plus`

**顯示格式：** `1.0.0 (41)`（版本號 + build number）

**實作：**
```dart
final packageInfo = await PackageInfo.fromPlatform();
final version = '${packageInfo.version} (${packageInfo.buildNumber})';
```

### 4.5 檔案
`lib/features/subscription/presentation/screens/settings_screen.dart`

---

## 5. 技術規格

### 5.1 新增依賴

| 套件 | 版本 | 用途 |
|------|------|------|
| `package_info_plus` | ^8.0.0 | 讀取 App 版本號 |

**註：** `url_launcher` 已安裝，無需新增。

### 5.2 檔案變更清單

| 檔案 | 動作 |
|------|------|
| `pubspec.yaml` | 新增 `package_info_plus` |
| `lib/features/auth/presentation/screens/login_screen.dart` | 登入頁改動 |
| `lib/features/subscription/presentation/screens/settings_screen.dart` | 設定頁改動 |

---

## 6. 實作任務

| # | 任務 | 檔案 |
|---|------|------|
| 1 | 新增 `package_info_plus` 依賴 | `pubspec.yaml` |
| 2 | 登入頁：調整按鈕順序（Google → Apple） | `login_screen.dart` |
| 3 | 登入頁：移除沙盒測試帳號區塊 | `login_screen.dart` |
| 4 | 登入頁：新增法律聲明 | `login_screen.dart` |
| 5 | 設定頁：改帳號顯示邏輯 | `settings_screen.dart` |
| 6 | 設定頁：刪除「匯出我的資料」 | `settings_screen.dart` |
| 7 | 設定頁：隱私權政策改開網頁 | `settings_screen.dart` |
| 8 | 設定頁：使用條款改開網頁 | `settings_screen.dart` |
| 9 | 設定頁：意見回饋改開 Telegram | `settings_screen.dart` |
| 10 | 設定頁：版本號動態顯示 | `settings_screen.dart` |

---

## 7. 測試計畫

### 7.1 登入頁測試
- [ ] Google 登入按鈕在 Apple 按鈕上方
- [ ] 沙盒測試帳號區塊已移除
- [ ] 法律聲明顯示正確
- [ ] 點擊「使用條款」開啟正確網頁
- [ ] 點擊「隱私權政策」開啟正確網頁
- [ ] Email + 密碼登入仍正常運作

### 7.2 設定頁測試
- [ ] Google 登入用戶顯示 email
- [ ] Apple 登入用戶顯示「Apple 帳號」或名稱
- [ ] 「匯出我的資料」已移除
- [ ] 點擊「隱私權政策」開啟正確網頁
- [ ] 點擊「使用條款」開啟正確網頁
- [ ] 點擊「意見回饋」開啟 Telegram
- [ ] 版本號動態顯示正確（格式：1.0.0 (XX)）

---

## 8. 上架前準備（另案處理）

以下項目不在本次範圍，需另行處理：

| 項目 | 狀態 |
|------|------|
| App 圖示 | 待確認 |
| 啟動畫面 (Splash Screen) | 待確認 |
| App Store 截圖 | 待準備 |
| App Store 描述文案 | 待撰寫 |
| App 顯示名稱 | 待確認 |

---

## 9. 相關文件

- 隱私權政策：`docs/legal/privacy-policy.md`
- 使用條款：`docs/legal/terms-of-service.md`
- UI 重構設計：`docs/plans/2026-03-10-ui-redesign-design.md`
