import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_mind_map_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';

import '../widget/features/user_profile/_harness.dart';
import 'proof_support.dart';

Partner _partner() => Partner(
      id: 'nani',
      name: 'Nani',
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      ownerUserId: 'u-proof',
    );

String _snapshot() => jsonEncode({
      'gameStage': {
        'current': 'opening',
        'status': 'normal',
        'nextStep': '她前面丟了嫉妒玩笑球，這看一遍未接視訊。先接住她的測試，再用輕鬆推拉接往前兩顆球。',
      },
      'topicDepth': {'current': 'event', 'suggestion': ''},
      'strategy': '主動製造互動',
      'targetProfile': {
        'interests': <String>[],
        'traits': ['會用玩笑測試對方反應', '有點小撒嬌風格'],
        'notes': <String>[],
      },
    });

Conversation _conversation() => Conversation(
      id: 'c-proof',
      name: '最近一次分析',
      messages: const [],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      partnerId: 'nani',
      lastAnalysisSnapshotJson: _snapshot(),
    );

void main() {
  setUpAll(loadProofFonts);

  testWidgets('about me capture', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(
            FakeUserProfileRepo(
              initial: UserProfile.create(
                interactionStyle: InteractionStyle.gentle,
                secondaryStyle: InteractionStyle.humorous,
                practiceGoals: const [
                  PracticeGoal.softInvite,
                  PracticeGoal.reduceAnxiety,
                ],
                topicSeeds: const [
                  TopicSeed.coffee,
                  TopicSeed.travel,
                  TopicSeed.food,
                ],
                customTopics: '日劇、週末探店',
                notes: '我慢熟，希望不要太快邀約',
                updatedAt: DateTime.utc(2026, 6, 1),
              ),
            ),
          ),
          authUserProfileScopeProvider.overrideWith(
            (_) => Stream.value(FakeUserProfileRepo.testUid),
          ),
        ],
        child: const AboutMeScreen(),
      ),
      outPath: outPath('about_me_profile.png'),
    );
  });

  testWidgets('partner mind map capture', (tester) async {
    final partner = _partner();
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          partnerByIdProvider(partner.id).overrideWith((_) => partner),
          partnerAggregateProvider(partner.id)
              .overrideWith((_) => PartnerAggregateView.empty()),
          conversationsByPartnerProvider(partner.id)
              .overrideWith((_) => [_conversation()]),
        ],
        child: PartnerMindMapScreen(partnerId: partner.id),
      ),
      outPath: outPath('partner_mindmap.png'),
    );
  });
}
