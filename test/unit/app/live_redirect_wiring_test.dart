// 正式路由的年齡確認接線（AGE-01）：liveAppRedirect／buildAgeGateScreen 讀的是
// SupabaseService 目前的使用者（session 裡的 app_metadata）與 onboarding 旗標，
// 不是測試自己組的 GoRouter。換成常數或讀錯來源，這裡會失敗。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/app/routes.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';

const _at = '2026-10-30T08:00:00.000Z';

User _user(Map<String, dynamic> appMetadata) => User(
      id: 'u1',
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: _at,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.markCompleted();
  });

  tearDown(() async {
    SupabaseService.debugResetForTesting();
    await OnboardingService.reset();
  });

  void signInAs(Map<String, dynamic> appMetadata) {
    final user = _user(appMetadata);
    SupabaseService.debugCurrentUserOverride = () => user;
  }

  test('帳號沒有年齡紀錄：導去 /age-gate，畫面是表單', () {
    signInAs(const {'provider': 'apple'});

    expect(liveAppRedirect('/'), '/age-gate');
    expect(liveAppRedirect('/age-gate'), isNull);
    expect(liveAppRedirect('/settings'), isNull);
    expect(buildAgeGateScreen().blocked, isFalse);
  });

  test('帳號記成未成年：導去 /age-gate，畫面直接是鎖住的', () {
    signInAs(const {
      'age_gate': {'result': 'minor', 'policy': 1, 'at': _at},
    });

    expect(liveAppRedirect('/'), '/age-gate');
    expect(liveAppRedirect('/settings/keyboard'), '/age-gate');
    expect(buildAgeGateScreen().blocked, isTrue);
  });

  test('帳號確認成年：首頁照常，/age-gate 回首頁', () {
    signInAs(const {
      'age_gate': {'result': 'adult', 'policy': 1, 'at': _at},
    });

    expect(liveAppRedirect('/'), isNull);
    expect(liveAppRedirect('/age-gate'), '/');
  });

  test('沒登入：照舊去登入頁，不問年齡', () {
    SupabaseService.debugCurrentUserOverride = () => null;

    expect(liveAppRedirect('/age-gate'), '/login');
  });
}
