// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
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
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('升級方案')),
      ),
    ),
  ],
);
