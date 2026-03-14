// lib/core/utils/platform_info.dart
// 平台資訊 - 條件式匯出

export 'platform_info_web.dart' if (dart.library.io) 'platform_info_native.dart';
