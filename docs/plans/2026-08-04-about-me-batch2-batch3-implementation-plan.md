# 「關於我」批2＋批3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把「關於我」從「描述你現在的樣子（給 AI 模仿）」改造成「說出你卡在哪、想變成什麼樣（給教練當標尺）」——批2做 App 端欄位/文案/預覽，批3做送進 AI 的指令反轉。

**Architecture:** 新增一個獨立的 `StuckPoint` enum（「我現在卡在哪」，Hive typeId 27）掛在 `UserProfile` 上；重新定義既有 `PracticeGoal` 的 5 個成員語意（2 個搬去 StuckPoint、2 個換成新概念、3 個保留改文案），讓「練習目標」直接變身「我想達成什麼」而不需要新 Hive typeId。`EffectiveStyle`／`resolveEffectiveStyle` 跟著加一個唯讀（不吃 partner override）的 `stuckPoints` 欄位。`effective_style_prompt_builder.dart` 是送進 AI 指令的唯一轉譯層，批3只改這一層與它輸出去的兩個後端 schema，不碰對話當下的其他判斷邏輯。

**Tech Stack:** Flutter/Dart（Riverpod、Hive CE、json_serializable 皆不涉及——本模組用純 Hive codegen）、Deno（Supabase Edge Functions，analyze-chat／coach-chat）。

**設計依據文件**（先讀，不要跳過）：
- `docs/plans/2026-08-03-about-me-batch2-field-redesign-design.md`
- `docs/plans/2026-08-03-about-me-batch3-ai-instruction-reversal-design.md`

**執行順序限制**：批2（Task 1–8）可以獨立完成、審查、甚至先部署（純 App 端，文案批 Eric 已核可）。批3（Task 9–16）**必須在批2之後**才動工（依賴 `PracticeGoal`／`StuckPoint` 的最終欄位形狀），而且完成後需要 Codex 雙審才可部署（AI prompt/token/cost 是專案 Critical Gotchas 高風險區）。兩批各自一次 commit 群組，不要混在一起 push。

---

## 批2實作範圍之外的既有測試鎖（先知道，別意外）

`test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`（484行）裡有一條測試名叫「主-only output is byte-for-byte identical to pre-pair format」，斷言字串包含 `Preferred voice: ...`。**這條測試批2完全不用動**（批2不碰這個檔案）；批3的 Task 9 會刻意打破它，那是預期行為，見 Task 9 說明。

---

### Task 1: 新增 `StuckPoint` enum ＋ `UserProfile.stuckPoints` 欄位

**Files:**
- Modify: `lib/features/user_profile/domain/entities/user_profile.dart`
- Test: `test/unit/features/user_profile/user_profile_test.dart`
- Test: `test/unit/features/user_profile/user_profile_hive_test.dart`

**背景**：現有 `@HiveType(typeId:` 用到 0–26，全部連號無空缺（用 `grep -rn "@HiveType(typeId:" lib/` 自行確認），所以新 enum 用 **typeId: 27**。`UserProfile` 本體現有 `@HiveField` 用到 6（`secondaryStyle`），新欄位用 **`@HiveField(7)`**。

**Step 1: 寫新 enum 定義**

在 `user_profile.dart` 的 `TopicSeed` enum 之後（第41行後）插入：

```dart
/// 我現在卡在哪 — multi select, max 2（2026-08 關於我重新定位案 批2 新增）。
/// anxiousWontSend／overExplains 承接舊 PracticeGoal.reduceAnxiety／
/// explainLess 的語意（那兩個 PracticeGoal 成員已重新定義成別的概念，
/// 見批3 前置的 PracticeGoal 改造）。
@HiveType(typeId: 27)
enum StuckPoint {
  @HiveField(0) fadesOut, // 聊一聊就冷掉，不知道怎麼接下去
  @HiveField(1) dontKnowHowToAsk, // 不知道怎麼開口約
  @HiveField(2) anxiousWontSend, // 會緊張、怕講錯話不敢傳
  @HiveField(3) overExplains, // 話太多、一直在解釋自己
  @HiveField(4) leftOnRead, // 一直被已讀不回
}
```

**Step 2: 在 `UserProfile` 加欄位＋常數**

在 `static const int maxNotesLength = 100;` 之後加：
```dart
  static const int maxStuckPoints = 2;
```

在 `@HiveField(6) final InteractionStyle? secondaryStyle;` 之後加：
```dart
  @HiveField(7)
  final List<StuckPoint> stuckPoints;
```

`UserProfile(...)` 主建構子加 `this.stuckPoints = const [],`；`UserProfile.create(...)` 工廠方法加參數 `List<StuckPoint> stuckPoints = const [],`，並在其他 bounds check 旁邊加：
```dart
    if (stuckPoints.length > maxStuckPoints) {
      throw ArgumentError('stuckPoints exceeds max $maxStuckPoints');
    }
```
回傳時加 `stuckPoints: List.unmodifiable(stuckPoints),`。`isEmpty` getter 加 `&& stuckPoints.isEmpty`。

**Step 3: 重新生成 Hive adapter**

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: `user_profile.g.dart` 新增 `StuckPointAdapter` 與 `UserProfileAdapter` 讀寫 field 7 的程式碼，無錯誤訊息。

**Step 4: 寫失敗測試（先確認新行為還不存在／新約束生效）**

在 `test/unit/features/user_profile/user_profile_test.dart` 加：
```dart
test('stuckPoints exceeds max throws', () {
  expect(
    () => UserProfile.create(
      stuckPoints: StuckPoint.values.take(3).toList(),
      updatedAt: DateTime.utc(2026),
    ),
    throwsArgumentError,
  );
});

test('isEmpty is false when only stuckPoints set', () {
  final p = UserProfile.create(
    stuckPoints: [StuckPoint.fadesOut],
    updatedAt: DateTime.utc(2026),
  );
  expect(p.isEmpty, isFalse);
});
```

