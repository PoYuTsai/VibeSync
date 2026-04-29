# Two-Layer User Profile — Design Plan

> **狀態**: Design locked, pending implementation kickoff
> **Trigger**: Bruce Discord 02:07-08 (2026-04-29) two-layer spec lock + hotfix `279dd31` 啟用 ScoreActionHint dead signal 後的下一步
> **依賴**: 不依賴 hotfix; 但與 hotfix 同樣處理「backend 已收 / 但無對應 UI 表面」的 dead-signal 系列改造
> **作者**: Eric (拍板) + Claude (brainstorm + 草擬)

## 1. Context

VibeSync 目前對「用戶自己」的描述只散落在兩處:

1. **每個對話**的 `SessionContext` 收集 `userStyle` (chip 5 選 1) + `userInterests` (free text) + `targetDescription`
2. **Edge Function 已宣告 schema** 接收這些欄位 (`analyze-chat/index.ts:248-255`), 但 client 端 `analysis_service.dart:619-624` **不傳送** userStyle / userInterests, 而 Edge prompt 也不使用 — 整條 dead signal pipeline

Bruce 的 2026-04-29 spec lock 提出: 把使用者識別資料**搬位置 + 分層**:

- **L1「關於我」** — 全域 default, 放在「我的報告」tab 頂部
- **L2「我的風格」** — per-partner override, 放在 PartnerDetail AppBar 👤 button
- **AI 解析**: `partner.styleOverride ?? user.profile`

本 plan 把這個高階 spec 落到可實作的 design + 出貨順序。

## 2. Locked Decisions (Brainstorm Q&A)

四個架構問題在 2026-04-29 session brainstorm 拍板:

| # | 問題 | 決策 | 理由摘要 |
|---|---|---|---|
| Q1 | 兩層欄位拆分 | **B — 識別 / 風格分層** | L1 = identity bundle (含 selfDescription); L2 = 只覆蓋 style + interests 的 presentation 角度. 對齊 Bruce 標籤含意 |
| Q2 | Override 粒度 | **B — per-field nullable** | `partner.styleOverride.style ?? user.style` per-field. 支援「對她我幽默點, 興趣保持原樣」真實情境 |
| Q3 | 既有 SessionContext 資料 | **B — 移除 NewConversationScreen 收集 + 一次性 bootstrap migration** | 兩層核心是「資料分層, 風格集中」, 留第三層稀釋價值; 一次性 migration 不丟老用戶填過的資料 |
| Q4 | AI prompt 整合 | **A — Passive context injection (low-risk)** | 不改 1.8x / heat 策略 / reply-type 規則; 送審前最後穩定化, 等 Bruce dogfood 再決定要不要 escalate |

## 3. Data Model + Storage

### 三個新 Hive 模型 (HiveTypeId 接續 Partner=8)

```dart
// HiveTypeId 9 — 全域「關於我」
@HiveType(typeId: 9)
class UserProfile {
  @HiveField(0) final UserStyle style;
  @HiveField(1) final String interests;       // free-text, e.g. "戶外, 咖啡, 獨立書店"
  @HiveField(2) final String selfDescription; // 一句話自述, max 100 chars
  @HiveField(3) final DateTime updatedAt;
}

// HiveTypeId 10 — per-partner per-field nullable override
@HiveType(typeId: 10)
class ProfileOverride {
  @HiveField(0) final UserStyle? style;       // null = 跟隨預設
  @HiveField(1) final String? interests;
  bool get isEmpty => style == null && interests == null;
}

// Partner 加 HiveField 7 (forward-compat)
@HiveField(7) final ProfileOverride? styleOverride;
```

### Storage 位置

新 Hive box `userProfileBox`, 單一 entry under key `'main'` (一個 app 一個用戶, 無 collection 需求). 與 `partnersBox` / `conversationsBox` 對稱, 共用 encryption + backup pipeline。

### 設計取捨

- **selfDescription 不允許 per-partner override** — identity 是「我是誰」不該跟人變; 只有 presentation 才 per-partner
- **selfDescription 上限 100 char** — identity 一句話原則, 太長變「碎念」對 prompt injection 沒幫助
- **`ProfileOverride.isEmpty` getter** — 兩欄都 null 時等同沒設, UI / 解析層可短路

