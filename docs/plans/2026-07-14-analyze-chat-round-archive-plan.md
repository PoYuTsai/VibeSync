# analyze-chat 分輪封存重設計 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 analyze-chat 從「無限疊加的長逐字稿 + 埋在底部的最新輪」改成「主畫面只顯示當前這一輪、舊輪 FIFO 封存 5 輪/對象、每輪只餵當輪片段 + 對象耐久資料給模型」。

**Architecture:** 客戶端為主。以 Hive `settingsBox`（動態 Map、免 build_runner、免新 adapter）存兩樣東西：(a) **每對象**（partnerId，legacy null 降級 conversationId）的 FIFO 5 輪封存清單；(b) **每對話**的 round cursor（記錄「當前輪起點 message index」，抗 FIFO 淘汰）。分析完成時，最新一輪照舊覆寫 conversation 級快照（`lastAnalysisSnapshotJson`/`lastEnthusiasmScore`，餵 partnerSummary 聚合），同時把被頂掉的上一輪凍結進封存盒。主畫面只渲染 `messages.sublist(currentRoundStart)`。模型輸入縮減（只送當輪片段）獨立為高風險 Phase E。

**Tech Stack:** Flutter 3.x / Riverpod / Hive（AES）；Supabase Edge Function `analyze-chat`（Deno）；`flutter test` 用真 Hive（`Hive.init` + `openBox<dynamic>`）。

**現況核對來源（開工前必讀）：** `docs/plans/2026-07-14-analyze-chat-round-archive-current-state.md`（六題附行號）與需求定案 `docs/plans/2026-07-14-analyze-chat-round-archive-design.md`。

---

## 全域約束（每個 Task 都適用）

- **絕不 build_runner**：不新增 Hive `@HiveField`、不新增 typeId adapter。所有新持久資料走 `StorageService.settingsBox`（`Box<dynamic>`，`lib/core/services/storage_service.dart:196`）以 JSON string 存。
- **絕不 `git add pubspec.lock`**（記憶鐵則）。
- **fail-open**：所有讀封存的路徑，box 未開／壞資料一律回空，**絕不**因封存壞掉而擋住主流程（比照 `HiveConversationArchiveStore.entryFor` `lib/features/conversation/data/repositories/conversation_archive_store.dart:71-100`）。
- **owner-scope key**：key 一律含 `ownerUserId`（legacy 空→`_legacy`），比照現有 `_keyFor` `conversation_archive_store.dart:148-152`。
- **TDD**：每個 Task 先寫失敗測試 → 跑到失敗 → 最小實作 → 跑到綠 → commit。一 commit 一 concern，繁中 commit message。
- **Phase E 是高風險區**（AI prompt/token/cost）：改動前後**必**量測 token，**必** Codex 雙審才可宣稱 dogfood safe。Phase A–D 不改模型輸入，風險低。
- **參考測試範式**：`test/unit/features/conversation/data/repositories/conversation_archive_store_test.dart`（真 Hive：`Hive.init('./.dart_tool/test_hive_xxx')` + `openBox<dynamic>('name_$timestamp')` + 注入 `() => box`，`tearDown` `box.deleteFromDisk()`）。

---

## Phase A — 封存資料層（model + store，純 Dart，可離線 TDD）

### Task A1: `AnalysisRoundSnapshot` model（含自訂 JSON 序列化）

`Message` **沒有** toJson/fromJson（`lib/features/conversation/domain/entities/message.dart:6-37` 只有 Hive 註記），封存要存 JSON 必須自訂，覆蓋全部 7 欄。

**Files:**
- Create: `lib/features/analysis_history/domain/entities/analysis_round_snapshot.dart`
- Test: `test/unit/features/analysis_history/domain/entities/analysis_round_snapshot_test.dart`

**Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_round_snapshot.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  test('round snapshot survives JSON round-trip incl. all message fields', () {
    final snap = AnalysisRoundSnapshot(
      roundId: 'r-1',
      conversationId: 'c-1',
      roundIndex: 2,
      createdAt: DateTime.utc(2026, 7, 14, 8, 30),
      startIndex: 3,
      endIndex: 5,
      enthusiasmScore: 72,
      rawResponseJson: '{"recommendation":{"text":"hi"}}',
      messages: [
        Message(
          id: 'm-3', content: '在幹嘛', isFromMe: false,
          timestamp: DateTime.utc(2026, 7, 14, 8, 0),
          enthusiasmScore: 60, quotedReplyPreview: '上一句',
          quotedReplyPreviewIsFromMe: true,
        ),
        Message(
          id: 'm-4', content: '想你', isFromMe: true,
          timestamp: DateTime.utc(2026, 7, 14, 8, 1),
        ),
      ],
    );

    final decoded = AnalysisRoundSnapshot.fromJson(snap.toJson());

    expect(decoded.roundId, 'r-1');
    expect(decoded.conversationId, 'c-1');
    expect(decoded.roundIndex, 2);
    expect(decoded.createdAt, snap.createdAt);
    expect(decoded.startIndex, 3);
    expect(decoded.endIndex, 5);
    expect(decoded.enthusiasmScore, 72);
    expect(decoded.rawResponseJson, '{"recommendation":{"text":"hi"}}');
    expect(decoded.messages.length, 2);
    expect(decoded.messages[0].id, 'm-3');
    expect(decoded.messages[0].content, '在幹嘛');
    expect(decoded.messages[0].isFromMe, false);
    expect(decoded.messages[0].timestamp, DateTime.utc(2026, 7, 14, 8, 0));
    expect(decoded.messages[0].enthusiasmScore, 60);
    expect(decoded.messages[0].quotedReplyPreview, '上一句');
    expect(decoded.messages[0].quotedReplyPreviewIsFromMe, true);
    expect(decoded.messages[1].isFromMe, true);
    expect(decoded.messages[1].quotedReplyPreview, isNull);
  });

  test('fromJson tolerates missing optional fields', () {
    final json = {
      'roundId': 'r-x', 'conversationId': 'c-x', 'roundIndex': 1,
      'createdAt': '2026-07-14T00:00:00.000Z',
      'startIndex': 0, 'endIndex': 1, 'messages': <dynamic>[
        {'id': 'm', 'content': 'hi', 'isFromMe': false, 'timestamp': '2026-07-14T00:00:00.000Z'},
      ],
    };
    final decoded = AnalysisRoundSnapshot.fromJson(json);
    expect(decoded.enthusiasmScore, isNull);
    expect(decoded.rawResponseJson, isNull);
    expect(decoded.messages.single.enthusiasmScore, isNull);
  });
}
```

**Step 2: 跑到失敗**

Run: `flutter test test/unit/features/analysis_history/domain/entities/analysis_round_snapshot_test.dart`
Expected: FAIL（`analysis_round_snapshot.dart` 不存在）。

**Step 3: 最小實作**

```dart
import 'package:vibesync/features/conversation/domain/entities/message.dart';

/// 一輪 analyze-chat 分析的離散封存體：當輪 OCR 片段 + 當時 AI 原始回應快照。
/// 存進 Hive settingsBox（JSON），故所有序列化自帶（Message 無內建 JSON）。
class AnalysisRoundSnapshot {
  const AnalysisRoundSnapshot({
    required this.roundId,
    required this.conversationId,
    required this.roundIndex,
    required this.createdAt,
    required this.startIndex,
    required this.endIndex,
    required this.messages,
    this.enthusiasmScore,
    this.rawResponseJson,
  });

  final String roundId;
  final String conversationId;
  final int roundIndex;
  final DateTime createdAt;
  final int startIndex; // 這一輪涵蓋 conversation.messages 的 [startIndex, endIndex)
  final int endIndex;
  final List<Message> messages; // 當輪片段（凍結副本）
  final int? enthusiasmScore; // 當輪熱度（顯示用）
  final String? rawResponseJson; // 當時 AI rawResponse 的 jsonEncode（重建建議卡用）

  Map<String, dynamic> toJson() => {
        'roundId': roundId,
        'conversationId': conversationId,
        'roundIndex': roundIndex,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'startIndex': startIndex,
        'endIndex': endIndex,
        if (enthusiasmScore != null) 'enthusiasmScore': enthusiasmScore,
        if (rawResponseJson != null) 'rawResponseJson': rawResponseJson,
        'messages': messages.map(_encodeMessage).toList(),
      };

