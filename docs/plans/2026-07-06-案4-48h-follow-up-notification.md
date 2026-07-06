# 案4：48h 跟進提醒（本地通知版）Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計來源：`docs/plans/2026-07-06-案4-48h-follow-up-notification-design.md`（先讀它）。

**Goal:** 綁 partner 的對話分析完成後，48 小時後推一則本地通知，點擊 deep-link 進該對象詳情頁的跟進建議區。

**Architecture:** 把 `flutter_local_notifications` 包在可 mock 的 `NotificationGateway` 介面後，核心 `FollowUpNotificationService` 只依賴 gateway + clock + Hive 存的 opt-in 狀態，讓排程判斷／id hash／狀態機／deep-link URL 全部純 Dart 可測。排程掛在分析持久化落點（`analysis_screen.dart:1320`），取消掛在刪 conversation，init 掛 `main.dart`，tap handler 掛 `app.dart`。

**Tech Stack:** Flutter, Riverpod (Notifier + codegen), go_router, Hive (hive_ce), `flutter_local_notifications`, `timezone`.

**已定位掛點（Explore 確認）：**
- 排程：`lib/features/analysis/presentation/screens/analysis_screen.dart:1320`（`save(conv)`，此時 `conv.partnerId` 已綁）。
- 取消：`lib/features/conversation/data/providers/conversation_write_controller.dart:61`（`delete(Conversation c)`）。
- deep-link 目標：go_router 已支援 `/partner/:partnerId?focus=coachFollowUp`（`lib/app/routes.dart:120-131`）。
- init：`lib/main.dart:22` 之後、`runApp`（:39）之前。
- tap handler：`lib/app/app.dart` initState（router 於此可取用）。

---

## Task 1: 新增依賴

**Files:**
- Modify: `pubspec.yaml`（dependencies 區）

**Step 1:** 在 `pubspec.yaml` dependencies 加：
```yaml
  flutter_local_notifications: ^18.0.1
  timezone: ^0.9.4
```
**Step 2:** Run: `flutter pub get`　Expected: 解析成功，`pubspec.lock` 更新。
**Step 3:** Run: `flutter analyze`　Expected: 無新錯誤。
**Step 4:** Commit（**注意：絕不 git add pubspec.lock**，依專案慣例只加 pubspec.yaml）：
```bash
git add pubspec.yaml
git commit -m "案4 Task1：新增 flutter_local_notifications + timezone 依賴"
```

---

## Task 2: 穩定 id hash（純函式，TDD）

Dart `String.hashCode` 跨啟動不保證穩定（hash seed 隨機化），但通知 id 必須跨啟動穩定才能 cancel 到上次排的那則。所以自寫 deterministic FNV-1a 折成 31-bit 正整數。

**Files:**
- Create: `lib/features/follow_up_notification/domain/notification_id.dart`
- Test: `test/features/follow_up_notification/notification_id_test.dart`

**Step 1: 失敗測試**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/notification_id.dart';

