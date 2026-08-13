// lib/features/partner/presentation/screens/add_partner_screen.dart
//
// Phase 2 Add Partner form. Reached via FAB from PartnerListScreen and
// from any future Partner-creation entry point.
//
// Design contract:
// - Uses PartnerWriteController.create, which owns persistence + invalidation.
// - Mints a fresh UUID for partner.id.
// - ownerUserId is sourced from authConversationScopeProvider; submit is
//   DISABLED while auth is loading or null. Creating an ownerless Partner
//   would silently fail to appear in partnerListProvider (auth-gated +
//   ownerUserId-filtered) — guard up-front instead of accepting silent
//   data loss. (Codex r1 P2/P1.4)
// - On success: the controller refreshes the partner list, then this screen
//   replaces /partner/new with /partner/:id so Home stays underneath.
// - Avatar picker is intentionally deferred to Phase 3/4 (parent A2 plan
//   Task 8 flagged it optional).
//
// Post-A2 visual redesign (Bruce 2026-04-27 Discord, Eric Q1b/Q2b/Q3a):
// - VibeSync purple gradient background.
// - Single free-text hint signals "name OR description" intent.
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the explanatory card / input /
// CTA now use the shared BrandKit primitives (BrandSurfaceCard +
// brandInputDecoration + BrandPrimaryButton) instead of the light warm-glass
// widgets, matching the shipped 關於我/作戰板 dark surface system.
//
// Layout-density fold (Bruce/Eric 2026-06-10, proof:
// test/visual_proof/density_proof_test.dart):
// - Problem was 太空/沒重心. ONLY layout density changed — same gradient,
//   same bubbles, same warm tokens, no new copy.
// - Explanatory text moved into a BrandSurfaceCard (heavy, deliberate center
//   of gravity); text tokens switch to onBackground* because they now sit on a
//   dark brand surface, not the bare gradient.
// - Content capped near full mobile width, biased to optical centre
//   (Spacer 3:4); field + CTA stay directly on the gradient under the card,
//   with a larger 24px rhythm so the form reads as a deliberate creation
//   panel rather than a small floating prompt.
// 一頁裝完（Eric 2026-08-12）：加了情境三選＋補充背景後整張表要捲到底才按得到
// 「建立」。純密度收斂——沒有拿掉任何欄位，改的是 AppBar 48、卡內距 16、區塊
// 間距 10/4、標籤降到 label 檔 12、chips 降到 12、說明文案縮短、選填備註的
// 0/300 常駐計數器拆掉。守門＝add_partner_screen_test 的「whole form fits one
// screen」（393×852 扣掉 safe area，CTA 底必須 ≤759）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';

// 標準 56 縮成 48：整張表單要一頁裝完（proof: add_partner_screen_test 的
// 「whole form fits one screen」），而這頁的 AppBar 只有標題＋返回。
const double _kToolbarHeight = 48;

class AddPartnerScreen extends ConsumerStatefulWidget {
  const AddPartnerScreen({super.key});

