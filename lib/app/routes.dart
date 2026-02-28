// lib/app/routes.dart
import 'package:go_router/go_router.dart';
import '../core/services/supabase_service.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/subscription/presentation/screens/paywall_screen.dart';
import '../features/subscription/presentation/screens/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final isLoggedIn = SupabaseService.isAuthenticated;
    final isLoginRoute = state.matchedLocation == '/login';

    if (!isLoggedIn && !isLoginRoute) {
      return '/login';
    }
    if (isLoggedIn && isLoginRoute) {
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
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
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
  ],
);
