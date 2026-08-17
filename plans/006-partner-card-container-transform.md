# 006 — 對象卡 → 詳情頁 container transform（引入 animations 套件）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH
- **Category**: Missed opportunity（空間連續性）
- **Estimated scope**: 3 files ＋ 1 新依賴

## Problem

`lib/features/partner/presentation/screens/partner_list_screen.dart:137-141` — 對象卡（頭像＋名字＋統計，與詳情頁頂部同素材）點下去走 `context.push('/partner/${p.id}')`，`lib/app/routes.dart:131-139` 是 plain `builder:`，內容被撕掉、詳情頁從右緣滑入重建。全 repo 零 `Hero`、零共享元素轉場——這是「元件講究、頁面硬切」最典型的縫。

```dart
// partner_list_screen.dart:137-141 — current
child: PartnerListCard(
  partner: p,
  aggregate: agg,
  onTap: () => context.push('/partner/${p.id}'),
  onDelete: () => _onDelete(context, ref, p, convCount),
),
```

## Target

用 `animations` 套件（pub.dev，flutter.dev 官方，v2.x）的 `OpenContainer`：卡片原地放大長成詳情頁。

```dart
OpenContainer(
  transitionType: ContainerTransitionType.fadeThrough,
  transitionDuration: const Duration(milliseconds: 380),
  closedElevation: 0,
  openElevation: 0,
  closedColor: Colors.transparent,
  openColor: AppColors.background, // 詳情頁背景色，依實際 scaffold 底色
  middleColor: AppColors.background,
  closedShape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18)), // 對齊 PartnerListCard 實際圓角
  closedBuilder: (context, open) => PartnerListCard(
    partner: p,
    aggregate: agg,
    onTap: open,           // 改由 OpenContainer 開頁
    onDelete: () => _onDelete(context, ref, p, convCount),
  ),
  openBuilder: (context, _) => PartnerDetailScreen(partnerId: p.id),
)
```

**架構取捨（必讀）**：`OpenContainer` 走自己的 `Navigator` route，不經 go_router——

- `/partner/:partnerId` 的 GoRoute **保留**（deep link、`focusCoachFollowUp` 等其他入口仍走它）。
- OpenContainer 打開的詳情頁不帶 `focusCoachFollowUp`（列表入口本來就不帶）。
- go_router 的 auth redirect 不會攔 OpenContainer route——列表頁本身已在 auth 牆內，可接受；若 repo 有 route-level analytics/guard 依賴 `/partner/:id` 被記錄，STOP 回報改用替代方案。
- 詳情頁內 `context.pop()`／back 手勢由 Navigator 正常處理（OpenContainer 支援反向 morph）。

reduced-motion：`OpenContainer` 跟系統 `disableAnimations` 的整合不完整——在 closedBuilder 外層判斷，reduce motion 時 fallback 回原本 `context.push`。

## Repo conventions to follow

- 依賴加法：`flutter pub add animations`（進 pubspec + lockfile，官方套件）。
- 圓角/顏色對照 `PartnerListCard` 現有 decoration（打開檔案抄實際值，不要猜）。

## Steps

1. `flutter pub add animations`。
2. `partner_list_screen.dart`：itemBuilder 裡的 `PartnerListCard` 包成上述 `OpenContainer`；reduce-motion fallback 保留 push 路徑。
3. 確認 `PartnerListCard` 的 `onTap` 用法（若卡內 InkWell 自己處理 tap，把 `open` 傳進去即可，不改卡內結構）。
4. 真機確認 morph 期間卡片圓角→全螢幕方角的過渡自然（`closedShape` 圓角要抄對）。
5. （選做，獨立 commit）同型縫：`partner_detail_screen.dart:698` 對話 tile → AnalysisScreen 比照辦理；`openBuilder: (context, _) => AnalysisScreen(conversationId: conversation.id)`（參數以 `routes.dart:120-127` 實際 builder 為準）。AnalysisScreen 很重，先驗第一個縫的手感與效能再決定做不做這步。

## Boundaries

- 不刪任何 GoRoute。
- 不動 PartnerDetailScreen／AnalysisScreen 內部。
- 若 `PartnerListCard.onTap` 簽名或列表結構漂移，STOP 回報。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`；`grep animations pubspec.yaml` 有版本。
- **Feel check**：
  - 點對象卡：卡片原地放大 morph 成詳情頁（~380ms fade-through），無左右滑感；back 反向縮回原卡位置。
  - 列表捲動到一半點卡、morph 起點就是該卡當下位置。
  - 詳情頁內刪除對象後返回，列表正常（onDelete 路徑沒被 OpenContainer 弄壞）。
  - deep link `/partner/<id>`（從教練通知等入口）仍正常開頁。
  - reduce motion：回到普通 push。
- **Done when**: 上述成立。