### Resolution helper (pure function, 易測)

```dart
EffectiveProfile resolve(UserProfile? user, Partner? partner) =>
    EffectiveProfile(
      style: partner?.styleOverride?.style ?? user?.style ?? UserStyle.steady,
      interests: partner?.styleOverride?.interests ?? user?.interests ?? '',
      selfDescription: user?.selfDescription ?? '',
    );
```

`UserStyle.steady` 為 last-resort default, 新用戶尚未設 L1 也不會炸。

## 4. Resolution + Payload Flow

### Resolution 在 client 端

簡化 Edge — 讓 Edge 拿到的是「最終值」, 不需懂 fallback chain. 失敗 fallback 集中在 Flutter 側可單元測。

### 新增 Riverpod provider

```dart
final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>(...);

final effectiveProfileFamily =
    Provider.family<EffectiveProfile, String /*partnerId*/>((ref, pid) {
  final user = ref.watch(userProfileProvider);
  final partner = ref.watch(partnerByIdProvider(pid));
  return resolve(user, partner);
});
```

`Provider.family` by partnerId — 同一 partner 多次 read 走 cache; partner 切換自動 invalidate。

### Payload 改動 (`analysis_service.dart:619-624`)

```dart
// 之後
'sessionContext': {
  'meetingContext': sessionContext.meetingContext.label,
  'duration': sessionContext.duration.label,
  'goal': sessionContext.goal.label,
  'userStyle': effective.style.label,           // ← dead signal 復活
  'userInterests': effective.interests,         // ←
  'selfDescription': effective.selfDescription, // ← 新欄位
},
```

三個關鍵點:

1. **Edge interface 已存在** — userStyle / userInterests 已宣告於 `SessionContextInput`, 不需 Edge schema 改動 (selfDescription 是新欄位需加 1 行)
2. **讀取來源切換** — 從 `sessionContext.userStyle` 改讀 `ref.read(effectiveProfileFamily(partnerId))`. SessionContext 那兩欄停止讀寫
3. **partnerless conversation** (孤兒對話如開場救星) — resolve 時 partner=null, fallback 到 user-only, 不 crash

### SessionContext schema 不破壞

- `SessionContext.userStyle` (HiveField 3) / `userInterests` (HiveField 4) **保留** Hive field, 加 `@deprecated` 註解
- 不做 schema migration 移除 — 移除 = 破壞既有 conversation, 不值得

## 5. L1 「關於我」 UI (我的報告 tab)

### 位置

`my_report_screen.dart:50` (headline「最近 七次 的節奏」之後, HeatTrendChart 之前). 與其他 chart card 同層級, 但視覺輕一階 (subtle glass surface)。

### 兩種狀態

**Empty state — UserProfile == null**:
```
┌─ 關於我 ──────────────────────┐
│  讓 VibeSync 知道你是誰        │
│  AI 才能幫你回得像你           │
│  [告訴 VibeSync →]            │
└────────────────────────────────┘
```
不強迫 onboarding (送審前不加引導步驟), 單行 CTA + tap → 全螢幕編輯頁。

**Filled state**:
```
┌─ 關於我 ────────────── 編輯 ─┐
│  💫 風格: 幽默               │
│  ❤️  興趣: 戶外、咖啡、書店    │
│  ✏️  自述: 工程師,話不多...   │
└────────────────────────────────┘
```
selfDescription 太長 fade-out 截斷; 右上「編輯」 → 全螢幕編輯頁。

### 編輯頁 (新 screen, 全螢幕)

- StyleChipPicker (5 chips, 與 NewConversationScreen reuse)
- InterestsTextField (chip-friendly free text, hint「用逗號分開」)
- SelfDescriptionTextField (max 100 char, char counter)
- Bottom: 儲存 / 取消

### 為何 full-screen 而非 modal sheet

3 fields + 100-char 自述 + chip picker + 鍵盤 在 iPhone SE (667px) 上 sheet 必擠; 與 NewConversationScreen 既有 full-screen pattern 一致。

