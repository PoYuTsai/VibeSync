// The test intentionally fills deprecated/experimental Sentry fields to prove
// the privacy scrubber removes them.
// ignore_for_file: deprecated_member_use, experimental_member_use

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:vibesync/core/observability/crash_reporting.dart';

void main() {
  group('CrashReporting privacy contract', () {
    test('boots normally when no compile-time DSN is configured', () async {
      var bootstrapCalls = 0;

      await CrashReporting.run(() {
        bootstrapCalls += 1;
      });

      expect(bootstrapCalls, 1);
    });

    test('disables content-rich and performance collection', () {
      final options = SentryFlutterOptions();

      CrashReporting.configureOptions(
        options,
        dsn: 'https://public@example.ingest.sentry.io/123',
        environment: 'Production',
      );

      expect(options.dsn, 'https://public@example.ingest.sentry.io/123');
      expect(options.environment, 'Production');
      expect(options.sendDefaultPii, isFalse);
      expect(options.reportPackages, isFalse);
      expect(options.reportViewHierarchyIdentifiers, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.attachThreads, isFalse);
      expect(options.captureFailedRequests, isFalse);
      expect(options.captureNativeFailedRequests, isFalse);
      expect(options.recordHttpBreadcrumbs, isFalse);
      expect(options.maxBreadcrumbs, 0);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.enableAutoNativeBreadcrumbs, isFalse);
      expect(options.enableAppLifecycleBreadcrumbs, isFalse);
      expect(options.enableWindowMetricBreadcrumbs, isFalse);
      expect(options.enableBrightnessChangeBreadcrumbs, isFalse);
      expect(options.enableTextScaleChangeBreadcrumbs, isFalse);
      expect(options.enableMemoryPressureBreadcrumbs, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.enableUserInteractionTracing, isFalse);
      expect(options.enableAutoPerformanceTracing, isFalse);
      expect(options.enableStandaloneAppStartTracing, isFalse);
      expect(options.enableTimeToFullDisplayTracing, isFalse);
      expect(options.anrEnabled, isFalse);
      expect(options.enableWatchdogTerminationTracking, isFalse);
      expect(options.enableAppHangTracking, isFalse);
      expect(options.enableFramesTracking, isFalse);
      expect(options.enableNativeTraceSync, isFalse);
      expect(options.enableScopeSync, isFalse);
      expect(options.enableNdkScopeSync, isFalse);
      expect(options.tracesSampleRate, 0);
      expect(options.profilesSampleRate, 0);
      expect(options.enableLogs, isFalse);
      expect(options.enableMetrics, isFalse);
      expect(options.sendClientReports, isFalse);
      expect(options.replay.sessionSampleRate, 0);
      expect(options.replay.onErrorSampleRate, 0);
      expect(options.replay.networkCaptureBodies, isFalse);
      expect(options.beforeSend, isNotNull);

      // Keep the two signals needed for crash-free health and native iOS
      // crashes. They do not include conversation or account content.
      expect(options.enableAutoSessionTracking, isTrue);
      expect(options.enableNativeCrashHandling, isTrue);
    });

    test('removes sensitive event content and attachment payloads', () {
      const sensitive = 'PRIVATE_CHAT_0912_alice@example.com';
      final hint = Hint.withAttachment(
        SentryAttachment.fromIntList(
          utf8.encode(sensitive),
          'private.txt',
        ),
      )
        ..screenshot = SentryAttachment.fromIntList(
          utf8.encode(sensitive),
          'screen.png',
        )
        ..viewHierarchy = SentryAttachment.fromIntList(
          utf8.encode(sensitive),
          'view.txt',
        )
        ..set('private', sensitive);

      final event = SentryEvent(
        platform: 'dart',
        release: 'com.vibesync@1.0.1+340',
        environment: 'Production',
        logger: sensitive,
        serverName: sensitive,
        message: SentryMessage(sensitive),
        transaction: sensitive,
        culprit: sensitive,
        user: SentryUser(id: sensitive, email: sensitive),
        request: SentryRequest(
          url: 'https://example.com/?chat=$sensitive',
          method: 'POST',
          data: sensitive,
          headers: const {'Authorization': sensitive},
        ),
        breadcrumbs: [
          Breadcrumb(message: sensitive, data: const {'chat': sensitive}),
        ],
        tags: const {'private': sensitive},
        extra: const {'chat': sensitive},
        exceptions: [
          SentryException(
            type: 'StateError',
            value: sensitive,
            throwable: StateError(sensitive),
            mechanism: Mechanism(
              type: 'FlutterError',
              description: sensitive,
              data: const {'private': sensitive},
            ),
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: 'C:/Users/$sensitive/project/lib/main.dart',
                  fileName: 'C:/Users/$sensitive/project/lib/main.dart',
                  function: 'CrashReporting.run',
                  lineNo: 42,
                  contextLine: sensitive,
                  preContext: const [sensitive],
                  postContext: const [sensitive],
                  vars: const {'chat': sensitive},
                ),
              ],
              registers: const {'secret': sensitive},
            ),
          ),
        ],
      );

      final safe = CrashReporting.sanitizeEvent(event, hint);
      final serialized = jsonEncode(safe.toJson());

      expect(serialized, isNot(contains(sensitive)));
      expect(safe.message, isNull);
      expect(safe.user, isNull);
      expect(safe.request, isNull);
      expect(safe.breadcrumbs, isNull);
      expect(safe.extra, isNull);
      expect(safe.tags, isNull);
      expect(safe.transaction, isNull);
      expect(safe.exceptions!.single.value, 'StateError');
      expect(safe.exceptions!.single.throwable, isNull);
      expect(safe.exceptions!.single.stackTrace!.frames.single.fileName,
          'lib_main.dart');
      expect(
        safe.exceptions!.single.stackTrace!.frames.single.absPath,
        isNull,
      );
      expect(hint.attachments, isEmpty);
      expect(hint.screenshot, isNull);
      expect(hint.viewHierarchy, isNull);
      expect(hint.get('private'), isNull);
    });
  });
}