  static AnalysisRoundSnapshot fromJson(Map<dynamic, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? const []);
    return AnalysisRoundSnapshot(
      roundId: json['roundId'] as String,
      conversationId: json['conversationId'] as String,
      roundIndex: (json['roundIndex'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      startIndex: (json['startIndex'] as num).toInt(),
      endIndex: (json['endIndex'] as num).toInt(),
      enthusiasmScore: (json['enthusiasmScore'] as num?)?.toInt(),
      rawResponseJson: json['rawResponseJson'] as String?,
      messages: rawMessages
          .map((e) => _decodeMessage((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  static Map<String, dynamic> _encodeMessage(Message m) => {
        'id': m.id,
        'content': m.content,
        'isFromMe': m.isFromMe,
        'timestamp': m.timestamp.toUtc().toIso8601String(),
        if (m.enthusiasmScore != null) 'enthusiasmScore': m.enthusiasmScore,
        if (m.quotedReplyPreview != null) 'quotedReplyPreview': m.quotedReplyPreview,
        if (m.quotedReplyPreviewIsFromMe != null)
          'quotedReplyPreviewIsFromMe': m.quotedReplyPreviewIsFromMe,
      };

  static Message _decodeMessage(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        content: j['content'] as String,
        isFromMe: j['isFromMe'] as bool,
        timestamp: DateTime.parse(j['timestamp'] as String),
        enthusiasmScore: (j['enthusiasmScore'] as num?)?.toInt(),
        quotedReplyPreview: j['quotedReplyPreview'] as String?,
        quotedReplyPreviewIsFromMe: j['quotedReplyPreviewIsFromMe'] as bool?,
      );
}
```

**Step 4: 跑到綠**

Run: `flutter test test/unit/features/analysis_history/domain/entities/analysis_round_snapshot_test.dart`
Expected: PASS（2 tests）。

**Step 5: Commit**

```bash
git add lib/features/analysis_history/domain/entities/analysis_round_snapshot.dart test/unit/features/analysis_history/domain/entities/analysis_round_snapshot_test.dart
git commit -m "新增 analyze-chat 分輪封存體 model 與自訂 JSON 序列化"
```

---

### Task A2: `AnalysisRoundArchiveStore`（每對象 FIFO 5 + 每對話 cursor）

比照 `HiveConversationArchiveStore` 的注入式 box provider（`() => Box`）與 fail-open 風格。用 `settingsBox`，value 存 **JSON string**（不用 Map，因為要存 list + 巢狀）。

**Key 設計：**
- 封存清單 key：`analysis_round_archive_v1:<ownerScope>:<partnerKey>` → JSON array（最多 5 個 round，尾端最新）。
- `partnerKey` = `conversation.partnerId`（非空 trim 後）否則 `conv:<conversation.id>`（legacy null 降級，避免全撞 null 桶）。
- cursor key：`analysis_round_cursor_v1:<ownerScope>:<conversation.id>` → int（最近完成輪的 endIndex；抗 FIFO 淘汰）。

**Files:**
- Create: `lib/features/analysis_history/data/repositories/analysis_round_archive_store.dart`
- Test: `test/unit/features/analysis_history/data/repositories/analysis_round_archive_store_test.dart`

**Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vibesync/features/analysis_history/data/repositories/analysis_round_archive_store.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_round_snapshot.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Conversation _conv({required String id, String? partnerId, String? owner}) => Conversation(
      id: id,
      partnerId: partnerId,
      ownerUserId: owner,
      messages: const [],
    ); // 依實際 Conversation 建構子必填欄位補齊（見 conversation.dart）

AnalysisRoundSnapshot _round(int idx, {String convId = 'c-1'}) => AnalysisRoundSnapshot(
      roundId: 'r-$idx',
      conversationId: convId,
      roundIndex: idx,
      createdAt: DateTime.utc(2026, 7, 14, idx),
      startIndex: idx - 1,
      endIndex: idx,
      messages: [Message(id: 'm-$idx', content: 'c$idx', isFromMe: false, timestamp: DateTime.utc(2026, 7, 14, idx))],
      enthusiasmScore: idx * 10,
      rawResponseJson: '{"round":$idx}',
    );

void main() {
  late Box<dynamic> box;
  late AnalysisRoundArchiveStore store;

  setUp(() async {
    Hive.init('./.dart_tool/test_hive_round_archive');
    box = await Hive.openBox<dynamic>('round_archive_${DateTime.now().microsecondsSinceEpoch}');
    store = AnalysisRoundArchiveStore(() => box);
  });
  tearDown(() async => box.deleteFromDisk());

  test('pushRound 依對象累積，最新在尾端', () {
    final c = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');
    store.pushRound(c, _round(1));
    store.pushRound(c, _round(2));
    final rounds = store.roundsForPartner(c);
    expect(rounds.map((r) => r.roundIndex), [1, 2]);
  });

  test('每對象最多保留 5 輪，FIFO 擠掉最舊', () {
    final c = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');
    for (var i = 1; i <= 7; i++) {
      store.pushRound(c, _round(i));
    }
    final rounds = store.roundsForPartner(c);
    expect(rounds.length, 5);
    expect(rounds.map((r) => r.roundIndex), [3, 4, 5, 6, 7]);
  });

  test('封存綁對象，不同對話同 partnerId 共用一盒', () {
    final a = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');
    final b = _conv(id: 'c-2', partnerId: 'p-1', owner: 'u-1');
    store.pushRound(a, _round(1, convId: 'c-1'));
    store.pushRound(b, _round(2, convId: 'c-2'));
    expect(store.roundsForPartner(a).length, 2);
    expect(store.roundsForPartner(b).length, 2);
  });

  test('legacy partnerId==null 降級以 conversationId 分桶，彼此不撞', () {
    final a = _conv(id: 'c-1', partnerId: null, owner: 'u-1');
    final b = _conv(id: 'c-2', partnerId: null, owner: 'u-1');
    store.pushRound(a, _round(1, convId: 'c-1'));
    store.pushRound(b, _round(9, convId: 'c-2'));
    expect(store.roundsForPartner(a).map((r) => r.roundIndex), [1]);
    expect(store.roundsForPartner(b).map((r) => r.roundIndex), [9]);
  });

  test('cursor 讀寫：未設過回 0', () {
    final c = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');
    expect(store.currentRoundStart(c), 0);
    store.setCurrentRoundStart(c, 5);
    expect(store.currentRoundStart(c), 5);
  });

  test('fail-open：壞資料回空、不 throw', () async {
    final c = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');
    await box.put('analysis_round_archive_v1:u-1:p-1', 'not-json{{{');
    expect(store.roundsForPartner(c), isEmpty);
  });

  test('fail-open：box 不可用回空、不 throw', () {
    final broken = AnalysisRoundArchiveStore(() => throw HiveError('no box'));
    expect(broken.roundsForPartner(_conv(id: 'c-9', partnerId: 'p-9', owner: 'u-1')), isEmpty);
    expect(broken.currentRoundStart(_conv(id: 'c-9', partnerId: 'p-9', owner: 'u-1')), 0);
  });
}
```

**Step 2: 跑到失敗**

Run: `flutter test test/unit/features/analysis_history/data/repositories/analysis_round_archive_store_test.dart`
Expected: FAIL（store 不存在）。

**Step 3: 最小實作**

```dart
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_round_snapshot.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

/// 每對象 FIFO 5 輪封存 + 每對話 round cursor，全存 settingsBox（JSON string）。
/// fail-open：任何讀取錯誤一律回空/0，絕不擋主流程。
class AnalysisRoundArchiveStore {
  AnalysisRoundArchiveStore(this._boxProvider);

  final Box<dynamic> Function() _boxProvider;

  static const _archivePrefix = 'analysis_round_archive_v1';
  static const _cursorPrefix = 'analysis_round_cursor_v1';
  static const maxRoundsPerPartner = 5;

  static String _ownerScope(Conversation c) {
    final owner = c.ownerUserId?.trim();
    return owner == null || owner.isEmpty ? '_legacy' : owner;
  }

  static String _partnerKey(Conversation c) {
    final pid = c.partnerId?.trim();
    return pid == null || pid.isEmpty ? 'conv:${c.id}' : pid;
  }

  static String _archiveKey(Conversation c) => '$_archivePrefix:${_ownerScope(c)}:${_partnerKey(c)}';
  static String _cursorKey(Conversation c) => '$_cursorPrefix:${_ownerScope(c)}:${c.id}';

  List<AnalysisRoundSnapshot> roundsForPartner(Conversation c) {
    try {
      final raw = _boxProvider().get(_archiveKey(c));
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AnalysisRoundSnapshot.fromJson(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void pushRound(Conversation c, AnalysisRoundSnapshot round) {
    try {
      final current = List<AnalysisRoundSnapshot>.from(roundsForPartner(c))..add(round);
      final trimmed = current.length > maxRoundsPerPartner
          ? current.sublist(current.length - maxRoundsPerPartner)
          : current;
      final encoded = jsonEncode(trimmed.map((r) => r.toJson()).toList());
      _boxProvider().put(_archiveKey(c), encoded);
    } catch (_) {
      // fail-open：封存寫失敗絕不擋分析主流程
    }
  }

  int currentRoundStart(Conversation c) {
    try {
      final raw = _boxProvider().get(_cursorKey(c));
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  void setCurrentRoundStart(Conversation c, int startIndex) {
    try {
      _boxProvider().put(_cursorKey(c), startIndex);
    } catch (_) {}
  }
}
```

> 註：測試 `_conv(...)` 的 `Conversation(...)` 建構子必填欄位請對照 `lib/features/conversation/domain/entities/conversation.dart` 補齊（如 `title`/`createdAt` 等）。若建構子過重，改用專案既有 Conversation test helper。

**Step 4: 跑到綠**

Run: `flutter test test/unit/features/analysis_history/data/repositories/analysis_round_archive_store_test.dart`
Expected: PASS（8 tests）。

**Step 5: Commit**

```bash
git add lib/features/analysis_history/data/repositories/analysis_round_archive_store.dart test/unit/features/analysis_history/data/repositories/analysis_round_archive_store_test.dart
git commit -m "新增分輪封存 store：每對象 FIFO 5 輪＋每對話 cursor"
```

---

### Task A3: Riverpod provider wiring

比照 `conversation_archive_providers.dart:8-10`。

**Files:**
- Create: `lib/features/analysis_history/data/providers/analysis_round_archive_providers.dart`

**Step 1–3: 實作（無新測試，wiring 只是 tear-off）**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/analysis_history/data/repositories/analysis_round_archive_store.dart';

final analysisRoundArchiveStoreProvider = Provider<AnalysisRoundArchiveStore>(
  (_) => AnalysisRoundArchiveStore(() => StorageService.settingsBox),
);

/// UI rebuild 訊號：每次封存/cursor 變動 state++（比照 ConversationArchiveController）。
class AnalysisRoundArchiveController extends Notifier<int> {
  @override
  int build() => 0;
  void bumped() => state++;
}

final analysisRoundArchiveControllerProvider =
    NotifierProvider<AnalysisRoundArchiveController, int>(AnalysisRoundArchiveController.new);
```

**Step 4: 驗證編譯**

Run: `flutter analyze lib/features/analysis_history/data/providers/analysis_round_archive_providers.dart`
Expected: No issues。

**Step 5: Commit**

```bash
git add lib/features/analysis_history/data/providers/analysis_round_archive_providers.dart
git commit -m "接上分輪封存 store 的 Riverpod provider"
```

---

## Phase B — 分析完成時寫入封存（核心機制）

### Task B1: 分析完成 hook — 頂掉上一輪進封存盒、更新 cursor

改 `_persistLatestAnalysisSnapshot`（`lib/features/analysis/presentation/screens/analysis_screen.dart:1434-1483`）。**保留現有 conversation 級寫回**（`lastAnalysisSnapshotJson`/`lastEnthusiasmScore`/`lastAnalyzedMessageCount`，餵 partnerSummary 聚合），**新增**：在覆寫前，把「即將被頂掉的上一輪」凍結進封存盒，並更新 cursor。

**核心機制（開工前務必理解，見 current-state.md 風險 #2/#3）：**
- `prevStart = store.currentRoundStart(conv)`（上一輪起點；未設過=0）
- `prevEnd = conv.lastAnalyzedMessageCount`（**覆寫前**的舊值＝上一輪終點）
- `prevSnapshot = conv.lastAnalysisSnapshotJson`（**覆寫前**＝上一輪的 rawResponse 快照）
- 若 `prevSnapshot != null && prevEnd > prevStart`：build `AnalysisRoundSnapshot(slice = messages[prevStart..prevEnd), rawResponseJson = prevSnapshot, enthusiasmScore = 舊 lastEnthusiasmScore)` → `pushRound`。
- 之後 cursor `setCurrentRoundStart(conv, prevEnd)`（新的一輪從舊終點起算）。
- 最後照現有邏輯覆寫 conversation 級欄位。

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:1434-1483`（`_persistLatestAnalysisSnapshot`）
- Test: `test/unit/features/analysis_history/round_archiving_flow_test.dart`（抽出可測的純函式，見 Step 1）

**Step 1: 先把「頂掉上一輪」邏輯抽成可單測的純函式，寫失敗測試**

在 store 檔或新 helper 檔加一個純函式（不碰 UI），讓分析畫面呼叫：

```dart
// test：模擬三輪連續分析的 cursor 與封存推進
test('連續三輪：上一輪各自入盒、cursor 正確推進、當前輪不入盒', () {
  // 用 in-memory box + store（比照 A2 setUp）
  final c = _conv(id: 'c-1', partnerId: 'p-1', owner: 'u-1');

  // Round A：messages 0..3，首輪無上一輪可封存
  archiveCompletedRound(store, c,
      messages: _msgs(3), prevSnapshotJson: null,
      prevAnalyzedCount: 0, prevEnthusiasm: null, now: DateTime.utc(2026, 7, 14, 1),
      newRoundId: 'A');
  expect(store.roundsForPartner(c), isEmpty);        // 首輪不入盒（它是當前輪）
  expect(store.currentRoundStart(c), 0);             // 當前輪 A 起點=0

  // Round B：補到 5，封存 A=[0,3)
  archiveCompletedRound(store, c,
      messages: _msgs(5), prevSnapshotJson: '{"r":"A"}',
      prevAnalyzedCount: 3, prevEnthusiasm: 60, now: DateTime.utc(2026, 7, 14, 2),
      newRoundId: 'B');
  final afterB = store.roundsForPartner(c);
  expect(afterB.map((r) => r.roundId), ['A-round']);
  expect(afterB.single.startIndex, 0);
  expect(afterB.single.endIndex, 3);
  expect(afterB.single.rawResponseJson, '{"r":"A"}');
  expect(afterB.single.enthusiasmScore, 60);
  expect(store.currentRoundStart(c), 3);             // 當前輪 B 起點=3

  // Round C：補到 7，封存 B=[3,5)
  archiveCompletedRound(store, c,
      messages: _msgs(7), prevSnapshotJson: '{"r":"B"}',
      prevAnalyzedCount: 5, prevEnthusiasm: 72, now: DateTime.utc(2026, 7, 14, 3),
      newRoundId: 'C');
  final afterC = store.roundsForPartner(c);
  expect(afterC.map((r) => r.startIndex), [0, 3]);
  expect(afterC.map((r) => r.endIndex), [3, 5]);
  expect(store.currentRoundStart(c), 5);
});
```

**Step 3: 實作純函式**

於 `analysis_round_archive_store.dart` 加頂層函式（或另置 `round_archiving.dart`）：

```dart
/// 分析完成時呼叫：把「即將被頂掉的上一輪」凍結進封存盒並推進 cursor。
/// 只負責封存側；conversation 級快照覆寫仍由呼叫端（analysis_screen）保留現狀。
void archiveCompletedRound(
  AnalysisRoundArchiveStore store,
  Conversation conversation, {
  required List<Message> messages,
  required String? prevSnapshotJson,
  required int prevAnalyzedCount,
  required int? prevEnthusiasm,
  required DateTime now,
  required String newRoundId,
}) {
  final prevStart = store.currentRoundStart(conversation);
  final prevEnd = prevAnalyzedCount;
  if (prevSnapshotJson != null && prevEnd > prevStart && prevEnd <= messages.length) {
    final existing = store.roundsForPartner(conversation);
    store.pushRound(
      conversation,
      AnalysisRoundSnapshot(
        roundId: '${conversation.id}-${existing.length + 1}',
        conversationId: conversation.id,
        roundIndex: existing.length + 1,
        createdAt: now,
        startIndex: prevStart,
        endIndex: prevEnd,
        messages: messages.sublist(prevStart, prevEnd),
        enthusiasmScore: prevEnthusiasm,
        rawResponseJson: prevSnapshotJson,
      ),
    );
  }
  store.setCurrentRoundStart(conversation, prevEnd);
}
```

> 註：測試 assert 的 `roundId`/`roundIndex` 依實作規則對齊（上例用 `${conv.id}-N`；請讓測試與實作一致，勿兩邊各寫各的）。

**Step 4: 跑到綠**

Run: `flutter test test/unit/features/analysis_history/round_archiving_flow_test.dart`
Expected: PASS。

**Step 5: 接進 `_persistLatestAnalysisSnapshot`（analysis_screen.dart）**

在現有覆寫（`conv.lastEnthusiasmScore = ...` `:1466` 一帶）**之前**插入：

```dart
// 讀取 store（screen 內已有 ref/WidgetRef）
final roundStore = ref.read(analysisRoundArchiveStoreProvider);
archiveCompletedRound(
  roundStore,
  conv,
  messages: conv.messages,
  prevSnapshotJson: conv.lastAnalysisSnapshotJson, // 覆寫前
  prevAnalyzedCount: conv.lastAnalyzedMessageCount, // 覆寫前
  prevEnthusiasm: conv.lastEnthusiasmScore,          // 覆寫前
  now: DateTime.now(),
  newRoundId: '${conv.id}-current',
);
ref.read(analysisRoundArchiveControllerProvider.notifier).bumped();
// ↓ 以下維持原本 conversation 級覆寫不動（餵 partnerSummary 聚合）
conv.lastEnthusiasmScore = result.enthusiasmScore;
conv.lastAnalyzedMessageCount = targetAnalyzedMessageCount;
...
```

> **重要順序**：`archiveCompletedRound` 必須在任何 `conv.lastAnalyzedMessageCount`/`conv.lastAnalysisSnapshotJson`/`conv.lastEnthusiasmScore` 被覆寫**之前**呼叫，否則封存到的是新輪不是舊輪。

**Step 6: 手動驗證＋Commit**

Run: `flutter test`（全套，確認無回歸）
```bash
git add -A
git commit -m "分析完成時把上一輪凍結進對象封存盒並推進 round cursor"
```

---

## Phase C — 主畫面只渲染當前輪

### Task C1: 逐字稿列表改為只顯示當前輪片段

`analysis_screen.dart:5560-5589`（逐則渲染）與 `:5590-5618`（「展開全部 X 則訊息」）目前吃 `conversation.messages` 全量。改成只吃當前輪 `messages.sublist(currentRoundStart)`。

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:5560-5618`
- Test: `test/widget/analysis/current_round_only_test.dart`（widget 層 smoke，若既有 widget test 基建允許；否則以 golden 邏輯抽出純函式測「切片」）

**Step 1: 抽「當前輪片段」為純 getter，寫失敗測試**

```dart
test('currentRoundMessages 只回 cursor 之後的訊息', () {
  final all = _msgs(7);
  expect(currentRoundMessages(all, currentRoundStart: 5).map((m) => m.id),
      ['m-5', 'm-6']);
});
test('currentRoundStart 超界時回全部（fail-safe）', () {
  final all = _msgs(3);
  expect(currentRoundMessages(all, currentRoundStart: 99), all);
});
test('cursor=0（首輪或 legacy）回全部', () {
  final all = _msgs(3);
  expect(currentRoundMessages(all, currentRoundStart: 0), all);
});
```

**Step 3: 實作純函式（放 analysis_screen 同檔或 util）**

```dart
List<Message> currentRoundMessages(List<Message> all, {required int currentRoundStart}) {
  if (currentRoundStart <= 0 || currentRoundStart >= all.length) return all;
  return all.sublist(currentRoundStart);
}
```

**Step 5: 接進渲染**

- 在 build 該區塊前取得 `final roundStart = ref.watch(analysisRoundArchiveControllerProvider); final start = ref.read(analysisRoundArchiveStoreProvider).currentRoundStart(conversation);`
- 逐則渲染（`:5560-5589`）與計數改用 `currentRoundMessages(conversation.messages, currentRoundStart: start)`。
- 「展開全部 X 則訊息」（`:5590-5618`）改義：X = 當前輪則數；若對象有封存輪，此處或改為導引至封存盒（Task D）。**首輪 / legacy cursor=0 時退回全量**，不破壞既有體驗。

**Step 6: 跑測試＋Commit**

```bash
flutter test test/widget/analysis/current_round_only_test.dart
git add -A
git commit -m "analyze-chat 主畫面逐字稿改為只渲染當前輪片段"
```

---

## Phase D — 封存盒（mailbox）UI

### Task D1: 右上角封存盒入口 + 未讀數

**Files:**
- Modify: `analysis_screen.dart`（AppBar actions 加 mailbox IconButton；`badges` 或既有 badge 元件顯示對象封存輪數）
- Create: `lib/features/analysis_history/presentation/screens/round_archive_sheet.dart`

**行為：** IconButton `Icons.inbox`（或 `Icons.history`）→ `showModalBottomSheet` 開 `RoundArchiveSheet`，讀 `roundsForPartner(conversation)`，倒序列出（最新在上），每列顯示 `第 N 輪 · createdAt · 熱度`。空盒隱藏入口或顯示「尚無歷史輪次」。

**Step: 實作 sheet（讀 store）**

```dart
class RoundArchiveSheet extends ConsumerWidget {
  const RoundArchiveSheet({super.key, required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(analysisRoundArchiveControllerProvider); // rebuild 訊號
    final rounds = ref.read(analysisRoundArchiveStoreProvider).roundsForPartner(conversation);
    final ordered = rounds.reversed.toList(); // 最新在上
    // ListView：每列 tap → 開 RoundDetail（Task D2）
    ...
  }
}
```

**驗證＋Commit**：widget smoke（sheet 開得起來、列數正確）→ commit「新增分輪封存盒入口與列表」。

### Task D2: 封存輪唯讀詳情（當時她說什麼＋當時 AI 建議）

**Files:**
- Create: `lib/features/analysis_history/presentation/screens/round_archive_detail.dart`

**行為：** 收 `AnalysisRoundSnapshot` → 上半渲染 `snapshot.messages`（比照主畫面 `_MessageBubble`，但唯讀）；下半用 `snapshot.rawResponseJson` 反序列化重建建議卡：`AnalysisResult.fromJson(jsonDecode(rawResponseJson))`（比照還原路徑 `analysis_screen.dart:1276-1278` 的 `Map.from(snapshot)..remove(_snapshotClientMetaKey)` → `AnalysisResult.fromJson`）。rawResponseJson 為 null 時只顯示逐字稿 + 「當時無建議快照」。

**驗證＋Commit**：widget smoke（給一個假 snapshot，能渲染訊息與建議）→ commit「新增封存輪唯讀詳情頁（當時對話＋當時建議）」。

---

## Phase E — 模型輸入縮減（只送當輪片段）【高風險｜獨立審】

> 此 Phase 改 AI 輸入行為，屬 CLAUDE.md 高風險區。**必須**量測 token、**必須** Codex 雙審。可在 Phase A–D 已 dogfood 穩定後再獨立進行，兩者解耦。

### Task E1: `_runAnalysis` 只送當輪未分析片段

現況 `analysis_screen.dart:3812-3818` 用 `take(limit)` 取**前綴**，無「skip 已分析」。改成：`sourceMessages = messages.sublist(currentRoundStart)`（＝當前輪片段）。`currentRoundStart` 取自 store（cursor）。

**必查的 server 契約（改前先確認，勿盲改）：**
- server 端 `previousAnalyzedCount`（client 傳 `conversation.lastAnalyzedMessageCount`，見 current-state.md Q5 `:3928` 一帶）在只送片段後語意是否仍正確——若 server 假設收到的是「全量 + previousAnalyzedCount 切點」，只送片段會讓切點錯位。**這是本 Task 最大風險點**，必須讀 `supabase/functions/analyze-chat/index.ts` 對 `previousAnalyzedCount` 的使用後再定改法（可能需同步改 server，或改傳 `previousAnalyzedCount: 0` 表示「片段即全部」）。
- `partnerSummary` 必須照送（current-state.md Q2）——它承載關係連續性，**絕不**因縮減片段被一起拿掉。

**Files:**
- Modify: `analysis_screen.dart:3812-3818`（sourceMessages 決定）
- 可能 Modify: `supabase/functions/analyze-chat/index.ts`（視 `previousAnalyzedCount` 契約）
- Test: 既有 analyze 相關 Dart 測試 + Deno 測試（`supabase/functions/analyze-chat/*_test.ts`）

**Step 1: 先寫「片段切法」純函式測試**（同 C1 的 `currentRoundMessages`，此處複用）→ **Step 2: 讀 server 契約** → **Step 3: 實作** → **Step 4: 跑 Dart + Deno 全測** → **Step 5: 量測 token**：對同一組樣本，記錄改前/改後送模型的 token（`index.ts` 既有 token telemetry / stop_reason），確認確實下降且分析品質未崩。

**Step 6: Commit（暫不宣稱 dogfood safe）**

```bash
git add -A
git commit -m "analyze-chat 只送當輪片段給模型，關係連續性改由 partnerSummary 承載"
```

### Task E2: Codex 雙審 + token 報告

- 直呼 `codex:rescue` 對抗式雙審（記憶：CC 直呼、拿到 verdict 才宣稱 dogfood safe）。
- 附 token 前後對照 + 分析品質抽樣（至少 3 個真實對象樣本，比對縮減片段後建議是否仍合理）。
- 雙審 APPROVED 前**絕不**宣稱 dogfood/build safe。

---

## Phase F — 整合驗證與收尾

### Task F1: 端到端回歸

- `flutter test`（全套綠）＋ `flutter analyze`（0 issue）。
- 手動 e2e：新對話首輪分析 → 補聊天第二輪 → 確認主畫面只剩第二輪、封存盒出現第一輪、點第一輪能看到當時對話＋當時建議 → 開新對話同對象 → 封存盒仍在。
- 驗證 partnerSummary 續更：連兩輪後，第三輪的 Partner Context 是否反映最新熱度（current-state.md 風險 #2）。
- legacy 對話（partnerId==null）：確認降級 conversationId 分桶、cursor=0 退回全量不崩。

### Task F2: 文件與記憶

- 更新 `docs/plans/2026-07-14-analyze-chat-round-archive-design.md` 狀態→ 已實作待 dogfood。
- 若過程有踩雷（build_runner/序列化/server 契約），寫回 `docs/bug-log.md` 或對應記憶（照維護協議）。
- 自動記憶：新增/更新本案 project 記憶（SHIPPED 狀態、待 Eric/Bruce 真機 dogfood 才 CLOSE）。

---

## 風險與待決清單（交 GLM/執行者前 Eric 可否決）

1. **Phase E 的 server `previousAnalyzedCount` 契約**：這是唯一可能連動改 Edge Function 的點。E1 開工前必先讀 `index.ts` 確認，勿盲改 client。
2. **熱度/特質續更依賴 conversation 級快照覆寫**（Phase B 保留）：這是設計成立的關鍵機制，Review 時重點看。
3. **FIFO 5 輪跨對話共桶**：同 partnerId 多對話共用 5 輪。若 Eric 要「每對話各 5 輪」而非「每對象 5 輪」，需改 `_partnerKey` 回 conversationId——但設計定案是綁對象，此處照設計。
4. **legacy partnerId==null**：降級 conversationId 分桶（不撞 null）；cursor=0 時主畫面退回全量（不破舊體驗）。
5. **「展開全部」控制項改義**（Task C1）：X 改為當前輪則數，或改導引至封存盒——UI 細節，實作時定。