## 6. L2 「我的風格」 UI (PartnerDetail per-partner override)

### Entry point

PartnerDetail AppBar `actions:`, IconButton(`Icons.person_outline`) 在 PopupMenuButton (⋮) 之前. 用 outline icon 而非 emoji 👤 避免 dark mode contrast 不穩。

### Bottom sheet shape (與 L1 形狀區分, light 感)

```
┌─────────────────────────────────┐
│   我對 Bruce 的風格   ✕         │
├─────────────────────────────────┤
│   風格                          │
│   [幽默*][穩重 ][直接 ][...]    │  * = 已自訂
│   跟隨預設: 穩重                │
│                                 │
│   興趣 (對她我想強調的)          │
│   [────────────────]            │
│   跟隨預設: 戶外、咖啡           │
│                                 │
│   [使用預設]   (僅當有 override) │
└─────────────────────────────────┘
```

### Per-field follow-default 操作

- **Style chips**: 沒選任何 = `style: null` (跟隨預設); 點一個 = override; 再點同一個 = 取消 override
- **Interests TextField**: empty = `interests: null` (跟隨預設); 有字 = override; placeholder 顯示 global 值 (greyed)
- 兩欄都 null → `ProfileOverride.isEmpty == true` → 解析時等同沒設

### Save UX

**Instant save** (debounce 500ms): chip 點 / text 改即觸發 `partnerRepository.update()`. Sheet 沒「儲存」 button, 只有 ✕. Override 是非破壞性 (隨時可清), 沒 commit/rollback 心智成本。

### 「使用預設」 button

底部, 僅當有任一 override 時出現. 一鍵清空兩欄, 加二次 confirm dialog (對 Bruce 的風格設定會清掉, 改為跟隨預設). 防誤觸 — 與 instant save 方向相反但對應不同心智 (微調可逆 / 清空 destructive)。

## 7. Migration + NewConversationScreen Cleanup

### Migration 觸發點

`StorageService.initialize()` 開完 Hive boxes 後跑一次. Gated by `settingsBox` flag `'userProfileMigrated': bool` — idempotent, 失敗也設 flag 避免重試風暴。

### Migration logic

```dart
Future<void> _maybeMigrateUserProfile() async {
  final settings = Hive.box(AppConstants.settingsBox);
  if (settings.get('userProfileMigrated', defaultValue: false)) return;

  final profileBox = Hive.box<UserProfile>(AppConstants.userProfileBox);
  if (profileBox.get('main') != null) {
    await settings.put('userProfileMigrated', true);
    return; // 已手動設過, 不蓋
  }

  try {
    final convBox = Hive.box<Conversation>(AppConstants.conversationsBox);
    final source = convBox.values
        .where((c) =>
            c.sessionContext?.userStyle != null ||
            (c.sessionContext?.userInterests?.isNotEmpty ?? false))
        .sortedBy((c) => c.updatedAt)
        .reversed
        .firstOrNull
        ?.sessionContext;

    if (source != null) {
      await profileBox.put('main', UserProfile(
        style: source.userStyle ?? UserStyle.steady,
        interests: source.userInterests ?? '',
        selfDescription: '', // 沒來源資料留空
        updatedAt: DateTime.now(),
      ));
    }
  } catch (e, st) {
    debugPrint('userProfile migration failed (non-fatal): $e\n$st');
  } finally {
    await settings.put('userProfileMigrated', true);
  }
}
```

### 不變式

1. **永遠 set flag** — 失敗也設 (最壞情況 = L1 空白, 用戶手動補)
2. **取最近一筆** (`sortedBy updatedAt → reversed → firstOrNull`) — 假設用戶最近偏好最準
3. **不跨用戶** — Hive 是 device-local, 無 cross-device 同步問題

### NewConversationScreen UI 變更

- 砍 `_userStyle` chip picker section + `_userInterestsController` TextField + 對應 padding
- 留 `meetingContext`, `duration`, `goal`, `targetDescription` (per-conversation 仍有意義)
- 寫 SessionContext 時 `userStyle: null, userInterests: null`

