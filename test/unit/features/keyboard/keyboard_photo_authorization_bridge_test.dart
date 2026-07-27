import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_context_bridge.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_photo_authorization_bridge.dart';

void main() {
  test('requests read-write Photos access over the keyboard bridge', () async {
    final channel = _FakeChannel('limited');
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    expect(
      await bridge.requestReadWriteAuthorization(),
      KeyboardPhotoAuthorizationStatus.limited,
    );
    expect(channel.methods, ['requestPhotoAuthorization']);
    expect(channel.arguments, [isNull]);
  });

  test('unknown native authorization value fails closed', () async {
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: _FakeChannel('future_status'),
    );

    await expectLater(
      bridge.requestReadWriteAuthorization(),
      throwsStateError,
    );
  });

  test('reads current read-write Photos access without prompting', () async {
    final channel = _FakeChannel('authorized');
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    expect(
      await bridge.currentReadWriteAuthorization(),
      KeyboardPhotoAuthorizationStatus.authorized,
    );
    expect(channel.methods, ['currentPhotoAuthorization']);
    expect(channel.arguments, [isNull]);
  });

  test('begins consent setup with a native epoch', () async {
    final channel = _FakeChannel({'epoch': 7});
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    expect(await bridge.beginScreenshotConsentSetup(), 7);
    expect(channel.methods, ['beginScreenshotConsentSetup']);
    expect(channel.arguments, [isNull]);
  });

  test('publishes an exact owner-bound consent receipt', () async {
    final channel = _FakeChannel({
      'storedOwnerUserId': 'owner-1',
      'storedVersion': 'keyboard_screenshot_ai_202607_v1',
    });
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    await bridge.publishScreenshotConsentReceipt(
      KeyboardScreenshotConsentReceipt(
        ownerUserId: 'owner-1',
        version: 'keyboard_screenshot_ai_202607_v1',
        acceptedAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 27, 12),
      ),
      expectedEpoch: 7,
    );

    expect(channel.methods, ['writeScreenshotConsentReceipt']);
    expect(channel.arguments.single, {
      'ownerUserId': 'owner-1',
      'version': 'keyboard_screenshot_ai_202607_v1',
      'enabled': true,
      'acceptedAt': '2026-07-01T00:00:00.000Z',
      'updatedAt': '2026-07-27T12:00:00.000Z',
      'expectedEpoch': 7,
    });
  });

  test('native receipt acknowledgement mismatch fails closed', () async {
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: _FakeChannel({
        'storedOwnerUserId': 'other-owner',
        'storedVersion': 'keyboard_screenshot_ai_202607_v1',
      }),
    );

    await expectLater(
      bridge.publishScreenshotConsentReceipt(
        KeyboardScreenshotConsentReceipt(
          ownerUserId: 'owner-1',
          version: 'keyboard_screenshot_ai_202607_v1',
          acceptedAt: DateTime.utc(2026, 7, 1),
          updatedAt: DateTime.utc(2026, 7, 27),
        ),
        expectedEpoch: 0,
      ),
      throwsStateError,
    );
  });

  test('clears the native consent receipt without payload', () async {
    final channel = _FakeChannel(null);
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    await bridge.clearScreenshotConsentReceipt();

    expect(channel.methods, ['clearScreenshotConsentReceipt']);
    expect(channel.arguments, [isNull]);
  });

  test('verifies native receipt with owner, version and acceptedAt', () async {
    final channel = _FakeChannel(true);
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: channel,
    );

    expect(
      await bridge.hasUsableScreenshotConsentReceipt(
        ownerUserId: 'owner-1',
        version: 'keyboard_screenshot_ai_202607_v1',
        acceptedAt: DateTime.utc(2026, 7, 1),
      ),
      isTrue,
    );
    expect(channel.methods, ['verifyScreenshotConsentReceipt']);
    expect(channel.arguments.single, {
      'ownerUserId': 'owner-1',
      'version': 'keyboard_screenshot_ai_202607_v1',
      'acceptedAt': '2026-07-01T00:00:00.000Z',
    });
  });

  test('invalid native receipt verification value fails closed', () async {
    final bridge = MethodChannelKeyboardPhotoAuthorizationBridge(
      channel: _FakeChannel('true'),
    );

    await expectLater(
      bridge.hasUsableScreenshotConsentReceipt(
        ownerUserId: 'owner-1',
        version: 'keyboard_screenshot_ai_202607_v1',
        acceptedAt: DateTime.utc(2026, 7, 1),
      ),
      throwsStateError,
    );
  });
}

class _FakeChannel implements KeyboardContextChannel {
  _FakeChannel(this.result);

  final Object? result;
  final methods = <String>[];
  final arguments = <Object?>[];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    methods.add(method);
    this.arguments.add(arguments);
    return result;
  }
}
