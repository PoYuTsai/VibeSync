// lib/core/services/social_auth/social_auth_native.dart
// Native 平台 (iOS/Android) 的社群登入實作

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_auth_interface.dart';

/// Native 平台的社群登入服務
class SocialAuthServiceImpl implements SocialAuthService {
  /// iOS Client ID for Google Sign In
  static const String _googleIOSClientId =
      '568378103108-ptl0icvkk7v2vp6ob21hatm73unokg52.apps.googleusercontent.com';

  /// Web Client ID for Supabase (serverClientId)
  static const String _googleWebClientId =
      '568378103108-3nsc1ecskfpod51dqgko2d7g2q7pccad.apps.googleusercontent.com';

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
    // For iOS native Google Sign In with Supabase
    // clientId comes from GoogleService-Info.plist (CLIENT_ID)
    // serverClientId is the Web client ID configured in Supabase
    final googleSignIn = GoogleSignIn(
      serverClientId: _googleWebClientId,
      scopes: ['email', 'profile'],
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw const AuthException('Google Sign In was cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw const AuthException('Google Sign In failed: No ID token');
    }

    return await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
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
