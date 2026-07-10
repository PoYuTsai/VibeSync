import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_temperature_style.dart';

void main() {
  group('practiceTemperatureBandForScore（鏡像 server temperatureBandFor）', () {
    // server 真相源：supabase/functions/practice-chat/temperature.ts
    // <=20 frozen / <=40 cold / <=60 neutral / <=80 warm / else hot
    test('邊界值與 server 5 檔完全一致', () {
      expect(practiceTemperatureBandForScore(0), 'frozen');
      expect(practiceTemperatureBandForScore(20), 'frozen');
      expect(practiceTemperatureBandForScore(21), 'cold');
      expect(practiceTemperatureBandForScore(40), 'cold');
      expect(practiceTemperatureBandForScore(41), 'neutral');
      expect(practiceTemperatureBandForScore(60), 'neutral');
      expect(practiceTemperatureBandForScore(61), 'warm');
      expect(practiceTemperatureBandForScore(80), 'warm');
      expect(practiceTemperatureBandForScore(81), 'hot');
      expect(practiceTemperatureBandForScore(100), 'hot');
    });

    test('超界分數 clamp 到 0-100 再分檔（鏡像 server clampTemperature）', () {
      expect(practiceTemperatureBandForScore(-5), 'frozen');
      expect(practiceTemperatureBandForScore(150), 'hot');
    });
  });

  group('practiceTemperatureColor', () {
    test('band 驅動 5 檔色票（frozen 無專屬色票與 cold 共色）', () {
      expect(
        practiceTemperatureColor(band: 'frozen', score: 10),
        AppColors.cold,
      );
      expect(
        practiceTemperatureColor(band: 'cold', score: 30),
        AppColors.cold,
      );
      expect(
        practiceTemperatureColor(band: 'neutral', score: 50),
        AppColors.warning,
      );
      expect(
        practiceTemperatureColor(band: 'warm', score: 70),
        AppColors.warm,
      );
      expect(
        practiceTemperatureColor(band: 'hot', score: 90),
        AppColors.hot,
      );
    });

    test('band 與 score 分歧時以 server band 為準', () {
      // server 是真相源：即使 score 落在別檔，band 有值就照 band。
      expect(
        practiceTemperatureColor(band: 'hot', score: 10),
        AppColors.hot,
      );
    });

    test('band 缺席（null）→ 用 score 鏡像 server 邊界推 band', () {
      expect(practiceTemperatureColor(band: null, score: 20), AppColors.cold);
      expect(practiceTemperatureColor(band: null, score: 40), AppColors.cold);
      expect(
        practiceTemperatureColor(band: null, score: 60),
        AppColors.warning,
      );
      expect(practiceTemperatureColor(band: null, score: 80), AppColors.warm);
      expect(practiceTemperatureColor(band: null, score: 81), AppColors.hot);
    });

    test('未知 band 字串（server 未來新檔）→ 退回 score 鏡像查表', () {
      expect(
        practiceTemperatureColor(band: 'scorching', score: 55),
        AppColors.warning,
      );
    });

    test('釘死舊 client 4 桶 bug 的三個分歧邊界（40/60/80）', () {
      // 舊 4 桶：>=40 warning / >=60 warm / >=80 hot（與 server 分歧）。
      // server：40=cold、60=neutral、80=warm。
      expect(practiceTemperatureColor(band: null, score: 40), AppColors.cold);
      expect(
        practiceTemperatureColor(band: null, score: 60),
        AppColors.warning,
      );
      expect(practiceTemperatureColor(band: null, score: 80), AppColors.warm);
    });
  });
}
