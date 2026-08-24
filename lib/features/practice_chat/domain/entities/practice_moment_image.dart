// 動態貼文配圖 id → client 端來源的對照。
//
// v1 只有一個 sentinel：`moment_self_portrait`＝「用她自己的圖鑑照片」，零新素材
// （D1）。20 張情境圖的 id 已在 Edge `moments_image_catalog.ts` 宣告，但**素材檔案
// 還不存在**，所以這裡先不列。
//
// **向前相容鐵則**：server 端先開閘門、client 還沒更新時會收到不認得的 id。
// 一律降級成純文字——不 crash、不顯示破圖。素材補齊那天只要在 [_sceneImageAssets]
// 加對照（新增資料，不改邏輯）。

/// 「用她自己的圖鑑照片」的哨兵 id，鏡像 Edge `SELF_PORTRAIT_IMAGE_ID`。
const String kMomentSelfPortraitImageId = 'moment_self_portrait';

/// 情境圖 id → bundled asset 路徑。**v1 刻意是空的**：素材未到位。
/// 補素材時只要在這裡加 20 筆並在 `pubspec.yaml` 掛上目錄，UI 一行都不用改。
const Map<String, String> _sceneImageAssets = <String, String>{};

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

/// [imageId] → 畫面要用的來源。null／空字串／**不認得的 id** 一律回 null
/// （＝這則當純文字貼文處理）。
MomentImageSource? resolveMomentImage(String? imageId) {
  final id = imageId?.trim();
  if (id == null || id.isEmpty) return null;
  if (id == kMomentSelfPortraitImageId) return const MomentSelfPortraitImage();
  final asset = _sceneImageAssets[id];
  if (asset != null) return MomentSceneImage(asset);
  return null;
}
