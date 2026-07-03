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
import '../features/practice_chat/presentation/screens/practice_chat_screen.dart';
import '../features/practice_chat/presentation/screens/practice_collection_screen.dart';
import '../features/onboarding/data/onboarding_service.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/subscription/presentation/screens/ai_privacy_screen.dart';
import '../features/subscription/presentation/screens/paywall_screen.dart';
import '../features/conversation/presentation/screens/profile_card_screen.dart';
import '../features/partner/presentation/screens/add_partner_screen.dart';
import '../features/partner/presentation/screens/partner_detail_screen.dart';
import '../features/partner/presentation/screens/partner_merge_picker_screen.dart';
import '../features/partner/presentation/screens/partner_mind_map_screen.dart';
import '../features/subscription/presentation/screens/settings_screen.dart';
import '../features/user_profile/presentation/screens/about_me_screen.dart';
import '../features/user_profile/presentation/screens/partner_style_edit_screen.dart';

final _routerRefreshListenable =
    _GoRouterRefreshStream(SupabaseService.authStateChanges);

/// Pure auth + onboarding gate decision used by the live router redirect.
///
/// Kept side-effect free and synchronous so the full redirect matrix is unit
/// testable without Supabase or SharedPreferences, and so the unauthenticated
/// auth gate stays synchronous (unchanged) rather than awaiting storage on
/// every navigation. The live redirect feeds [isOnboardingCompleted] from the
/// in-memory [OnboardingService.isCompletedSync] cache primed at startup.
String? resolveAppRedirect({
  required bool isLoggedIn,
  required bool isOnboardingCompleted,
  required bool isPasswordRecovery,
  required String matchedLocation,
}) {
  final isLoginRoute = matchedLocation == '/login';
  final isOnboardingRoute = matchedLocation == '/onboarding';

  // Unauthenticated: only /login is reachable. (Auth gate — unchanged.)
  if (!isLoggedIn) {
    return isLoginRoute ? null : '/login';
  }

  // Authenticated below.

  // Password recovery keeps the user on /login to set a new password.
  if (isLoginRoute && isPasswordRecovery) {
    return null;
  }

  // Onboarding not finished -> force first-run onboarding (except when on it).
  if (!isOnboardingCompleted) {
    return isOnboardingRoute ? null : '/onboarding';
  }

  // Onboarding finished -> never show /login or /onboarding again.
  if (isLoginRoute || isOnboardingRoute) {
    return '/';
  }

  return null;
}

final router = GoRouter(
  initialLocation: '/login',
  refreshListenable: _routerRefreshListenable,
  redirect: (context, state) => resolveAppRedirect(
    isLoggedIn: SupabaseService.isAuthenticated,
    isOnboardingCompleted: OnboardingService.isCompletedSync,
    isPasswordRecovery: SupabaseService.isPasswordRecoveryInProgress,
    matchedLocation: state.matchedLocation,
  ),
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
      builder: (context, state) => MainShell(
        initialTabIndex:
            MainShell.tabIndexFromRoute(state.uri.queryParameters['tab']),
        routeTab: state.uri.queryParameters['tab'],
      ),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => NewConversationScreen(
        partnerId: state.uri.queryParameters['partnerId'],
        seedFromLatestOpener: state.uri.queryParameters['source'] == 'opener',
      ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
        // 作戰板 nextStep 節點入口：捲到 Coach 1:1 並預填（絕不 auto-send）。
        coachPrefillQuestion:
            state.uri.queryParameters[AnalysisScreen.coachPrefillQueryParam],
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
        focusCoachFollowUp:
            state.uri.queryParameters[PartnerDetailScreen.focusQueryParam] ==
                PartnerDetailScreen.coachFollowUpFocusValue,
        openCoachInputOnFocus: state.uri
                .queryParameters[PartnerDetailScreen.focusActionQueryParam] ==
            PartnerDetailScreen.openCoachInputFocusActionValue,
      ),
    ),
    GoRoute(
      path: '/partner/:partnerId/merge',
      builder: (context, state) => PartnerMergePickerScreen(
        fromPartnerId: state.pathParameters['partnerId']!,
        // Optional ?target= for the same-name dedupe banner CTA preselect.
        // Validated owner-scoped against partnerListProvider candidates inside
        // the screen — unknown / self / out-of-scope ids fall back to PR-B
        // row-tap flow (Codex spec patch §6 / §7.5).
        initialTargetId: state.uri.queryParameters['target'],
      ),
    ),
    GoRoute(
      path: '/partner/:partnerId/mindmap',
      builder: (context, state) => PartnerMindMapScreen(
        partnerId: state.pathParameters['partnerId']!,
      ),
    ),
    GoRoute(
      path: '/partner/:partnerId/my-style',
      builder: (context, state) => PartnerStyleEditScreen(
        partnerId: state.pathParameters['partnerId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    // F5-A7：設定頁常駐「AI 與你的隱私」靜態揭露（onboarding 第 4 頁可略過的補位）。
    GoRoute(
      path: '/settings/ai-privacy',
      builder: (context, state) => const AiPrivacyScreen(),
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) => const PaywallScreen(),
    ),
    GoRoute(
      path: '/opener',
      builder: (context, state) => OpeningRescueScreen(
        partnerId: state.uri.queryParameters['partnerId'],
      ),
    ),
    GoRoute(
      path: '/practice-chat',
      builder: (context, state) => PracticeChatScreen(
        startProfileId: state.uri.queryParameters['profileId'],
      ),
    ),
    GoRoute(
      path: '/practice-collection',
      builder: (context, state) => const PracticeCollectionScreen(),
    ),
    // literal '/profile/about-me' MUST come before '/profile/:id' so
    // 'about-me' isn't matched as a conversationId by the parametric route.
    GoRoute(
      path: '/profile/about-me',
      builder: (context, state) => const AboutMeScreen(),
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
