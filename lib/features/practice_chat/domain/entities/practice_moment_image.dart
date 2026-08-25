// 動態貼文配圖 id → client 端來源的對照。
//
// v1 只有一個 sentinel：`moment_self_portrait`＝「用她自己的圖鑑照片」，零新素材
// （D1）。20 張情境圖的 id 已在 Edge `moments_image_catalog.ts` 宣告，但**素材檔案
// 還不存在**，所以這裡先不列。
//
// **向前相容鐵則**：server 端先開閘門、client 還沒更新時會收到不認得的 id。
// 一律降級成純文字——不 crash、不顯示破圖。素材補齊那天只要在 [_sceneImageAssets]
// 加對照（新增資料，不改邏輯）。

import '../../../../core/config/environment.dart';

/// 「用她自己的圖鑑照片」的哨兵 id，鏡像 Edge `SELF_PORTRAIT_IMAGE_ID`。
const String kMomentSelfPortraitImageId = 'moment_self_portrait';

/// 情境圖 id → bundled asset 路徑。2026-08-25 素材到位（PR #30）補齊 20 筆。
/// 與 Edge `AVAILABLE_MOMENT_IMAGE_IDS` 的場景 id 一一對應，由
/// test/lint/moments_scene_asset_parity_test.dart 三方對帳（Edge、本表、檔案）。
final Map<String, String> _sceneImageAssets = <String, String>{
  for (final id in _sceneImageIds)
    id: 'assets/images/practice_moments/$id.webp',
};

/// 20 個場景 id。檔名規則固定為 `<id>.webp`，所以只列 id、路徑用推導——
/// 這裡若手打 20 條完整路徑，打錯一條就是那個題材永遠安靜地退回純文字。
const List<String> _sceneImageIds = <String>[
  'moment_coffee_cup',
  'moment_cafe_corner',
  'moment_dessert_plate',
  'moment_home_cooking',
  'moment_late_night_snack',
  'moment_street_night',
  'moment_sunset_sky',
  'moment_sea_view',
  'moment_mountain_trail',
  'moment_gym_corner',
  'moment_yoga_mat',
  'moment_cat_nap',
  'moment_dog_walk',
  'moment_bookshelf',
  'moment_desk_work',
  'moment_exhibition_wall',
  'moment_live_stage',
  'moment_flower_bunch',
  'moment_rainy_window',
  'moment_train_window',
];

/// 一則貼文的配圖要畫什麼。
sealed class MomentImageSource {
  const MomentImageSource();
}

/// 用該角色的圖鑑照片（走 `PracticeGirlPhoto`，內建 errorBuilder 永不 crash）。
class MomentSelfPortraitImage extends MomentImageSource {
  const MomentSelfPortraitImage();
}

/// 用 bundled 情境圖 asset。
class MomentSceneImage extends MomentImageSource {
  const MomentSceneImage(this.assetPath);

  final String assetPath;
}

/// 用 server 生成、存在 Supabase Storage 的遠端圖（PR-5）。
class MomentRemoteImage extends MomentImageSource {
  const MomentRemoteImage(this.url);

  final String url;
}

/// [imageId] → 畫面要用的來源。null／空字串／**不認得的 id** 一律回 null
/// （＝這則當純文字貼文處理）。
/// 生成配圖 URL 的縱深防禦：只信任 https 且 host 等於本 app 的 Supabase
/// host。server 給的值本就該合法；擋的是 API 回應被污染或未來 bug 把任意
/// URL 塞進來的情況。不合法一律回 null（該則降級走 imageId／純文字）。
String? resolveMomentImageUrl(String? imageUrl) {
  final raw = imageUrl?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https') return null;
  final allowedHost = Uri.tryParse(AppConfig.supabaseUrl)?.host;
  if (allowedHost == null || allowedHost.isEmpty) return null;
  if (uri.host != allowedHost) return null;
  return raw;
}

MomentImageSource? resolveMomentImage(String? imageId) {
  final id = imageId?.trim();
  if (id == null || id.isEmpty) return null;
  if (id == kMomentSelfPortraitImageId) return const MomentSelfPortraitImage();
  final asset = _sceneImageAssets[id];
  if (asset != null) return MomentSceneImage(asset);
  return null;
}
