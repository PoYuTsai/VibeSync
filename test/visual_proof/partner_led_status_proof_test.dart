// 首頁對象卡第二行燈號標籤的改前／改後對照（Bruce 2026-10-21 燈號標籤規格）。
//
// 本機工具：設了 LED_PROOF_OUT 才跑，CI 跳過。同一份檔先在改版前的元件上跑
// （LED_PROOF_PHASE=before），改完再跑一次（LED_PROOF_PHASE=after）；兩邊都在時，
// 最後一個測試把同名 PNG 拼成左右對照圖放到 compare/。只用 PartnerListCard 的公開介面，
// 兩個版本都能編譯。每張卡另外記下幾何數字（geometry.json），用來比對標籤以外有沒有移動。
//
//   LED_PROOF_OUT=<資料夾> LED_PROOF_PHASE=before \
//     flutter test --concurrency=2 test/visual_proof/partner_led_status_proof_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/app/main_shell.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_list_card.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

final String? _outRoot = Platform.environment['LED_PROOF_OUT'];
final String _phase = Platform.environment['LED_PROOF_PHASE'] ?? 'current';
const _statusKey = ValueKey('partner-card-v3-status');

String _phasePath(String name) => '$_outRoot/$_phase/$name';

/// 跟 partner_home_capture_test 一樣：先載微軟正黑當 AppTC，再走 loadProofFonts。
Future<void> _loadFonts() async {
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

class _FakeOptInStore extends FollowUpOptInStore {
  @override
  FollowUpOptIn read() => FollowUpOptIn.unknown;

  @override
  Future<void> write(FollowUpOptIn value) async {}
}

List<Override> _homeOverrides() => [
      subscriptionProvider.overrideWith(
        (_) => _SeededSubscriptionNotifier(
          const SubscriptionState(
            tier: SubscriptionTierHelper.free,
            monthlyMessagesUsed: 7,
            monthlyLimit: 30,
          ),
        ),
      ),
      subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      userProfileControllerProvider
          .overrideWith(_NullUserProfileController.new),
      analysisHistoryEventsProvider
          .overrideWithValue(const <AnalysisHistoryEvent>[]),
      followUpOptInStoreProvider.overrideWithValue(_FakeOptInStore()),
      authConversationScopeProvider.overrideWith(
        (_) => Stream.value('u-proof'),
      ),
    ];

/// 一張卡的假資料：燈號與決定分開給（燈色和要不要回是兩套資料）。
class _Seed {
  const _Seed(
    this.id,
    this.name, {
    this.light,
    this.decision,
    this.heat,
    this.v3 = true,
    this.interests = const [],
    this.traits = const [],
  });

  final String id;
  final String name;
  final GuideV3Light? light;
  final GuideV3Decision? decision;
  final int? heat;
  final bool v3;
  final List<String> interests;
  final List<String> traits;

  Partner get partner => Partner(
        id: id,
        name: name,
        createdAt: DateTime(2026, 4, 20),
        updatedAt: DateTime(2026, 4, 20),
        ownerUserId: 'u-proof',
      );

  PartnerAggregateView aggregate() => PartnerAggregateView(
        unionInterests: interests,
        unionTraits: traits,
        unionNotes: null,
        latestHeat: heat,
        totalRounds: 3,
        totalMessages: 0,
        lastInteraction: DateTime.now().subtract(const Duration(days: 2)),
        latestIsGuideV3: v3,
        latestGuideV3Signals: decision == null
            ? null
            : PartnerGuideV3Signals(decision: decision!, light: light),
      );
}

/// 規格的三種標準案例：黃燈 輪到你回、綠燈 輪到你回、紅燈 先等她。
const _standard = [
  _Seed(
    'yuki',
    '小雪',
    light: GuideV3Light.yellow,
    decision: GuideV3Decision.send,
    interests: ['咖啡'],
    traits: ['慢熱'],
  ),
  _Seed(
    'mina',
    'Mina',
    light: GuideV3Light.green,
    decision: GuideV3Decision.send,
    interests: ['爬山'],
    traits: ['愛分享'],
  ),
  _Seed(
    'rei',
    '阿蕾',
    light: GuideV3Light.red,
    decision: GuideV3Decision.hold,
    interests: ['貓'],
    traits: ['回得慢'],
  ),
];

/// 邊界：資料允許的其他組合、讀不懂的燈號、關心、舊版熱度與待分析。
/// 姓名直接寫案例，方便看圖；不能跟任何狀態字相同，否則找字會撞到。
const _edgeCases = [
  _Seed(
    'e1',
    '組合：黃＋等她',
    light: GuideV3Light.yellow,
    decision: GuideV3Decision.hold,
  ),
  _Seed(
    'e2',
    '組合：綠＋先停',
    light: GuideV3Light.green,
    decision: GuideV3Decision.stop,
  ),
  _Seed(
    'e3',
    '組合：紅＋收尾',
    light: GuideV3Light.red,
    decision: GuideV3Decision.close,
  ),
  _Seed('e4', '燈號讀不懂', decision: GuideV3Decision.send),
  _Seed('e5', '關心（不顯示）', decision: GuideV3Decision.care),
  _Seed('e6', '舊版熱度', v3: false, heat: 68, interests: ['美食']),
  _Seed('e7', '舊版未分析', v3: false),
];

double _r(double v) => (v * 100).roundToDouble() / 100;

Map<String, double> _rect(Rect r, Offset origin) => {
      'x': _r(r.left - origin.dx),
      'y': _r(r.top - origin.dy),
      'w': _r(r.width),
      'h': _r(r.height),
    };

/// 一張卡的幾何：卡片、頭像、姓名、標籤列、興趣列、日期、刪除鈕（相對卡片左上角），
/// 加上標籤需要的寬度與文字區可用寬度。
Map<String, Object?> _cardGeometry(WidgetTester tester, _Seed s) {
  // 用頭像的 key 找卡，不靠清單順序。
  final card = find.ancestor(
    of: find.byKey(ValueKey('partner-avatar-liquid-${s.id}')),
    matching: find.byType(PartnerListCard),
  );
  if (card.evaluate().isEmpty) return {'id': s.id, 'built': false};
  final cardRect = tester.getRect(card);
  final origin = cardRect.topLeft;
  Finder inCard(Finder matching) =>
      find.descendant(of: card, matching: matching);

  // 頭像也會寫姓名前兩個字（兩個字的名字會撞到），姓名那行是限一行的 Text。
  final name = inCard(
    find.byWidgetPredicate(
      (w) => w is Text && w.data == s.name && w.maxLines == 1,
    ),
  );
  final column = find.ancestor(of: name, matching: find.byType(Column)).first;
  final available = tester.getSize(column).width;
  final tags = [...s.interests, ...s.traits].take(3).join(' · ');
  final out = <String, Object?>{
    'id': s.id,
    'card': _rect(cardRect, Offset(cardRect.left, cardRect.top)),
    // 截圖裡的絕對位置：對照圖用它框出唯一允許改動的那一列。
    'cardAbs': _rect(cardRect, Offset.zero),
    'avatar': _rect(
      tester.getRect(
        inCard(find.byKey(ValueKey('partner-avatar-liquid-${s.id}'))),
      ),
      origin,
    ),
    'name': _rect(tester.getRect(name), origin),
    'textColumnWidth': _r(available),
  };
  if (tags.isNotEmpty) {
    out['tags'] = _rect(tester.getRect(inCard(find.text(tags))), origin);
  }
  final date = inCard(find.text('2天前'));
  if (date.evaluate().isNotEmpty) {
    out['date'] = _rect(tester.getRect(date), origin);
  }
  final delete = inCard(find.byIcon(Icons.delete_outline));
  if (delete.evaluate().isNotEmpty) {
    out['delete'] = _rect(tester.getRect(delete), origin);
  }
  final slot = inCard(find.byKey(_statusKey));
  if (slot.evaluate().isEmpty) {
    out['status'] = null;
    return out;
  }
  final slotBox = tester.renderObject<RenderBox>(slot);
  final needed = slotBox.getMaxIntrinsicWidth(double.infinity);
  final texts = <String>[];
  var truncated = false;
  for (final element in find
      .descendant(of: slot, matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    texts.add(paragraph.text.toPlainText());
    truncated = truncated || paragraph.didExceedMaxLines;
  }
  out['status'] = {
    ..._rect(tester.getRect(slot), origin),
    'texts': texts,
    'neededWidth': _r(needed),
    'fits': needed <= available + 0.01 && !truncated,
    'truncated': truncated,
    // 用型別名字找，改版前沒有這個元件也能編譯。
    'signal': find
        .descendant(
          of: slot,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'JapaneseLedSignal',
          ),
        )
        .evaluate()
        .isNotEmpty,
  };
  return out;
}

/// 卡片清單（跟首頁一樣左右各 16 邊距、卡片間上下 4），可指定畫面寬與文字縮放。
Widget _cardList(
  List<_Seed> seeds, {
  required double screenWidth,
  double textScale = 1.0,
}) {
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: screenWidth,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.backgroundGradientStart,
                AppColors.backgroundGradientMid,
                AppColors.backgroundGradientEnd,
              ],
              stops: [0, .58, 1],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in seeds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: PartnerListCard(
                    partner: s.partner,
                    aggregate: s.aggregate(),
                    onTap: () {},
                    onDelete: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 改版前的膠囊在窄寬或大字會溢出（Row 裡的字沒有 Flexible）；改前那一輪要拍得到
/// 原樣，所以溢出只記下來，不讓測試失敗。其他錯誤照常丟出。
Future<T> _tolerateOverflow<T>(
  List<String> overflows,
  Future<T> Function() body,
) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) {
      overflows.add(message.split('\n').first);
      return;
    }
    previous?.call(details);
  };
  try {
    return await body();
  } finally {
    FlutterError.onError = previous;
  }
}

