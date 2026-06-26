# 翻牌儀式「完美復刻」實作計畫（Batch A–D）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 高風險動畫，**逐批雙審**（Codex evidence 後才說 dogfood safe）。每批落地→全量測試→Codex→Eric TF 目檢，再開下一批。

**Goal:** 把每日翻牌揭曉儀式從現有「單段翻牌」升級成參考影片的「兩段升階」（白卡預覽 → 收回蓄力 → 盛大金框典藏卡＋軌道彗星 halo），同時守住現有 forward-only／零 Timer／pumpAndSettle 必收斂／reduce-motion 露 hero 鐵則。

**Architecture:** 退役 `_flip`（2400ms 單段）→ 單一 forward-only `_reveal`（7500ms）＋具名 beat 常數驅動兩段時間軸。儀式純由 `drawStatus` 狀態機驅動，不碰計費／網路／quota／RPC／migration／Edge。新繪圖（軌道 halo、金框卡、能量邊框）逐批疊上，每批先讓既有 37 測 + 新 beat 測全綠再交付。

**Tech Stack:** Flutter 3.x、`AnimationController`/`CustomPainter`（純原生、零 lottie/rive/序列幀）、Riverpod（`practiceChatControllerProvider`、`practiceDrawSfxProvider`）、`flutter_test`（widget test）。

**設計來源：** `docs/plans/2026-06-26-翻牌儀式復刻-design.md`
**主檔：** `lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart`（903 行）
**測試契約檔：** `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`（37 測；儀式段 981–1264、音效段 1297–1403）

---

## 共通鐵則（每批每步都不得破）

1. **forward-only**：`_reveal` 單向 `forward(from:0)`，零 `Timer`／`Future.delayed`／`repeat()`；`completed` → `_toHidden()`。
2. **唯一 repeat = `_waiting`**，且 gate 在「drawing 且非 reduce-motion」；reveal/error/402/429/hidden/dispose 一律 `stop()`＋`stopWaitingLoop()`。故 `pumpAndSettle` 必收斂。
3. **reduce-motion = 逃生閥**：reveal 當下 `_toHidden()` 露 hero，正面卡永不出現；haptic／一次性音效照觸發，不啟動 `_waiting` loop。
4. **正面卡禁字串**：正面 meta 用 `·` 串接，**絕不**出現 hero 的 `「名字，年齡」`（`${girl.displayName}，${girl.age}`）精確字串——否則撞 line 1087/1069 測。
5. **三條 controller dispose 先收**；`_sfx` 於 `initState` 以 `ref.read` 鎖定、dispose 不碰 ref。
6. **確定性繪圖**：所有 painter 零 `Random`、`shouldRepaint` 精準。

## 既有測試契約（Batch A 不得回退，逐條對照）

| 測試（行號） | 契約 | Batch A 對應 |
|---|---|---|
| 抽牌中浮現卡背（1046） | drawing → `back` findsOne、`front` findsNothing | drawing 分支不動 |
| reveal 走完露 hero（1069） | 全 settle → back/front 皆 nothing、hero findsOne、`名字，年齡` findsOne（僅 hero） | 新 7.5s 時間軸 settle 後 `_toHidden` |
| **正面卡暫留（1090）** | reveal 後 pump **1500ms** → `front` findsOne；再 pumpAndSettle → `front` nothing | beat 須保證 **t=1500ms 在白卡預覽段**（見下方時間軸）|
| reduce-motion 跳翻面（1116） | reveal → `front` nothing、hero findsOne | reduce-motion 早退不變 |
| 等待微動（1162） | drawing 中 float 變化、`back` findsOne/`front` nothing | drawing 分支不動 |
| 等待中 402（1196） | pumpAndSettle 收斂、`front` nothing、hero nothing、`upgrade` findsOne | 失敗兜底不變 |
| reduce-motion 等待靜止（1223） | float 恆定 | drawing 分支不動 |
| 音效 ×6（1297–1403） | whoosh=1/waitingStart/waitingStop/chime/looping 計數 | sfx 呼叫點維持「一次」語意 |

---

## 兩段升階時間軸（Batch A 鎖定，B–D 沿用）

`_reveal` 全長 **7500ms**。具名 beat 常數（fraction = ms / 7500）：

