# analyze-chat 分輪封存重設計 — Implementation Plan（純顯示層 v2）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 主畫面對話筐只顯示「最新一輪」，舊輪次收進右上角封存盒（一次分析＝一張卡）；模型輸入、計費、prompt 一律不動。

**Architecture:** 純顯示層改動 ＋ 一個輕量本地封存盒。封存走既有 `settingsBox` 動態 `Map<String,String>` 先例（`HiveConversationArchiveStore` 同款，免 build_runner、免新增 Hive typeId）。key=conversationId，value=JSON（`List<卡>`，FIFO 裁 5）；另存一個 round cursor（當前輪起點 index）。分析完成時把「上一個當前輪（片段＋建議快照）」封成一張卡 push 進盒，主畫面只渲染 `messages.sublist(currentRoundStart)`。

**Tech Stack:** Flutter / Riverpod / Hive（`settingsBox`）/ 純 Dart JSON 序列化。

**設計依據：** `docs/plans/2026-07-14-analyze-chat-round-archive-design.md`
**現況地圖（行號）：** `docs/plans/2026-07-14-analyze-chat-round-archive-current-state.md`

---

## 全域約束（每個 Task 都適用）

1. **絕不碰模型輸入**：`_runAnalysis` 送模型的 `sourceMessages`（analysis_screen.dart:3814）維持現狀；不加不減。
2. **絕不碰計費**：`lastAnalyzedCharCount` baseline、扣費口徑照舊。
3. **絕不誤觸 aggregate 回寫**：`partner_aggregates.dart` 讀 conversation 級 `lastAnalysisSnapshotJson` / `lastEnthusiasmScore`；本案只讀顯示，回寫路徑一律不動。
4. 一 commit 一 concern，繁體中文 commit message，完工即 push。
5. 封存 store 的 `settingsBox` 存取、owner-scope key、fail-open 慣例，**逐行對照** `lib/features/conversation/data/repositories/conversation_archive_store.dart:64-153` 與 `lib/features/conversation/data/providers/conversation_archive_providers.dart:9`，不自創 API。
6. 非高風險（模型不動）→ **免 Codex 雙審**；輕量自審 ＋ 端到端回歸即可。

---

## Phase A — 封存資料層（純 Dart，可離線 TDD）

### Task A1: `AnalysisRoundCard` model（純 Dart + JSON 序列化）

**Files:**
- Create: `lib/features/analysis/domain/entities/analysis_round_card.dart`
- Test: `test/features/analysis/domain/entities/analysis_round_card_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_round_card.dart';

void main() {
  test('round-trips through JSON preserving segment and recommendation', () {
    final card = AnalysisRoundCard(
      id: 'r1',
      createdAtMillis: 1720000000000,
      segment: const [
        ArchivedMessage(content: '你今天在幹嘛', isFromMe: false, timestampMillis: 1),
        ArchivedMessage(content: '在忙工作', isFromMe: true, timestampMillis: 2),
      ],
      recommendationJson: '{"reply":"可以約她週末"}',
    );

    final restored = AnalysisRoundCard.fromJson(card.toJson());

    expect(restored.id, 'r1');
    expect(restored.createdAtMillis, 1720000000000);
    expect(restored.segment.length, 2);
    expect(restored.segment.first.content, '你今天在幹嘛');
    expect(restored.segment.first.isFromMe, false);
    expect(restored.recommendationJson, '{"reply":"可以約她週末"}');
  });

  test('tolerates missing/legacy fields without throwing (fail-open)', () {
    final restored = AnalysisRoundCard.fromJson(const {'id': 'x'});
    expect(restored.id, 'x');
    expect(restored.segment, isEmpty);
    expect(restored.recommendationJson, '');
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/analysis/domain/entities/analysis_round_card_test.dart`
Expected: FAIL（`analysis_round_card.dart` 不存在）。

**Step 3: Write minimal implementation**

