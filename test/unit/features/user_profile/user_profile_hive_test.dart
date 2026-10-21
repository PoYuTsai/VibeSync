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
      Hive.registerAdapter(StuckPointAdapter());
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
        PracticeGoal.comfortableChat,
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

  test('style pair (主+副) survives Hive round-trip', () async {
    final original = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      secondaryStyle: InteractionStyle.humorous,
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    await box.put('me', original);
    final restored = box.get('me')!;

    expect(restored.interactionStyle, InteractionStyle.steady);
    expect(restored.secondaryStyle, InteractionStyle.humorous);
  });

  test('stuckPoints survives Hive round-trip', () async {
    final original = UserProfile.create(
      stuckPoints: const [StuckPoint.leftOnRead],
      updatedAt: DateTime.utc(2026, 8, 4),
    );

    await box.put('me', original);
    final restored = box.get('me')!;

    expect(restored.stuckPoints, [StuckPoint.leftOnRead]);
  });

  test('legacy 6-field binary (pre style pair) reads secondaryStyle=null',
      () async {
    // Write with the pre-pair wire format (fields 0..5 only), then re-read
    // with the current generated adapter — proves zero-migration for every
    // existing user row.
    Hive.registerAdapter(_LegacyUserProfileAdapter(), override: true);
    final legacyBox = await Hive.openBox<UserProfile>(
        'test_user_profile_legacy_${DateTime.now().microsecondsSinceEpoch}');
    await legacyBox.put(
      'me',
      UserProfile(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
    );
    final boxName = legacyBox.name;
    await legacyBox.close();

    Hive.registerAdapter(UserProfileAdapter(), override: true);
    final reopened = await Hive.openBox<UserProfile>(boxName);
    final restored = reopened.get('me')!;

    expect(restored.interactionStyle, InteractionStyle.gentle);
    expect(restored.secondaryStyle, isNull);
    await reopened.close();
  });

  // 規格 PR-8：近況兩格（HiveField 8、9）。
  test('recent note survives Hive round-trip', () async {
    final original = UserProfile.create(
      notes: '不要太快邀約',
      recentNote: '這週在跟交友軟體認識的人聊，她回很慢',
      recentNoteUpdatedAt: DateTime.utc(2026, 10, 18, 9),
      updatedAt: DateTime.utc(2026, 10, 21),
    );
    await box.put('me', original);
    final restored = box.get('me')!;
    expect(restored.recentNote, '這週在跟交友軟體認識的人聊，她回很慢');
    expect(restored.recentNoteUpdatedAt, DateTime.utc(2026, 10, 18, 9));
    expect(restored.notes, '不要太快邀約');
  });

  test('PR-8 前後的 adapter 相容：舊資料讀回近況是 null；舊版讀新資料會略過這兩格',
      () async {
    final name = 'test_user_profile_pre_pr8_${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(
      () => Hive.registerAdapter(UserProfileAdapter(), override: true),
    );

    // PR-8 之前的 App 寫的資料（只有第 0–7 格），新版讀回來。
    Hive.registerAdapter(_PrePr8UserProfileAdapter(), override: true);
    var oldBox = await Hive.openBox<UserProfile>(name);
    await oldBox.put(
      'me',
      UserProfile.create(notes: '慢熟', updatedAt: DateTime.utc(2026, 8, 1)),
    );
    await oldBox.close();

    Hive.registerAdapter(UserProfileAdapter(), override: true);
    final currentBox = await Hive.openBox<UserProfile>(name);
    final fromOld = currentBox.get('me')!;
    expect(fromOld.notes, '慢熟');
    expect(fromOld.recentNote, isNull);
    expect(fromOld.recentNoteUpdatedAt, isNull);

    // 新版寫的資料（多第 8、9 格），PR-8 之前的 App 讀回來不會出錯。
    await currentBox.put(
      'me',
      UserProfile.create(
        notes: '慢熟',
        recentNote: '這週很忙',
        recentNoteUpdatedAt: DateTime.utc(2026, 10, 20),
        updatedAt: DateTime.utc(2026, 10, 21),
      ),
    );
    await currentBox.close();

    Hive.registerAdapter(_PrePr8UserProfileAdapter(), override: true);
    oldBox = await Hive.openBox<UserProfile>(name);
    expect(oldBox.get('me')!.notes, '慢熟');
    await oldBox.deleteFromDisk();
  });
}

/// The exact `write` shape the generated adapter had before secondaryStyle
/// (@HiveField(6)) was added — used to fabricate authentic legacy rows.
class _LegacyUserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final typeId = 9;

  @override
  UserProfile read(BinaryReader reader) =>
      throw UnsupportedError('write-only legacy adapter');

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.interactionStyle)
      ..writeByte(1)
      ..write(obj.practiceGoals)
      ..writeByte(2)
      ..write(obj.topicSeeds)
      ..writeByte(3)
      ..write(obj.customTopics)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.updatedAt);
  }
}

/// PR-8 之前產生的 adapter：只寫、只讀第 0–7 格（照當時的 `user_profile.g.dart`）。
class _PrePr8UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final typeId = 9;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      interactionStyle: fields[0] as InteractionStyle?,
      secondaryStyle: fields[6] as InteractionStyle?,
      practiceGoals: fields[1] == null
          ? const []
          : (fields[1] as List).cast<PracticeGoal>(),
      topicSeeds:
          fields[2] == null ? const [] : (fields[2] as List).cast<TopicSeed>(),
      stuckPoints:
          fields[7] == null ? const [] : (fields[7] as List).cast<StuckPoint>(),
      customTopics: fields[3] as String?,
      notes: fields[4] as String?,
      updatedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.interactionStyle)
      ..writeByte(1)
      ..write(obj.practiceGoals)
      ..writeByte(2)
      ..write(obj.topicSeeds)
      ..writeByte(3)
      ..write(obj.customTopics)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.updatedAt)
      ..writeByte(6)
      ..write(obj.secondaryStyle)
      ..writeByte(7)
      ..write(obj.stuckPoints);
  }
}
