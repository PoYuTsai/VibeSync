// Visual proof for the low-risk entry screens migrated onto BrandKit (Task B).
// Renders each screen to a PNG so the暗紫橘統一 can be eyeballed against the
// shipped 關於我/作戰板 reference.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('add partner capture', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (ref) => Stream.value('u-proof'),
          ),
        ],
        child: const AddPartnerScreen(),
      ),
      outPath: outPath('add_partner.png'),
    );
  });
}
