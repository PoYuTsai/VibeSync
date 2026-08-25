// D3：**只有 debug build 吃得到**的動態 feed 假資料與情境切換列。
//
// ## 為什麼需要它
// 分支版 App 連的是正式後端，而規則禁止從非 `main` 分支部署 Edge——所以 backend
// 還沒上線前，這個畫面在 Eric 手機上會是空白的，他自己訂的「兩個人在 branch 真機
// 跑完」合併條件就無法成立。這是驗收工具，不是產品功能。
//
// ## release build 為什麼編譯不進去
// 本檔在 `lib/` 內的**唯一**引用點是 `practice_moments_screen.dart`，而且每一處都
// 包在 `if (kDebugMode) { ... }` 裡。`kDebugMode` 是 `const bool`，release AOT 會把
// 整段條件連同它引用到的所有東西一起 tree-shake 掉——**這是編譯期消除，不是 runtime
// 判斷**。機械證明在 `test/lint/moments_debug_fixture_guard_test.dart`。
//
// ## 與 no-canned 鐵則的界線
// no-canned 管的是 **Edge server 端**「生成失敗不准把假成功寫進 DB／回給使用者」。
// 本檔是 **client 端**開發機上的畫面素材，而且 feed 是唯讀的：`practice_moments`
// mode 不接受 client 送內容，client 端**沒有任何寫入 API**。所以這些假資料
// **永遠不可能**進到 `practice_moment_posts`。兩者互不重疊。
//
// ## 假資料的密度刻意貼近上線後的樣子
// 20 則裡只有 3 則有圖（15%，對齊 `IMAGE_PROBABILITY = 0.15`）。假資料若每則都有圖，
// Eric 在手機上看到的密度感就不是上線後的樣子，會誤導版面判斷。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_moment_image.dart';
import '../../domain/entities/practice_moment_post.dart';

/// 情境索引。用 `int` 而不是 enum：畫面端的欄位型別因此完全不指向本檔，
/// release 端連型別參照都不留。
const int kMomentsDebugOff = 0;
const int kMomentsDebugMixedFeed = 1;
const int kMomentsDebugTextOnly = 2;
const int kMomentsDebugLoading = 3;
const int kMomentsDebugEmpty = 4;
const int kMomentsDebugError = 5;

const List<String> _scenarioLabels = <String>[
  '真實',
  '圖文',
  '純文字',
  '載入中',
  '空',
  '錯誤',
];

/// 情境 → 要餵給畫面的 AsyncValue。`null`＝不覆寫，走真正的 provider。
///
/// 只在 `if (kDebugMode)` 內被呼叫。
AsyncValue<List<PracticeMomentPost>>? practiceMomentsDebugFeed(
  int scenario,
  DateTime now,
) {
  switch (scenario) {
    case kMomentsDebugMixedFeed:
      return AsyncData<List<PracticeMomentPost>>(_mixedFeed(now));
    case kMomentsDebugTextOnly:
      return AsyncData<List<PracticeMomentPost>>(
        _mixedFeed(now).where((p) => p.imageId == null).toList(),
      );
    case kMomentsDebugLoading:
      return const AsyncLoading<List<PracticeMomentPost>>();
    case kMomentsDebugEmpty:
      return const AsyncData<List<PracticeMomentPost>>(<PracticeMomentPost>[]);
    case kMomentsDebugError:
      return AsyncError<List<PracticeMomentPost>>(
        Exception('practice_moments_failed'),
        StackTrace.empty,
      );
    default:
      return null;
  }
}

/// 一則假貼文。[minutesAgo] 讓四種相對時間分支（剛剛／N 分鐘前／N 小時前／
/// 昨天 HH:mm／M月D日）都能在同一屏被看到。
PracticeMomentPost _post({
  required String profileId,
  required int minutesAgo,
  required String body,
  required DateTime now,
  String? imageId,
}) {
  final postedAt = now.subtract(Duration(minutes: minutesAgo));
  return PracticeMomentPost(
    profileId: profileId,
    postDate: postedAt.toLocal().toIso8601String().substring(0, 10),
    slot: minutesAgo.isEven ? 0 : 1,
    dayPart: 'afternoon',
    postedAt: postedAt.toUtc(),
    body: body,
    imageId: imageId,
  );
}