在 `test/unit/features/user_profile/user_profile_hive_test.dart` 加一條 round-trip 測試（照現有其他欄位的 round-trip 測試寫法抄一份，換成 `stuckPoints: [StuckPoint.leftOnRead]`）。

**Step 5: 跑測試**

Run: `flutter test test/unit/features/user_profile/user_profile_test.dart test/unit/features/user_profile/user_profile_hive_test.dart`
Expected: 全部 PASS（Step 1–3 已經把實作寫完，這裡是驗證，不是紅燈流程——這個 Task 是加欄位不是改行為，可以實作+測試一起寫，但仍要跑過確認）。

**Step 6: Commit**
```bash
git add lib/features/user_profile/domain/entities/user_profile.dart \
        lib/features/user_profile/domain/entities/user_profile.g.dart \
        test/unit/features/user_profile/user_profile_test.dart \
        test/unit/features/user_profile/user_profile_hive_test.dart
git commit -m "加：UserProfile 新增 StuckPoint（我現在卡在哪）欄位"
```

---

### Task 2: 重新定義 `PracticeGoal` 5 個成員語意

**Files:**
- Modify: `lib/features/user_profile/domain/entities/user_profile.dart`
- Test: `test/unit/features/user_profile/user_profile_test.dart`

**決定**（Eric 已核可）：`PracticeGoal` 的 Hive `@HiveField` **index 不變**（0–4），但改 Dart 識別字與語意：

| index | 舊識別字／語意 | 新識別字／語意 |
|---|---|---|
| 0 | `softInvite` 自然邀約 | `softInvite`（保留識別字）想約得出來 |
| 1 | `reduceAnxiety` 降低焦慮 | **`comfortableChat`**（新識別字）想先能自在聊天，不要那麼緊繃 |
| 2 | `humorousReply` 幽默回覆 | `humorousReply`（保留識別字）想讓對話更幽默、有來有往 |
| 3 | `buildCloseness` 培養親近 | `buildCloseness`（保留識別字）想培養穩定的親近感 |
| 4 | `explainLess` 減少解釋 | **`findCompatiblePartner`**（新識別字）想找到聊得來的對象、不設限交往 |

因為 Hive 用 `@HiveField(index)` 序列化、不記識別字名稱，這個改動**對已存的使用者資料零遷移成本**——舊資料裡 index 1／4 的位元會直接被讀成新語意，這是 Eric 已核可的既定取捨（見批2設計文件）。

**Step 1: 改 enum 定義**

```dart
@HiveType(typeId: 11)
enum PracticeGoal {
  @HiveField(0) softInvite,
  @HiveField(1) comfortableChat,
  @HiveField(2) humorousReply,
  @HiveField(3) buildCloseness,
  @HiveField(4) findCompatiblePartner,
}
```

**Step 2: 全域搜尋並替換舊識別字**

Run: `grep -rln "PracticeGoal.reduceAnxiety\|PracticeGoal.explainLess" lib/ test/`
Expected（本次盤點的完整清單，逐一確認沒有漏網之魚）：
- `lib/features/analysis/domain/coach/coach_action_policy.dart`（→ Task 4 處理，這裡改的是判斷邏輯本身，不只是改名）
- `lib/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart`
- `lib/features/user_profile/presentation/screens/about_me_screen.dart`
- `lib/features/user_profile/presentation/screens/partner_style_edit_screen.dart`
- `lib/features/user_profile/presentation/widgets/about_me_card.dart`
- `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart`（→ Task 9 一起處理文案）
- 上述每個檔案對應的 test/widget test（`user_profile_test.dart`／`partner_style_override_test.dart`／`onboarding_questionnaire_test.dart`／`about_me_card_test.dart`／`partner_style_edit_screen_test.dart`／`effective_style_prompt_builder_test.dart`／`resolve_effective_style_test.dart`）
- `test/visual_proof/profile_mindmap_capture_test.dart`、`test/visual_proof/report_insight_proof_test.dart`（視覺快照 fixture，若引用了舊識別字要換成新的並重跑快照）

對每個檔案：把 `PracticeGoal.reduceAnxiety` 換成 `PracticeGoal.comfortableChat`、`PracticeGoal.explainLess` 換成 `PracticeGoal.findCompatiblePartner`；label switch 裡的中文字串換成新文案（表格見上）。**`coach_action_policy.dart` 不要在這裡改**——那裡的邏輯要整條換成判斷 `StuckPoint`，留給 Task 4，這裡先跳過那個檔案。

**Step 3: 跑全套受影響測試**

Run: `flutter test test/unit/features/user_profile/ test/widget/features/user_profile/ test/widget/features/onboarding/`
Expected: 先看到因為字串斷言對不上而 FAIL 的清單，逐一把測試裡的舊中文字串／舊識別字改成新的，直到全部 PASS。

**Step 4: Commit**
```bash
git add -u lib/features/user_profile lib/features/onboarding test/
git commit -m "改：PracticeGoal 5 選項重新設計為「我想達成什麼」（練習目標語意反轉）"
```

（`coach_action_policy.dart`／`about_me_screen.dart` 版面／`about_me_card.dart` 摘要行留到 Task 4/5/7 各自的 commit，這裡先只 commit 上面列的機械式改名部分——如果 git diff 混在一起也沒關係，但建議按檔案分開 add 以利之後 review。）

---

### Task 3: `EffectiveStyle` ／ `resolveEffectiveStyle` 加 `stuckPoints`

**Files:**
- Modify: `lib/features/user_profile/domain/entities/effective_style.dart`
- Modify: `lib/features/user_profile/domain/services/resolve_effective_style.dart`
- Test: `test/unit/features/user_profile/domain/resolve_effective_style_test.dart`

