import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
  });

  tearDown(() {
    AiDataSharingConsent.debugUserIdOverride = null;
  });

  test('keyboard screenshot consent is independent from general AI consent',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${AiDataSharingConsent.acceptedKeyForTesting}::owner-1',
      true,
    );

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
  });

  test('partner sharing defaults off and cannot enable before consent',
      () async {
    expect(
      await AiDataSharingConsent.hasKeyboardPartnerContextSharingEnabled(),
      isFalse,
    );
    expect(
      await AiDataSharingConsent.setKeyboardPartnerContextSharingEnabled(true),
      isFalse,
    );
  });

  test('revoking screenshot consent also revokes partner context sharing',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1',
      true,
    );
    await prefs.setString(
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1',
      DateTime.utc(2026, 7, 27).toIso8601String(),
    );
    expect(
      await AiDataSharingConsent.setKeyboardPartnerContextSharingEnabled(true),
      isTrue,
    );

    await AiDataSharingConsent.revokeKeyboardScreenshotConsent();

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
    expect(
      await AiDataSharingConsent.keyboardScreenshotConsentAcceptedAt(),
      isNull,
    );
    expect(
      await AiDataSharingConsent.hasKeyboardPartnerContextSharingEnabled(),
      isFalse,
    );
  });
}
