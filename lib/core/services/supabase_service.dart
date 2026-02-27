// lib/core/services/supabase_service.dart
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

  /// Get current session token
  static String? get accessToken => currentUser != null
      ? client.auth.currentSession?.accessToken
      : null;

  /// Invoke Edge Function
  static Future<FunctionResponse> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    return await client.functions.invoke(
      functionName,
      body: body,
    );
  }
}
