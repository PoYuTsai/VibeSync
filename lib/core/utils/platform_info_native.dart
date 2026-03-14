// lib/core/utils/platform_info_native.dart
// Native 平台資訊 (iOS/Android)

import 'dart:io' show Platform;

/// 是否為 iOS 平台
bool get isIOSPlatform => Platform.isIOS;

/// 是否為 Android 平台
bool get isAndroidPlatform => Platform.isAndroid;

/// 是否為行動裝置平台
bool get isMobilePlatform => Platform.isIOS || Platform.isAndroid;
