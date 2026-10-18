import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  // Bruce 2026-10-18（#97）：三個功能留空格一律用「＿＿」；開場救星「帶到自己」的範例
  // 改留空格給他填，填好才能複製。
  group('openerCardCopyMode', () {
    test('一般卡直接複製', () {
      expect(
        OpeningRescueScreen.openerCardCopyMode(
          content: '半馬賽前最怕哪一段？',
          direction: null,
        ),
        OpenerCardCopyMode.copy,
      );
    });

    test('方向＋範例卡留了＿＿：先填好再複製', () {
      expect(
        OpeningRescueScreen.openerCardCopyMode(
          content: '我最近都在＿＿夜跑，妳都跑哪？',
          direction: '可以先分享自己夜跑的經驗',
        ),
        OpenerCardCopyMode.fillThenCopy,
      );
    });

    test('舊快照的範例沒留空格（細節是編的）：照舊只給方向、不給複製', () {
      expect(
        OpeningRescueScreen.openerCardCopyMode(
          content: '我最近都跑環河公園那，妳都跑哪？',
          direction: '可以先分享自己夜跑的經驗',
        ),
        OpenerCardCopyMode.directionOnly,
      );
    });

    test('一般卡萬一留了＿＿：也先填好，不把空格傳出去', () {
      expect(
        OpeningRescueScreen.openerCardCopyMode(
          content: '我住＿＿附近，妳呢',
          direction: null,
        ),
        OpenerCardCopyMode.fillThenCopy,
      );
    });
  });

  test('範例上方的說明：有空格叫他換成自己的，舊範例照舊', () {
    expect(
      OpeningRescueScreen.openerExampleCaption('我最近都在＿＿夜跑，妳都跑哪？'),
      '把＿＿換成你的再傳：',
    );
    expect(
      OpeningRescueScreen.openerExampleCaption('我最近都跑河濱，妳都跑哪？'),
      '範例，換成你自己的經驗再傳：',
    );
  });
}
