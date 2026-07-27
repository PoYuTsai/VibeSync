import 'keyboard_context_bridge.dart';

enum KeyboardPhotoAuthorizationStatus {
  authorized,
  limited,
  denied,
  restricted,
  notDetermined,
}

abstract class KeyboardPhotoAuthorizationRequesting {
  Future<KeyboardPhotoAuthorizationStatus> requestReadWriteAuthorization();

  Future<KeyboardPhotoAuthorizationStatus> currentReadWriteAuthorization();
}

class KeyboardScreenshotConsentReceipt {
  const KeyboardScreenshotConsentReceipt({
    required this.ownerUserId,
    required this.version,
    required this.acceptedAt,
    required this.updatedAt,
  });

  final String ownerUserId;
  final String version;
  final DateTime acceptedAt;
  final DateTime updatedAt;

  Map<String, Object> toJson() {
    return {
      'ownerUserId': ownerUserId,
      'version': version,
      'enabled': true,
      'acceptedAt': acceptedAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

abstract class KeyboardScreenshotConsentReceiptPublishing {
  Future<int> beginScreenshotConsentSetup();

  Future<void> publishScreenshotConsentReceipt(
    KeyboardScreenshotConsentReceipt receipt, {
    required int expectedEpoch,
  });

  Future<void> clearScreenshotConsentReceipt();

  Future<bool> hasUsableScreenshotConsentReceipt({
    required String ownerUserId,
    required String version,
    required DateTime acceptedAt,
  });
}

class MethodChannelKeyboardPhotoAuthorizationBridge
    implements
        KeyboardPhotoAuthorizationRequesting,
        KeyboardScreenshotConsentReceiptPublishing {
  MethodChannelKeyboardPhotoAuthorizationBridge({
    KeyboardContextChannel channel = const FlutterKeyboardContextChannel(),
  }) : _channel = channel;

  final KeyboardContextChannel _channel;

  @override
  Future<KeyboardPhotoAuthorizationStatus>
      requestReadWriteAuthorization() async {
    final value = await _channel.invoke('requestPhotoAuthorization');
    return _decodeAuthorization(value);
  }

  @override
  Future<KeyboardPhotoAuthorizationStatus>
      currentReadWriteAuthorization() async {
    final value = await _channel.invoke('currentPhotoAuthorization');
    return _decodeAuthorization(value);
  }

  KeyboardPhotoAuthorizationStatus _decodeAuthorization(Object? value) {
    return switch (value) {
      'authorized' => KeyboardPhotoAuthorizationStatus.authorized,
      'limited' => KeyboardPhotoAuthorizationStatus.limited,
      'denied' => KeyboardPhotoAuthorizationStatus.denied,
      'restricted' => KeyboardPhotoAuthorizationStatus.restricted,
      'not_determined' => KeyboardPhotoAuthorizationStatus.notDetermined,
      _ => throw StateError(
          'keyboard photo authorization returned an invalid status',
        ),
    };
  }

  @override
  Future<int> beginScreenshotConsentSetup() async {
    final response = await _channel.invoke('beginScreenshotConsentSetup');
    if (response is! Map ||
        response['epoch'] is! int ||
        (response['epoch'] as int) < 0) {
      throw StateError(
        'keyboard screenshot consent epoch returned an invalid value',
      );
    }
    return response['epoch'] as int;
  }

  @override
  Future<void> publishScreenshotConsentReceipt(
    KeyboardScreenshotConsentReceipt receipt, {
    required int expectedEpoch,
  }) async {
    if (expectedEpoch < 0) {
      throw ArgumentError.value(expectedEpoch, 'expectedEpoch');
    }
    final response = await _channel.invoke(
      'writeScreenshotConsentReceipt',
      {
        ...receipt.toJson(),
        'expectedEpoch': expectedEpoch,
      },
    );
    if (response is! Map ||
        response['storedOwnerUserId'] != receipt.ownerUserId ||
        response['storedVersion'] != receipt.version) {
      throw StateError(
        'keyboard screenshot consent bridge returned an invalid response',
      );
    }
  }

  @override
  Future<void> clearScreenshotConsentReceipt() {
    return _channel.invoke('clearScreenshotConsentReceipt').then<void>((_) {});
  }

  @override
  Future<bool> hasUsableScreenshotConsentReceipt({
    required String ownerUserId,
    required String version,
    required DateTime acceptedAt,
  }) async {
    final response = await _channel.invoke(
      'verifyScreenshotConsentReceipt',
      {
        'ownerUserId': ownerUserId,
        'version': version,
        'acceptedAt': acceptedAt.toUtc().toIso8601String(),
      },
    );
    if (response is! bool) {
      throw StateError(
        'keyboard screenshot consent verification returned an invalid value',
      );
    }
    return response;
  }
}