```dart
/// 一次分析 = 一張封存卡。自足：複製當輪片段 ＋ 當輪建議快照。
class AnalysisRoundCard {
  const AnalysisRoundCard({
    required this.id,
    required this.createdAtMillis,
    required this.segment,
    required this.recommendationJson,
  });

  final String id;
  final int createdAtMillis;
  final List<ArchivedMessage> segment;
  final String recommendationJson; // 與 conversation.lastAnalysisSnapshotJson 同格式

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAtMillis': createdAtMillis,
        'segment': segment.map((m) => m.toJson()).toList(),
        'recommendationJson': recommendationJson,
      };

  factory AnalysisRoundCard.fromJson(Map<String, dynamic> json) {
    final rawSegment = json['segment'];
    return AnalysisRoundCard(
      id: (json['id'] as String?) ?? '',
      createdAtMillis: (json['createdAtMillis'] as num?)?.toInt() ?? 0,
      segment: rawSegment is List
          ? rawSegment
              .whereType<Map>()
              .map((e) => ArchivedMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      recommendationJson: (json['recommendationJson'] as String?) ?? '',
    );
  }
}

class ArchivedMessage {
  const ArchivedMessage({
    required this.content,
    required this.isFromMe,
    this.timestampMillis,
  });

  final String content;
  final bool isFromMe;
  final int? timestampMillis;

  Map<String, dynamic> toJson() => {
        'content': content,
        'isFromMe': isFromMe,
        if (timestampMillis != null) 'timestampMillis': timestampMillis,
      };

  factory ArchivedMessage.fromJson(Map<String, dynamic> json) => ArchivedMessage(
        content: (json['content'] as String?) ?? '',
        isFromMe: (json['isFromMe'] as bool?) ?? false,
        timestampMillis: (json['timestampMillis'] as num?)?.toInt(),
      );
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/analysis/domain/entities/analysis_round_card_test.dart`
Expected: PASS。

**Step 5: Commit**

```bash
git add lib/features/analysis/domain/entities/analysis_round_card.dart test/features/analysis/domain/entities/analysis_round_card_test.dart
git commit -m "新增 analyze-chat 分輪封存卡 model（純 Dart JSON）"
```

---

### Task A2: `AnalysisRoundArchiveStore`（settingsBox 動態 Map，每對話 FIFO 5）

**Files:**
- Create: `lib/features/analysis/data/repositories/analysis_round_archive_store.dart`
- Test: `test/features/analysis/data/repositories/analysis_round_archive_store_test.dart`
- Pattern to mirror: `lib/features/conversation/data/repositories/conversation_archive_store.dart:64-153`

**Step 1: Write the failing test（用假 box，不碰真 Hive）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_round_card.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_round_archive_store.dart';

// 以 in-memory Map 假冒 settingsBox（依實際 store 介面調整）
class _FakeBox {
  final Map<String, String> _m = {};
  String? get(String k) => _m[k];
  Future<void> put(String k, String v) async => _m[k] = v;
}

