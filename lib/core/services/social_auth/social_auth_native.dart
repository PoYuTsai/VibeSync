// lib/core/services/social_auth/social_auth_native.dart
// Native 平台 (iOS/Android) 的社群登入實作

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/auth_callback_contract.dart';
import '../../config/environment.dart';
import '../../utils/platform_info.dart';
import 'social_auth_interface.dart';

/// Native 平台的社群登入服務
class SocialAuthServiceImpl implements SocialAuthService {
  @override
  bool get isAvailable => true;

  @override
  Future<AuthResponse> signInWithApple() async {
    // Android deliberately uses the Supabase Apple web provider so an
    // existing iPhone Apple account (including Hide My Email) can return
    // through the frozen OAuth callback. iOS keeps the native token flow.
    if (isAndroidPlatform) {
      return _signInWithOAuth(
        provider: OAuthProvider.apple,
        providerLabel: 'Apple',
      );
    }

    return _signInWithAppleNative();
  }

  Future<AuthResponse> _signInWithAppleNative() async {
    // Generate a secure random nonce
    final rawNonce = _generateRandomString(32);
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    // Request Apple Sign In
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple Sign In failed: No identity token');
    }

    // Sign in to Supabase with the Apple ID token
    return await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    return _signInWithOAuth(
      provider: OAuthProvider.google,
      providerLabel: 'Google',
    );
  }

  Future<AuthResponse> _signInWithOAuth({
    required OAuthProvider provider,
    required String providerLabel,
  }) async {
    // 凍結 redirect 契約的唯一真相源是 AppConfig.authRedirectUri
    // （contracts/auth-callback.json 對帳），此處不得硬編第二份
    final expectedCallback = Uri.parse(AppConfig.authRedirectUri);
    final authUrl = await Supabase.instance.client.auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: AppConfig.authRedirectUri,
    );

    // Use flutter_web_auth_2 for both native platforms. On Android this is
    // also the Apple web flow; on iOS the existing Google behavior remains
    // ASWebAuthenticationSession.
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.url,
      callbackUrlScheme: expectedCallback.scheme,
      options: const FlutterWebAuth2Options(
        preferEphemeral: false, // Use shared Safari cookies
      ),
    );

    final callbackUri = Uri.parse(result);
    if (!AuthCallbackUriPolicy.isOAuthCallback(callbackUri)) {
      throw AuthException(
        '$providerLabel Sign In failed: Invalid callback URL',
      );
    }

    final sessionResponse =
        await Supabase.instance.client.auth.getSessionFromUrl(
      callbackUri,
    );

    return AuthResponse(session: sessionResponse.session);
  }

  /// Generate a random string for nonce
  String _generateRandomString(int length) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }
}

/// 取得社群登入服務實例
SocialAuthService getSocialAuthService() => SocialAuthServiceImpl();
