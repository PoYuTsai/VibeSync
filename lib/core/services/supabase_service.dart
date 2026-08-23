// lib/core/services/supabase_service.dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'keyboard_privacy_purge_service.dart';
import '../config/auth_callback_contract.dart';
import '../config/environment.dart';
import 'auth_recovery_helper.dart';
import 'auth_diagnostics_service.dart';
import 'email_auth_callback_failure.dart';
import 'revenuecat_service.dart';
import 'social_auth/social_auth_service.dart';

class SupabaseService {
  static late SupabaseClient _client;
  static bool _initialized = false;
  static StreamSubscription<AuthState>? _authStateSubscription;
  static StreamSubscription<Uri>? _authDeepLinkSubscription;
  static bool _passwordRecoveryInProgress = false;
  static final AppLinks _appLinks = AppLinks();
  static final EmailAuthCallbackFailureStore _emailCallbackFailures =
      EmailAuthCallbackFailureStore();

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
        // Supabase's default observer accepts any URI carrying `code`.
        // Native callbacks are routed through the exact Email policy below;
        // keep web's existing URL handling unchanged.
        detectSessionInUri: kIsWeb,
      ),
      debug: kDebugMode,
    );
    _client = Supabase.instance.client;
    _authStateSubscription?.cancel();
    _authStateSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
    );
    _authDeepLinkSubscription?.cancel();
    if (!kIsWeb) {
      _authDeepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(_handleIncomingAuthLink(uri)),
        onError: (error, stackTrace) {
          debugPrint(
            'Email auth callback listener skipped: ${error.runtimeType}',
          );
        },
      );
    }
    _initialized = true;
  }

  static Future<void> _handleIncomingAuthLink(Uri uri) async {
    if (!AuthCallbackUriPolicy.isEmailCallback(uri)) {
      // OAuth callbacks belong to FlutterWebAuth2; wrong-scheme/host links
      // are ignored before any session exchange can occur.
      return;
    }

    if (!AuthCallbackUriPolicy.isProcessableEmailAuthCallback(uri)) {
      _publishEmailAuthCallbackFailure(uri);
      return;
    }

    try {
      await _client.auth.getSessionFromUrl(uri);
      clearEmailAuthCallbackFailure();
    } on AuthException catch (error) {
      _publishEmailAuthCallbackFailure(uri, error: error);
      debugPrint('Email auth callback rejected: ${error.runtimeType}');
    } catch (error) {
      _publishEmailAuthCallbackFailure(uri, error: error);
      debugPrint('Email auth callback failed: ${error.runtimeType}');
    }
  }

  static void _handleAuthStateChange(AuthState authState) {
    _passwordRecoveryInProgress = AuthRecoveryHelper.nextPasswordRecoveryState(
      event: authState.event,
      currentState: _passwordRecoveryInProgress,
    );
    if (authState.event == AuthChangeEvent.passwordRecovery ||
        authState.event == AuthChangeEvent.signedIn) {
      clearEmailAuthCallbackFailure();
    }
    if (authState.event == AuthChangeEvent.passwordRecovery) {
      unawaited(
        AuthDiagnosticsService.log(
          event: 'password_recovery_entered',
          status: 'success',
          email: authState.session?.user.email,
          message: 'Supabase auth entered password recovery mode.',
        ),
      );
    }
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
          'SupabaseService not initialized. Call initialize() first.');
    }
    return _client;
  }

  static User? get currentUser =>
      _initialized ? _client.auth.currentUser : null;

  static bool get isAuthenticated => currentUser != null;

  static bool get isPasswordRecoveryInProgress => _passwordRecoveryInProgress;

  static EmailAuthCallbackFailure? get pendingEmailAuthCallbackFailure =>
      _emailCallbackFailures.pending;

  static Stream<EmailAuthCallbackFailure> get emailAuthCallbackFailureChanges =>
      _emailCallbackFailures.events;

  static EmailAuthCallbackFailure? consumeEmailAuthCallbackFailure() =>
      _emailCallbackFailures.consume();

  static void clearEmailAuthCallbackFailure() {
    _emailCallbackFailures.clear();
  }

  static void _publishEmailAuthCallbackFailure(
    Uri uri, {
    Object? error,
  }) {
    _emailCallbackFailures.publish(
      EmailAuthCallbackFailureClassifier.fromCallback(uri, error: error),
    );
  }

  static Stream<AuthState> get authStateChanges {
    if (!_initialized) {
      throw StateError(
          'SupabaseService not initialized. Call initialize() first.');
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
      emailRedirectTo: AppConfig.authEmailRedirectUri,
    );
  }

  static Future<void> resendSignUpConfirmation({
    required String email,
  }) async {
    await client.auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: AppConfig.authEmailRedirectUri,
    );
  }

  static Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConfig.authEmailRedirectUri,
    );
  }

  static Future<UserResponse> updatePassword({
    required String password,
  }) async {
    return await client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  static Future<void> deleteAccount({
    required String confirmation,
  }) async {
    final response = await invokeFunction(
      'delete-account',
      body: {'confirmation': confirmation},
      timeout: const Duration(seconds: 60),
    );

    if (response.status >= 200 && response.status < 300) {
      return;
    }

    final data = response.data;
    if (data is Map && data['error'] is String) {
      final error = data['error'] as String;
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        throw Exception('$error: $detail');
      }
      throw Exception(error);
    }

    throw Exception('Delete account failed');
  }

  static void clearPasswordRecoveryState() {
    _passwordRecoveryInProgress = false;
  }

  /// Sign out
  static Future<void> signOut() async {
    final ownerUserId = currentUser?.id;
    await KeyboardPrivacyPurgeService.live.purge(
      KeyboardContextPurgeScope.logout,
      ownerUserId: ownerUserId,
    );

    Object? signOutError;

    try {
      await client.auth.signOut();
    } catch (error) {
      signOutError = error;
    }

    try {
      await RevenueCatService.logout();
    } catch (error) {
      debugPrint('RevenueCat logout cleanup error: $error');
      signOutError ??= error;
    }

    _passwordRecoveryInProgress = false;

    if (signOutError == null) {
      return;
    }

    if (signOutError is Exception) {
      throw signOutError;
    }

    throw Exception(signOutError.toString());
  }

  static Future<void> clearLocalSessionAfterDeletion() async {
    try {
      await client.auth.signOut();
    } catch (error) {
      debugPrint('Auth sign-out cleanup after deletion: $error');
    }

    try {
      await RevenueCatService.logout();
    } catch (error) {
      debugPrint('RevenueCat logout cleanup after deletion: $error');
    }

    _passwordRecoveryInProgress = false;
  }

  // 社群登入服務實例 (平台相容)
  static final SocialAuthService _socialAuth = getSocialAuthService();

  /// Check if social auth is available on this platform
  static bool get isSocialAuthAvailable => _socialAuth.isAvailable;

  /// Sign in with Apple (iOS Native)
  /// Uses sign_in_with_apple package and Supabase signInWithIdToken
  static Future<AuthResponse> signInWithApple() async {
    return await _socialAuth.signInWithApple();
  }

  /// Sign in with Google (Native)
  /// Uses google_sign_in package for native UX (shows existing accounts)
  static Future<AuthResponse> signInWithGoogle() async {
    return await _socialAuth.signInWithGoogle();
  }

  /// Ensure subscription record exists for user
  /// Creates a free tier subscription if none exists
  static Future<void> ensureSubscriptionExists(String userId) async {
    final existing = await client
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      return;
    }

    final nowIso = DateTime.now().toIso8601String();

    try {
      await client.from('subscriptions').insert({
        'user_id': userId,
        'tier': 'free',
        'monthly_messages_used': 0,
        'daily_messages_used': 0,
        'daily_reset_at': nowIso,
        'monthly_reset_at': nowIso,
        'started_at': nowIso,
      });
    } on PostgrestException catch (error) {
      if (error.code != '23505') {
        rethrow;
      }

      debugPrint(
        'Subscription bootstrap raced with an existing row for user $userId; continuing.',
      );
    }
  }

  /// Get current session token
  static String? get accessToken =>
      currentUser != null ? client.auth.currentSession?.accessToken : null;

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
