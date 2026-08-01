// lib/core/services/social_auth/social_auth_interface.dart
// 社群登入介面 - 定義跨平台 API

import 'package:supabase_flutter/supabase_flutter.dart';

/// 社群登入服務介面
abstract class SocialAuthService {
  /// Sign in with Apple (iOS only)
  Future<AuthResponse> signInWithApple();

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle();

  /// Check if social auth is available on this platform
  bool get isAvailable;
}
