// test/unit/config/environment_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/config/environment.dart';

void main() {
  group('AppConfig', () {
    test('defaults to dev environment when ENV not defined', () {
      // Without ENV defined, should default to dev
      expect(AppConfig.isDevelopment, isTrue);
      expect(AppConfig.isProduction, isFalse);
      expect(AppConfig.isStaging, isFalse);
    });

    test('environment returns Environment enum', () {
      expect(AppConfig.environment, isA<Environment>());
    });

    test('supabaseUrl returns non-empty string', () {
      expect(AppConfig.supabaseUrl, isNotEmpty);
    });

    test('supabaseAnonKey returns non-empty string', () {
      expect(AppConfig.supabaseAnonKey, isNotEmpty);
    });

    test('environmentName returns human-readable name', () {
      expect(AppConfig.environmentName, equals('Development'));
    });

    test('debugEnabled is true in dev environment', () {
      expect(AppConfig.debugEnabled, isTrue);
    });

    test('showEnvironmentBadge is true in non-prod', () {
      expect(AppConfig.showEnvironmentBadge, isTrue);
    });

    test('isProduction returns correct value for dev', () {
      // In test environment, we're running in dev mode
      expect(AppConfig.isProduction, isFalse);
    });

    test('dev supabaseUrl points to localhost', () {
      // In dev mode, should point to localhost
      if (AppConfig.isDevelopment) {
        expect(AppConfig.supabaseUrl, contains('localhost'));
      }
    });
  });

  group('Environment enum', () {
    test('has three values', () {
      expect(Environment.values.length, equals(3));
    });

    test('contains dev, staging, prod', () {
      expect(Environment.values, contains(Environment.dev));
      expect(Environment.values, contains(Environment.staging));
      expect(Environment.values, contains(Environment.prod));
    });
  });
}
