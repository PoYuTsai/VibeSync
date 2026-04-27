// lib/app/routes.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../core/services/supabase_service.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';
import 'main_shell.dart';
import '../features/learning/presentation/screens/article_detail_screen.dart';
import '../features/opener/presentation/screens/opening_rescue_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/subscription/presentation/screens/paywall_screen.dart';
import '../features/conversation/presentation/screens/profile_card_screen.dart';
import '../features/partner/presentation/screens/add_partner_screen.dart';
import '../features/partner/presentation/screens/partner_detail_screen.dart';
import '../features/partner/presentation/screens/partner_merge_picker_screen.dart';
import '../features/subscription/presentation/screens/settings_screen.dart';

final _routerRefreshListenable =
    _GoRouterRefreshStream(SupabaseService.authStateChanges);

final router = GoRouter(
  initialLocation: '/login',
  refreshListenable: _routerRefreshListenable,
  redirect: (context, state) {
    final isLoggedIn = SupabaseService.isAuthenticated;
    final isLoginRoute = state.matchedLocation == '/login';
    final isPasswordRecoveryRoute =
        isLoginRoute && SupabaseService.isPasswordRecoveryInProgress;

    if (!isLoggedIn && !isLoginRoute) {
      return '/login';
    }
    if (isLoggedIn && isLoginRoute && !isPasswordRecoveryRoute) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const MainShell(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => NewConversationScreen(
        partnerId: state.uri.queryParameters['partnerId'],
      ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    // literal '/partner/new' MUST come before '/partner/:partnerId' so
    // 'new' isn't matched as a partnerId by the parametric route.
    GoRoute(
      path: '/partner/new',
      builder: (context, state) => const AddPartnerScreen(),
    ),
    GoRoute(
      path: '/partner/:partnerId',
      builder: (context, state) => PartnerDetailScreen(
        partnerId: state.pathParameters['partnerId']!,
      ),
    ),
    GoRoute(
      path: '/partner/:partnerId/merge',
      builder: (context, state) => PartnerMergePickerScreen(
        fromPartnerId: state.pathParameters['partnerId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) => const PaywallScreen(),
    ),
    GoRoute(
      path: '/opener',
      builder: (context, state) => const OpeningRescueScreen(),
    ),
    GoRoute(
      path: '/profile/:id',
      builder: (context, state) => ProfileCardScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/article/:id',
      builder: (context, state) => ArticleDetailScreen(
        articleId: state.pathParameters['id']!,
      ),
    ),
  ],
);

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
