// lib/core/services/supabase_service.dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'keyboard_privacy_purge_service.dart';
import '../config/environment.dart';
import 'auth_recovery_helper.dart';
import 'auth_diagnostics_service.dart';
import 'guest_session_vault.dart';
import 'revenuecat_service.dart';
import 'social_auth/social_auth_service.dart';

class SupabaseService {
  static late SupabaseClient _client;
  static bool _initialized = false;
  static StreamSubscription<AuthState>? _authStateSubscription;
  static bool _passwordRecoveryInProgress = false;
  static final AppLinks _appLinks = AppLinks();

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
      debug: kDebugMode,
    );
    _client = Supabase.instance.client;
    _authStateSubscription?.cancel();
    _authStateSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
    );
    await _syncPasswordRecoveryStateFromInitialLink();
    _initialized = true;
  }

  static Future<void> _syncPasswordRecoveryStateFromInitialLink() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      _passwordRecoveryInProgress =
          AuthRecoveryHelper.isPasswordRecoveryLink(initialLink);
      if (_passwordRecoveryInProgress) {
        unawaited(
          AuthDiagnosticsService.log(
            event: 'recovery_link_detected',
            status: 'info',
            message: 'Password recovery deep link detected on app start.',
            metadata: {
              'coldStart': true,
              'hasCurrentUser': currentUser != null,
            },
          ),
        );
      }
    } catch (error) {
      debugPrint('Password recovery link sync skipped: $error');
    }
  }

  static void _handleAuthStateChange(AuthState authState) {
    _passwordRecoveryInProgress = AuthRecoveryHelper.nextPasswordRecoveryState(
      event: authState.event,
      currentState: _passwordRecoveryInProgress,
    );
    _syncGuestSessionVault(authState.session);
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

  /// 批 B 訪客模式：目前 session 是否為匿名（訪客）帳號。
  static bool get isGuestUser => currentUser?.isAnonymous ?? false;

  static bool get isPasswordRecoveryInProgress => _passwordRecoveryInProgress;

  static Stream<AuthState> get authStateChanges {
    if (!_initialized) {
      throw StateError(
          'SupabaseService not initialized. Call initialize() first.');
    }
    return _client.auth.onAuthStateChange;
  }

  /// 訪客額度綁裝置：訪客 refresh token 的 Keychain 鏡存。
  static GuestSessionVault guestSessionVault = GuestSessionVault();

  /// 匿名 session 建立/換發 → 鏡存最新 refresh token；非匿名 session 出現
  /// （linking 完成或登入既有帳號）→ 清 vault。無 session（登出）不動 vault
  /// （token 反正已被 revoke，見 GuestSessionVault 類註解）。
  /// vault 內部已串行化，unawaited 不會造成寫入亂序。
  static void _syncGuestSessionVault(Session? session) {
    if (session == null) return;
    unawaited(guestSessionVault.syncAuthSession(
      isAnonymous: session.user.isAnonymous,
      refreshToken: session.refreshToken,
    ));
  }

  /// 批 B 訪客模式：匿名登入（先逛逛，不用註冊）。
  static Future<AuthResponse> signInAnonymously() async {
    return await client.auth.signInAnonymously();
  }

  /// 訪客入口（綁裝置版）：先試復活本機 Keychain 裡的舊訪客 session
  /// （同帳號＝同剩餘額度），token 真死（4xx）才開新匿名帳號；
  /// 網路類錯誤外拋讓使用者重試（保 vault）。邏輯在 GuestSignInFlow
  /// （可單元測試），此處只接線。
  static Future<AuthResponse> signInAsGuest() {
    return GuestSignInFlow(
      vault: guestSessionVault,
      restoreSession: (token) => client.auth.setSession(token),
      freshSignIn: () => client.auth.signInAnonymously(),
      discardSession: () => client.auth.signOut(),
    ).signIn();
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
      emailRedirectTo: AppConfig.authRedirectUri,
    );
  }

  static Future<void> resendSignUpConfirmation({
    required String email,
  }) async {
    await client.auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: AppConfig.authRedirectUri,
    );
  }

  static Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConfig.authRedirectUri,
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
    // 帳號已從 server 刪除，vault 內 token（若有）已死，直接清。
    await guestSessionVault.clear();
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

  /// 批 B 訪客轉正：把 Apple identity 連結到匿名帳號（uid 不變）。
  static Future<AuthResponse> linkWithApple() async {
    return await _socialAuth.linkWithApple();
  }

  /// 批 B 訪客轉正：把 Google identity 連結到匿名帳號（uid 不變）。
  static Future<AuthResponse> linkWithGoogle() async {
    return await _socialAuth.linkWithGoogle();
  }

  /// 批 B 訪客轉正：email＋密碼。updateUser 會寄確認信；點擊連結前
  /// 帳號仍是匿名（訪客額度不變），介面需明講。
  static Future<UserResponse> registerGuestWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.updateUser(
      UserAttributes(email: email, password: password),
      emailRedirectTo: AppConfig.authRedirectUri,
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
