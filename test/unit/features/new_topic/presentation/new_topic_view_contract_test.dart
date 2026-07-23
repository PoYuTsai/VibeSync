import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_view.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  test('route mode 解析：只認 new_topic，unknown fallback opener', () {
    expect(
      OpeningRescueScreen.modeFromQuery('new_topic'),
      OpeningRescueMode.newTopic,
    );
    expect(
      OpeningRescueScreen.modeFromQuery(null),
      OpeningRescueMode.opener,
    );
    expect(
      OpeningRescueScreen.modeFromQuery('opener'),
      OpeningRescueMode.opener,
    );
    expect(
      OpeningRescueScreen.modeFromQuery('NEW_TOPIC'),
      OpeningRescueMode.opener,
    );
    expect(
      OpeningRescueScreen.modeFromQuery('garbage'),
      OpeningRescueMode.opener,
    );
  });

  test('情境四 enum chips：payload 值鎖 server 契約、無自由輸入', () {
    expect(
      NewTopicView.situationOptions.map((o) => o.value).toList(),
      ['went_cold', 'after_date', 'stuck', 'warm_up'],
    );
    expect(
      NewTopicView.situationOptions.map((o) => o.label).toList(),
      ['冷掉了', '剛約完', '聊著但卡住', '想升溫'],
    );
  });

  test('New Topic 專用進度文案五句', () {
    expect(NewTopicView.progressPhrases, hasLength(5));
    expect(NewTopicView.progressPhrases.first, contains('作戰板'));
    expect(NewTopicView.progressPhrases.last, contains('請保持連線'));
  });

  test('Free upsell 文案：一張完整推薦卡＋精簡再解鎖 4 個', () {
    expect(
      NewTopicView.freeUpsellHeadline,
      '免費版先看最推薦的 1 個完整方案',
    );
    expect(NewTopicView.freeUpsellBody, '升級可再解鎖另外 4 個話題');
  });
}
