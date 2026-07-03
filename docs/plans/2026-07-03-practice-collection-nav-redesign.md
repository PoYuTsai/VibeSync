# 練習室導覽重構＋圖鑑 gacha 化 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計定稿：`docs/plans/2026-07-03-practice-collection-nav-redesign-design.md`（先讀）。

**Goal:** 導覽鏈路改為「首頁 → 圖鑑（gacha hub）→ 練習室對話」：翻牌全收斂圖鑑、點已抽卡進對話、鎖卡近全黑剪影＋問號。

**Architecture:** 純 client UI。翻牌觸發點與付費 gating 從 `practice_chat_screen.dart` 搬到 `practice_collection_screen.dart`（搬家非複製）；controller 新增一條免費開局縫 `startSessionWithProfile`。`drawNewPracticeGirl()` 本體與 requestId 扣費鏈路**一行不動**。

**Tech Stack:** Flutter 3.x、Riverpod、go_router、既有 `PracticeDrawCeremony` 儀式動畫（只搬掛載點）。

**鐵則（每個 task 都適用）：**
- 絕不改 `drawNewPracticeGirl()`、`_pendingDrawStore`、`_saveDraftFromState` 的內部邏輯。
- 絕不碰 migration／Edge／RPC。
- 絕不 `git add pubspec.lock`（會漂）。
- 測試指令一律 targeted scope：`flutter test test/widget/features/practice_chat/ test/unit/features/practice_chat/`（unit 路徑不存在就先 `find test -path "*practice*"` 確認）。
- 全量 suite 有 ~28 個 baseline stale 失敗與本案無關，只看 practice scope 是否零新增失敗。

---

### Task 1: Controller 新縫 `startSessionWithProfile(profileId)`

**Files:**
- Modify: `lib/features/practice_chat/data/providers/practice_chat_providers.dart`（在 `resumeSession`（約 :567）後面加）
- Test: 找既有 controller unit 測試檔（`grep -rln "resumeSession\|drawNewPracticeGirl" test/ | head`），跟著同檔同 harness 寫；找不到就新建 `test/unit/features/practice_chat/practice_chat_controller_start_with_profile_test.dart`，harness 抄同目錄鄰檔。

**行為規格：**
1. 該 profileId 在 `PracticeSessionRepository.recentSessions()` 有場次（同 profileId 取最新一段）→ 走 `resumeSession(session)` 續玩。
2. 沒有 → 純 client 開新局：state 建構**比照 `drawNewPracticeGirl` 成功分支（:623-652）**，差異＝girl 從 `girlProfileById(profileId)` 解析（解析不到直接 return，不碰 state）、**不打 `_api.drawProfile`、不碰 `_pendingDrawStore`、不呼叫 `_saveDraftFromState`**（邊界防護：翻牌 draft 只由翻牌鏈路寫）、不帶 drawFreeAllowance 等 draw 額度欄位（沿用 prior 的值）。
3. 兩條路都要 `_hintGeneration++` 與 `_clearPendingHintRequestId()`（換場慣例，抄 `resumeSession`）。
4. 開新局也要 `_notifyProfileUnlocked(girl.profileId)`（冪等，無害）。

**Step 1: Write the failing tests**（三條）

```dart
// 1. 無既有場次 → 開新局：girl 正確、revealed、messages 空、roundIndex 1
// 2. 有既有場次 → 續玩：state.sessionId == 該 session.id、messages 保留
// 3. 開新局不寫翻牌 draft、不打 draw API（用既有 fake/spy api 與 draft store，
//    斷言 zero interactions；spy 怎麼接看同檔鄰測試怎麼 stub drawProfile）
```

controller 的 repository 依賴怎麼拿：先 `grep -n "PracticeSessionRepository\|practiceSessionRepositoryProvider" lib/features/practice_chat/data/providers/practice_chat_providers.dart` 確認 controller 建構時有沒有 repo；沒有就從 provider graph 注入（比照 `_pendingDrawStore` 的注入方式），**不要**在 controller 裡直接 `ref.read` 新 provider 以外的野路子。

