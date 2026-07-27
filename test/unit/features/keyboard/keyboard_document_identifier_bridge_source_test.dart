import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the keyboard extension dying at launch.
///
/// `UITextDocumentProxy.documentIdentifier` is imported as a non-optional
/// `UUID`, but UIKit really does hand back nil before a document is attached to
/// the input session. Reading it directly made Swift bridge a nil `NSUUID`,
/// which trapped with `EXC_BREAKPOINT` inside
/// `UUID._unconditionallyBridgeFromObjectiveC` roughly 180ms after the
/// extension launched. iOS then stopped offering the keyboard from the globe at
/// all, so the whole feature — including the text-only flow — disappeared.
void main() {
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );

  test('document identifier is never bridged straight off the proxy', () {
    final source = controller.readAsStringSync();

    expect(
      source,
      isNot(contains('textDocumentProxy.documentIdentifier')),
      reason: 'A direct read traps on a nil NSUUID and kills the extension '
          'before the keyboard can appear.',
    );
    expect(source, contains('private var currentDocumentIdentifier: UUID?'));
    expect(source, contains('Selector(("documentIdentifier"))'));
    expect(source, contains('responds(to: selector)'));
    expect(source, contains('as? NSUUID'));
  });

  test('an unknown document can never unlock a legacy insertion', () {
    final source = controller.readAsStringSync();
    final guardStart = source.indexOf('func insertGeneratedReply()');
    expect(guardStart, greaterThanOrEqualTo(0));
    final guardBody = source.substring(guardStart, guardStart + 900);

    expect(
      guardBody,
      contains('let boundDocumentIdentifier = pending.documentIdentifier'),
      reason: 'Optional equality would let two nil identifiers compare equal '
          'and insert a reply into an unverified chat.',
    );
    expect(
      guardBody,
      contains('currentDocumentIdentifier == boundDocumentIdentifier'),
    );
  });
}