**決定**：`stuckPoints` **只吃 global，不做 partner override 合併**（`PartnerStyleOverride` 沒有這個欄位，批2/3都不新增——報告從頭到尾只把 A1 定位成全域「關於我」的內容，不是 per-partner 覆寫項）。

**Step 1: 寫失敗測試**

在 `resolve_effective_style_test.dart` 加：
```dart
test('stuckPoints always comes from global, partner has no override field', () {
  final global = UserProfile.create(
    stuckPoints: [StuckPoint.fadesOut, StuckPoint.leftOnRead],
    updatedAt: DateTime.utc(2026),
  );
  final effective = resolveEffectiveStyle(global: global, partner: null);
  expect(effective.stuckPoints, [StuckPoint.fadesOut, StuckPoint.leftOnRead]);
});

test('stuckPoints empty when global is null', () {
  final effective = resolveEffectiveStyle(global: null, partner: null);
  expect(effective.stuckPoints, isEmpty);
});
```

Run: `flutter test test/unit/features/user_profile/domain/resolve_effective_style_test.dart`
Expected: FAIL（`EffectiveStyle` 還沒有 `stuckPoints` getter，compile error）。

**Step 2: 實作**

`effective_style.dart` 加欄位：
```dart
  final List<StuckPoint> stuckPoints;
```
建構子加 `this.stuckPoints = const [],`。

`resolve_effective_style.dart` 的 `resolveEffectiveStyle(...)` 回傳值加：
```dart
    stuckPoints: global?.stuckPoints ?? const [],
```

**Step 3: 跑測試確認過**

Run: `flutter test test/unit/features/user_profile/domain/resolve_effective_style_test.dart`
Expected: PASS

**Step 4: Commit**
```bash
git add lib/features/user_profile/domain/entities/effective_style.dart \
        lib/features/user_profile/domain/services/resolve_effective_style.dart \
        test/unit/features/user_profile/domain/resolve_effective_style_test.dart
git commit -m "加：EffectiveStyle 補上 stuckPoints（只吃 global，不做 partner override）"
```

---

### Task 4: `coach_action_policy.dart` tie-breaker 改判斷 `StuckPoint`

**Files:**
- Modify: `lib/features/analysis/domain/coach/coach_action_policy.dart:264-373`
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:7439-7456`
- Test: `test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`

**背景**：`evaluate`/`_select` 目前用 `practiceGoals.contains(PracticeGoal.reduceAnxiety)`（行319）決定要不要 `_buildPausePursuit`，用 `practiceGoals.contains(PracticeGoal.explainLess)`（行366）決定要不要 `_buildPreferenceSignal`。這兩條邏輯語意上屬於「用戶現在的處境」不是「想達成的目標」，改判斷新的 `StuckPoint.anxiousWontSend`／`StuckPoint.overExplains`。

**Step 1: 寫失敗測試**

在 `coach_action_policy_test.dart` 找到現有測「reduceAnxiety practice goal keeps pausePursuit」和「explainLess practice goal」的測試（用 `grep -n "reduceAnxiety\|explainLess" test/unit/features/analysis/domain/coach/coach_action_policy_test.dart` 定位），複製一份改成用 `stuckPoints: [StuckPoint.anxiousWontSend]` / `stuckPoints: [StuckPoint.overExplains]` 傳入、`practiceGoals: const []`（確認新邏輯不再依賴 practiceGoals）。

Run: `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
Expected: 新測試 FAIL（`evaluate` 還沒有 `stuckPoints` 參數，compile error）。

**Step 2: 實作**

`evaluate`／`_select` 兩個方法簽名都加 `required List<StuckPoint> stuckPoints,`。

行319：
```dart
      if (practiceGoals.contains(PracticeGoal.reduceAnxiety)) {
```
改成：
```dart
      if (stuckPoints.contains(StuckPoint.anxiousWontSend)) {
```

行366：
```dart
      if (practiceGoals.contains(PracticeGoal.explainLess)) {
```
改成：
```dart
      if (stuckPoints.contains(StuckPoint.overExplains)) {
```

`_select` 呼叫 `_select(...)` 時（在 `evaluate` 內）也要把 `stuckPoints: stuckPoints,` 傳下去。

**Step 3: 更新呼叫端**

`analysis_screen.dart:7439-7444` 現在只抓 `practiceGoals`，仿照同一段加：
```dart
                                final stuckPoints = partnerId != null
                                    ? ref
                                        .watch(
                                            effectiveStyleProvider(partnerId))
                                        .stuckPoints
                                    : const <StuckPoint>[];
```
`CoachActionPolicy.evaluate(...)` 呼叫加 `stuckPoints: stuckPoints,`。

**Step 4: 跑測試確認全綠**

Run: `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
Expected: PASS（含舊有測試——舊的 reduceAnxiety/explainLess 測試已在 Task 2 改名或在這裡改判斷依據，確認沒有殘留斷言舊行為的測試）

Run: `flutter analyze lib/features/analysis/presentation/screens/analysis_screen.dart`
Expected: `No issues found!`

**Step 5: Commit**
```bash
git add lib/features/analysis/domain/coach/coach_action_policy.dart \
        lib/features/analysis/presentation/screens/analysis_screen.dart \
        test/unit/features/analysis/domain/coach/coach_action_policy_test.dart