**Step 2:** 跑測試確認 FAIL（method 不存在）。

**Step 3: 實作**

```dart
/// 圖鑑點已抽卡進對話：有既有場次續玩、沒有就以該角色免費開新局。
/// 不走 draw、不扣翻牌額度、不寫翻牌 draft（draft 只由翻牌鏈路寫）。
void startSessionWithProfile(String profileId) {
  final existing = _sessionRepository
      .recentSessions()
      .where((s) => s.profileId == profileId)
      .firstOrNull;
  if (existing != null) {
    resumeSession(existing);
    return;
  }
  final girl = girlProfileById(profileId);
  if (girl == null) return; // catalog 解析不到：不碰 state
  _hintGeneration++;
  _clearPendingHintRequestId();
  final prior = state;
  final sessionId = const Uuid().v4();
  final difficulty = prior.difficulty.isNotEmpty
      ? prior.difficulty
      : practiceDifficultyId(prior.difficultyPreference);
  state = PracticeChatState(
    sessionId: sessionId,
    createdAt: DateTime.now(),
    girl: girl,
    personaId: girl.personaId,
    personaLabel: practicePersonaLabel(girl.personaId),
    difficulty: difficulty,
    difficultyLabel: practiceDifficultyLabel(difficulty),
    difficultyPreference: prior.difficultyPreference,
    drawStatus: PracticeDrawStatus.revealed,
    roundIndex: 1,
    visiblePracticeThreadId: sessionId,
    learningMode: prior.learningMode,
    temperatureScore: prior.learningMode == PracticeLearningMode.beginner
        ? kInitialPracticeTemperatureScore
        : null,
    familiarityScore: prior.learningMode == PracticeLearningMode.beginner
        ? kInitialPracticeFamiliarityScore
        : null,
    relationshipStageLabel:
        prior.learningMode == PracticeLearningMode.beginner
            ? kInitialPracticeRelationshipStageLabel
            : null,
    hintUsedCount: 0,
    drawFreeAllowance: prior.drawFreeAllowance,
    drawFreeUsed: prior.drawFreeUsed,
    drawFreeRemaining: prior.drawFreeRemaining,
    drawExtraCost: prior.drawExtraCost,
    drawNextResetAt: prior.drawNextResetAt,
  );
  _notifyProfileUnlocked(girl.profileId);
}
```

（欄位名以實際 `PracticeChatState`（:42）為準；`firstOrNull` 需 `package:collection` 或手寫 for loop——看檔內既有用法。）

**Step 4:** 跑測試 PASS。

**Step 5: Commit**

```bash
git add lib/features/practice_chat/data/providers/practice_chat_providers.dart test/<測試檔>
git commit -m "圖鑑點卡進對話 controller 縫：startSessionWithProfile 續玩/免費開新局，不碰翻牌 draft 與扣費"
```

---

### Task 2: 鎖卡近全黑剪影＋大問號

**Files:**
- Modify: `lib/features/practice_chat/presentation/screens/practice_collection_screen.dart`（`_CollectionCardPhoto` :455-510、`_CollectionCard` 鎖卡 overlay :383-402、`_greyscaleMatrix` :30）
- Test: `test/widget/features/practice_chat/practice_collection_screen_test.dart`（既有檔，先讀）

**Step 1: 失敗測試**——鎖卡不再出現 `Icons.lock_rounded`、出現 key `collection-mystery-<profileId>` 的「？」文字；名字仍是「？？？」。既有斷言鎖頭 icon 的測試改掉。

**Step 2:** 跑 `flutter test test/widget/features/practice_chat/practice_collection_screen_test.dart` 確認 FAIL。

**Step 3: 實作**
- `_greyscaleMatrix` 旁新增剪影矩陣（灰階係數整體 ×0.07，即亮度壓到 ~7% 保輪廓）：

