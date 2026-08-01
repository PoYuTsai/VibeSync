// lib/core/services/social_auth/social_auth_interface.dart
// 社群登入介面 - 定義跨平台 API

import 'package:supabase_flutter/supabase_flutter.dart';

/// 社群登入服務介面
abstract class SocialAuthService {
  /// Sign in with Apple (iOS only)
  Future<AuthResponse> signInWithApple();

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle();

  /// 批 B 訪客模式：把 Apple identity 連結到目前（匿名）帳號，uid 不變。
  Future<AuthResponse> linkWithApple();

  /// 批 B 訪客模式：把 Google identity 連結到目前（匿名）帳號，uid 不變。
  Future<AuthResponse> linkWithGoogle();

  /// Check if social auth is available on this platform
  bool get isAvailable;
}
