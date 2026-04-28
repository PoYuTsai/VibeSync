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
//
// Post-A2 visual redesign (Bruce 2026-04-27 Discord, Eric Q1b/Q2b/Q3a):
// - VibeSync purple gradient bg + 3 static brand-colored bubbles
//   (purple/orange/pink — purple = mood, orange = action, per token system).
// - GlassmorphicTextField for input + GradientButton (orange CTA) — orange
//   matches the FAB the user just tapped to get here.
// - Single free-text hint signals "name OR description" intent.
// - Bubbles are intentionally STATIC (no AnimationController) so this
//   screen's widget tests don't hit GradientBackground's pumpAndSettle hang.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/glassmorphic_text_field.dart';
import '../../../../shared/widgets/gradient_button.dart';
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
  void initState() {
    super.initState();
    // GlassmorphicTextField has no onChanged — listen on the controller
    // so the CTA enable state tracks live input.
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '新增對象',
          style: TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AddPartnerBackground()),
          SafeArea(
            child: Padding(
              // `extendBodyBehindAppBar` lets the gradient sit under the
              // transparent AppBar; content still needs to clear the toolbar.
              padding: const EdgeInsets.fromLTRB(
                24,
                kToolbarHeight + 16,
                24,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassmorphicTextField(
                    controller: _name,
                    hintText: '例：Alice 🧚🏻‍♀️ / 咖啡廳的捲髮女孩 ☕',
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    text: '建立',
                    onPressed: canSubmit ? () => _submit(ownerId) : null,
                    isLoading: _busy,
                  ),
                  if (!authReady)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        '請先登入再建立對象',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Static gradient + brand-colored bubbles for AddPartnerScreen.
///
/// Uses the same `backgroundGradient*` tokens as `GradientBackground`, but
/// the bubbles here are STATIC (no AnimationController). This is deliberate:
/// `GradientBackground`'s 3 infinite controllers cause `pumpAndSettle` to
/// hang in widget tests, and AddPartner's tests rely on it. Brand-color
/// pick: purple (primaryLight) + orange (ctaStart) + pink (bokehPink) so
/// the screen reads as "VibeSync 紫橘", not the rainbow palette of the
/// reference screenshot.
class _AddPartnerBackground extends StatelessWidget {
  const _AddPartnerBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundGradientStart,
            AppColors.backgroundGradientMid,
            AppColors.backgroundGradientEnd,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -40,
              left: -30,
              child: _StaticBubble(
                color: AppColors.primaryLight,
                size: 170,
                opacity: 0.55,
              ),
            ),
            Positioned(
              top: 60,
              right: -50,
              child: _StaticBubble(
                color: AppColors.ctaStart,
                size: 150,
                opacity: 0.5,
              ),
            ),
            Positioned(
              bottom: 120,
              left: 40,
              child: _StaticBubble(
                color: AppColors.bokehPink,
                size: 130,
                opacity: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticBubble extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _StaticBubble({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: 60,
            spreadRadius: 25,
          ),
        ],
      ),
    );
  }
}