```dart
/// 鎖卡剪影：灰階×0.07 近全黑，只留人形輪廓隱約可辨。
const List<double> _silhouetteMatrix = <double>[
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0, 0, 0, 1, 0, //
];
```

- `_CollectionCardPhoto` locked 分支：ColorFilter 換 `_silhouetteMatrix`，黑 overlay alpha 從 0.55 降到 0.25（矩陣已壓暗，overlay 只做勻化）。
- `_CollectionCard` 鎖卡中央：鎖頭圓徽換大「？」：

```dart
Center(
  child: Text(
    '？',
    key: ValueKey('collection-mystery-${profile.profileId}'),
    style: AppTypography.headlineLarge.copyWith(
      color: Colors.white.withValues(alpha: 0.55),
      fontSize: 44,
      fontWeight: FontWeight.w900,
    ),
  ),
),
```

- fallback（asset 載入失敗）鎖卡已顯示 '?'，行為不變。

**Step 4:** 測試 PASS。**Step 5: Commit**：`git commit -m "圖鑑鎖卡改近全黑剪影＋大問號：不露人像細節，保輪廓神秘感"`

---

### Task 3: 點已抽卡進對話

**Files:**
- Modify: `practice_collection_screen.dart`（`_CollectionCard.onTap` :322-330；`_CollectionCard` 要能拿 ref → 改 ConsumerWidget）
- Test: 同 Task 2 測試檔

**Step 1: 失敗測試**——點已解鎖卡：controller 收到 `startSessionWithProfile(profileId)`（override provider 用 spy notifier，比照檔內既有 override 手法）＋ router push `/practice-chat`（測試 harness 若已有 GoRouter stub 就斷言 location；沒有就只驗 controller 呼叫＋onTap 不再開全螢幕照片 dialog）。

**Step 2:** FAIL。

**Step 3: 實作**——`_CollectionCard` 改 `ConsumerWidget`，onTap unlocked 分支：

```dart
if (unlocked) {
  ref
      .read(practiceChatControllerProvider.notifier)
      .startSessionWithProfile(profile.profileId);
  context.push('/practice-chat');
  return;
}
```

移除 `showPracticeGirlFullPhoto` 呼叫與 import（看大圖由對話頁 profile sheet 承擔）。鎖卡 snackbar 提示不動。

**Step 4:** PASS。**Step 5: Commit**：`git commit -m "圖鑑點已抽卡直進練習室對話：有進度續玩、沒進度免費開新局"`

---

### Task 4a: 圖鑑翻牌鈕＋付費 gating 搬家

**Files:**
- Modify: `practice_collection_screen.dart`（`_CollectionHeader` :152-261 改造＋screen state 加 gating）
- 參考（先讀再搬）: `practice_chat_screen.dart` `_requestNewPartner`（:111-168）
- Test: 同 Task 2 測試檔

**設計：**
- `_CollectionHeader` 的 `ShaderMask('Collection')` 外包 `Row`：左標題、右翻牌鈕（`ValueKey('collection-draw-button')`）。鈕＝品牌漸層膠囊（`AppColors.ctaStart→ctaEnd` 或金橘 `Color(0xFFFFC24D)→brandFlame` 配頁面視覺）＋`Icons.style_rounded`＋「翻牌」字樣＋微光 boxShadow。
- **今日未翻（`!state.isRevealed`）→ 脈動微光**：`AnimationController` repeat 呼吸 boxShadow alpha。**repeat 鐵則**：只在 `!state.isRevealed && !reduceMotion` 時跑，revealed／dispose 一律 stop（不然 `pumpAndSettle` 會 hang，這是本 repo 既定鐵則）。
- **gating 整段搬家**（語義照抄 `_requestNewPartner`，兩態分流）：
  - `state.isDrawing` → return（防連點）。
  - **locked（今日首抽）**：直接 `drawNewPracticeGirl()`（Free 每日首抽免費，比照 `_PracticeLockedEntry` 現行為；`drawUpgradeRequired`/`drawQuotaExceeded` 已鎖時分別導 paywall／snackbar 顯示 `errorMessage`）。
  - **revealed（換一位）**：`subscription.isFreeUser || state.drawUpgradeRequired` → `context.push('/paywall')`；`drawQuotaExceeded` → `lockDrawQuotaExceeded()`＋snackbar；額度不足（搬 `_hasInsufficientPaidDrawQuota`）→ 同鎖；免費次數用完要扣額度（搬 `_needsPaidDrawConfirmation`＋`_paidDrawSpendMessage`）→ **改用 `showDialog` AlertDialog 確認**（圖鑑頁沒有 inline notice 區，不搬 `_NewPartnerQuotaNotice` 的二段按鈕模式），確認才 `drawNewPracticeGirl()`。