| 常數 | fraction | 對應 ms | 區間內容 |
|---|---|---|---|
| `_kFlip1End` | `0.0933` | 700 | 卡背→**白卡預覽** 翻面（rotateY 0→π，中點 flash） |
| `_kPreviewEnd` | `0.3333` | 2500 | 白卡停留、資訊浮出（屏息：waiting loop 已停） |
| `_kRechargeEnd` | `0.4133` | 3100 | 翻回卡背（蓄力重啟） |
| `_kHaloClimax` | `0.5733` | 4300 | 卡背發亮、光環 sweep 衝高潮 |
| `_kGrandFlipEnd` | `0.6667` | 5000 | 高潮翻面 卡背→**典藏卡**＋flash |
| `_kHoldEnd` | `0.8667` | 6500 | 典藏卡停留、資訊落位、光環 settle |
| （end） | `1.0` | 7500 | overlay 淡出，露出底下 hero |

**關鍵不變量**：t=1500ms（fraction 0.2）落在 `[_kFlip1End, _kPreviewEnd]` → 白卡預覽顯正面 → 守 line 1090 測。t=3600ms（0.48）落在 `[_kRechargeEnd, _kHaloClimax]` → 顯卡背。t=5600ms（0.747）落在 `[_kGrandFlipEnd, _kHoldEnd]` → 顯典藏卡正面。

---

## Batch A — 兩段骨架（最高風險，雙審）

**目標**：退役 `_flip`→`_reveal` 兩段時間軸，**複用現有卡面 `_CeremonyCardFront`/`_CeremonyCardBack`＋`_SweepGlowPainter`**（無新 painter），跑通時間軸＋reduce-motion＋pumpAndSettle＋既有音效 beat。

**Files:**
- Modify: `lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart`
- Test: `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`

### Task A1：新增「兩段升階」beat 邊界測試（紅燈）

先寫 4 個釘住新行為的測試，對著「現有單段 `_flip`」必失敗。加在儀式段末（line 1264 之後、音效段之前）。

**Step 1: 寫失敗測試**

```dart
  // ── 兩段升階儀式骨架（Batch A）──────────────────────────────────────────
  Future<void> _drawToReveal(
    WidgetTester tester, {
    required Completer<PracticeDrawResult> completer,
    required PracticeGirlProfile girl,
  }) async {
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 600)); // 等待微動
    completer.complete(_drawResultFor(girl));
    await tester.pump(); // 進入 revealing：_reveal.forward(from:0)
  }

  testWidgets('兩段升階：第一段翻出白卡預覽（~1.5s 顯正面卡、不顯卡背）',
      (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await _drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(const Duration(milliseconds: 1500)); // 白卡預覽段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：蓄力段翻回卡背（~3.6s 顯卡背、不顯正面）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await _drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(const Duration(milliseconds: 3600)); // 蓄力段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：高潮後典藏卡停留（~5.6s 顯正面卡）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await _drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(const Duration(milliseconds: 5600)); // 典藏卡停留段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：整條 7.5s 時間軸 pumpAndSettle 收斂、最終露 hero',
      (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle(); // 整條走完必收斂

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
  });
```

**Step 2: 跑測試確認紅燈**

Run: `flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart --plain-name "兩段升階"`
Expected: FAIL（現有單段 `_flip`：~3.6s 早已 settle 露 hero，無卡背；~5.6s 同；白卡段時間點不符）。

**Step 3: Commit 紅燈測試**

```bash
git add test/widget/features/practice_chat/practice_chat_screen_style_test.dart
git commit -m "test(practice-chat): 翻牌兩段升階 beat 邊界測試（Batch A 紅燈）"
```

### Task A2：`_flip`→`_reveal` 控制器＋具名 beat 常數

**Step 1: 換控制器宣告**（取代 line 60–63 `_flip`）

```dart
  // 兩段升階揭曉時間軸（白卡預覽→收回蓄力→盛大典藏卡→淡出），全部塞進這一條
  // forward-only controller（無 Timer/repeat）。退役舊 `_flip`（單段 2400ms）。
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7500),
  );
```

**Step 2: 換 beat 常數**（取代 line 83–88 `_kRotateEnd`/`_kHoldEnd`）

