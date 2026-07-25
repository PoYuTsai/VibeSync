// test/unit/core/services/usage_service_paid_entitlement_test.dart
//
// `UsageService.hasUnexpiredPaidEntitlement` 是互動電子書付費閘門用來判斷
// 「本機快取的付費身分還能不能信」的依據。電子書是第一個完全離線可讀的付費
// 內容，所以這個判斷必須 fail closed：任何不確定都回 false。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

const _testHivePath = './.dart_tool/test_hive_usage_paid_entitlement';
const _owner = 'user-paid-0001';

void main() {
  setUpAll(() => Hive.init(_testHivePath));

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  late Box box;

  setUp(() async {
    box = await Hive.openBox(AppConstants.usageBox);
    await box.clear();
    UsageService.debugCurrentUserIdOverride = _owner;
  });

  tearDown(() async {
    UsageService.debugCurrentUserIdOverride = null;
    await box.clear();
  });

  Future<void> writePaidSnapshot({
    required String owner,
    required String tier,
    required DateTime expiresAt,
  }) async {
    await box.put('last_known_paid_user_id', owner);
    await box.put('last_known_paid_tier', tier);
    await box.put('last_known_paid_expires_at', expiresAt.toIso8601String());
  }

  test('到期日還在未來 → 信任快取的付費身分', () async {
    await writePaidSnapshot(
      owner: _owner,
      tier: SubscriptionTierHelper.starter,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 10)),
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isTrue);
  });

  test('到期日已過 → 不信任（這就是飛航模式繞道的關閉點）', () async {
    await writePaidSnapshot(
      owner: _owner,
      tier: SubscriptionTierHelper.starter,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('剛好到期的那一刻起就不信任', () async {
    final at = DateTime.utc(2026, 7, 26, 12);
    await writePaidSnapshot(
      owner: _owner,
      tier: SubscriptionTierHelper.essential,
      expiresAt: at,
    );
    expect(
      UsageService.hasUnexpiredPaidEntitlement(
        now: at.subtract(const Duration(seconds: 1)),
      ),
      isTrue,
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(now: at), isFalse);
    expect(
      UsageService.hasUnexpiredPaidEntitlement(
        now: at.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test('快照屬於別的帳號 → 不信任', () async {
    await writePaidSnapshot(
      owner: 'someone-else',
      tier: SubscriptionTierHelper.starter,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 10)),
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('tier 是 free → 不信任', () async {
    await writePaidSnapshot(
      owner: _owner,
      tier: SubscriptionTierHelper.free,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 10)),
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('沒有到期日或格式壞掉 → 不信任', () async {
    await box.put('last_known_paid_user_id', _owner);
    await box.put('last_known_paid_tier', SubscriptionTierHelper.starter);
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);

    await box.put('last_known_paid_expires_at', 'not-a-date');
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('完全沒有快照 → 不信任', () async {
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('沒有登入帳號 → 不信任', () async {
    await writePaidSnapshot(
      owner: _owner,
      tier: SubscriptionTierHelper.starter,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 10)),
    );
    UsageService.debugCurrentUserIdOverride = '';
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });

  test('syncSubscriptionSnapshot 寫入的快照可以被讀到', () async {
    // 走真實寫入路徑，確認 key 名稱沒有分歧。
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.starter,
      monthlyLimit: 500,
      dailyLimit: 50,
      paidExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isTrue);

    // 降級為 free 並清掉付費快照後就不再信任。
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: 30,
      dailyLimit: 3,
      clearPaidSnapshot: true,
    );
    expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
  });
}
