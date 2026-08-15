// 對象頁「問教練」CTA spec（2026-08-15 拍板：三入口共用獨立聊天視窗）。
//
// 內嵌 CoachSurface 時代退場：三情境 chip、知識庫入口與 lifecyclePhase
// 種入的行為規格搬到 global_coach_screen_test（視窗鎖定模式）。本檔只驗
// CTA 卡：渲染、導航、零 AI 副作用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart';

const _partnerId = 'p1';

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: CoachFollowUpSection(partnerId: _partnerId),
          ),
        ),
        GoRoute(
          path: '/coach',
          builder: (_, state) => Scaffold(
            body: Text(
              'coach-window-${state.uri.queryParameters['partnerId']}',
            ),
          ),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('渲染 CTA：標題「問教練 Sydney」＋額度 caption', (tester) async {
    await _pump(tester);

    expect(find.text('問教練 Sydney'), findsOneWidget);
    expect(find.text('釐清免費，正式建議才扣 1 則'), findsOneWidget);
  });

  testWidgets('點 CTA → /coach?partnerId= 鎖定本對象的聊天視窗', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('coach_follow_up_cta')));
    await tester.pumpAndSettle();

    expect(find.text('coach-window-$_partnerId'), findsOneWidget);
  });
}
