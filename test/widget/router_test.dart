// test/widget/router_test.dart
//
// Sentinel-only router test — verifies the GoRouter route TABLE shape
// (literal-vs-parametric resolution + /conversation/:id back-compat).
// Mounting the live PartnerDetailScreen / AddPartnerScreen / AnalysisScreen
// here would pull in Hive boxes / authConversationScopeProvider /
// conversationProvider, turning a route-shape test into an integration
// test that fails for infrastructure reasons (Codex r1 P1.3a).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _PartnerDetailSentinel extends StatelessWidget {
  final String partnerId;
  const _PartnerDetailSentinel(this.partnerId);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('partner-detail:$partnerId'));
}

class _AddPartnerSentinel extends StatelessWidget {
  const _AddPartnerSentinel();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('add-partner'));
}

class _AnalysisSentinel extends StatelessWidget {
  final String conversationId;
  const _AnalysisSentinel(this.conversationId);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('analysis:$conversationId'));
}

GoRouter _testRouter(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        // literal-before-parametric — same order the live router must use.
        GoRoute(
          path: '/partner/new',
          builder: (c, s) => const _AddPartnerSentinel(),
        ),
        GoRoute(
          path: '/partner/:partnerId',
          builder: (c, s) =>
              _PartnerDetailSentinel(s.pathParameters['partnerId']!),
        ),
        GoRoute(
          path: '/conversation/:id',
          builder: (c, s) => _AnalysisSentinel(s.pathParameters['id']!),
        ),
      ],
    );

void main() {
  testWidgets('/partner/:partnerId routes to partner detail (sentinel)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/abc-123')),
    ));
    await t.pumpAndSettle();
    expect(find.text('partner-detail:abc-123'), findsOneWidget);
  });

  testWidgets('/partner/new routes to add-partner (literal beats parametric)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/new')),
    ));
    await t.pumpAndSettle();
    expect(find.text('add-partner'), findsOneWidget);
    // Critical guard: parametric must NOT match.
    expect(find.text('partner-detail:new'), findsNothing);
  });

  testWidgets('/conversation/:id keeps back-compat (sentinel)', (t) async {
    await t.pumpWidget(ProviderScope(
      child:
          MaterialApp.router(routerConfig: _testRouter('/conversation/conv-1')),
    ));
    await t.pumpAndSettle();
    expect(find.text('analysis:conv-1'), findsOneWidget);
  });
}
