// lib/core/services/social_auth/social_auth_service.dart
// 條件式匯出 - 根據平台選擇正確的實作

export 'social_auth_interface.dart';
export 'social_auth_web.dart' if (dart.library.io) 'social_auth_native.dart';