```dart
  // _reveal 兩段升階切點（0..1，沿用具名 beat 手法；fraction = ms / 7500）：
  static const double _kFlip1End = 0.0933; // ~700ms  卡背→白卡預覽 翻面
  static const double _kPreviewEnd = 0.3333; // ~2500ms 白卡停留、資訊浮出（屏息）
  static const double _kRechargeEnd = 0.4133; // ~3100ms 翻回卡背（蓄力重啟）
  static const double _kHaloClimax = 0.5733; // ~4300ms 卡背發亮、光環衝高潮
  static const double _kGrandFlipEnd = 0.6667; // ~5000ms 高潮翻面→典藏卡
  static const double _kHoldEnd = 0.8667; // ~6500ms 典藏卡停留、落位、settle
  // _kHoldEnd → 1.0 (~7500ms)：overlay 淡出露 hero
```

**Step 3: 全檔 `_flip` → `_reveal` 改名**（listener、status listener、`_toHidden`、`_onStateChange`、`build` overlay fade、`_buildCaption`、`_buildStage`、dispose）。逐處：
- line 95 `_flip.addListener(_onTick);` → `_reveal.addListener(_onTick);`
- line 97–101 status listener：`_flip.addStatusListener` → `_reveal.addStatusListener`
- line 106 `!_flip.isAnimating` → `!_reveal.isAnimating`
- line 124 `_flip.value = 0;` → `_reveal.value = 0;`
- line 143–145、line 180、line 189–191：`_flip` → `_reveal`
- line 205 `_flip.dispose();` → `_reveal.dispose();`
- line 226 overlay fade、line 265 caption：`_flip.value` → `_reveal.value`

**Step 4: 跑既有測試（確認改名沒破回退，beta 測仍紅）**

Run: `flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart`
Expected: 既有 33 綠、4 個「兩段升階」仍 FAIL（時間軸尚未重寫）。

**Step 5: Commit**

```bash
git add lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart
git commit -m "refactor(practice-chat): 退役 _flip 換 forward-only _reveal＋具名 beat 常數（Batch A 骨架）"
```

### Task A3：重寫 `_buildStage` reveal 分支為兩段時間軸

**Step 1: 取代 line 338–418**（reveal 分支，drawing 分支 line 287–336 完全不動）

```dart
    // ── 兩段升階揭曉：白卡預覽 → 收回蓄力 → 盛大典藏卡 → 淡出 ──
    final f = _reveal.value;
    double seg(double from, double to) =>
        ((f - from) / (to - from)).clamp(0.0, 1.0);

    double angle; // rotateY 角度
    bool showFront; // 過半才換正面
    double frontAppear = 1; // 正面資訊浮出
    double frontDepart = 0; // 落位下沉
    double backGlow = 0.6; // 卡背金光
    double sweepRot = 0; // 光環旋轉進度
    double sweepIntensity = 0; // 光環強度
    double flashCenter = -1; // 觸發 flash 的旋轉中點（rot 0..1）；<0 不畫

    if (f < _kFlip1End) {
      // 第一段：卡背→白卡預覽（rotateY 0→π）。
      final rot = seg(0, _kFlip1End);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 0;
      flashCenter = rot;
      sweepRot = rot;
      sweepIntensity = math.sin(math.pi * rot) * 0.7;
    } else if (f < _kPreviewEnd) {
      // 白卡停留、資訊浮出（屏息）。
      angle = math.pi;
      showFront = true;
      frontAppear = Curves.easeOut.transform(seg(_kFlip1End, _kPreviewEnd));
    } else if (f < _kRechargeEnd) {
      // 翻回卡背（蓄力重啟），rotateY π→0。
      final rot = 1 - seg(_kPreviewEnd, _kRechargeEnd);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 1;
      flashCenter = rot;
    } else if (f < _kHaloClimax) {
      // 卡背發亮、光環 sweep 衝高潮（Batch A 複用 _SweepGlowPainter）。
      final climb = seg(_kRechargeEnd, _kHaloClimax);
      angle = 0;
      showFront = false;
      backGlow = 0.6 + 0.4 * climb;
      sweepRot = climb;
      sweepIntensity = climb;
    } else if (f < _kGrandFlipEnd) {
      // 高潮翻面：卡背→典藏卡（Batch A 仍用現有正面，Batch C 換金框）。
      final rot = seg(_kHaloClimax, _kGrandFlipEnd);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 0;
      backGlow = 1;
      flashCenter = rot;
      sweepRot = rot;
      sweepIntensity = 1 - rot;
    } else if (f < _kHoldEnd) {
      // 典藏卡停留、資訊落位、光環 settle。
      angle = math.pi;
      showFront = true;
      frontAppear = Curves.easeOut.transform(seg(_kGrandFlipEnd, _kHoldEnd));
    } else {
      // 淡出，露出底下 hero。
      angle = math.pi;
      showFront = true;
      frontAppear = 1;
      frontDepart = seg(_kHoldEnd, 1);
    }

    final flash = flashCenter < 0
        ? 0.0
        : math.exp(-math.pow((flashCenter - 0.5) / 0.16, 2).toDouble());

    final Widget faceFront = _CeremonyCardFront(
      girl: _revealGirl,
      width: _cardW,
      height: _cardH,
      appear: frontAppear,
      depart: frontDepart,
    );
    final Widget face = showFront
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: faceFront,
          )
        : _CeremonyCardBack(width: _cardW, height: _cardH, glow: backGlow);

    return SizedBox(
      width: _stageW,
      height: _stageH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (sweepIntensity > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SweepGlowPainter(
                      progress: sweepRot, intensity: sweepIntensity),
                ),
              ),
            ),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: face,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  twinkle: f,
                  intensity:
                      (sweepIntensity * 0.7 + flash * 0.6) * (1 - frontDepart),
                ),
              ),
            ),
          ),
          if (flash > 0.02)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RevealFlashPainter(intensity: flash),
                ),
              ),
            ),
        ],
      ),
    );
```

