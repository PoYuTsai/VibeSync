# Spec 2: Partner Style Override — Design

> **狀態**: Design locked 2026-05-01（Spec 1 ship + TF smoke 後）
> **Trigger**: Spec 1「About Me」全域 ship，Bruce/Eric 拍板分層教練設定
> **Supersedes**: `2026-04-30-memory-coach-spec2b-partner-coaching-override-draft.md`、`2026-04-30-two-layer-profile-design.md` 中與 Spec 2 相關段落（兩份在命名 / entry / reset / 儲存設計都被新版改寫）
> **不依賴**: prompt 注入（排後續）/ Coach Action Card / Partner Data Quality Guard / 完整 agentic coach
> **Implementation plan**: `2026-05-01-partner-style-override-impl.md`
> **作者**: Eric（拍板）+ Claude（brainstorm + 草擬）

## 1. 一句話定位

讓使用者在 Partner detail 設定「我面對這個人想用的互動策略」（per-partner override of global About Me），AI fallback chain：partner override → 全域 About Me → generic coach。

## 2. 為什麼新做一份（不沿用 04-30 草稿）

| 維度 | 04-30 兩份草稿 | 2026-05-01 收斂版 |
|------|----------------|-------------------|
| 命名 | 「這個對象的互動設定」/ 避用「我的風格」 | 「我的風格 · 對小明」（延續 Spec 1 第一人稱） |
| Entry | AppBar person icon → 全螢幕 / bottom sheet | Partner detail inline card（PartnerTraitsCard 下方） |
| Reset | 整體「重設為全域」按鈕 | per-field「沿用全域」灰字 link |
| 儲存 | 嵌入 `Partner.styleOverride` HiveField 7 | 獨立 Hive box `partner_style_overrides` + 新 entity |
| Prompt | 草稿含 prompt contract 段落 | Spec 2 不寫 prompt impl，data contract 簽完即止 |

收斂版選擇背後理由見 §3-§5。

## 3. Override 欄位（Spec 1 UserProfile 的子集）

| 欄位 | 型別 | 是否覆蓋 | 理由 |
|------|------|---------|------|
| interactionStyle | `InteractionStyle?` | ✅ | 「面對這個人我想用什麼風格」 |
| practiceGoals | `List<PracticeGoal>` (max 3) | ✅ | 「這個人專屬的練習目標」 |
| notes | `String?` (max 100) | ✅ | 面對這個人的特別提醒 |
| ~~topicSeeds~~ | — | ❌ | AI 從對話歷史已提取 partner 興趣，重複 |
| ~~customTopics~~ | — | ❌ | 同上 |

## 4. 繼承語意（per-field inherit）

- 欄位 `null` / empty → fallback 全域 About Me
- 欄位非 null → partner 覆蓋
- 編輯畫面預設**空白**，灰字 placeholder 顯示「（沿用全域：穩重）」依當前全域值
- 全域改動會自動傳播到沒覆蓋的欄位（避免 stale snapshot）
- ⚠️ 全部欄位變空 → repository 應**刪整 row**（避免 partner 一次「清空所有自訂」後 box 留下 isEmpty entry）

## 5. UI 設計

### 5.1 Partner detail 入口（inline card）

位置：`PartnerDetailScreen` ListView，**PartnerTraitsCard 下方**。

```
┌─ 我的風格 · 對小明 ───────── › ─┐
│  沿用全域預設 / 已自訂風格        │
└──────────────────────────────────┘
```

副標二態：
- 全部欄位空 → 「沿用全域預設」
- 任一欄位有值 → 「已自訂風格」

點整張卡 → 進編輯畫面 `/partner/:id/my-style`。

### 5.2 編輯畫面

AppBar：title「我的風格 · 對小明」（partner.name），返回鍵自動存。

三段欄位 + 每欄位下方：
- 沒選任何值 → placeholder 提示「（沿用全域：X）」
- 已自訂 → 該欄位下方出現「沿用全域」灰字 link，點擊清空該欄位

### 5.3 與 Spec 1 AboutMeCard 的視覺對稱

`PartnerStyleEntryCard` 沿用 `AboutMeCard` 的玻璃卡片 surface + glassTextPrimary/Secondary 色彩 token，避免 readability 重蹈 Spec 1 修補（commit `eea34bd`）。

## 6. Data Contract

### 6.1 新 entity（Hive `@HiveType(typeId: 13)`）

