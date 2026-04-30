import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';

class _FakeRepo implements UserProfileRepository {
  final Map<String, UserProfile> _byOwner = {};
  @override
  Future<UserProfile?> load(String uid) async => _byOwner[uid];
  @override
  Future<void> save(UserProfile p, String uid) async => _byOwner[uid] = p;
  @override
  Future<void> clear(String uid) async => _byOwner.remove(uid);
}

void main() {
  testWidgets('/profile/about-me resolves to AboutMeScreen', (tester) async {
    final router = GoRouter(
      initialLocation: '/profile/about-me',
      routes: [
        GoRoute(
          path: '/profile/about-me',
          builder: (_, __) => const AboutMeScreen(),
        ),
        // The parametric sibling route is included to ensure literal-first
        // ordering: navigating to '/profile/about-me' must NOT fall into
        // '/profile/:id' (which would render ProfileCardScreen).
        GoRoute(
          path: '/profile/:id',
          builder: (_, __) =>
              const Scaffold(body: Text('profile-card-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(_FakeRepo()),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value('test-user')),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // AppBar title 「關於我」 confirms AboutMeScreen rendered (not ProfileCardScreen).
    expect(find.widgetWithText(AppBar, '關於我'), findsOneWidget);
    expect(find.text('profile-card-stub'), findsNothing);
  });
}
