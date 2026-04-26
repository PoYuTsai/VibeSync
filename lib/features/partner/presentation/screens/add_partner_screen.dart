// lib/features/partner/presentation/screens/add_partner_screen.dart
//
// Phase 2 Add Partner form. Reached via FAB from PartnerListScreen and
// from any future Partner-creation entry point.
//
// Design contract:
// - Uses PartnerRepository.upsertIfAbsent (the only A2 public write).
// - Mints a fresh UUID for partner.id.
// - ownerUserId is sourced from authConversationScopeProvider; submit is
//   DISABLED while auth is loading or null. Creating an ownerless Partner
//   would silently fail to appear in partnerListProvider (auth-gated +
//   ownerUserId-filtered) — guard up-front instead of accepting silent
//   data loss. (Codex r1 P2/P1.4)
// - On success: invalidate partnerListProvider so the home reflects the
//   new row immediately, then `context.replace` to /partner/:id (NOT
//   `context.go`). `replace` swaps the top stack entry so Home stays
//   underneath; back from detail returns to the Partner list. (Codex r1 P1.2)
// - Avatar picker is intentionally deferred to Phase 3/4 (parent A2 plan
//   Task 8 flagged it optional).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../conversation/data/providers/conversation_providers.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';

class AddPartnerScreen extends ConsumerStatefulWidget {
  const AddPartnerScreen({super.key});

  @override
  ConsumerState<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

class _AddPartnerScreenState extends ConsumerState<AddPartnerScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit(String ownerId) async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final now = DateTime.now();
    final partner = Partner(
      id: const Uuid().v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
      ownerUserId: ownerId,
    );
    try {
      await ref.read(partnerRepositoryProvider).upsertIfAbsent(partner);
      if (!mounted) return;
      ref.invalidate(partnerListProvider);
      // pushReplacement (NOT go): swaps /partner/new with /partner/:id so
      // back from detail returns to Home (Partner list) underneath, not to
      // the add form. (Codex r1 P1.2)
      GoRouter.of(context).pushReplacement('/partner/${partner.id}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('建立對象失敗，請再試一次')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authConversationScopeProvider);
    final ownerId = authAsync.valueOrNull;
    final authReady = !authAsync.isLoading && ownerId != null;
    final canSubmit = authReady && _name.text.trim().isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('新增對象')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '對象名稱',
                hintText: '例：Alice / 阿志 / 小張',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: canSubmit ? () => _submit(ownerId) : null,
              child: const Text('建立'),
            ),
            if (!authReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('請先登入再建立對象',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}