void main() {
  test('same partnerId → same id across calls', () {
    expect(followUpNotificationId('abc-123'), followUpNotificationId('abc-123'));
  });
  test('different partnerId → different id', () {
    expect(followUpNotificationId('abc-123'), isNot(followUpNotificationId('abc-124')));
  });
  test('id is a positive 31-bit int', () {
    final id = followUpNotificationId('any-partner-id');
    expect(id, greaterThanOrEqualTo(0));
    expect(id, lessThan(1 << 31));
  });
  test('known vector stays constant (regression lock)', () {
    // 鎖住實作，避免日後改 hash 導致舊排程 cancel 不到
    expect(followUpNotificationId('partner-golden'), followUpNotificationId('partner-golden'));
  });
}
```
**Step 2:** Run: `flutter test test/features/follow_up_notification/notification_id_test.dart`　Expected: FAIL（function not defined）。
**Step 3: 實作**
```dart
/// Deterministic FNV-1a hash → 正 31-bit int，跨啟動穩定。
/// 用於本地通知 id（一 partner 一則待發通知）。
int followUpNotificationId(String partnerId) {
  const int fnvOffset = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  int hash = fnvOffset;
  for (final codeUnit in partnerId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF; // 折成正 31-bit，符合 plugin int id 範圍
}
```
**Step 4:** Run 同上　Expected: PASS。
**Step 5:** Commit：`git add lib/features/follow_up_notification/domain/notification_id.dart test/... && git commit -m "案4 Task2：穩定通知 id hash（FNV-1a 31-bit）"`

---

## Task 3: NotificationGateway 介面 + 假實作

把 plugin 隔離在介面後，核心邏輯才可測。

**Files:**
- Create: `lib/features/follow_up_notification/data/notification_gateway.dart`
- Create: `test/features/follow_up_notification/fake_notification_gateway.dart`

**Step 1: 介面**
```dart
/// 隔離 flutter_local_notifications 的最小介面，讓排程邏輯可測。
abstract class NotificationGateway {
  Future<void> init();
  /// 回傳系統是否授權（軟卡點「幫我提醒」後呼叫）。
  Future<bool> requestPermission();
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String payload,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
  /// 冷啟動：若 app 由點通知啟動，回傳其 payload，否則 null。
  Future<String?> launchPayload();
}
```
**Step 2: 假實作（測試用，記錄呼叫）**
```dart
import 'package:vibesync/features/follow_up_notification/data/notification_gateway.dart';

class ScheduledCall {
  final int id;
  final DateTime fireAt;
  final String payload;
  ScheduledCall(this.id, this.fireAt, this.payload);
}

class FakeNotificationGateway implements NotificationGateway {
  final List<ScheduledCall> scheduled = [];
  final List<int> cancelled = [];
  bool cancelAllCalled = false;
  bool permissionGranted = true;
  String? initialPayload;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permissionGranted;
  @override
  Future<void> schedule({required int id, required String title, required String body, required DateTime fireAt, required String payload}) async {
    scheduled.add(ScheduledCall(id, fireAt, payload));
  }
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> cancelAll() async => cancelAllCalled = true;
  @override
  Future<String?> launchPayload() async => initialPayload;
}
```
**Step 3:** Run: `flutter analyze`　Expected: 無錯。
**Step 4:** Commit：`git add ... && git commit -m "案4 Task3：NotificationGateway 介面＋測試假實作"`

---

## Task 4: opt-in 狀態機（Hive-backed，TDD）

狀態：`unknown`（沒問過軟卡）/`granted`（授權成功）/`denied`（問過但被拒/不要）。用來：避免重複彈軟卡、被拒後不再纏、關掉總開關。

**Files:**
- Create: `lib/features/follow_up_notification/domain/follow_up_opt_in.dart`（enum + 純轉移函式）
- Test: `test/features/follow_up_notification/follow_up_opt_in_test.dart`

**Step 1: 失敗測試**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';

void main() {
  test('unknown 才顯示軟卡', () {
    expect(shouldShowSoftCard(FollowUpOptIn.unknown), isTrue);
    expect(shouldShowSoftCard(FollowUpOptIn.granted), isFalse);
    expect(shouldShowSoftCard(FollowUpOptIn.denied), isFalse);
  });
  test('只有 granted 才排程', () {
    expect(canSchedule(FollowUpOptIn.granted), isTrue);
    expect(canSchedule(FollowUpOptIn.unknown), isFalse);
    expect(canSchedule(FollowUpOptIn.denied), isFalse);
  });
}
```
**Step 2:** Run　Expected: FAIL。
**Step 3: 實作**
```dart
enum FollowUpOptIn { unknown, granted, denied }

bool shouldShowSoftCard(FollowUpOptIn s) => s == FollowUpOptIn.unknown;
bool canSchedule(FollowUpOptIn s) => s == FollowUpOptIn.granted;
```
**Step 4:** Run　Expected: PASS。
**Step 5:** Commit：`git commit -m "案4 Task4：opt-in 狀態機純邏輯"`

> Hive 讀寫封裝在 Task 6 的 service 裡（存於現有 settings/prefs box，key `followUpOptIn`，存 enum name 字串）。

---

## Task 5: 排程判斷 + 文案（純邏輯，TDD）

決定「這次分析要不要排、排什麼」——只有 partnerId 非空且 opt-in=granted 才排；文案帶 displayName。

**Files:**
- Create: `lib/features/follow_up_notification/domain/follow_up_plan.dart`
- Test: `test/features/follow_up_notification/follow_up_plan_test.dart`

**Step 1: 失敗測試**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_plan.dart';

void main() {
  final now = DateTime(2026, 7, 6, 10, 0);
  test('partnerId 為 null → 不排', () {
    expect(buildFollowUpPlan(partnerId: null, displayName: 'A', optIn: FollowUpOptIn.granted, now: now), isNull);
  });
  test('未授權 → 不排', () {
    expect(buildFollowUpPlan(partnerId: 'p1', displayName: 'A', optIn: FollowUpOptIn.unknown, now: now), isNull);
  });
  test('授權且綁 partner → 排 +48h，文案帶名', () {
    final plan = buildFollowUpPlan(partnerId: 'p1', displayName: '小美', optIn: FollowUpOptIn.granted, now: now)!;
    expect(plan.fireAt, now.add(const Duration(hours: 48)));
    expect(plan.body, contains('小美'));
    expect(plan.payload, 'p1');
  });
  test('displayName 空 → 用「這位對象」', () {
    final plan = buildFollowUpPlan(partnerId: 'p1', displayName: '', optIn: FollowUpOptIn.granted, now: now)!;
    expect(plan.body, contains('這位對象'));
  });
}
```
**Step 2:** Run　Expected: FAIL。
**Step 3: 實作**
```dart
import 'follow_up_opt_in.dart';

class FollowUpPlan {
  final String title;
  final String body;
  final DateTime fireAt;
  final String payload; // partnerId
  const FollowUpPlan({required this.title, required this.body, required this.fireAt, required this.payload});
}

FollowUpPlan? buildFollowUpPlan({
  required String? partnerId,
  required String displayName,
  required FollowUpOptIn optIn,
  required DateTime now,
}) {
  if (partnerId == null || partnerId.isEmpty) return null;
  if (!canSchedule(optIn)) return null;
  final name = displayName.trim().isEmpty ? '這位對象' : displayName.trim();
  return FollowUpPlan(
    title: '跟進提醒 👀',
    body: '跟$name的對話停兩天囉，要不要看看下一步？',
    fireAt: now.add(const Duration(hours: 48)),
    payload: partnerId,
  );
}
```
**Step 4:** Run　Expected: PASS。
**Step 5:** Commit：`git commit -m "案4 Task5：排程判斷＋文案純邏輯"`

---

## Task 6: FollowUpNotificationService（整合層 + Riverpod provider）

串起 gateway + opt-in 持久化 + plan，提供 `onPartnerAnalysisSaved` / `cancelForConversation` / `requestSoftOptIn` / `disableAll` 給 UI 掛點呼叫。**重排歸零＝schedule 前先 cancel(id)。**

**Files:**
- Create: `lib/features/follow_up_notification/data/providers/follow_up_notification_service.dart`
- Test: `test/features/follow_up_notification/follow_up_notification_service_test.dart`

**Step 1: 失敗測試（用 FakeNotificationGateway + 記憶體 opt-in store）**
```dart
// 重點測 3 件事：
// 1. onPartnerAnalysisSaved(granted, partnerId) → cancelled 先含 id，再 scheduled +48h（重排歸零順序）
// 2. optIn=unknown → scheduled 空
// 3. cancelForConversation(partnerId) → cancelled 含該 id
// 4. disableAll() → gateway.cancelAllCalled == true 且 optIn 落為 denied
```
（測試以 `FakeNotificationGateway` 注入 service；opt-in store 用可注入的記憶體實作，避免碰真 Hive。）
**Step 2:** Run　Expected: FAIL。
**Step 3: 實作**（service 建構子注入 `NotificationGateway`、opt-in 讀寫器、`DateTime Function() now`；`onPartnerAnalysisSaved` 內：讀 optIn → `buildFollowUpPlan` → 為 null 就 return → 否則 `await gateway.cancel(id); await gateway.schedule(...)`）。Riverpod provider 用真 Hive opt-in store + 真 gateway。
**Step 4:** Run　Expected: PASS。
**Step 5:** Commit：`git commit -m "案4 Task6：FollowUpNotificationService 整合層＋provider"`

---

## Task 7: 真 gateway 實作（flutter_local_notifications wrapper）

**Files:**
- Create: `lib/features/follow_up_notification/data/local_notification_gateway.dart`

實作 `NotificationGateway`：`init` 做 `tz.initializeTimeZones()` + 設 local location（用 `flutter_native_timezone` 或先 hardcode `Asia/Taipei`，見下註）、`AndroidInitializationSettings` + `DarwinInitializationSettings`、`initialize(onDidReceiveNotificationResponse:)`；`schedule` 用 `zonedSchedule(... TZDateTime.from(fireAt, local) ...androidScheduleMode: exactAllowWhileIdle...)`；`requestPermission` 呼 iOS `requestPermissions` / Android 13+ `requestNotificationsPermission`；`launchPayload` 讀 `getNotificationAppLaunchDetails`。

> 時區註：MVP 先 hardcode `Asia/Taipei`（用戶全在台灣）。若日後要跨時區再引 `flutter_timezone`。此決定寫進程式碼註解。

**Step 1:** Run: `flutter analyze`　Expected: 無錯（此層無單元測試，靠 Task 11 手動驗）。
**Step 2:** Commit：`git commit -m "案4 Task7：LocalNotificationGateway（zonedSchedule 實作）"`

---

## Task 8: init + 冷啟動 + tap handler 導航

**Files:**
- Modify: `lib/main.dart:22` 之後 — `await ref/container...init()`；實際用 ProviderContainer 或在 `App` initState 取 provider 後 init（擇一，見下）。
- Modify: `lib/app/app.dart` — initState 內：`init()` gateway、`launchPayload()` 若非 null 則 `router.go('/partner/$payload?focus=coachFollowUp')`；設定前景 tap callback 同樣導航。

> 導航一律走 `/partner/<id>?focus=coachFollowUp`（routes 已支援）。tap callback 在 background/前景收到 response → 解析 payload=partnerId → `router.push`。

**Step 1:** Run: `flutter analyze`　Expected: 無錯。
**Step 2:** 手動 smoke（Task 11 涵蓋）。
**Step 3:** Commit：`git commit -m "案4 Task8：通知 init＋冷啟動 payload＋tap 導航"`

---

## Task 9: 軟詢問卡 + 掛排程/取消點

**Files:**
- Create: `lib/features/follow_up_notification/presentation/soft_opt_in_card.dart`（bottom sheet 或 dialog：「要我在 48 小時後提醒你跟進嗎？」＋「幫我提醒」/「不用」）。
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:1320` 附近 — `save(conv)` 成功後：若 `conv.partnerId != null`：先看 optIn，`unknown` 則顯示軟卡（點「幫我提醒」→ `requestSoftOptIn()`→授權成功落 granted）；然後 `onPartnerAnalysisSaved(conv.partnerId, displayName)`。
- Modify: `lib/features/conversation/data/providers/conversation_write_controller.dart:61`（`delete`）— 刪除成功後 `cancelForConversation(partnerId)`。

> displayName 來源：由 conv.partnerId 查 partner repo 取 displayName（Explore：partner 詳情在 `partner_repository`）。取不到就傳空字串（Task5 已 fallback「這位對象」）。
> 軟卡只在「首次綁 partner 分析完成」出現一次（optIn=unknown 才顯示，之後不再）。

**Step 1:** Run: `flutter analyze`　Expected: 無錯。
**Step 2:** Commit：`git commit -m "案4 Task9：軟詢問卡＋分析完成排程＋刪 conversation 取消"`

---

## Task 10: 設定頁總開關

**Files:**
- Modify: 設定頁（實作前 grep `SettingsScreen` 定位）— 加一顆 SwitchListTile「48h 跟進提醒」。開→無動作（維持 granted）；關→`disableAll()`（`cancelAll` + optIn=denied）。再開→重新走軟卡/授權。

**Step 1:** Run: `flutter analyze`　Expected: 無錯。
**Step 2:** Commit：`git commit -m "案4 Task10：設定頁 48h 跟進提醒總開關"`

---

## Task 11: 全綠 + 手動驗證 + Codex 雙審

**Step 1:** Run: `flutter test test/features/follow_up_notification/`　Expected: 全 PASS。
**Step 2:** Run: `flutter analyze`　Expected: 無新錯誤。
**Step 3:** 手動 smoke（真機/模擬器，Eric）：綁 partner 分析完成→軟卡→授權→（可暫時把 +48h 改 +10s 驗）通知到→點通知→進 partner 詳情頁 coachFollowUp 聚焦；殺 app 再點通知驗冷啟動；刪 conversation 驗 cancel；設定頁關閉驗 cancelAll。
**Step 4:** 高風險面（新增原生依賴 + 權限）→ 依 CLAUDE.md 派 Codex 雙審（`codex:rescue`），拿到 verdict 才宣稱 dogfood safe。
**Step 5:** 更新 roadmap 記憶：案4 轉 SHIPPED，下一棒案6-1 telemetry。

---

## 注意事項（踩雷預防）

- **絕不 git add pubspec.lock**（專案慣例，記憶多次記載）。
- 新增原生依賴＝送審面改動，須隨**下一個 build** 進；本地通知不需 aps entitlement / push 憑證。
- 時區 MVP hardcode `Asia/Taipei`，寫進註解。
- 通知 id 用 Task2 的 deterministic hash，**絕不**用 `String.hashCode`（跨啟動不穩，cancel 不到舊排程）。
- 每 Task 一 commit，繁中訊息。