- 402/429 事後錯誤呈現：`ref.listen` controller，`drawUpgradeRequired`→paywall 導引 snackbar＋動作鈕、`drawQuotaExceeded`/`errorMessage`→snackbar。文案沿用 controller 現成 `errorMessage`，不造新文案。

**Steps:** 失敗測試（鈕存在、locked 點擊觸發 draw、Free revealed 點擊導 paywall、需確認時彈 dialog）→ FAIL → 實作 → PASS → Commit：`git commit -m "翻牌鈕搬圖鑑 Collection 標題右側：兩態 gating 搬家＋付費確認 dialog＋未翻脈動微光"`

---

### Task 4b: 儀式 overlay 搬圖鑑＋揭曉後新卡高亮定位

**Files:**
- Modify: `practice_collection_screen.dart`、`practice_chat_screen.dart`（:300-306 Stack 移除）
- Test: 同 Task 2 測試檔＋跑 `test/widget/features/practice_chat/`（ceremony 既有測試在哪先 `grep -rln "PracticeDrawCeremony" test/`，掛載點換頁後那些測試要跟著搬 harness）

**Step 1: 實作搬家**——collection 的 `Scaffold.body` 外包：

```dart
body: Stack(children: [
  <原 body Container>,
  const Positioned.fill(child: PracticeDrawCeremony()),
]),
```

chat screen :301-306 的 Stack 拆掉還原成 `content` 直接回傳。**搬家非複製：全 repo `grep -n "PracticeDrawCeremony()" lib/` 確認只剩圖鑑一處掛載。**

**Step 2: 揭曉高亮**——screen state 記 `_highlightProfileId`；`ref.listen(practiceCollectionProvider)` 集合新增時取新 id，`Scrollable.ensureVisible`（卡片包 key）捲動定位＋該卡 border 微光高亮 1.5s 後淡出（單次 `AnimationController.forward`，非 repeat）。稀有度 filter 開著時新卡可能不在 visible 清單 → 高亮前先 `setState(() => _filter = null)`。

**Step 3:** 失敗測試→實作→PASS（含既有 ceremony 測試零回歸）。

**Step 4: Commit**：`git commit -m "翻牌儀式 overlay 搬圖鑑頁＋揭曉後新卡捲動定位高亮，練習室掛載點移除"`

---

### Task 5: 練習室收法（三處）

**Files:**
- Modify: `practice_chat_screen.dart`
- Test: `practice_chat_screen_style_test.dart`＋相關既有測試（先 `grep -rln "換一位\|翻開今日對象\|practice-draw-cta" test/`）

