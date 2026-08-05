// 鏡像 server supabase/functions/practice-chat/acquaintance_origin.ts 的
// buildAcquaintanceOrigin。錨點值是直接跑 server 端 buildAcquaintanceOrigin
// 印出來的真實結果（見 PR 說明），不是 Dart 內部自洽的循環驗證。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_acquaintance_origin.dart';

void main() {
  group('practiceAcquaintanceOriginFor — 錨點：與 server buildAcquaintanceOrigin 逐字一致', () {
    final anchors = <(String profileId, String professionId, String threadId, String expectedId)>[
      ('practice_girl_001', 'flight_attendant', 'thread-a', 'friend_intro'),
      ('practice_girl_001', 'flight_attendant', 'thread-c', 'work_encounter'),
      ('practice_girl_004', 'barista', 'session-xyz', 'social_gathering'),
      ('practice_girl_010', 'nurse_clinic', 'session-xyz', 'street_approach'),
      ('practice_girl_025', 'nurse_clinic', 't-001', 'hobby_class'),
      ('practice_girl_050', 'marketing_planner', 't-002', 'work_encounter'),
      (
        'practice_girl_073',
        'pastry_chef',
        'long-thread-id-123456',
        'work_encounter',
      ),
      ('practice_girl_099', 'architect', 'same-thread-id', 'dating_app'),
      ('practice_girl_002', 'college_student', 'student-thread-1', 'nightclub'),
      (
        'practice_girl_002',
        'college_student',
        'student-thread-2',
        'social_gathering',
      ),
      (
        'practice_girl_002',
        'college_student',
        'student-thread-3',
        'work_encounter',
      ),
      ('practice_girl_001', 'flight_attendant', 'campus-check', 'work_encounter'),
    ];

    for (final (profileId, professionId, threadId, expectedId) in anchors) {
      test('$profileId|$threadId -> $expectedId', () {
        final origin = practiceAcquaintanceOriginFor(
          profileId: profileId,
          professionId: professionId,
          threadId: threadId,
        );
        expect(origin.id, expectedId);
        expect(origin.label, isNotEmpty);
        expect(origin.sharedFact, isNotEmpty);
      });
    }
  });

  test('同一個 profileId+threadId 永遠算出同一個管道（跨呼叫穩定）', () {
    final first = practiceAcquaintanceOriginFor(
      profileId: 'practice_girl_030',
      professionId: 'barista',
      threadId: 'thread-x',
    );
    final second = practiceAcquaintanceOriginFor(
      profileId: 'practice_girl_030',
      professionId: 'barista',
      threadId: 'thread-x',
    );
    expect(first.id, second.id);
  });

  test('非在校身分的職業，抽再多次也不會抽到校園認識', () {
    for (var i = 0; i < 60; i++) {
      final origin = practiceAcquaintanceOriginFor(
        profileId: 'practice_girl_060',
        professionId: 'barista',
        threadId: 'thread-$i',
      );
      expect(origin.id, isNot('campus'));
    }
  });

  group('practiceThreadIdFor — 鏡像 server threadIdForPracticeRequest', () {
    test('有值且非空白 → 用 visiblePracticeThreadId', () {
      expect(
        practiceThreadIdFor(
          sessionId: 'session-1',
          visiblePracticeThreadId: 'thread-9',
        ),
        'thread-9',
      );
    });

    test('缺席 → fallback sessionId', () {
      expect(
        practiceThreadIdFor(sessionId: 'session-1'),
        'session-1',
      );
    });

    test('空字串或純空白 → fallback sessionId', () {
      expect(
        practiceThreadIdFor(sessionId: 'session-1', visiblePracticeThreadId: ''),
        'session-1',
      );
      expect(
        practiceThreadIdFor(
          sessionId: 'session-1',
          visiblePracticeThreadId: '   ',
        ),
        'session-1',
      );
    });
  });
}
