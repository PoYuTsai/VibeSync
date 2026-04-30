import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';

class FakeUserProfileRepo implements UserProfileRepository {
  FakeUserProfileRepo({UserProfile? initial}) {
    if (initial != null) byOwner[testUid] = initial;
  }

  static const testUid = 'test-user';
  final Map<String, UserProfile> byOwner = {};
  bool throwOnSave = false;

  @override
  Future<UserProfile?> load(String uid) async => byOwner[uid];

  @override
  Future<void> save(UserProfile profile, String uid) async {
    if (throwOnSave) throw Exception('save boom');
    byOwner[uid] = profile;
  }

  @override
  Future<void> clear(String uid) async => byOwner.remove(uid);
}

Widget aboutMeHarness({
  required FakeUserProfileRepo repo,
  String? uid = FakeUserProfileRepo.testUid,
}) {
  final router = GoRouter(
    initialLocation: '/profile/about-me',
    routes: [
      GoRoute(
        path: '/profile/about-me',
        builder: (_, __) => const AboutMeScreen(),
      ),
      GoRoute(
        path: '/back',
        builder: (_, __) => const Scaffold(body: Text('back-stub')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      userProfileRepositoryProvider.overrideWithValue(repo),
      authUserProfileScopeProvider.overrideWith((ref) => Stream.value(uid)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
