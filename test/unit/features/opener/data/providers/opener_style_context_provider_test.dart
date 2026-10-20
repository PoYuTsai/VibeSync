import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/data/providers/opener_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';

// 「關於我」只給 Coach 1:1（2026-08-04）：openerStyleContextProvider 固定回 null，
// 也不讀任何關於我或對象風格設定（2026-10-20 拆掉空管線）。關於我的資料來源
// 換成一碰就丟錯的版本，再確認它們連建立都沒有。
void main() {
  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        userProfileRepositoryProvider
            .overrideWith((ref) => throw StateError('開場救星不得讀關於我')),
        partnerStyleRepositoryProvider
            .overrideWith((ref) => throw StateError('開場救星不得讀對象風格設定')),
      ]);

  for (final partnerId in <String?>[null, '', 'p1']) {
    test('returns null without reading About Me sources (partnerId=$partnerId)',
        () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      expect(
        await c.read(openerStyleContextProvider(partnerId).future),
        isNull,
      );
      expect(c.exists(userProfileControllerProvider), isFalse);
      expect(c.exists(userProfileRepositoryProvider), isFalse);
      expect(c.exists(partnerStyleRepositoryProvider), isFalse);
      expect(c.exists(partnerStyleOverrideProvider('p1')), isFalse);
    });
  }
}