/// 20 則、多角色、時間跨到前天；其中 3 則有圖（15%），一則剛好卡在
/// server 端 66 字的長度上界。
List<PracticeMomentPost> _mixedFeed(DateTime now) {
  return <PracticeMomentPost>[
    _post(
      profileId: 'practice_girl_001',
      minutesAgo: 0,
      body: '今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著。',
      now: now,
      imageId: 'moment_coffee_cup',
    ),
    _post(
      profileId: 'practice_girl_007',
      minutesAgo: 12,
      body: '早上出門忘了帶傘，結果整條路上只有我一個人在跑。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_003',
      minutesAgo: 41,
      body: '剪了瀏海，還在適應鏡子裡的自己，同事說看起來年輕三歲。',
      now: now,
      imageId: kMomentSelfPortraitImageId,
    ),
    _post(
      profileId: 'practice_girl_005',
      minutesAgo: 96,
      body: '週末把陽台整理了一遍，多出一個可以發呆的角落。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_002',
      minutesAgo: 155,
      body: '剛剛在捷運上看完一整本書，下車的時候有點捨不得。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_009',
      minutesAgo: 210,
      body: '練完瑜伽整個人鬆掉，站在鏡子前面愣了三秒才想起要換衣服。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_004',
      minutesAgo: 265,
      body: '家裡的貓今天特別黏人，鍵盤上多了很多不明字元。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_006',
      minutesAgo: 320,
      body: '最近開始學做菜，今天的番茄炒蛋總算沒有變成番茄湯。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_008',
      minutesAgo: 388,
      body: '今天妝感難得滿意，決定在下班前先偷偷留一張紀念。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_010',
      minutesAgo: 455,
      body: '下班經過河堤，風有點涼，走著走著就多繞了兩公里。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_001',
      minutesAgo: 610,
      body: '剛剛把去年的照片翻出來，發現自己那時候瀏海真的很短。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_011',
      minutesAgo: 900,
      body: '今天客戶臨時改需求，改到第四版的時候我開始佩服自己。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_012',
      minutesAgo: 1180,
      body: '睡前泡了一壺花茶，整個房間都是那個味道，很安心。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_013',
      minutesAgo: 1450,
      // server 端 66 字的長度上界：版面要撐得住最長的一則。
      body: '把冬天的衣服全部收進箱子，衣櫃空出一整排，看著就覺得整個人都輕了一點，'
          '好像連日子也跟著鬆開了一些，於是順手連書桌也一起擦了一遍才甘心',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_014',
      minutesAgo: 1720,
      body: '展覽最後一間展間只有我一個人，站著看了很久才走。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_015',
      minutesAgo: 2100,
      body: '新外套第一天上身，被風吹得有點狼狽但還是拍了一張。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_016',
      minutesAgo: 2540,
      body: '剛剛下了一場很大的雨，窗戶上的水痕比我畫的還好看。',
      now: now,
      imageId: 'moment_rainy_window',
    ),
    _post(
      profileId: 'practice_girl_017',
      minutesAgo: 3010,
      body: '搬完家第一天，坐在地板上吃泡麵，覺得這樣也不錯。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_018',
      minutesAgo: 3600,
      body: '週末去了海邊，回來鞋子裡都是沙，但是完全不後悔。',
      now: now,
    ),
    _post(
      profileId: 'practice_girl_019',
      minutesAgo: 4300,
      body: '今天終於把拖了兩個月的健檢做完，護理師說我血壓偏低。',
      now: now,
    ),
  ];
}

/// 情境切換列。只在 `if (kDebugMode)` 內被建構，release 端不存在。
class PracticeMomentsDebugBar extends StatelessWidget {
  const PracticeMomentsDebugBar({
    super.key,
    required this.scenario,
    required this.onChanged,
  });

  static const barKey = ValueKey('moments-debug-bar');

  final int scenario;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // 雙保險：即使有人在 release 端硬把它放進 widget tree 也畫不出東西。
    if (!kDebugMode) return const SizedBox.shrink();
    return Padding(
      key: barKey,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Text(
            'DEBUG',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _scenarioLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _DebugChip(
                        label: _scenarioLabels[i],
                        selected: scenario == i,
                        onTap: () => onChanged(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugChip extends StatelessWidget {
  const _DebugChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ctaStart.withValues(alpha: 0.22)
              : AppColors.brandSurface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.ctaStart.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected
                ? AppColors.onBackgroundPrimary
                : AppColors.onBackgroundSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