final Map<String, Object?> _geometry = {};

/// 每拍完一組就寫一次：最後一個測試（拼對照圖）要讀這一輪的幾何來畫框。
void _flushGeometry() {
  File(_phasePath('geometry.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_geometry));
}

Future<void> _captureCardList(
  WidgetTester tester, {
  required String name,
  required List<_Seed> seeds,
  required double screenWidth,
  double textScale = 1.0,
}) async {
  final overflows = <String>[];
  final cards = <Map<String, Object?>>[];
  await _tolerateOverflow(overflows, () async {
    await pumpAndCapture(
      tester,
      size: Size(screenWidth, 24 + seeds.length * (8 + 112 * textScale)),
      child: Align(
        alignment: Alignment.topLeft,
        child: _cardList(
          seeds,
          screenWidth: screenWidth,
          textScale: textScale,
        ),
      ),
      beforeCapture: (tester) async {
        for (final s in seeds) {
          cards.add(_cardGeometry(tester, s));
        }
      },
      outPath: _phasePath('$name.png'),
    );
  });
  _geometry[name] = {
    'screenWidth': screenWidth,
    'textScale': textScale,
    'overflowErrors': overflows,
    'cards': cards,
  };
  _flushGeometry();
}

/// 只放大一張卡的標籤附近：用 Transform 放大後裁切，字與信號機用向量重畫，不是放大點陣圖。
class _ZoomRegion extends StatelessWidget {
  const _ZoomRegion({
    required this.child,
    required this.childSize,
    required this.region,
    required this.zoom,
  });

  final Widget child;
  final Size childSize;
  final Rect region;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: region.width * zoom,
        height: region.height * zoom,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.translate(
            offset: Offset(-region.left * zoom, -region.top * zoom),
            child: Transform.scale(
              scale: zoom,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(size: childSize, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProofBottomNav extends StatelessWidget {
  const _ProofBottomNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (icon, label, selected) in const [
              (Icons.home, '首頁', true),
              (Icons.bar_chart_outlined, '分析', false),
              (Icons.menu_book_outlined, '學習', false),
            ])
              Container(
                constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? 20 : 14,
                  vertical: 11,
                ),
                decoration: selected
                    ? BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.ctaStart, AppColors.ctaEnd],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      )
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.66),
                      size: 22,
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// PNG 檔頭的寬高（IHDR）。
Size _pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}

void main() {
  if (_outRoot == null) {
    test('首頁對象卡燈號標籤對照（設 LED_PROOF_OUT 才跑）', () {
      markTestSkipped('本機對照工具：沒有設 LED_PROOF_OUT');
    });
    return;
  }

  setUpAll(_loadFonts);

  testWidgets('首頁整頁：三種標準案例＋一張舊版熱度卡（390 寬、字 1.0）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      const legacy = _Seed(
        'joyce',
        'Joyce',
        v3: false,
        heat: 68,
        interests: ['茄汁牛肉飯'],
        traits: ['喜歡碎碎念'],
      );
      final seeds = [..._standard, legacy];
      final cards = <Map<String, Object?>>[];
      await pumpAndCapture(
        tester,
        child: ProviderScope(
          overrides: [
            ..._homeOverrides(),
            partnerListProvider
                .overrideWith((_) => [for (final s in seeds) s.partner]),
            for (final s in seeds) ...[
              partnerAggregateProvider(s.id).overrideWith((_) => s.aggregate()),
              conversationsByPartnerProvider(s.id)
                  .overrideWith((_) => const <Conversation>[]),
            ],
          ],
          child: GradientBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                centerTitle: true,
                elevation: 0,
                title: Text('VibeSync', style: AppTypography.headlineMedium),
              ),
              body: const PartnerListScreen(
                bottomPadding: 32.0 + homeFabReservedHeight,
              ),
              floatingActionButton: const HomeFab(),
              bottomNavigationBar: const _ProofBottomNav(),
            ),
          ),
        ),
        beforeCapture: (tester) async {
          for (final s in seeds) {
            cards.add(_cardGeometry(tester, s));
          }
        },
        outPath: _phasePath('home_390_scale1.0.png'),
      );
      _geometry['home_390_scale1.0'] = {
        'screenWidth': 390,
        'textScale': 1.0,
        'cards': cards,
      };
      _flushGeometry();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('三種燈號各一張卡（390 寬、字 1.0）', (tester) async {
    for (final s in _standard) {
      await _captureCardList(
        tester,
        name: 'card_${s.light!.wire}_390_scale1.0',
        seeds: [s],
        screenWidth: 390,
      );
    }
  });

  testWidgets('不同寬度與文字縮放', (tester) async {
    for (final (width, scale) in const [
      (375.0, 1.0),
      (430.0, 1.0),
      (320.0, 1.0),
      (390.0, 1.3),
      (390.0, 2.0),
      (320.0, 1.3),
      (320.0, 2.0),
    ]) {
      await _captureCardList(
        tester,
        name: 'cards_${width.toInt()}_scale$scale',
        seeds: _standard,
        screenWidth: width,
        textScale: scale,
      );
    }
  });

  testWidgets('邊界組合（390 寬、字 1.0）', (tester) async {
    await _captureCardList(
      tester,
      name: 'edge_cases_390_scale1.0',
      seeds: _edgeCases,
      screenWidth: 390,
    );
  });

  testWidgets('三色標籤放大 4 倍', (tester) async {
    const zoom = 4.0;
    const screenWidth = 390.0;
    const cardWidth = screenWidth - 32;
    final rows = <Widget>[];
    for (final s in _standard) {
      // 先量這張卡的大小與標籤列位置，再用同一張卡做放大裁切。
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cardWidth,
                child: PartnerListCard(
                  partner: s.partner,
                  aggregate: s.aggregate(),
                  onTap: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final cardRect = tester.getRect(find.byType(PartnerListCard));
      final slotRect =
          tester.getRect(find.byKey(_statusKey)).shift(-cardRect.topLeft);
      // 從頭像右緣到尾欄前，上下各多留 6。
      final region = Rect.fromLTRB(
        60,
        slotRect.top - 6,
        cardWidth - 12 - 64 - 8,
        slotRect.bottom + 6,
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ZoomRegion(
            zoom: zoom,
            childSize: cardRect.size,
            region: region,
            child: PartnerListCard(
              partner: s.partner,
              aggregate: s.aggregate(),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
    }
    await pumpAndCapture(
      tester,
      size: const Size((cardWidth - 84 - 60) * zoom + 32, 640),
      child: Material(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
      outPath: _phasePath('zoom_labels_x4.png'),
    );
  });

  testWidgets('改前改後拼成左右對照（兩邊都拍過才拼）', (tester) async {
    final before = Directory('$_outRoot/before');
    final after = Directory('$_outRoot/after');
    if (!before.existsSync() || !after.existsSync()) {
      markTestSkipped('還沒有 before 與 after 兩組圖');
      return;
    }
    final names = before
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.png'))
        .where((n) => File('${after.path}/$n').existsSync())
        .toList()
      ..sort();
    // 框線位置取改後那輪的幾何：標籤列以外的位置兩輪逐點相同（geometry.json 已比對），
    // 所以同一組框可以套在兩張圖上。
    final geometryFile = File('${after.path}/geometry.json');
    final geometry = geometryFile.existsSync()
        ? jsonDecode(geometryFile.readAsStringSync()) as Map<String, dynamic>
        : const <String, dynamic>{};
    List<Rect> markers(String name) {
      final entry = geometry[name.replaceAll('.png', '')];
      if (entry is! Map<String, dynamic>) return const [];
      final out = <Rect>[];
      for (final card
          in (entry['cards'] as List).cast<Map<String, dynamic>>()) {
        final status = card['status'];
        final abs = card['cardAbs'];
        final nameRect = card['name'];
        if (status is! Map<String, dynamic> ||
            abs is! Map<String, dynamic> ||
            nameRect is! Map<String, dynamic>) {
          continue;
        }
        double n(Object? v) => (v! as num).toDouble();
        out.add(
          Rect.fromLTWH(
            n(abs['x']) + n(nameRect['x']) - 3,
            n(abs['y']) + n(status['y']) - 3,
            n(card['textColumnWidth']) + 6,
            n(status['h']) + 6,
          ),
        );
      }
      return out;
    }

    for (final name in names) {
      final beforeBytes = File('${before.path}/$name').readAsBytesSync();
      final afterBytes = File('${after.path}/$name').readAsBytesSync();
      // 原圖是 3 倍像素：除以 3 回到 logical 尺寸，合成時再用 3 倍輸出，約一比一。
      final beforeSize = _pngSize(beforeBytes) / 3;
      final afterSize = _pngSize(afterBytes) / 3;
      final height = beforeSize.height > afterSize.height
          ? beforeSize.height
          : afterSize.height;
      final boxes = markers(name);
      Widget column(String label, Uint8List bytes, Size size) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    Image.memory(
                      bytes,
                      width: size.width,
                      height: size.height,
                      filterQuality: FilterQuality.medium,
                    ),
                    for (final box in boxes)
                      Positioned.fromRect(
                        rect: box,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
      await pumpAndCapture(
        tester,
        size: Size(
          beforeSize.width + afterSize.width + 48,
          height + (boxes.isEmpty ? 64 : 96),
        ),
        rasterDecodeWait: const Duration(milliseconds: 800),
        child: Material(
          color: const Color(0xFF0B0712),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    column('改前（ed94a198）', beforeBytes, beforeSize),
                    const SizedBox(width: 16),
                    column('改後', afterBytes, afterSize),
                  ],
                ),
                if (boxes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '白框＝唯一允許改動的燈號標籤列；框外位置與改前逐點量測相同',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        outPath: '$_outRoot/compare/$name',
      );
    }
  });
}