```dart
@immutable
@HiveType(typeId: 13)
class PartnerStyleOverride {
  static const int maxPracticeGoals = 3;
  static const int maxNotesLength = 100;

  @HiveField(0) final String partnerId;
  @HiveField(1) final InteractionStyle? interactionStyle;
  @HiveField(2) final List<PracticeGoal> practiceGoals;
  @HiveField(3) final String? notes;
  @HiveField(4) final DateTime updatedAt;

  const PartnerStyleOverride({
    required this.partnerId,
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
    required this.updatedAt,
  });

  /// Validates + normalizes inputs. Always use from controller / repo.
  factory PartnerStyleOverride.create({
    required String partnerId,
    InteractionStyle? interactionStyle,
    List<PracticeGoal> practiceGoals = const [],
    String? notes,
    required DateTime updatedAt,
  });

  bool get isEmpty;
}
```

### 6.2 EffectiveStyle（in-memory value object，非 Hive）

```dart
@immutable
class EffectiveStyle {
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;

  const EffectiveStyle({
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
  });
}
```

### 6.3 Resolver（pure function）

```dart
EffectiveStyle resolveEffectiveStyle({
  UserProfile? global,
  PartnerStyleOverride? partner,
}) {
  return EffectiveStyle(
    interactionStyle: partner?.interactionStyle ?? global?.interactionStyle,
    practiceGoals: (partner?.practiceGoals.isNotEmpty ?? false)
        ? partner!.practiceGoals
        : (global?.practiceGoals ?? const []),
    notes: partner?.notes ?? global?.notes,
  );
}
```

### 6.4 Repository

`PartnerStyleRepository`（Hive box `partner_style_overrides`，key = partnerId）。
- `load(partnerId) -> PartnerStyleOverride?`
- `save(PartnerStyleOverride)` — 若 `isEmpty` → 改呼叫 `delete(partnerId)`（避免 box 殘留 empty entry）
- `delete(partnerId)`
- `clearAll()`

`UserProfileRepository`（Spec 1）**不動**。

### 6.5 Cascade delete

`PartnerRepository.delete(partnerId)` 完成後 → 也呼叫 `PartnerStyleRepository.delete(partnerId)`。理由：partner 已刪除，override 不再有意義，避免 box 累積孤兒 row。

### 6.6 Riverpod providers

```dart
final partnerStyleOverrideProvider =
    AsyncNotifierProviderFamily<PartnerStyleOverrideController,
        PartnerStyleOverride?, String>(
      PartnerStyleOverrideController.new,
    );

final effectiveStyleProvider =
    Provider.family<EffectiveStyle, String>((ref, partnerId) {
  final global = ref.watch(userProfileProvider).valueOrNull;
  final partner = ref.watch(partnerStyleOverrideProvider(partnerId)).valueOrNull;
  return resolveEffectiveStyle(global: global, partner: partner);
});
```

- `partnerStyleOverrideProvider(partnerId)` — 編輯畫面 + entry card 副標 binary state 用
- `effectiveStyleProvider(partnerId)` — 編輯畫面 placeholder（顯示 fallback 後的 global 值用）+ 未來 prompt builder 用

### 6.7 StorageService 整合

```dart
// initialize()
Hive.registerAdapter(PartnerStyleOverrideAdapter()); // typeId=13
await Hive.openBox<PartnerStyleOverride>(
  'partner_style_overrides',
  encryptionCipher: HiveAesCipher(encryptionKey),
);

// getter
static Box<PartnerStyleOverride> get partnerStyleOverridesBox =>
    Hive.box<PartnerStyleOverride>('partner_style_overrides');

// clearAll() — 鏡像 Spec 1 修補 (1c43bae)
await partnerStyleOverridesBox.clear();
```

## 7. Out-of-Scope（Spec 2 不做）

- 不動 OCR / `analyze-chat` prompt deployment
- 不寫 prompt builder 注入（contract 簽完，注入排後續 Spec）
- 不做主動提醒 / push
- 不做 Coach Action Card v2 / 文章推薦 bind / Partner Data Quality Guard
- 不做完整 agentic coach
- 不做 partner list 卡片「已自訂」標示
- 不做 partner-only 新欄位（如「關係目的」enum，留 future Spec）
- 不做 EffectiveStyle 的 origin tracking（contract 留空間，未來純加值不破壞）

## 8. Follow-ups（不擋 Spec 2）

1. **Generic coach fallback** — 兩層都空時 prompt 怎麼處理 → prompt 實作階段再決定
2. **「關係目的」enum** — partner-only 維度，可考慮 Spec 3 候選
3. **Origin tracking** — 等 prompt 實作確認需要時再加

## 9. ADR 候選

實作完成後若觸發分歧仲裁（特別是「為何 Partner Style Override 用獨立 Hive box 而非 `Partner.styleOverride` embed」），新增 ADR-16 in `docs/decisions.md`。
