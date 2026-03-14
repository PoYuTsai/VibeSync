// lib/core/services/social_auth/social_auth_web.dart
// Web 平台的社群登入 - 不支援，拋出錯誤

import 'package:supabase_flutter/supabase_flutter.dart';
import 'social_auth_interface.dart';

/// Web 平台的社群登入服務 (不支援)
class SocialAuthServiceImpl implements SocialAuthService {
  @override
  bool get isAvailable => false;

  @override
  Future<AuthResponse> signInWithApple() {
    throw const AuthException('Apple Sign In is not supported on Web');
  }

  @override
  Future<AuthResponse> signInWithGoogle() {
    throw const AuthException('Google Sign In is not supported on Web');
  }
}

/// 取得社群登入服務實例
SocialAuthService getSocialAuthService() => SocialAuthServiceImpl();
