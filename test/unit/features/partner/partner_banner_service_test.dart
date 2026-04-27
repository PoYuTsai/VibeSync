import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/partner/data/services/partner_banner_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isDismissed returns false when key absent for uid', () async {
    expect(await PartnerBannerService.isDismissed('u1'), isFalse);
  });

  test('markDismissed then isDismissed returns true for same uid', () async {
    await PartnerBannerService.markDismissed('u1');
    expect(await PartnerBannerService.isDismissed('u1'), isTrue);
  });

  test('markDismissed for uid A does not affect uid B (per-account isolation)',
      () async {
    await PartnerBannerService.markDismissed('uA');
    expect(await PartnerBannerService.isDismissed('uA'), isTrue);
    expect(await PartnerBannerService.isDismissed('uB'), isFalse);
  });
}
