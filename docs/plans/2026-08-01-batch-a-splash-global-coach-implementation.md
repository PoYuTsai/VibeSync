# 批 A：Splash 縮短＋全域教練 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Splash 3.5 秒縮到約 2 秒；首頁「問教練」卡升級為不綁對象的全域教練對話（新 `global` scope，client＋Edge）。

**Architecture:** Splash 純動畫時間軸壓縮。全域教練＝`CoachScope` 加第三種 type `global`，沿用統一 Hive box／額度／隱私 cascade；新路由 `/coach` 掛現有 `CoachSurface`；Edge `coach-chat` schema 白名單加 `global`＋prompt 全域變體。設計檔：`docs/plans/2026-08-01-splash-global-coach-guest-mode-design.md`。

**Tech Stack:** Flutter/Riverpod/go_router、Hive（typeId 26 統一 box，欄位不動）、Supabase Edge（Deno＋zod）。

**風險與交付：** Edge 改動＝R2，Task 8 跨模型審查通過前**絕不 push**。無 migration。push main 即自動部署 Edge，盯 push-triggered workflow，不重複手動部署。

**既有事實（2026-08-01 於 main 查證）：**
- Splash 序列硬寫死在 `splash_screen.dart:136-161`：標題 0s→副標題 1.0s→shimmer 1.8s→圓點 2.0s→`onComplete` 3.5s；標題 controller 1.6s（`:60-63`）。
- `CoachScopeType`（`unified_coach_result.dart:12-17`）只有 `conversation`／`partner`，Hive 持久化值**絕不可改既有值**。
- `CoachScope`（`coach_scope.dart`）：`wireConversationId` 對 partner 送 `partner:<id>` 合成 id；`toWireJson()` 送結構化 scope。
- Edge `schemas.ts:19-29` `CoachScopeSchema` 判別式 union 只有兩型；`:127-147` superRefine 驗 scope 與頂層 id 一致性；`billing.ts:33` `deriveCoachScopeKey` 兩型分支＋fallback。
- `effectiveStyleContext`（關於我）管線 scope 無關：client `coachChatStyleContextProvider`（`coach_chat_providers.dart:48-59`）→ wire `effectiveStyleContext`（`coach_chat_api_service.dart:254-257`）→ prompt `section("使用者風格設定", …)`（`prompts.ts:22`）。global scope 只要以 `partnerId: null` 解析即可繼承。
- 首頁問教練卡：`home_feature_entries.dart` `coachKey` 卡，onTap 打 `coach_entry_tap`（帶 `has_partner`）後分流導航。**埋點字典不改**（事件與 properties 維持原樣，避免踩「改字典必同批改三處」鐵則）。
- CoachSurface 建構子只必填 `scope`（`coach_surface.dart:52-61`），有 `prefillText`＋`focusRequestToken` 可做引導問句。

**鐵則提醒：** 動畫零無限 repeat 或嚴格 gate（splash 光球是 repeat——widget test 用 `pump(duration)` 步進，**絕不 pumpAndSettle**）；pump `PartnerListScreen` 的測試必用 `test/helpers/home_screen_overrides.dart`。

---

## Task 1: Splash 縮短到約 2 秒

**Files:**
- Modify: `lib/features/splash/presentation/screens/splash_screen.dart`
- Test: `test/widget/splash/splash_duration_test.dart`（新建）

**Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/splash/presentation/screens/splash_screen.dart';

void main() {
  testWidgets('splash 在 2 秒內完成 onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(onComplete: () => completed = true),
    ));
    // 光球是 repeat 動畫，只能 pump 步進，絕不 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 2100));
    expect(completed, isTrue);
  });
}
```

（package 名以 `pubspec.yaml` 的 `name:` 為準，import 路徑照 repo 既有測試慣例。）

**Step 2: 跑測試確認紅**

Run: `flutter test test/widget/splash/splash_duration_test.dart`
Expected: FAIL（3.5 秒才 complete，2.1 秒時 `completed == false`）

**Step 3: 壓縮時間軸**

`_startAnimationSequence` 的四段 delay 改為：副標題 550ms、shimmer +450ms（累計 1.0s）、圓點 +200ms（累計 1.2s）、完成 +800ms（**累計 2.0s**）。標題 controller `1600ms → 900ms`、副標題/shimmer/圓點 controller 時長若 >800ms 也等比縮（目檢動畫曲線仍順）。光球三顆 controller 不動。

**Step 4: 跑測試確認綠**

Run: `flutter test test/widget/splash/splash_duration_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/features/splash test/widget/splash
git commit -m "splash：時間軸 3.5 秒壓縮到 2 秒（光球背景不動）"
```

---

## Task 2: CoachScope 加 `global` type（client 值物件層）

**Files:**
- Modify: `lib/features/coach_chat/domain/entities/unified_coach_result.dart:12-17`（`CoachScopeType` 加 `static const String global = 'global';`，註解標明 2026-08-01 新增、同為 Hive 持久化值不可改）
- Modify: `lib/features/coach_chat/domain/entities/coach_scope.dart`
- Test: 找到現有 CoachScope 測試（`grep -rln "CoachScope(" test/ | head`），沒有就新建 `test/unit/coach_chat/coach_scope_test.dart`

**Step 1: 寫失敗測試**

```dart
test('global scope 的 key/wire 形狀', () {
  const scope = CoachScope.global();
  expect(scope.type, CoachScopeType.global);
  expect(scope.id, 'me');
  expect(scope.key, 'global:me');
  expect(scope.wireConversationId, 'global:me');
  expect(scope.toWireJson(), {'type': 'global'});
  expect(scope.isConversation, isFalse);
  expect(scope.isGlobal, isTrue);
});
```

**Step 2: 跑測試確認紅**（`CoachScope.global` 不存在，編譯錯即紅）

**Step 3: 實作**

`coach_scope.dart`：

```dart
/// 全域教練（不綁對象）。id 固定哨兵值——一個使用者恰一條全域對話串。
const CoachScope.global()
    : type = CoachScopeType.global,
      id = 'me';