**Step 2: 修 overlay fade**（build，原 line 225–228 用 `_kHoldEnd`，改吃新 `_reveal`）

```dart
    if (_phase == _CeremonyPhase.revealing) {
      final t = ((_reveal.value - _kHoldEnd) / (1 - _kHoldEnd)).clamp(0.0, 1.0);
      revealFade = 1 - Curves.easeIn.transform(t);
    }
```

**Step 3: 跑「兩段升階」測試確認綠燈**

Run: `flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart --plain-name "兩段升階"`
Expected: 4 PASS。

**Step 4: 跑全檔測試**

Run: `flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart`
Expected: 41 PASS（37 既有 + 4 新；含 line 1090 正面卡暫留以 1500ms 命中白卡段、音效 6 測不變）。

**Step 5: Commit**

```bash
git add lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart
git commit -m "feat(practice-chat): _reveal 兩段升階時間軸（複用現有卡面/sweep，Batch A 骨架跑通)"
```

### Task A4：全量回歸 + 雙審

**Step 1: 全量測試**

Run: `flutter test`
Expected: 無新增失敗（對照 baseline；既有 stale rot 不算本批）。
> 註：本機環境 28 既存失敗為 baseline stale rot，與本批零關係——比對清單而非絕對數字。

**Step 2: analyze**

Run: `flutter analyze lib/features/practice_chat test/widget/features/practice_chat`
Expected: No issues（本批檔案）。

**Step 3: Codex 雙審**（高風險動畫）

交付 diff 給 Codex，重點查：forward-only 無 Timer/repeat、pumpAndSettle 收斂論證、reduce-motion 早退、beat fraction 命中 1500ms 不變量、sfx 呼叫點未改語意。取得 LGTM evidence 才算 dogfood-safe。

**Step 4: 不 push，等 Eric**（測試期協議：高風險批 push=自動部署無關但仍以 Eric 出新 TF build 目檢為驗收門）。
> Batch A 純前端 widget、不碰 Edge，push 不觸發部署；但仍遵「逐批雙審 evidence 後才宣告安全」。Eric 出新 TF build 目檢兩段儀式感＋低階機流暢度。

---

## Batch B — 軌道彗星 halo（高風險，雙審）

**目標**：新 `_OrbitalHaloPainter` 取代 `_SweepGlowPainter` 當高潮 halo，兩層 CustomPaint 夾卡片做景深。

**Files:** 同主檔 + 同測試檔（新增 painter smoke 測）。

**Task B1**：寫 `_OrbitalHaloPainter(progress, intensity, half)` 紅燈 smoke 測（建構不丟、`shouldRepaint` 對 progress/intensity 敏感、`half: front/back` 兩態）。
**Task B2**：實作 painter——2–3 條繞 X 軸傾斜 θ 的 3D 圓（φ∈[0,2π] 參數化，`(r·cosφ, r·sinφ·cosθ, r·sinφ·sinθ)` 投影成 2D 橢圓）；彗星 head（φ=progress·2π＋環偏移）＋M 個遞減 alpha/半徑拖尾；確定性零 Random。
**Task B3**：`_buildStage` 高潮段（`_kRechargeEnd`→`_kGrandFlipEnd`）以兩層夾卡——卡片下方畫 `half:back`（投影 z<0）、卡片上方畫 `half:front`（z>0）。退役 `_SweepGlowPainter`（或降級 fallback）。
**Task B4**：全量測試 + Codex 雙審（重點：投影數學、確定性、夾層 z 排序）。