git commit -m "改：教練動作卡 tie-breaker 改判斷 StuckPoint，不再誤讀已重新定義的 PracticeGoal"
```

---

### Task 5: `about_me_screen.dart` 版面改造

**Files:**
- Modify: `lib/features/user_profile/presentation/screens/about_me_screen.dart`
- Test: 若無現成 widget test，於 `test/widget/features/user_profile/about_me_screen_test.dart` 新增（先 `find test/widget -iname "about_me_screen*"` 確認現況）

**這個 Task 涵蓋批2設計文件的第167–170項（新增 A1/A2、互動風格改問法、自述改邊界導向、版面順序、移除舊練習目標區塊）。**

**Step 1**：新增兩個 state set：
```dart
  final Set<StuckPoint> _draftStuckPoints = <StuckPoint>{};
```
（放在 `_draftGoals` 旁邊）；`_hydrate`／`_isDraftEmpty`／`_isDirty`／`_onPrimaryTap` 存檔邏輯、`UserProfile.create(...)` 呼叫都要比照 `_draftGoals` 加一份 `stuckPoints: _draftStuckPoints.toList()`。

**Step 2**：加 toggle 方法（比照 `_toggleGoal`，上限改 `UserProfile.maxStuckPoints`）：
```dart
  void _toggleStuckPoint(StuckPoint s) {
    if (_draftStuckPoints.contains(s)) {
      setState(() => _draftStuckPoints.remove(s));
      return;
    }
    if (_draftStuckPoints.length >= UserProfile.maxStuckPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多選 2 個'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _draftStuckPoints.add(s));
  }
```

**Step 3**：`build` 裡的版面順序調整——把原本「練習目標」`ProfileChipSection<PracticeGoal>` 整段**移除**，改成放在最前面（`_AboutMeIntroCard` 之後、互動風格之前）兩個新區塊：
```dart
                  ProfileChipSection<StuckPoint>(
                    title: '我現在卡在哪',
                    subtitle: '最多 2 個，教練會盯著這裡幫你推一把。',
                    options: StuckPoint.values,
                    labelOf: _stuckPointLabel,
                    isSelected: _draftStuckPoints.contains,
                    onTap: _toggleStuckPoint,
                  ),
                  const SizedBox(height: 14),
                  ProfileChipSection<PracticeGoal>(
                    title: '我想達成什麼',
                    subtitle: '最多 3 個，這是教練幫你的主要方向。',
                    options: PracticeGoal.values,
                    labelOf: _practiceGoalLabel,
                    isSelected: _draftGoals.contains,
                    onTap: _toggleGoal,
                  ),
                  const SizedBox(height: 14),
```
互動風格區塊留在原位但改 subtitle（見下）；「常聊話題」「自訂話題」「想讓AI知道的事」維持原順序不動。

**Step 4**：文案改動（逐一對照批2設計文件第二節）：
- `_AboutMeIntroCard` 標題「讓建議更像你」→「讓教練真的懂你」；副文案換成「AI 會用這些設定了解你的處境，幫你往前推一步；不會照你現在的樣子模仿你。」
- 互動風格 `ProfileChipSection` 的 `subtitle` 改成：「先點主風格，再點副風格（可只選主）。這是你現在的舒適區，不是要 AI 模仿——是讓它知道哪些建議對你來說是往前一步。」
- 「想讓AI知道的事」`_ProfileInputSection` 的 `subtitle` 改成：「有什麼是你不想做的？例如「不要太快邀約」「不要開黃腔」。」

**Step 5**：加 `_stuckPointLabel` 函式（放在檔案底部 `_practiceGoalLabel` 旁邊）：
```dart
String _stuckPointLabel(StuckPoint s) => switch (s) {
      StuckPoint.fadesOut => '聊一聊就冷掉，不知道怎麼接下去',
      StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
      StuckPoint.anxiousWontSend => '會緊張、怕講錯話不敢傳',
      StuckPoint.overExplains => '話太多、一直在解釋自己',
      StuckPoint.leftOnRead => '一直被已讀不回',
    };
```
`_practiceGoalLabel` 的 switch 已在 Task 2 換過識別字，這裡確認文案是最終版（見 Task 2 表格右欄）。

**Step 6: 跑 widget test**

Run: `flutter test test/widget/features/user_profile/about_me_screen_test.dart`（若檔案不存在，先確認是否要新增——這個畫面過去似乎沒有專屬 widget test，用 `about_me_card_test.dart` 的寫法起手：`pumpWidget` + `ProviderScope overrides` + `setSurfaceSize`）
Expected: 至少驗證「A1/A2 兩區塊都渲染」「選滿 2 個 A1 再點第 3 個不會多選」「舊練習目標區塊已不存在（`find.text('練習目標')` 應為 0）」

**Step 7: Commit**
```bash
git add lib/features/user_profile/presentation/screens/about_me_screen.dart test/widget/features/user_profile/about_me_screen_test.dart
git commit -m "改：關於我頁面改教練導向——新增卡在哪/想達成什麼、互動風格改問法、自述改邊界導向"
```

---

### Task 6: 存檔預覽機制（成長框架，純本地模板，不呼叫 AI）

**Files:**
- Create: `lib/features/user_profile/domain/services/growth_preview_builder.dart`
- Create: `lib/features/user_profile/presentation/widgets/growth_preview_sheet.dart`
- Modify: `lib/features/user_profile/presentation/screens/about_me_screen.dart`（`_onPrimaryTap` 的「儲存」分支）
- Test: `test/unit/features/user_profile/domain/growth_preview_builder_test.dart`

**Step 1: 寫失敗測試（純函式，先寫 TDD）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/growth_preview_builder.dart';

void main() {
  const builder = GrowthPreviewBuilder();

  test('both A1 and A2 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: [PracticeGoal.softInvite],
      comfortStyle: null,
    );
    expect(text, contains('你想'));
    expect(text, contains('教練會盯著你'));
  });

  test('only A2 filled', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: [PracticeGoal.softInvite],
      comfortStyle: null,
    );
    expect(text, contains('教練會照著這個方向'));
  });

  test('only A1 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: const [],
      comfortStyle: null,
    );
    expect(text, contains('教練會盯著你'));
    expect(text, isNot(contains('你想')));
  });

  test('neither filled falls back to generic line', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: const [],
      comfortStyle: null,
    );
    expect(text, contains('先摸清你的說話習慣和邊界'));
  });

  test('comfort style appends the pacing note', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: const [],
      comfortStyle: InteractionStyle.steady,
    );
    expect(text, contains('教練知道你平常偏穩重'));
  });
}
```

Run: `flutter test test/unit/features/user_profile/domain/growth_preview_builder_test.dart`
Expected: FAIL（檔案不存在）

**Step 2: 實作**

```dart
import '../entities/user_profile.dart';

/// 存檔後的成長框架預覽——純本地模板句，不呼叫 AI、不扣額度。
class GrowthPreviewBuilder {
  const GrowthPreviewBuilder();

  String build({
    required List<StuckPoint> stuckPoints,
    required List<PracticeGoal> goals,
    required InteractionStyle? comfortStyle,
  }) {
    final goalPhrase = goals.map(_goalPhrase).join('、');
    final stuckPhrase = stuckPoints.map(_stuckPhrase).join('、');

    final String main;
    if (goalPhrase.isNotEmpty && stuckPhrase.isNotEmpty) {
      main = '你想$goalPhrase。教練會盯著你$stuckPhrase的地方，幫你往前推一步。';
    } else if (goalPhrase.isNotEmpty) {
      main = '你想$goalPhrase。教練會照著這個方向，幫你一步步往前推。';
    } else if (stuckPhrase.isNotEmpty) {
      main = '教練會盯著你$stuckPhrase的地方，幫你想辦法往前推一步。';
    } else {
      main = '教練會先摸清你的說話習慣和邊界，抓對時機幫你往前推一步。';
    }

    if (comfortStyle == null) return main;
    return '$main\n教練知道你平常偏${_styleLabel(comfortStyle)}，'
        '會照你的步調來，不會突然要你變一個人。';
  }

  static String _goalPhrase(PracticeGoal g) => switch (g) {
        PracticeGoal.softInvite => '約得出來',
        PracticeGoal.comfortableChat => '先能自在聊天',
        PracticeGoal.humorousReply => '讓對話更幽默、有來有往',
        PracticeGoal.buildCloseness => '培養穩定的親近感',
        PracticeGoal.findCompatiblePartner => '找到聊得來的對象',
      };

  static String _stuckPhrase(StuckPoint s) => switch (s) {
        StuckPoint.fadesOut => '話題卡住接不下去',
        StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
        StuckPoint.anxiousWontSend => '緊張不敢傳',
        StuckPoint.overExplains => '容易解釋太多',
        StuckPoint.leftOnRead => '已讀不回',
      };

  static String _styleLabel(InteractionStyle s) => switch (s) {
        InteractionStyle.steady => '穩重',
        InteractionStyle.direct => '直接',
        InteractionStyle.humorous => '幽默',
        InteractionStyle.gentle => '溫柔',
        InteractionStyle.playful => '俏皮',
      };
}
```

**Step 3: 跑測試確認過**

Run: `flutter test test/unit/features/user_profile/domain/growth_preview_builder_test.dart`
Expected: PASS

**Step 4: 接上 UI**

新增 `growth_preview_sheet.dart`：一個 `showModalBottomSheet` helper，接受 `String previewText`，顯示文字＋一顆「好，我知道了」按鈕，按下 `Navigator.pop`。

在 `about_me_screen.dart` 的 `_onPrimaryTap`「儲存」分支，`await controller.save(profile);` 成功、**且** `!_isDraftEmpty`（略過／清除設定不觸發）之後、`popIfPossible()` 之前，插入：
```dart
    if (mounted) {
      final preview = const GrowthPreviewBuilder().build(
        stuckPoints: _draftStuckPoints.toList(),
        goals: _draftGoals.toList(),
        comfortStyle: _draftPair.primary,
      );
      await showGrowthPreviewSheet(context, preview);
    }
```
（放在原本的 `messenger.showSnackBar(...)`／`funnelTracker.track(...)` 之後，`popIfPossible()` 之前——sheet 關閉後才跳回上一頁。）

**Step 5: widget test**

驗證：存檔後 sheet 出現、內容含預期關鍵字；點「略過」／「清除設定」不出現 sheet。

**Step 6: Commit**
```bash
git add lib/features/user_profile/domain/services/growth_preview_builder.dart \
        lib/features/user_profile/presentation/widgets/growth_preview_sheet.dart \
        lib/features/user_profile/presentation/screens/about_me_screen.dart \
        test/unit/features/user_profile/domain/growth_preview_builder_test.dart
git commit -m "加：關於我存檔後的成長框架預覽（純本地模板，不呼叫 AI）"
```

---

### Task 7: `about_me_card.dart` 連帶更新

**Files:**
- Modify: `lib/features/user_profile/presentation/widgets/about_me_card.dart`
- Test: `test/widget/features/user_profile/about_me_card_test.dart`

**Step 1**：`_EmptyState` 標題「讓 VibeSync 更像你的教練」→「讓教練真的懂你」；副文案「填一下互動風格與練習目標，AI 會調整建議語氣，不會替你假裝成另一個人。」→「填一下你卡在哪、想達成什麼，AI 會幫你抓方向、推你一步，不會照你現在的樣子模仿你。」；pill `'練習目標'` → `'我想達成什麼'`（可再加一顆 `'我現在卡在哪'`）。

**Step 2**：`_FilledState.build` 裡：
```dart
    if (profile.practiceGoals.isNotEmpty) {
      lines.add(_summaryLine(
        '練習目標',
        profile.practiceGoals.map(_practiceGoalLabel).join('、'),
      ));
    }
```
改成兩段（先卡在哪、後想達成什麼，呼應頁面新順序）：
```dart
    if (profile.stuckPoints.isNotEmpty) {
      lines.add(_summaryLine(
        '卡在哪',
        profile.stuckPoints.map(_stuckPointLabel).join('、'),
      ));
    }
    if (profile.practiceGoals.isNotEmpty) {
      lines.add(_summaryLine(
        '想達成什麼',
        profile.practiceGoals.map(_practiceGoalLabel).join('、'),
      ));
    }
```
`_practiceGoalLabel` switch 換成 Task 2 的新識別字＋新文案；新增 `_stuckPointLabel`（照抄 Task 5 Step 5 那份）。

底部提示「AI 會參考這些設定調整建議語氣」→「AI 會參考這些設定幫你抓方向、推你一步」。

**Step 3: 跑 widget test**

Run: `flutter test test/widget/features/user_profile/about_me_card_test.dart`
Expected: 先 FAIL（斷言舊文案的測試會炸），逐一把斷言換成新文案，加一條「填了 stuckPoints 時渲染「卡在哪」那一行」，直到 PASS。

**Step 4: Commit**
```bash
git add lib/features/user_profile/presentation/widgets/about_me_card.dart test/widget/features/user_profile/about_me_card_test.dart
git commit -m "改：關於我報告頁卡片跟著批2欄位改版，文案改教練導向"
```

---

### Task 8: 批2收尾——全套回歸

**Step 1**

Run: `flutter analyze lib test`
Expected: `No issues found!`

**Step 2**

Run: `flutter test`
Expected: 全綠。特別注意 `test/visual_proof/profile_mindmap_capture_test.dart`、`test/visual_proof/report_insight_proof_test.dart`——這兩個是視覺快照測試，若 fixture 資料用到舊 `PracticeGoal` 識別字要一併更新，且視覺快照圖檔可能需要用 `--update-goldens`（依專案既有慣例，先跑一次看有沒有 golden mismatch 再決定）。

**Step 3**

批2到這裡文案已由 Eric 逐段核可、風險屬低（純 App 端），可以視 CLAUDE.md 的標準交付路徑走 commit/push/Build & Distribute；批3還沒開始，先不要合併推播動作，讓批2自己一個交付單位。

---

## 批3：AI 指令風格反轉（高風險，完成後需雙審才可部署）

---

### Task 9: `_voiceLine` 指令反轉

**Files:**
- Modify: `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart`
- Test: `test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`（484行，本 Task 會動到裡面大量斷言）

**這是整個批3最關鍵、風險最高的一步：會刻意打破「主-only 輸出 byte-for-byte 不變」這條鎖測試。**

**Step 1: 讀懂現有鎖測試**

Run: `flutter test test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`
Expected: 目前全綠（改動前的基準線，記錄下來，之後才知道哪些是「預期改變」哪些是「不小心改壞」）。

**Step 2: 改 `_voiceLine`**

現在：
```dart
  static String? _voiceLine(EffectiveStyle effective) {
    final style = effective.interactionStyle;
    if (style == null) return null;
    final secondary = effective.secondaryStyle;
    if (secondary == null) {
      return '- Preferred voice: ${_styleLabel(style)}；${_stylePrompt(style)}';
    }
    return '- Preferred voice: 以${_styleLabel(style)}為主、'
        '${_styleLabel(secondary)}為輔；${_stylePrompt(style)}。'
        '${_secondaryStylePrompt(secondary)}';
  }
```

改成（兩行輸出，comfort-zone 框架＋stretch 規則）：
```dart
  static String? _voiceLine(EffectiveStyle effective) {
    final style = effective.interactionStyle;
    if (style == null) return null;
    final secondary = effective.secondaryStyle;
    final comfortDesc = secondary == null
        ? _styleLabel(style)
        : '以${_styleLabel(style)}為主、${_styleLabel(secondary)}為輔';
    return '- 使用者目前的舒適區：$comfortDesc。這不是你要模仿的模板，'
        '是他現在寫得出來的範圍。\n'
        '- 五種回覆風格請照常全力發揮，不要因為舒適區而收斂任何一種；'
        '至少一種要明顯超出他的舒適區。';
  }
```

`_stylePrompt`／`_secondaryStylePrompt` 兩個 helper 這裡不再被 `_voiceLine` 呼叫——檢查是否還有其他呼叫點（`grep -n "_stylePrompt\|_secondaryStylePrompt" lib/features/user_profile/domain/services/effective_style_prompt_builder.dart`），若無其他呼叫端，整個刪除（不留死程式碼）。

**Step 3: 更新測試**

`effective_style_prompt_builder_test.dart` 裡所有 `expect(context, contains('Preferred voice: ...'))` 全部要改成新格式的斷言，例如：
```dart
expect(context, contains('使用者目前的舒適區：幽默'));
expect(context, contains('不要因為舒適區而收斂任何一種'));
```

「主-only output is byte-for-byte identical to pre-pair format」這條測試名稱與內容本身要改掉——它原本的目的是保護回歸，但這次是**刻意**改變輸出，改成新測試：
```dart
test('comfort-zone framing never collapses to a template instruction', () {
  final effective = EffectiveStyle(interactionStyle: InteractionStyle.humorous);
  final context = builder.buildForAnalysis(
    global: UserProfile.create(
      interactionStyle: InteractionStyle.humorous,
      updatedAt: DateTime.utc(2026),
    ),
    partner: null,
    includePartnerOverride: false,
  );
  expect(context, isNot(contains('Preferred voice')));
  expect(context, contains('這不是你要模仿的模板'));
});
```
（其餘測試同理，逐一跑 `flutter test` 看 FAIL 訊息、對照新格式修正斷言字串，不要為了讓測試過而弱化斷言內容。）

**Step 4: 跑測試**

Run: `flutter test test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`
Expected: PASS（全部斷言都已更新為新格式）

**Step 5: Commit**
```bash
git add lib/features/user_profile/domain/services/effective_style_prompt_builder.dart \
        test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart
git commit -m "改：舒適區指令反轉——Preferred voice 模板改成舒適區標尺框架（刻意打破既有 byte-for-byte 鎖）"
```

---

### Task 10: `buildForCoachFollowUp` 補讀處境與邊界

**Files:**
- Modify: `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart`
- Test: 同上測試檔

**Step 1: 寫失敗測試**

```dart
test('buildForCoachFollowUp includes stuck points and boundary notes', () {
  final context = builder.buildForCoachFollowUp(
    global: UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      stuckPoints: [StuckPoint.fadesOut],
      notes: '不要太快邀約',
      updatedAt: DateTime.utc(2026),
    ),
    partner: null,
    includePartnerOverride: false,
  );
  expect(context, contains('話題卡住'));
  expect(context, contains('不要太快邀約'));
});
```

Run: `flutter test test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`
Expected: FAIL（現在的 `buildForCoachFollowUp` 不讀 stuckPoints/notes）

**Step 2: 實作**

`buildForCoachFollowUp` 現在只有 voiceLine + practiceGoals 兩段，加入 stuckPoints 與 notes：
```dart
  String? buildForCoachFollowUp({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) {
    final effective = resolveEffectiveStyle(
      global: global,
      partner: includePartnerOverride ? partner : null,
    );
    final lines = <String>[];

    final voiceLine = _voiceLine(effective);
    if (voiceLine != null) lines.add(voiceLine);

    if (effective.stuckPoints.isNotEmpty) {
      lines.add(
        '- Stuck points: ${effective.stuckPoints.map(_stuckPointLabel).join('、')}；'
        '這是使用者現在卡住的處境，回答時要接住這個情境，不要給通用建議。',
      );
    }

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- Practice focus: ${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- Boundary: $notes；這是使用者的邊界，任何建議都不能違反。');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 僅用來調整教練語氣與任務 framing；不要拿來推斷對方或寫長期人格。',
    );
    return _truncate(lines.join('\n'), coachFollowUpMaxChars);
  }
```
新增 `_stuckPointLabel`（同 Task 5/6 的文案）；`_goalLabel`/`_goalPrompt` 依 Task 2 表格更新成新識別字對應的文案。

**Step 3**：`coachFollowUpMaxChars` 常數從 500 改 900（Task 11 會同步放寬後端）。

**Step 4: 跑測試**

Run: `flutter test test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add lib/features/user_profile/domain/services/effective_style_prompt_builder.dart \
        test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart
git commit -m "加：Coach 1:1 補讀使用者卡在哪與邊界（原本故意不讀，這次拍板補上）"
```

---

### Task 11: `coach-chat/schemas.ts` 上限放寬

**Files:**
- Modify: `supabase/functions/coach-chat/schemas.ts:103`
- Test: `supabase/functions/coach-chat/*.test.ts`（先 `grep -rn "effectiveStyleContext" supabase/functions/coach-chat/*.test.ts` 找到驗證長度上限的測試）

**Step 1**：把 `effectiveStyleContext: z.string().max(500).nullable().optional(),` 改成 `z.string().max(900).nullable().optional(),`。

**Step 2**：找到既有測試裡如果有斷言「超過500字被拒絕」的案例，改成902字（超過新上限）才觸發拒絕，900字剛好通過。

**Step 3: 跑測試**

Run: `deno test supabase/functions/coach-chat/ --allow-all`（或依專案既有跑法，先看 `docs/shared-agent-rules.md` 或既有 CI script 用的指令）
Expected: PASS

**Step 4: Commit**
```bash
git add supabase/functions/coach-chat/schemas.ts supabase/functions/coach-chat/*.test.ts
git commit -m "改：coach-chat effectiveStyleContext 上限 500→900，配合補讀處境/邊界後內容變長"
```

---

### Task 12: `analyze-chat` 新增 `stretchLevels` 平行欄位

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（`openers` schema 說明處，約行394-436；main SYSTEM_PROMPT 的 schema 說明；repair schema 同段）
- Test: `supabase/functions/analyze-chat/*.test.ts`（先找現有 openers schema 相關測試）

**Step 1**：在 `OPENER_REPAIR_PROMPT` 與主 SYSTEM_PROMPT 的 schema 說明裡，`openers` 物件之後加一段：
```
  "stretchLevels": {
    "extend": "within" | "stretch" | "far",
    "resonate": "within" | "stretch" | "far",
    "tease": "within" | "stretch" | "far",
    "humor": "within" | "stretch" | "far",
    "coldRead": "within" | "stretch" | "far"
  }
```
並在 schema 說明文字裡補一句：「每個 stretchLevels 對應同名 opener 相對使用者舒適區的延伸程度；within=他現在就寫得出來／stretch=比他平常大膽一步但做得到／far=差距太大這次先不推；五個 key 裡至少一個要是 stretch。當使用者沒有提供舒適區設定（沒有 Preferred voice/舒適區資訊）時，全部回傳 "within"。」

**Step 2**：找到解析/驗證 AI 回應 JSON 的地方（`grep -n "openers\[" supabase/functions/analyze-chat/index.ts` 或找 response schema 驗證函式），比照 `openers` 五個 key 的存在性檢查，加一份 `stretchLevels` 的存在性/值域檢查（值只能是 within/stretch/far 三選一，缺漏或不合法時 fallback 為 "within" 而不是整包拒絕重試——避免這個新欄位變成新的 503 來源）。

**Step 3: 寫/改測試**

針對 AI 回應驗證邏輯的既有測試檔，加案例：
- `stretchLevels` 五個 key 都合法值 → 正常通過
- `stretchLevels` 缺一個 key → fallback 該 key 為 within，不整包拒絕
- `stretchLevels` 某 key 值不合法字串 → fallback 為 within

Run: `deno test supabase/functions/analyze-chat/ --allow-all`
Expected: 先 FAIL（新驗證邏輯還沒寫），實作後 PASS

**Step 4: Commit**
```bash
git add supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/*.test.ts
git commit -m "加：analyze-chat 新增 stretchLevels 平行欄位，AI 自判延伸程度取代批1本地規則"
```

---

### Task 13: client 端停用本地規則、改讀新欄位

**Files:**
- Modify: `lib/features/user_profile/domain/services/reply_stretch_classifier.dart`
- Modify: 呼叫 `ReplyStretchClassifier.classifyByTypeString` 的畫面（`grep -rn "ReplyStretchClassifier" lib/ --include="*.dart" | grep -v test`）
- Test: `test/unit/features/user_profile/domain/reply_stretch_classifier_test.dart`

**Step 1**：找出所有呼叫 `ReplyStretchClassifier` 的地方，確認它們現在怎麼取得「延伸標記」顯示在 UI 上（大概率是分析結果畫面渲染五張回覆卡時呼叫）。

**Step 2**：改成優先讀 analyze-chat 回應裡的 `stretchLevels[type]`（後端已在 Task 12 提供），`ReplyStretchClassifier` 本地對照表**保留檔案但加註解**標示「已由後端 stretchLevels 取代，僅在後端未提供該欄位時（例如舊版 App 呼叫到還沒升級的 Edge Function）當 fallback」——不要整個刪除，因為要應付「舊 client／新 Edge」或「新 client／還沒部署完的舊 Edge」這種部署時序空窗（Edge Function 部署與 App Store 審核不同步，client 要能容忍後端還沒給 `stretchLevels` 的情況）。

**Step 3: 跑測試**

Run: `flutter test test/unit/features/user_profile/domain/reply_stretch_classifier_test.dart`
Expected: 既有測試應該不受影響（本地規則邏輯沒變，只是變成 fallback），確認 PASS；另外在呼叫端的 widget test 加一條「後端有給 stretchLevels 時優先使用，不落地方規則」。

**Step 4: Commit**
```bash
git add lib/features/user_profile/domain/services/reply_stretch_classifier.dart <呼叫端畫面路徑>
git commit -m "改：延伸標記優先讀後端 stretchLevels，本地規則降級為部署空窗期 fallback"
```

---

### Task 14: 清除兩行死指令

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（`sessionContext.userStyle`／`userInterests`，約行6796-6797、7441-7442）
- Test: 若有測試斷言這兩行存在（不太可能，但先 `grep -rn "userStyle\|userInterests" supabase/functions/analyze-chat/*.test.ts` 確認）

**Step 1**：刪除兩處 `- 用戶風格：${sessionContext.userStyle || "未提供"}` / `` `- User style: ${sessionContext.userStyle || "not provided"}` `` 及對應的 `userInterests` 行。確認 `sessionContext` 型別定義裡這兩個欄位是否還有其他讀取點，若無其他用途，型別定義裡的欄位也一併移除（不留死欄位）。

**Step 2: 跑測試**

Run: `deno test supabase/functions/analyze-chat/ --allow-all`
Expected: PASS（這兩行純輸出裝飾字串，理論上不影響任何既有測試斷言；若有測試斷言 contextInfo 包含這兩行文字，代表測試也在鎖死指令，要一併清掉那條斷言）

**Step 3: Commit**
```bash
git add supabase/functions/analyze-chat/index.ts
git commit -m "清：analyze-chat 移除兩行永遠是「未提供」的死指令（與 effectiveStyleContext 重複打架）"
```

---

### Task 15: 批3收尾——全套回歸

**Step 1**

Run: `flutter analyze lib test`
Expected: `No issues found!`

**Step 2**

Run: `flutter test`
Expected: 全綠

**Step 3**

Run: `deno test supabase/functions/analyze-chat/ supabase/functions/coach-chat/ --allow-all`（或專案既有 CI 指令）
Expected: 全綠

**Step 4**

回顧 Task 9 Step 1 記錄的「改動前基準線」，列出所有預期改變的斷言／行為，確認沒有意外之外的行為變化（例如 token 用量、其他 prompt 段落被誤動）。

---

### Task 16: 批3雙審與部署前檢查

批3屬 AGENTS.md 定義的 Critical Gotchas 高風險區（AI prompt/token/cost 行為），依專案規則：

1. 呼叫 Codex 進行對抗式雙審（`codex:rescue` 或專案既有的 cross-model-review 流程），重點審查：
   - `_voiceLine` 反轉後是否真的不會讓五種回覆收斂（描述 vs 實測要對照）
   - `stretchLevels` 缺欄位時的 fallback 邏輯是否會變成新的 503 來源
   - `coachFollowUpMaxChars`/`effectiveStyleContext.max` 放寬後，實際組合出來的 prompt 長度有沒有真的在 900 字內（不是理論上，是用最長情境跑一次算字數）
2. 雙審 findings 全部處理完、APPROVED 或 Eric 明確 waiver 後，才能部署 Edge Function（`analyze-chat` 部署需要 `--no-verify-jwt`，見 AGENTS.md Critical Gotchas）
3. 部署後留 Eric 真機 dogfood：分析結果能不能看到 stretch 標記、Coach 1:1 能不能接住「我常聊到一半冷掉」這類處境（見批3設計文件第六節「怎麼驗」）
