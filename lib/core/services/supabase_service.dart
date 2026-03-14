// lib/core/services/supabase_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static late SupabaseClient _client;
  static bool _initialized = false;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    if (_initialized) return;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _client = Supabase.instance.client;
    _initialized = true;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError('SupabaseService not initialized. Call initialize() first.');
    }
    return _client;
  }

  static User? get currentUser => _initialized ? _client.auth.currentUser : null;

  static bool get isAuthenticated => currentUser != null;

  static Stream<AuthState> get authStateChanges {
    if (!_initialized) {
      throw StateError('SupabaseService not initialized. Call initialize() first.');
    }
    return _client.auth.onAuthStateChange;
  }

  /// Sign in with email and password
  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign up with email and password
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Sign out
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Sign in with Apple (iOS Native)
  /// Uses sign_in_with_apple package and Supabase signInWithIdToken
  static Future<AuthResponse> signInWithApple() async {
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
    return await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  /// Generate a random string for nonce
  static String _generateRandomString(int length) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// Sign in with Google (OAuth)
  static Future<bool> signInWithGoogle() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.poyutsai.vibesync://login-callback',
    );
  }

  /// Ensure subscription record exists for user
  /// Creates a free tier subscription if none exists
  static Future<void> ensureSubscriptionExists(String userId) async {
    final existing = await client
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      await client.from('subscriptions').insert({
        'user_id': userId,
        'tier': 'free',
        'monthly_messages_used': 0,
        'daily_messages_used': 0,
        'started_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Get current session token
  static String? get accessToken => currentUser != null
      ? client.auth.currentSession?.accessToken
      : null;

  /// Invoke Edge Function with timeout
  static Future<FunctionResponse> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return await client.functions
        .invoke(
          functionName,
          body: body,
        )
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Edge Function timeout after ${timeout.inSeconds}s',
          ),
        );
  }
}