bool get isGlobal => type == CoachScopeType.global;
```

`wireConversationId`：global 回 `'global:me'`（合成 id，Edge Task 6 會認得）。
`toWireJson()`：global 回 `{'type': 'global'}`（無 id 欄——server 端一人一串，不需要 id）。

**Step 4: 跑測試確認綠** → **Step 5: Commit**（`教練：CoachScope 加 global type（值物件層）`）

---

## Task 3: 二值假設全面查帳（global 落地的正確性關鍵）

現有程式多處寫 `scope.isConversation ? A : B`，隱含「不是 conversation 就是 partner」。global 加入後這些分支會把 global 誤當 partner。

**Step 1: 列出所有嫌疑點**

```bash
grep -rn "isConversation\|scopeType ==\|CoachScopeType\." lib/ --include=*.dart | grep -v "_test\|coach_scope.dart\|unified_coach_result.dart"
```

**Step 2: 逐點分類修正**（預期熱點，以 grep 實際結果為準）：
- `coach_surface.dart:178`（conversation 讀取）與 `:444`（partnerId 推導）：global 時兩者都要是 `null`，不可落入 partner 分支拿 `scope.id`（'me' 不是 partnerId）。
- `coach_chat_repository_impl.dart` 的 scopeType 謂詞／隱私清除 cascade：global 紀錄要能被 `clearAll` 清掉；scopeType assert 白名單加 `global`。
- controller ask 路徑（`coach_chat_providers.dart`）：global → `partnerId: null`、`includePartnerOverride: false` 解析 styleContext；payload 不帶 `partnerId`／`conversationSummary`／`partnerHint`。
- `UnifiedCoachResult` 建構處：global 紀錄 `scopeType: CoachScopeType.global, scopeId: 'me'`，`conversationId`/`partnerId` 皆 null。

**Step 3: 對每個修正點補測試**（repository global 紀錄存讀＋clearAll 清除；controller payload 形狀），先紅後綠。

**Step 4: 全套 coach 測試**

Run: `flutter test test/unit/coach_chat test/widget/coach_chat 2>/dev/null || flutter test $(grep -rln "coach" test/ --include=*_test.dart | tr '\n' ' ')`
Expected: 全綠

**Step 5: Commit**（`教練：global scope 落地二值假設修正＋repository/controller 測試`）

---

## Task 4: `/coach` 路由＋全域教練頁

**Files:**
- Create: `lib/features/coach_chat/presentation/screens/global_coach_screen.dart`
- Modify: `lib/app/routes.dart`（加 `/coach` route；照既有 route 寫法，**不動** `followUpDeepLink` 與 redirect 規則）
- Test: `test/widget/coach_chat/global_coach_screen_test.dart`

**Step 1: 失敗測試**——pump `GlobalCoachScreen`（Riverpod overrides 照既有 coach widget 測試的做法），驗：AppBar 標題「問教練」、`CoachSurface` 存在且 `scope == CoachScope.global()`、空狀態顯示引導問句 chips。

**Step 2: 確認紅 → Step 3: 實作**

`GlobalCoachScreen`＝`Scaffold`＋AppBar「問教練」＋`CoachSurface(scope: CoachScope.global(), prefillText: …, focusRequestToken: …)`。引導問句 chips（螢幕層 state，點了把文字經 `prefillText`＋token 遞增送進輸入框，**絕不自動送出**——quota 安全）：

- 「不知道怎麼開啟話題，給我一點方向？」
- 「對方回得很短，我該怎麼判斷？」
- 「怎麼把聊天推進到約出來？」

空狀態視覺：沿用 `CoachSurface` 既有空狀態；螢幕頂部加 Sydney greeting 圖（`assets/images/coach/` 現成素材）＋一句「隨時問我，聊天卡住我來接」。

**Step 4: 綠 → Step 5: Commit**（`教練：/coach 路由＋全域教練頁（引導問句只預填不送出）`）

---

## Task 5: 首頁「問教練」卡改導 `/coach`

**Files:**
- Modify: `lib/features/partner/presentation/widgets/home_feature_entries.dart`（coach 卡 onTap：埋點照舊打 `coach_entry_tap` 帶 `has_partner`——**字典零改動**；分流導航整段換成 `context.push('/coach')`）
- Test: `test/unit/features/partner/partner_list_screen_test.dart`（既有 coach 卡導向測試改期望值；**必用 `test/helpers/home_screen_overrides.dart`**）

**Steps:** 改測試期望（紅）→ 改 onTap（綠）→ 跑 `flutter test test/unit/features/partner/` 全綠 → Commit（`首頁：問教練卡改導全域教練 /coach（埋點字典不變）`）。

---

## Task 6: Edge schema＋scopeKey 加 `global`

**Files:**
- Modify: `supabase/functions/coach-chat/schemas.ts`（union 加 `z.object({ type: z.literal("global") }).strict()`；superRefine 加規則：`scope.type === 'global'` 時 `payload.conversationId` 必須 === `'global:me'` 且 `partnerId` 必須為空，否則 `scope_global_shape_mismatch`）
- Modify: `supabase/functions/coach-chat/billing.ts:33` `deriveCoachScopeKey` 加分支 `if (input.scope?.type === "global") return "global";`（scopeKey 每 user 帳本已隔離，不需再帶 id）
- Modify: 先查 `grep -n '"partner:' supabase/functions/coach-chat/index.ts`——凡是認 `partner:` 合成 conversationId 的地方，鏡射處理 `global:`（AI 鍵盤案教訓：server 端漏一處白名單＝整條線靜默壞）
- Test: `schemas.ts`／`billing_test.ts` 對應 Deno 測試

**Steps:** 先寫紅測試（global scope 通過 parse、shape mismatch 被拒、`deriveCoachScopeKey` 回 `global`、既有兩型不回歸）→ 實作 → `cd supabase/functions/coach-chat && deno test --allow-all` 全綠 → Commit（`Edge：coach-chat scope 白名單加 global＋scopeKey/合成 id 鏡射`）。**不 push。**

---

## Task 7: Edge prompt 全域變體

**Files:**
- Modify: `supabase/functions/coach-chat/prompts.ts`
- Modify: `supabase/functions/coach-chat/index.ts`（把 scope 型別傳進 prompt builder，若尚未傳）
- Test: `prompts_test.ts`

**Step 1: 紅測試**——global scope 時 prompt 含全域指引段、不含對象相關 section；conversation/partner scope 輸出 byte-for-byte 不變（快照式斷言防回歸）。

**Step 3: 實作**——scope 為 global 時 append 一段：

```
本次是全域教練對話：使用者沒有綁定特定對象，問題偏通用（開場、判讀、推進、心態）。
直接給可執行的建議。若使用者明確在問某個特定對象的具體對話，
提醒他到該對象頁的「跟進」區問，那裡你能看到完整上下文。
```

「使用者風格設定」section 照舊（`effectiveStyleContext` 有就注入）。

**Steps:** 紅 → 綠（`deno test --allow-all`）→ Commit（`Edge：coach-chat prompt 全域變體（既有兩 scope 輸出鎖不變）`）。**不 push。**

---

## Task 8: 跨模型審查（R2 gate）＋push 部署

1. 全量驗證：`flutter analyze`（/mnt/c 全 repo 要 11 分鐘，**背景跑**，快照時間必須晚於最後一次碼改動）＋全套 `flutter test`＋coach-chat `deno test --allow-all`。
2. 依 `cross-model-review` 流程出 review packet 送審（Codex 空窗則 Grok 主審＋GLM 證偽；**packet 放 repo 外目錄跑**——grok-codex 在 repo cwd 會被 AGENTS.md 帶偏拒審）。executor 不自審；P1 全修，至多兩輪。
3. 審過後 push main → 盯 push-triggered Edge deploy workflow（`gh run list`），**不重複手動部署**。
4. exact-SHA `Build & Distribute` 照 AGENTS.md 交付慣例監控。

---

## Task 9: 收尾

- 更新 `docs/plans/2026-08-01-splash-global-coach-guest-mode-design.md` 批 A 狀態註記。
- 回報 Eric（繁中）：commit/push 狀態、Edge 部署結果與 run URL、Bruce dogfood 腳本三項——啟動變快體感／首頁問教練直接能聊（含引導 chips 只預填不自動送）／填過關於我的帳號感覺個人化語氣。
- 批 B（訪客模式）依設計檔另開實作計畫，**不混本批**。
