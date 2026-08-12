import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_room_entry_card.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('learning hero with quiet beam capture', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 760),
      rasterDecodeWait: const Duration(milliseconds: 500),
      child: const ProviderScope(
        child: Scaffold(
          body: SizedBox.expand(child: PracticeRoomEntryCard()),
        ),
      ),
      outPath: outPath('ocr_cleanup_hero_after.png'),
    );
  });
}
