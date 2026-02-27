// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/conversation/presentation/screens/home_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('新增對話')),
      ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('對話 ${state.pathParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
