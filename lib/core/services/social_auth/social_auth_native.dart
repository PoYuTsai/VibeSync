// lib/core/services/social_auth/social_auth_native.dart
// Native 平台 (iOS/Android) 的社群登入實作

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/environment.dart';
import 'social_auth_interface.dart';

/// Native 平台的社群登入服務
class SocialAuthServiceImpl implements SocialAuthService {
  @override
  bool get isAvailable => true;

  @override
  Future<AuthResponse> signInWithApple() async {
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
    // 凍結 redirect 契約的唯一真相源是 AppConfig.authRedirectUri
    // （contracts/auth-callback.json 對帳），此處不得硬編第二份
    final expectedCallback = Uri.parse(AppConfig.authRedirectUri);
    final authUrl = await Supabase.instance.client.auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: AppConfig.authRedirectUri,
    );

    // Use flutter_web_auth_2 for ASWebAuthenticationSession on iOS
    // This provides the smooth native OAuth experience like Claude app
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.url,
      callbackUrlScheme: expectedCallback.scheme,
      options: const FlutterWebAuth2Options(
        preferEphemeral: false, // Use shared Safari cookies
      ),
    );

    final callbackUri = Uri.parse(result);
    if (callbackUri.scheme != expectedCallback.scheme ||
        callbackUri.host != expectedCallback.host) {
      throw const AuthException('Google Sign In failed: Invalid callback URL');
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
