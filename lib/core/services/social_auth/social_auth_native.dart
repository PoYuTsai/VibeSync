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
  // Callback scheme for OAuth
  static const String _callbackScheme = 'com.poyutsai.vibesync';

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
    // Get the Supabase URL from config
    final supabaseUrl = AppConfig.supabaseUrl;
    final redirectUri = '$_callbackScheme://login-callback';

    // Construct the OAuth URL for Google via Supabase
    final authUrl = Uri.parse('$supabaseUrl/auth/v1/authorize').replace(
      queryParameters: {
        'provider': 'google',
        'redirect_to': redirectUri,
      },
    );

    // Use flutter_web_auth_2 for ASWebAuthenticationSession on iOS
    // This provides the smooth native OAuth experience like Claude app
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _callbackScheme,
      options: const FlutterWebAuth2Options(
        preferEphemeral: false, // Use shared Safari cookies
      ),
    );

    // Parse the callback URL to get the tokens
    final uri = Uri.parse(result);

    // Check for error
    final error = uri.queryParameters['error'];
    if (error != null) {
      final errorDescription = uri.queryParameters['error_description'] ?? error;
      throw AuthException(errorDescription);
    }

    // The callback URL contains the access_token in the fragment
    // Format: scheme://callback#access_token=xxx&refresh_token=yyy&...
    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      // Maybe tokens are in query params instead
      final accessToken = uri.queryParameters['access_token'];
      final refreshToken = uri.queryParameters['refresh_token'];

      if (accessToken != null) {
        return await Supabase.instance.client.auth.setSession(refreshToken ?? accessToken);
      }
      throw const AuthException('Google Sign In failed: No tokens received');
    }

    // Parse fragment parameters
    final params = Uri.splitQueryString(fragment);
    final accessToken = params['access_token'];
    final refreshToken = params['refresh_token'];

    if (accessToken == null) {
      throw const AuthException('Google Sign In failed: No access token');
    }

    // Set the session in Supabase
    return await Supabase.instance.client.auth.setSession(refreshToken ?? accessToken);
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