void main() {
  AnalysisRoundCard card(String id, int ts) => AnalysisRoundCard(
        id: id,
        createdAtMillis: ts,
        segment: [ArchivedMessage(content: id, isFromMe: false)],
        recommendationJson: '{}',
      );

  test('append 後可讀回，且最新在最前', () async {
    final store = AnalysisRoundArchiveStore(box: _FakeBox());
    await store.append('conv-1', card('a', 1));
    await store.append('conv-1', card('b', 2));

    final list = store.read('conv-1');
    expect(list.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('每對話 FIFO 上限 5，第 6 張擠掉最舊', () async {
    final store = AnalysisRoundArchiveStore(box: _FakeBox());
    for (var i = 1; i <= 6; i++) {
      await store.append('conv-1', card('c$i', i));
    }
    final list = store.read('conv-1');
    expect(list.length, 5);
    expect(list.map((c) => c.id).contains('c1'), isFalse); // 最舊被擠掉
    expect(list.first.id, 'c6'); // 最新在最前
  });

  test('不同對話互不干擾', () async {
    final store = AnalysisRoundArchiveStore(box: _FakeBox());
    await store.append('conv-1', card('a', 1));
    await store.append('conv-2', card('b', 1));
    expect(store.read('conv-1').single.id, 'a');
    expect(store.read('conv-2').single.id, 'b');
  });

  test('壞 JSON fail-open 回空陣列不丟例外', () async {
    final box = _FakeBox();
    await box.put('analysis_rounds::conv-x', 'not-json');
    final store = AnalysisRoundArchiveStore(box: box);
    expect(store.read('conv-x'), isEmpty);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/analysis/data/repositories/analysis_round_archive_store_test.dart`
Expected: FAIL（store 不存在）。

**Step 3: Write minimal implementation**

- 依 `conversation_archive_store.dart` 的實際 `settingsBox` 存取型別調整 `box` 介面（`_FakeBox` 只是測試替身）。
- FIFO：新卡 push 到頭端，超過 5 砍尾端。owner-scope key 若既有 store 有前綴慣例，一併沿用。

```dart
import 'dart:convert';
import 'package:vibesync/features/analysis/domain/entities/analysis_round_card.dart';

const int kMaxRoundsPerConversation = 5;

class AnalysisRoundArchiveStore {
  AnalysisRoundArchiveStore({required this.box});
  final dynamic box; // 對照既有 store：實際型別為 settingsBox

  String _key(String conversationId) => 'analysis_rounds::$conversationId';

  List<AnalysisRoundCard> read(String conversationId) {
    final raw = box.get(_key(conversationId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AnalysisRoundCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const []; // fail-open
    }
  }

  Future<void> append(String conversationId, AnalysisRoundCard card) async {
    final current = List<AnalysisRoundCard>.from(read(conversationId));
    current.insert(0, card); // 最新在最前
    while (current.length > kMaxRoundsPerConversation) {
      current.removeLast(); // FIFO 擠掉最舊
    }
    await box.put(
      _key(conversationId),
      jsonEncode(current.map((c) => c.toJson()).toList()),
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/analysis/data/repositories/analysis_round_archive_store_test.dart`
Expected: PASS（4 tests）。

**Step 5: Commit**

```bash
git add lib/features/analysis/data/repositories/analysis_round_archive_store.dart test/features/analysis/data/repositories/analysis_round_archive_store_test.dart
git commit -m "新增分輪封存 store（settingsBox 每對話 FIFO 5）"
```

---

### Task A3: Riverpod provider wiring

**Files:**
- Create: `lib/features/analysis/data/providers/analysis_round_archive_providers.dart`
- Pattern to mirror: `lib/features/conversation/data/providers/conversation_archive_providers.dart:9`

**Step 1:** 依既有 archive provider 同款，注入真 `settingsBox`，導出 `analysisRoundArchiveStoreProvider`（store 單例）＋ `analysisRoundsProvider = Provider.family<List<AnalysisRoundCard>, String>`（吃 conversationId 回卡列表，供 UI 讀）。

**Step 2:** provider container smoke：`read/append` 走真 store 介面不炸。

**Step 3: Commit**

```bash
git add lib/features/analysis/data/providers/analysis_round_archive_providers.dart
git commit -m "掛上分輪封存 Riverpod provider"
```

---

## Phase B — 分析完成時歸檔（核心機制）

### Task B1: 分析完成 hook — 舊當前輪滑進盒 + 更新邊界

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`（分析成功寫回點：`:814` / `:1422` / `:4063` 附近，`_finalRecommendation = result.recommendation` 那幾處）
- Create: `lib/features/analysis/domain/services/round_boundary.dart`（純函式，好 TDD）
- 邊界來源：分析開跑前的 `conversation.lastAnalyzedMessageCount`（conversation.dart:58-59）
- cursor 儲存：同 `settingsBox`，key=`analysis_round_cursor::<conversationId>` → int（避免動 `Conversation` Hive 結構＝否決 B）

**機制（在「新一輪分析成功寫回」的那一刻執行）：**

1. `boundaryBeforeRun` = 這次分析**開跑前**的 `lastAnalyzedMessageCount`（務必在既有更新之前先抓）。
2. `prevRoundStart` = cursor 現值（首輪缺省 0）。
3. 若 `prevRoundStart < boundaryBeforeRun`：把 `messages[prevRoundStart..boundaryBeforeRun)` map 成 `ArchivedMessage`，連同「上一輪的建議快照」（上一次 `lastAnalysisSnapshotJson` 或當時 `_finalRecommendation` 序列化）封成 `AnalysisRoundCard`，`append` 進 store。
4. 更新 cursor = `boundaryBeforeRun`（新的當前輪從舊邊界起）。
5. `lastAnalyzedMessageCount` 本身照現狀更新（計費/既有邏輯不動）。

**Step 1: Write the failing test（純函式）**

```dart
// lib/features/analysis/domain/services/round_boundary.dart
class RoundBoundary {
  static ({int archiveStart, int archiveEnd, int nextRoundStart}) compute({
    required int prevRoundStart,      // 上一個當前輪起點（cursor）
    required int boundaryBeforeRun,   // 這次分析開跑前 lastAnalyzedMessageCount
  }) {
    return (
      archiveStart: prevRoundStart,
      archiveEnd: boundaryBeforeRun,
      nextRoundStart: boundaryBeforeRun,
    );
  }
}
```

```dart
test('第二輪：封存 [0,3)，新當前輪從 3 起', () {
  final r = RoundBoundary.compute(prevRoundStart: 0, boundaryBeforeRun: 3);
  expect(r.archiveStart, 0);
  expect(r.archiveEnd, 3);
  expect(r.nextRoundStart, 3);
});
test('首輪（0/0）空區間 → 呼叫端不 append', () {
  final r = RoundBoundary.compute(prevRoundStart: 0, boundaryBeforeRun: 0);
  expect(r.archiveStart, r.archiveEnd);
});
```

**Step 2–4:** 跑測試（先紅後綠）。

**Step 5:** 在 `analysis_screen.dart` 分析成功寫回處接上：`archiveStart < archiveEnd` 才 `append`（首輪跳過），再寫 cursor。

**Step 6: Commit**

```bash
git add lib/features/analysis/domain/services/round_boundary.dart test/... lib/features/analysis/presentation/screens/analysis_screen.dart
git commit -m "分析完成時把上一輪滑進封存盒並更新當前輪起點"
```

---

## Phase C — 主畫面只渲染當前輪

### Task C1: 逐字稿列表只顯示當前輪片段

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:5560-5618`（逐字稿逐則渲染 ＋ `:5590` 的「展開全部 X 則」toggle ＝ 疊加元兇）

**改法：**
1. 逐字稿列表資料源從 `conversation.messages`（全量）改為 `conversation.messages.sublist(currentRoundStart)`（只當前輪；`currentRoundStart` 讀 cursor，缺省 0，並 clamp 在 `[0, messages.length]` 防越界）。
2. `:5590` 的「展開全部 X 則訊息」toggle **移除**（疊加沒了就不需要）；保守做法改文案為「查看封存輪次」導去 Phase D 入口。
3. **只改渲染**：`conversation.messages` 本體、送模型 `sourceMessages`、計費一律不動。

**Step 1: widget test 冒煙**
- 塞 8 則 messages、cursor=5 → 逐字稿只出現 index 5..7 三則，且「展開全部」toggle 不存在。

**Step 2: Commit**

```bash
git add lib/features/analysis/presentation/screens/analysis_screen.dart test/...
git commit -m "主畫面逐字稿只渲染當前輪、移除展開全部疊加入口"
```

---

## Phase D — 封存盒（mailbox）UI

### Task D1: 右上角封存盒入口 + 卡片列表

**Files:**
- Modify: `analysis_screen.dart`（AppBar / 右上 actions 加 mailbox icon）
- Create: `lib/features/analysis/presentation/widgets/round_archive_sheet.dart`

**改法：** 右上 icon（可帶卡數 badge）→ 開 bottom sheet / 頁面，讀 `analysisRoundsProvider(conversationId)`，逐張列出（時間 + 摘要一行）。空盒顯示 empty state。

**Step:** widget test — 塞 2 張卡 → 入口顯示、sheet 列出 2 張、最新在最前。Commit。

### Task D2: 封存輪唯讀詳情（當時她說什麼 + 當時 AI 建議）

**Files:**
- Create: `lib/features/analysis/presentation/widgets/round_archive_detail.dart`

**改法：** 點一張卡 → 唯讀詳情：上半 = `segment` 逐則氣泡（當時逐字稿），下半 = `recommendationJson` 反序列化後的建議（重用主畫面 `_buildRecommendationContent` 唯讀版，`analysis_screen.dart:4789`）。唯讀，無任何再分析/扣費入口。

**Step:** widget test — 塞 1 張卡 → 詳情同時顯示片段與建議。Commit。

---

## Phase F — 整合驗證與收尾（輕量，免 Codex 雙審）

### Task F1: 端到端回歸

1. 首輪分析 → 主畫面只有這輪、盒空。
2. 補聊天紀錄 → 第二輪分析 → 主畫面只有第二輪；盒內第一輪 1 張、內容＝當時片段＋當時建議。
3. 連補到第 6 輪 → 盒內剩 5 張、最舊被擠掉。
4. 開新對話 → conversationId scope 下新對話盒空、舊對話盒不受影響。
5. **回歸不變項**：模型輸入無變（比對 request payload）、計費無變、partner aggregate 熱度照常更新。
6. `flutter test`（相關子集）全綠 ＋ `flutter analyze` 無新錯。

### Task F2: 文件與記憶

1. 更新 `docs/snapshot.md`（若列 in-flight 工作）。
2. 教訓非必要不寫；要寫依維護協議進 `docs/decisions.md`。
3. commit + push。

---

## 待決清單（交 GLM/執行者前 Eric 可否決）

1. **封存範圍**：目前定 **conversationId**（綁單次對話，開新對話不帶過去）。若要「綁對象（partnerId）、開新對話保留該對象歷史」→ store key 改 partnerId + legacy `partnerId==null` fallback（current-state Q4）。**這會改資料模型，動工前確認。**
2. **保留張數**：5 / 對話（FIFO）。
3. **Phase C 的「展開全部」toggle**：移除 vs 改成「查看封存輪次」入口——擇一。
4. **首輪是否入盒**：目前首輪不入盒，只有被下一輪頂替時才入盒。