## 8. Edge Function Prompt Integration

### 部署紀律 (CLAUDE.md 硬規則對齊)

此改動 = prompt 變動, **必須獨立 commit + 獨立 deploy**, 不得與其他 Edge function 改動混. Deploy 仍走 `--no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg`。

### 新增 selfDescription field

`SessionContextInput` interface (`index.ts:248-255`) 加一行:
```typescript
selfDescription?: string;
```

### Prompt block builder (新 helper)

```typescript
function buildUserProfileBlock(ctx: SessionContextInput): string {
  const lines: string[] = [];
  if (ctx.userStyle?.trim()) lines.push(`個性傾向: ${ctx.userStyle}`);
  if (ctx.userInterests?.trim()) lines.push(`興趣: ${ctx.userInterests}`);
  if (ctx.selfDescription?.trim()) lines.push(`自述: ${ctx.selfDescription}`);
  if (lines.length === 0) return '';
  return `[使用者背景]\n${lines.join('\n')}\n\n`;
}
```

### 插入位置

既有 sessionContext block (meetingContext / duration / goal) **之後**, conversation messages **之前**. Identity context 先建立, Claude 才能用它解讀後面對話。

### Empty handling 三檔

| 輸入 | 輸出 | 說明 |
|---|---|---|
| 三欄全空 | empty string (整 block 省略) | zero-impact baseline |
| 部分空 | header + 有值的 lines | 稀疏但有 header |
| 三欄全填 | 完整 block | happy path |

### **關鍵保險: OCR-mode 短路**

`analyzeMode === 'ocr'` 或 `'recognize-only'` 時 `buildUserProfileBlock` 直接 return ''. 理由:

1. **零功能效益** — OCR 是字元辨識, user identity 對辨識「哈/呵」沒幫助
2. **Baseline drift 是真實風險** — OCR-stable baseline 是 `28c0965`, prompt 任何變動 = 行為微飄, 而**沒有**自動 OCR 回歸測試
3. **CLAUDE.md 硬規則對齊** — 「OCR 變更不與 prompt 改動混」 的精神就是「OCR 路徑 prompt 極端穩定」
4. **Invariant 可驗證性** — 「OCR mode prompt 與舊版 byte-equivalent」 比 「改了但輸出還一樣」 容易斷言

### Token budget

結構化形式 30-80 tokens / request, <1% 既有 payload 大小, 對 cost 無感。Haiku free tier 也安全 (per ADR-11)。

### Edge tests

`buildUserProfileBlock_test.ts`:
- 4 cases: 全空 / 單欄 / 雙欄 / 三欄
- OCR mode short-circuit case
- Regression: 全空時 prompt 與舊版 byte-equivalent

## 9. Test Pyramid

| 層 | 測試對象 | 工具 | 覆蓋目標 |
|---|---|---|---|
| Edge unit | `buildUserProfileBlock`, OCR short-circuit | Deno test | 4 cases (空/單/雙/三欄) + OCR mode = empty + 與舊版 byte-equivalent |
| Domain unit | `resolve(user, partner)`, `ProfileOverride.isEmpty` | flutter test | per-field fallback chain 8 case 矩陣 (override null/has × user null/has) |
| Migration unit | `_maybeMigrateUserProfile` | flutter test | 三 fixtures (空 conv box / 單筆 / 多筆取最新); flag idempotency; failure path 設 flag |
| Widget | L1 card (empty/filled), L1 editor, L2 sheet (3 states), 「使用預設」 confirm | flutter test | UI 行為 + per-field clear affordance |
| Integration | analysis_service payload contains effective values | flutter test | partner with/without override → payload 對應; partnerless → user-only |

## 10. 4-Phase Ship Order + Risk Gates

依 CLAUDE.md「OCR 變更獨立 commit」 + testing phase 直接 commit+push 協議。

### Phase 1 — Edge Function (idle, 對 client 透明)
- 加 `selfDescription` field 到 `SessionContextInput`
- 加 `buildUserProfileBlock` + OCR short-circuit
- Deno tests
- Deploy `--no-verify-jwt`. **獨立 commit, 獨立 deploy**.
- **風險: 低** (client 還沒送資料, behavior == baseline)

