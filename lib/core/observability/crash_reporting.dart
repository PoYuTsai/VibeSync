// Sentry marks some privacy/performance switches experimental even though
// explicitly disabling them is part of this module's fail-closed contract.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/environment.dart';

typedef AppBootstrap = FutureOr<void> Function();

/// Privacy-first crash reporting for production builds.
///
/// The SDK is a complete no-op when `SENTRY_DSN` is absent. When enabled, it
/// keeps crash grouping metadata and stack locations while removing content
/// that could contain conversations, names, account data, or request payloads.
abstract final class CrashReporting {
  static const _dsn = String.fromEnvironment('SENTRY_DSN');

  static Future<void> run(AppBootstrap appBootstrap) async {
    final dsn = _dsn.trim();
    if (dsn.isEmpty) {
      await appBootstrap();
      return;
    }

    var appStarted = false;
    Future<void> guardedBootstrap() async {
      appStarted = true;
      await appBootstrap();
    }

    try {
      await SentryFlutter.init(
        (options) => configureOptions(
          options,
          dsn: dsn,
          environment: AppConfig.environmentName,
        ),
        appRunner: guardedBootstrap,
      );
    } catch (_) {
      // Monitoring must never become a new startup outage. Only fall back when
      // Sentry failed before the application bootstrap was entered; bootstrap
      // failures themselves remain real application failures.
      if (appStarted) rethrow;
      debugPrint('Crash reporting unavailable; starting without telemetry.');
      await appBootstrap();
    }
  }

  @visibleForTesting
  static void configureOptions(
    SentryFlutterOptions options, {
    required String dsn,
    required String environment,
  }) {
    options
      ..dsn = dsn
      ..environment = environment
      ..sendDefaultPii = false
      ..reportPackages = false
      ..reportViewHierarchyIdentifiers = false
      ..attachScreenshot = false
      ..attachViewHierarchy = false
      ..attachThreads = false
      ..captureFailedRequests = false
      ..captureNativeFailedRequests = false
      ..recordHttpBreadcrumbs = false
      ..maxBreadcrumbs = 0
      ..enablePrintBreadcrumbs = false
      ..enableAutoNativeBreadcrumbs = false
      ..enableAppLifecycleBreadcrumbs = false
      ..enableWindowMetricBreadcrumbs = false
      ..enableBrightnessChangeBreadcrumbs = false
      ..enableTextScaleChangeBreadcrumbs = false
      ..enableMemoryPressureBreadcrumbs = false
      ..enableUserInteractionBreadcrumbs = false
      ..enableUserInteractionTracing = false
      ..enableAutoPerformanceTracing = false
      ..enableStandaloneAppStartTracing = false
      ..enableTimeToFullDisplayTracing = false
      ..anrEnabled = false
      ..enableWatchdogTerminationTracking = false
      ..enableAppHangTracking = false
      ..enableFramesTracking = false
      ..enableNativeTraceSync = false
      ..enableScopeSync = false
      ..enableNdkScopeSync = false
      ..tracesSampleRate = 0
      ..profilesSampleRate = 0
      ..enableLogs = false
      ..enableMetrics = false
      ..sendClientReports = false
      ..beforeSend = sanitizeEvent;

    options.replay
      ..sessionSampleRate = 0
      ..onErrorSampleRate = 0
      ..networkCaptureBodies = false;
  }

  @visibleForTesting
  static SentryEvent sanitizeEvent(SentryEvent event, Hint hint) {
    hint
      ..attachments.clear()
      ..screenshot = null
      ..viewHierarchy = null
      ..clear();

    final safeExceptions =
        event.exceptions?.map(_sanitizeException).toList(growable: false);

    return SentryEvent(
      eventId: event.eventId,
      timestamp: event.timestamp,
      platform: event.platform,
      release: event.release,
      dist: event.dist,
      environment: event.environment,
      level: event.level,
      exceptions: safeExceptions,
      sdk: event.sdk,
      debugMeta: event.debugMeta,
      type: event.type,
    );
  }

  static SentryException _sanitizeException(SentryException exception) {
    final type = _safeIdentifier(exception.type, fallback: 'UnhandledError');
    return SentryException(
      type: type,
      value: type,
      stackTrace: _sanitizeStackTrace(exception.stackTrace),
      mechanism: _sanitizeMechanism(exception.mechanism),
      threadId: exception.threadId,
    );
  }

  static SentryStackTrace? _sanitizeStackTrace(SentryStackTrace? stackTrace) {
    if (stackTrace == null) return null;

    return SentryStackTrace(
      frames: stackTrace.frames.map(_sanitizeFrame).toList(growable: false),
      lang: _safeIdentifier(stackTrace.lang),
      snapshot: stackTrace.snapshot,
    );
  }

  static SentryStackFrame _sanitizeFrame(SentryStackFrame frame) {
    return SentryStackFrame(
      fileName: _safeFileName(frame.fileName),
      function: _safeSymbol(frame.function),
      module: _safeFileName(frame.module),
      lineNo: frame.lineNo,
      colNo: frame.colNo,
      inApp: frame.inApp,
      package: _safeFileName(frame.package),
      native: frame.native,
      platform: _safeIdentifier(frame.platform),
      imageAddr: _safeAddress(frame.imageAddr),
      symbolAddr: _safeAddress(frame.symbolAddr),
      instructionAddr: _safeAddress(frame.instructionAddr),
      rawFunction: _safeSymbol(frame.rawFunction),
      stackStart: frame.stackStart,
      symbol: _safeSymbol(frame.symbol),
    );
  }

  static Mechanism? _sanitizeMechanism(Mechanism? mechanism) {
    if (mechanism == null) return null;
    return Mechanism(
      type: _safeIdentifier(mechanism.type, fallback: 'generic')!,
      handled: mechanism.handled,
      synthetic: mechanism.synthetic,
      isExceptionGroup: mechanism.isExceptionGroup,
      exceptionId: mechanism.exceptionId,
      parentId: mechanism.parentId,
    );
  }

  static String? _safeIdentifier(String? value, {String? fallback}) {
    if (value == null || value.trim().isEmpty) return fallback;
    final sanitized =
        value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.$<>:+-]'), '_');
    if (sanitized.isEmpty) return fallback;
    return sanitized.length <= 120 ? sanitized : sanitized.substring(0, 120);
  }

  static String? _safeSymbol(String? value) => _safeIdentifier(value);

  static String? _safeAddress(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return RegExp(r'^(0x)?[0-9a-fA-F]+$').hasMatch(trimmed) ? trimmed : null;
  }

  static String? _safeFileName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().replaceAll('\\', '/').split('?').first;
    final libIndex = normalized.lastIndexOf('/lib/');
    final candidate = libIndex >= 0
        ? normalized.substring(libIndex + 1)
        : normalized.split('/').last;
    return _safeIdentifier(candidate);
  }
}
