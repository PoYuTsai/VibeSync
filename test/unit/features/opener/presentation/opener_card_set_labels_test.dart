import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  test('卡片標籤依 server 給的卡片組：五風格維持舊標籤，一句推薦＋四句備選用新標籤', () {
    expect(OpeningRescueScreen.openerTypeLabel('tease'), '調情');
    expect(OpeningRescueScreen.openerTypeLabel('tease', cardSet: 2), '換個方向');
    expect(OpeningRescueScreen.openerTypeLabel('coldRead', cardSet: 2), '帶到自己');
    expect(
      OpeningRescueScreen.openerCardSet2Labels.keys.toSet(),
      OpeningRescueScreen.openerTypeLabels.keys.toSet(),
      reason: '兩組標籤涵蓋同一組五個 key（server OPENER_TYPES）',
    );
    expect(OpeningRescueScreen.openerTypeLabel('unknown', cardSet: 2), 'unknown');
  });

  test('標題：五風格寫「種風格」，一句推薦＋四句備選不是風格', () {
    expect(OpeningRescueScreen.openerStylesHeaderSuffix(cardCount: 5),
        ' ・5 種風格');
    expect(
        OpeningRescueScreen.openerStylesHeaderSuffix(cardCount: 5, cardSet: 2),
        ' ・5 則');
  });
}