### Phase 2 — Foundation + L1 UI (使用者首次能設)
- Hive: UserProfile model + adapter, `userProfileBox`
- Domain: `resolve()`, EffectiveProfile, UserProfileRepository, userProfileProvider
- analysis_service: 改注入 EffectiveProfile (此時 partner override 還空, 等同 global)
- UI: My Report 「關於我」 card (empty/filled) + 全螢幕編輯
- **風險: 中** (新 Hive type 上線, 需驗 dogfood 兩天無 box error)

### Phase 3 — L2 per-partner override
- Hive: ProfileOverride model + adapter, Partner HiveField 7 (forward-compat)
- UI: PartnerDetail AppBar 👤 + bottom sheet (per-field clear, instant save, 「使用預設」 confirm)
- **風險: 中-高** (動 Partner schema, 需確認 forward-compat 真不破壞舊資料 — Hive `unknown field` 行為要 dogfood 驗一次)

### Phase 4 — Migration + cleanup
- `_maybeMigrateUserProfile` at startup
- NewConversationScreen 砍 userStyle picker + interests TextField
- **風險: 低** (migration 失敗 fallback = 空 L1, 用戶可手動補)

### Risk gates 之間

- **Phase 1 → 2**: Bruce TF dogfood 1 天 (確認 OCR 沒 regression, selfDescription 是新 schema field)
- **Phase 2 → 3**: dogfood 2 天 (確認 L1 設了之後 AI 回覆有變化)
- **Phase 3 → 4**: dogfood 1 天 (Partner schema 對舊資料無影響)

### 規模感 (粗估)

| Phase | 約 LOC | 約 tests |
|---|---|---|
| 1 | 50 | 4 |
| 2 | 400 | 20 |
| 3 | 300 | 12 |
| 4 | 150 | 5 |
| **總計** | **~900** | **~41** |

## 11. Out of Scope

本 plan **不涵蓋** 的相鄰主題:

- **Hotfix `279dd31`** (ScoreActionHint 行動下一步) — 已 ship 於 2026-04-29 21:00, 與本 plan 並行但獨立。Hotfix 處理「health card next-step dead signal」, 本 plan 處理「user identity dead signal」, 兩者皆是 dead-signal 系列但範圍不同
- **AI prompt active bias** (Q4 option B) — 等 Phase 4 後 Bruce dogfood 訊號決定是否升級
- **AI prompt full behavioral integration** (Q4 option C) — 送審前禁區, 送審後另議
- **第三層 per-conversation override** (Q3 option A) — 已捨棄, 兩層即足
- **Onboarding 強制流程** — 送審前不加新引導步驟
- **Cross-device 同步** — Hive device-local, 此 plan 假設單裝置使用

## 12. Open Follow-ups

實作期間若觸發以下訊號, 拉回此 plan 補充:

1. **Phase 3 Hive forward-compat 真實行為** — 加 HiveField 7 後, 用舊 app version 開新 app version 寫入的資料是否會丟掉 field 7? 需 dogfood 驗
2. **Bruce dogfood 反應 prompt active bias 是否需要** — 若 L1 設了之後 AI 回覆「沒感覺到差別」, escalate 到 Q4-B
3. **Phase 2 L1 編輯頁是否拿來雙用** (兼當 onboarding 第一步) — 若送審後 PM 提引導需求, 此 screen 可重用
4. **selfDescription 100 char 是否夠** — dogfood 用戶若反映「想多寫點」, 考慮放寬到 200 (但需重評 prompt token budget)

---

## Reference

- Brainstorm session: 2026-04-29 (Path Y locked, 4 decisions in single session)
- Bruce two-layer spec lock: Discord 2026-04-29 02:07-08
- Related hotfix: commit `279dd31` (ScoreActionHint dead signal activation)
- ADR-11 (model selection): `docs/decisions.md`
- OCR-stable baseline: commit `28c0965` (CLAUDE.md hard rule)
- Code map memory: observation `1030` (2026-04-29 hotfix architecture map)