  @override
  ConsumerState<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

class _AddPartnerScreenState extends ConsumerState<AddPartnerScreen> {
  final _name = TextEditingController();
  final _backgroundNote = TextEditingController();
  MeetingContext _meetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
  UserGoal _goal = UserGoal.dateInvite;
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
    _backgroundNote.dispose();
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
      customNote: _normalizedBackgroundNote,
      defaultMeetingContext: _meetingContext,
      defaultAcquaintanceDuration: _duration,
      defaultGoal: _goal,
    );
    try {
      await ref.read(partnerWriteControllerProvider.notifier).create(partner);
      if (!mounted) return;
      // pushReplacement (NOT go): swaps /partner/new with /partner/:id so
      // back from detail returns to Home (Partner list) underneath, not to
      // the add form. (Codex r1 P1.2)
      GoRouter.of(context).pushReplacement('/partner/${partner.id}');
    } catch (_) {
      if (!mounted) return;
      showBrandFeedbackSnackBar(
        context,
        title: '建立對象失敗，請再試一次',
        icon: Icons.error_outline_rounded,
        accentColor: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String? get _normalizedBackgroundNote {
    final note = _backgroundNote.text.trim();
    return note.isEmpty ? null : note;
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
        toolbarHeight: _kToolbarHeight,
        centerTitle: true,
        title: const Text(
          '新增對象',
          style: TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: BrandPageBackground(child: SizedBox.expand()),
          ),
          SafeArea(
            // 夥伴稿：表單在上、「建立」貼底。表單本身可捲（小螢幕／鍵盤彈出
            // 時），CTA 固定在底部不隨內容漂走。
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 372),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        // `extendBodyBehindAppBar` lets the gradient sit under
                        // the transparent AppBar; content still needs to clear
                        // the toolbar.
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          _kToolbarHeight,
                          16,
                          8,
                        ),
                        children: [
                          _buildIdentityCard(),
                          const SizedBox(height: 20),
                          _buildContextCard(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BrandPrimaryButton(
                            label: '建立',
                            onPressed:
                                canSubmit ? () => _submit(ownerId) : null,
                            isLoading: _busy,
                            verticalPadding: 16,
                          ),
                          if (!authReady)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '請先登入再建立對象',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.onBackgroundSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '對象名稱',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '必填',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.ctaStart,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('add-partner-name-field'),
          controller: _name,
          cursorColor: AppColors.ctaStart,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: Colors.white),
          decoration: brandInputDecoration(
            hintText: '輸入她的名字或暱稱',
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            hintStyle: AppTypography.bodyLarge.copyWith(
              color: Colors.white.withValues(alpha: 0.40),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContextCard() {
    final note = _backgroundNote.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '幫教練進一步認識她',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _GroupedRows(
          rows: [
            _FormRowData(
              key: const ValueKey('add-partner-meeting-context-row'),
              label: '認識情境',
              value: _meetingContext.displayLabel,
              onTap: () => _pickMeetingContext(),
            ),
            _FormRowData(
              key: const ValueKey('add-partner-duration-row'),
              label: '認識多久',
              value: _duration.displayLabel,
              onTap: () => _pickDuration(),
            ),
            _FormRowData(
              key: const ValueKey('add-partner-goal-row'),
              label: '目前目標',
              value: _goal.displayLabel,
              onTap: () => _pickGoal(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GroupedRows(
          rows: [
            _FormRowData(
              key: const ValueKey('add-partner-background-row'),
              label: '補充背景',
              value: note.isEmpty ? '選填' : note,
              muted: note.isEmpty,
              onTap: _editBackgroundNote,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickMeetingContext() async {
    final picked = await _pickOption<MeetingContext>(
      title: '認識情境',
      options: MeetingContext.visibleAnalysisOptions,
      labelOf: (value) => value.displayLabel,
      selected: _meetingContext,
    );
    if (picked != null && mounted) setState(() => _meetingContext = picked);
  }

  Future<void> _pickDuration() async {
    final picked = await _pickOption<AcquaintanceDuration>(
      title: '認識多久',
      options: AcquaintanceDuration.values,
      labelOf: (value) => value.displayLabel,
      selected: _duration,
    );
    if (picked != null && mounted) setState(() => _duration = picked);
  }

  Future<void> _pickGoal() async {
    final picked = await _pickOption<UserGoal>(
      title: '目前目標',
      options: UserGoal.values,
      labelOf: (value) => value.displayLabel,
      selected: _goal,
    );
    if (picked != null && mounted) setState(() => _goal = picked);
  }

  /// 下鑽選項：走 bottom sheet 而非 push 新頁——回來不用重建整張表單，
  /// 也不會多一層 route 讓返回鍵語意變兩段。
  Future<T?> _pickOption<T>({
    required String title,
    required Iterable<T> options,
    required String Function(T) labelOf,
    required T selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final option in options)
              InkWell(
                key: ValueKey('add-partner-option-${labelOf(option)}'),
                onTap: () => Navigator.of(sheetContext).pop(option),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labelOf(option),
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.onBackgroundPrimary,
                            ),
                          ),
                        ),
                        if (option == selected)
                          const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: AppColors.ctaStart,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 補充背景直接綁 [_backgroundNote]：sheet 用臨時 controller 會在收合動畫
  /// 還在跑時就被 dispose（TextField 仍在重建）→ 「used after disposed」。
  Future<void> _editBackgroundNote() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '補充背景（選填）',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '補上聊天看不到的關係或背景，分析時會先帶入。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('add-partner-background-field'),
                  controller: _backgroundNote,
                  autofocus: true,
                  maxLength: 300,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  cursorColor: AppColors.ctaStart,
                  style: AppTypography.bodyLarge.copyWith(color: Colors.white),
                  // counterText 清掉：0/300 自己吃掉一列高，maxLength 仍然擋得住。
                  decoration: brandInputDecoration(hintText: '沒有可以留空')
                      .copyWith(counterText: ''),
                ),
                const SizedBox(height: 12),
                BrandPrimaryButton(
                  key: const ValueKey('add-partner-background-save'),
                  label: '完成',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _FormRowData {
  const _FormRowData({
    required this.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.muted = false,
  });

  final Key key;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// true＝值是「選填」這類 placeholder，用弱色。
  final bool muted;
}

/// 原生 grouped form 語法：一張低對比 surface，列與列之間只有 hairline。
class _GroupedRows extends StatelessWidget {
  const _GroupedRows({required this.rows});

  final List<_FormRowData> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            _FormRow(data: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.data});

  final _FormRowData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: data.key,
        borderRadius: BorderRadius.circular(18),
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  data.label,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyMedium.copyWith(
                      color: data.muted
                          ? AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.7)
                          : AppColors.onBackgroundSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.ctaStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
