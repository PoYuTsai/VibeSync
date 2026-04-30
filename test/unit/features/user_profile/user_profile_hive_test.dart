import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Directory tmp;
  late Box<UserProfile> box;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('user_profile_hive_test');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
      Hive.registerAdapter(UserProfileAdapter());
      Hive.registerAdapter(InteractionStyleAdapter());
      Hive.registerAdapter(PracticeGoalAdapter());
      Hive.registerAdapter(TopicSeedAdapter());
    }
    box = await Hive.openBox<UserProfile>(
        'test_user_profile_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  test('UserProfile survives Hive round-trip', () async {
    final original = UserProfile.create(
      interactionStyle: InteractionStyle.gentle,
      practiceGoals: const [
        PracticeGoal.softInvite,
        PracticeGoal.reduceAnxiety,
      ],
      topicSeeds: const [
        TopicSeed.coffee,
        TopicSeed.travel,
        TopicSeed.movies,
      ],
      customTopics: '日劇、週末探店',
      notes: '我慢熟，希望不要太快邀約',
      updatedAt: DateTime.utc(2026, 4, 30, 12, 0),
    );

    await box.put('me', original);
    final restored = box.get('me')!;

    expect(restored.interactionStyle, InteractionStyle.gentle);
    expect(restored.practiceGoals, original.practiceGoals);
    expect(restored.topicSeeds, original.topicSeeds);
    expect(restored.customTopics, '日劇、週末探店');
    expect(restored.notes, '我慢熟，希望不要太快邀約');
    expect(restored.updatedAt, original.updatedAt);
  });

  test('UserProfile with all-null optional fields round-trips', () async {
    final original = UserProfile.create(
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await box.put('me', original);
    final restored = box.get('me')!;

    expect(restored.interactionStyle, isNull);
    expect(restored.practiceGoals, isEmpty);
    expect(restored.topicSeeds, isEmpty);
    expect(restored.customTopics, isNull);
    expect(restored.notes, isNull);
    expect(restored.updatedAt, original.updatedAt);
  });
}