**測試契約**：既有 41 + B smoke 全綠；halo 只在蓄力→高潮段亮（reduce-motion 不進此段）。

---

## Batch C — 金框典藏卡＋能量邊框＋teal＋星塵/光束（中風險，審）

**目標**：`_CeremonyCardFront` 改兩態（`variant: preview` 白卡＋`variant: grand` 金框典藏卡）；加 `_EnergyBorderPainter`；星塵加密＋橫掃光束。

**Files:** 同主檔 + 同測試檔。

**Task C1**：`_CeremonyCardFront` 加 `variant` 參數，Stage-1 preview = 現有白/粉 matte 近原樣；Stage-2 grand = 金框＋底部 frosted 深色玻璃資訊欄＋teal accent 文字。**同照片同欄位**，仍避開 `名字，年齡` 精確字串。`_buildStage` 第一段傳 `preview`、高潮段傳 `grand`。
**Task C2**：`_EnergyBorderPainter`——卡框 青→金 描邊掃動＋底邊噴火花（golden-angle 確定性粒子），只在 `_kRechargeEnd`→`_kHaloClimax` 亮。
**Task C3**：`_StarfieldPainter` 調密度＋加一道橫掃光束（沿用確定性佈點）。
**Task C4**：全量測試 + 雙審。

**測試契約**：既有全綠；`名字，年齡` 仍僅 hero 一處（line 1069/1087）；新增 variant smoke 測。
**目檢否決點**：teal 是新引入 accent，Eric 可於 TF 目檢否決退回純金。

---

## Batch D — 音效 riser/settle（中風險，審）

**目標**：維持離散音效 + 加 `riser`/`settle` 兩顆 wav，靠 `_reveal` listener edge-detect 跨 beat 觸發。

**Files:** 主檔 + `practice_draw_sfx.dart`（抽象加 2 method）+ `practice_draw_audio_sfx.dart`（真 impl）+ 2 wav + licenses + 測試檔。

**Task D1**：`PracticeDrawSfx` 抽象加 `playRiser()`/`playSettle()`（no-op 預設）；spy 加計數。寫紅燈：跨 `_kRechargeEnd` 觸發 riser 一次、跨 `_kGrandFlipEnd` 觸發 settle 一次、`forward(from:0)` 後可重觸發。
**Task D2**：`_reveal.addListener` 內 edge-detect——每 beat 一個 idempotent bool（`_firedRiser`/`_firedSettle`），跨門檻時觸發並設 true；`forward(from:0)`／`_toHidden` 時全部重置。零 Timer。
**Task D3**：`reveal_chime` 改配 **Stage-1 白卡預覽**揭曉（對齊 `_kFlip1End` 中點）；屏息靠「reveal 起手提早停 waiting loop」（已是現行為，waiting_loop 必留）。
**Task D4**：`AudioPlayersPracticeDrawSfx` 接 2 顆真 wav（riser 蓄力、settle 落定）；沿用 lazy/guarded headless 安全、3→5 player 管理、idempotent stop。licenses 模板補齊（commit 前 `git add`）。
**Task D5**：全量測試 + 雙審（重點：edge-detect 跨 beat 各觸發一次、pumpAndSettle 跨完所有門檻、headless 安全）。
> ⚠️ pubspec.lock 鐵則（沿用 Batch 4.7B 教訓）：本機 Dart 3.11 `pub get` 會漂 matcher/test_api，**revert 成 audioplayers-only 後絕不再 pub get**。

**測試契約**：既有音效 6 測語意不破（whoosh/waitingStart/waitingStop/chime/looping）；新增 riser/settle edge-detect 測。

---

## 全批驗收

- 每批：既有 37 + 累積新測全綠、`flutter analyze` 乾淨、Codex LGTM evidence、Eric 出新 TF build 目檢（儀式感 + 低階機流暢度）。
- 跨批不變量：forward-only／零 Timer／唯一 repeat=`_waiting`／pumpAndSettle 收斂／reduce-motion 露 hero／`名字，年齡` 僅 hero／確定性 painter。
- 全批完成 → 更新 memory `project_practice_card_draw_replication_2026-06-26`、必要時 `docs/decisions.md`。