**三處改動：**
1. `_PracticeOpeningControls`（:461-513）：刪頂部 Row（「為你抽了一位…」＋「換一位」TextButton），刪 `onNewPartner` 參數與 :234 的傳入。
2. `_PracticeLockedEntry`（:336-458）：主 CTA（`practice-draw-cta`）改導引鈕「去圖鑑翻牌」→ `context.push('/practice-collection')`；`drawNewPracticeGirl` 呼叫移除；402/429 補充文案區塊保留（state 還原自 draft 時仍可能帶旗標）。副標改「到角色圖鑑翻開今日對象，開始練習。」
3. `_DebriefActionsBar`（:1867）「換一位」→「去圖鑑換人」，`onNewPartner` callback 在 screen 層（:293）改傳 `() => context.go('/practice-collection')`——**先讀 `lib/app/routes.dart`:165-180 確認 `/practice-collection` 是 top-level GoRoute、`go` 會收斂 stack**；若是 shell 內巢狀路由則改用 `push` 並在計畫偏差記錄。

**Steps:** 逐處失敗測試→FAIL→實作→PASS→單顆 commit：`git commit -m "練習室翻牌入口全收斂圖鑑：刪換一位控制列、locked 入口改導引、debrief 換人改回圖鑑"`

---

### Task 6: 首頁——hero 進圖鑑＋圖鑑 chip 移除

**Files:**
- Modify: `lib/features/practice_chat/presentation/widgets/practice_room_entry_card.dart`（:36）
- Modify: `lib/features/learning/presentation/screens/learning_screen.dart`（:60-74 Row 拆掉只留標題、:16-17 import 清理）
- Modify: `practice_collection_screen.dart`（刪 `PracticeCollectionEntryChip` :514-551 死碼）
- Test: `test/widget/features/practice_chat/practice_room_entry_card_test.dart`＋collection 測試檔中 chip 相關測試刪除

**Steps:** 失敗測試（hero onTap push `/practice-collection`）→ 實作：:36 改 `onTap: () => context.push('/practice-collection')` → chip 移除＋死碼刪 → PASS → Commit：`git commit -m "首頁 hero 改進圖鑑＋移除右下角色圖鑑入口 chip（圖鑑由 hero 承擔）"`

---

### Task 7: chat screen 死碼清理＋收斂驗證

**Files:**
- Modify: `practice_chat_screen.dart`：刪 `_requestNewPartner`、`_startNewPartner`、`_regeneratePersona`、`_needsPaidDrawConfirmation`、`_hasInsufficientPaidDrawQuota`、`_paidDrawSpendMessage`、`_confirmPaidNewPartnerSpend` state、`_NewPartnerQuotaNotice`（:277-279 呼叫處一併）。
- Modify: `practice_chat_providers.dart`：`startNewPartner`/`regeneratePersona` wrapper（:701-704）若已無呼叫者（`grep -rn "startNewPartner\|regeneratePersona" lib/ test/`）一併刪；有測試引用就改測試直呼 `drawNewPracticeGirl`。

**Steps:**
1. 逐一 grep 確認零呼叫者後刪除。
2. `flutter analyze lib/features/practice_chat lib/features/learning`（0 issues）。
3. `flutter test test/widget/features/practice_chat/ && flutter test <practice unit 測試路徑>` 全綠。
4. Commit：`git commit -m "清掉練習室翻牌 gating 死碼：翻牌觸發點唯一收斂圖鑑"`

---

### Task 8: 收尾驗證＋Codex review gate

1. `flutter analyze`（全 repo；只允許既有 baseline issues）。
2. practice scope 全測綠＋確認零新增失敗。
3. **push**（commit 後立即 push，全域鐵則）。
4. **Codex review（必過才可宣稱 dogfood safe）**：本案動 paywall 導流（gating 搬家）＝高風險 zone，照 `feedback_cc_calls_codex_review_directly` 直呼 `codex:rescue` 送審 range（Task 1 首 commit 到最後）。review 重點指名：gating 搬家語義等價性（Free/paywall/quota/確認四分流）、draft 不被點卡開局污染、ceremony 單一掛載、repeat 動畫 gate。
5. 拿到 APPROVED 才回報 Eric；本案需新 TF build 才能 dogfood（首頁/圖鑑/練習室動線全是 client 行為）。
