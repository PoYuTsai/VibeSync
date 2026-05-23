import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/services/analysis_hint_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('markEditMessageSeen scopes the hint by partner id', () async {
    await AnalysisHintService.markEditMessageSeen(partnerId: 'partner-a');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_partner_partner-a'),
      isTrue,
    );
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_partner_partner-b'),
      isNull,
    );
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_global'),
      isNull,
    );
  });

  test('markEditMessageSeen falls back to the global key without partner id',
      () async {
    await AnalysisHintService.markEditMessageSeen();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_global'),
      isTrue,
    );
  });

  test('markEditMessageSeen trims blank partner ids into the global key',
      () async {
    await AnalysisHintService.markEditMessageSeen(partnerId: '   ');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_global'),
      isTrue,
    );
    expect(
      prefs.getBool('analysis_edit_message_hint_seen_v2_partner_   '),
      isNull,
    );
  });

  test('hasSeenEditMessage stays false in debug builds for dogfood retesting',
      () async {
    await AnalysisHintService.markEditMessageSeen(partnerId: 'partner-a');

    expect(
      await AnalysisHintService.hasSeenEditMessage(partnerId: 'partner-a'),
      isFalse,
    );
  });
}
