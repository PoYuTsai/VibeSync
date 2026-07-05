import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';

void main() {
  final personaIds = practicePersonas.map((p) => p.id).toSet();

  test('陪練女孩 catalog 共 100 位（與 server GIRL_PROFILES 對齊）', () {
    expect(practiceGirlProfiles.length, 100);
  });

  test('profileId / photoId = practice_girl_NNN（1-based、3 位）且唯一', () {
    for (var i = 0; i < practiceGirlProfiles.length; i++) {
      final expected = 'practice_girl_${(i + 1).toString().padLeft(3, '0')}';
      expect(practiceGirlProfiles[i].profileId, expected);
      expect(practiceGirlProfiles[i].photoId, expected);
    }
    final ids = practiceGirlProfiles.map((g) => g.profileId).toSet();
    expect(ids.length, practiceGirlProfiles.length); // 無重複
  });

  test('每位 personaId 都在 client persona allowlist 內', () {
    for (final g in practiceGirlProfiles) {
      expect(personaIds.contains(g.personaId), true,
          reason: '${g.profileId} 的 personaId ${g.personaId} 不在 allowlist');
    }
  });

  test('每位都是成年（age >= 22）、有顯示名與職業', () {
    for (final g in practiceGirlProfiles) {
      expect(g.age >= 22, true, reason: '${g.profileId} age=${g.age}');
      expect(g.displayName.trim().isNotEmpty, true);
      expect(g.professionId.trim().isNotEmpty, true);
      expect(g.professionLabel.trim().isNotEmpty, true);
      expect(g.nameId.trim().isNotEmpty, true);
    }
  });

  test('前 20 位 nameId 不重複（spec 要求）', () {
    final first20 = practiceGirlProfiles.take(20).map((g) => g.nameId).toList();
    expect(first20.toSet().length, 20);
  });
}
