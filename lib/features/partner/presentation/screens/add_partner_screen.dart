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
// - 建好直接選截圖（onboarding 轉換第 10 步）：帶 `?next=screenshot` 進來時，
//   再建一個空的分析片段疊在對象頁上，落地就是選截圖；按返回回到對象頁。
//   導航順序在 [followUpAfterPartnerCreated]。
// - Avatar picker is intentionally deferred to Phase 3/4 (parent A2 plan
//   Task 8 flagged it optional).
//
// Post-A2 visual redesign (Bruce 2026-04-27 Discord, Eric Q1b/Q2b/Q3a):
// - VibeSync purple gradient background.
// - Name remains free text; partner background is chips-only so third-person
//   context cannot drift into the user's own goals.
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

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';
import '../../domain/services/partner_memory_tag_catalog.dart';
import '../widgets/partner_memory_chip_picker.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';

// 標準 56 縮成 48：整張表單要一頁裝完（proof: add_partner_screen_test 的
// 「whole form fits one screen」），而這頁的 AppBar 只有標題＋返回。
const double _kToolbarHeight = 48;

class AddPartnerScreen extends ConsumerStatefulWidget {
  const AddPartnerScreen({super.key, this.nextStep});

  /// 建好對象卡之後接著做什麼（路由的 [nextQueryParam]）。目前只認
  /// [nextStepScreenshot]；沒帶或不認得的值＝只到對象頁（原本的行為）。
  final String? nextStep;

  /// 路由查詢參數名：`/partner/new?next=…`。
  static const nextQueryParam = 'next';

  /// 建好直接打開一個空的分析片段，落地就是選截圖（onboarding 轉換第 10 步）。
  static const nextStepScreenshot = 'screenshot';

  /// 「建好直接選截圖」的入口：onboarding 分流「有，幫我分析對話」與首頁空白的
  /// 「建立對象卡，開始分析」共用。
  ///
  /// 登入前完成 onboarding 時，這串會原樣存進暫存、登入後才 push
  /// （OnboardingService.stashPendingHandoff），所以改字要顧到手機裡已經存著的
  /// 舊值；更早的版本存的是沒帶參數的 `/partner/new`，照舊只到對象頁。
  static const screenshotFlowLocation =
      '/partner/new?$nextQueryParam=$nextStepScreenshot';

  @override
  ConsumerState<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

/// 建好對象卡之後的導航（onboarding 轉換第 10 步）。
///
/// 抽成可注入的函式，是因為 widget 測試裡從 async 送出鏈發出的導航不好驗
/// （add_partner_screen_test 開頭的已知限制）；換成記錄器就能斷言呼叫順序。
///
/// - 沒帶 [AddPartnerScreen.nextStepScreenshot]：只把新增頁換成對象頁，返回回
///   首頁、不回表單（跟原本一樣）。
/// - 帶了：先建空片段，再在同一幀「換成對象頁＋把片段疊上去」。畫面直接從表單
///   滑到選截圖，不會先閃過一張空白的對象頁；堆疊是首頁 → 對象頁 → 片段，按
///   返回時分析頁的 `_cleanupAndGoBack` 會刪掉沒內容的空片段、回到對象頁。
/// - 建空片段失敗：照樣落在對象頁（等於沒帶參數的落點），再跳既有的錯誤字。
/// - 等寫入的空檔裡使用者可以按返回離開（[isStillOnForm] 變 false）：不再替他
///   換頁；空片段已經建好的話就收回（[discardEmptyConversation]），因為分析頁
///   根本沒打開，`_cleanupAndGoBack` 不會跑，不收回會在對象頁留一個空的
///   「新對話」（Codex 第二批主審第 1 輪 P3）。收回失敗只記 log，不擋使用者。
@visibleForTesting
Future<void> followUpAfterPartnerCreated({
  required String partnerId,
  required String? nextStep,
  required bool Function() isStillOnForm,
  required Future<Conversation> Function() createEmptyConversation,
  required Future<void> Function(Conversation conversation)
      discardEmptyConversation,
  required void Function(String location) replaceWith,
  required void Function(String location) push,
  required void Function() onCreateConversationFailed,
}) async {
  final partnerLocation = '/partner/$partnerId';
  // 建對象的空檔就離開了：對象照樣建好（首頁看得到），不換頁、也不建片段。
  if (!isStillOnForm()) return;
  if (nextStep != AddPartnerScreen.nextStepScreenshot) {
    replaceWith(partnerLocation);
    return;
  }
  final Conversation conversation;
  try {
    conversation = await createEmptyConversation();
  } catch (_) {
    if (isStillOnForm()) replaceWith(partnerLocation);
    onCreateConversationFailed();
    return;
  }
  if (!isStillOnForm()) {
    try {
      await discardEmptyConversation(conversation);
    } catch (error) {
      debugPrint('Discard unused empty conversation failed: $error');
    }
    return;
  }
  replaceWith(partnerLocation);
  push('/conversation/${conversation.id}');
}

class _AddPartnerScreenState extends ConsumerState<AddPartnerScreen> {
  final _name = TextEditingController();
  Set<String> _memoryTags = <String>{};
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showBrandFeedbackSnackBar(
        context,
        title: '建立對象失敗，請再試一次',
        icon: Icons.error_outline_rounded,
        accentColor: AppColors.error,
      );
      return;
    }
    if (!mounted) return;
    // 換頁後這個畫面就會被拆掉：router、messenger、片段寫入、這頁的 route 都在
    // 換頁前抓好。
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final route = ModalRoute.of(context);
    final conversationWriter =
        ref.read(conversationWriteControllerProvider.notifier);
    await followUpAfterPartnerCreated(
      partnerId: partner.id,
      nextStep: widget.nextStep,
      // 只看 mounted 不夠：按返回後退場動畫期間這頁還掛著（mounted 仍是 true），
      // 但 go_router 已經退回首頁，這時換頁會把首頁換掉。route.isActive 在按下
      // 返回的那一刻就變 false。
      isStillOnForm: () => mounted && (route?.isActive ?? true),
      // 跟對象頁「分析新片段 → 截圖開始」同一個寫法（new_conversation_sheet）。
      createEmptyConversation: () => conversationWriter.create(
        name: '新對話',
        messages: [],
        partnerId: partner.id,
      ),
      // 跟分析頁 _cleanupAndGoBack 同一個刪法；建好到這裡沒人碰過，一定還是空的。
      discardEmptyConversation: conversationWriter.delete,
      // pushReplacement (NOT go): swaps /partner/new with /partner/:id so
      // back from detail returns to Home (Partner list) underneath, not to
      // the add form. (Codex r1 P1.2)
      replaceWith: (location) => router.pushReplacement<void>(location),
      push: (location) => router.push<void>(location),
      onCreateConversationFailed: () {
        messenger?.showSnackBar(
          buildBrandFeedbackSnackBar(
            title: '建立對話失敗，請再試一次',
            icon: Icons.error_outline_rounded,
            accentColor: AppColors.error,
          ),
        );
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  String? get _normalizedBackgroundNote {
    final note = PartnerMemoryTagCatalog.serialize(_memoryTags);
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
      // 走共用 brandAppBar：標題字體／字級／字重跟其他頁同一顆
      // （自己寫 TextStyle 會掉回 iOS 預設 .SF UI Display 22/w400）。
      appBar: brandAppBar(title: '新增對象', toolbarHeight: _kToolbarHeight),
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
    final note = PartnerMemoryTagCatalog.compactSummary(_memoryTags);
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
              label: '關於她',
              value: note.isEmpty ? '選填' : note,
              muted: note.isEmpty,
              onTap: _editMemoryTags,
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
    return showAppSheet<T>(
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
                onTap: () {
                  AppHaptics.tap();
                  Navigator.of(sheetContext).pop(option);
                },
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

  Future<void> _editMemoryTags() async {
    var draft = Set<String>.of(_memoryTags);
    final selected = await showAppSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '關於她（選填）',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '只選你確定的資料；關係進度和回覆狀態會由聊天分析更新。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: PartnerMemoryChipPicker(
                        selected: draft,
                        onChanged: (value) {
                          setSheetState(() => draft = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BrandPrimaryButton(
                    key: const ValueKey('add-partner-background-save'),
                    label: '完成',
                    onPressed: () => Navigator.of(sheetContext).pop(draft),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _memoryTags = selected);
    }
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
        onTap: AppHaptics.onPress(data.onTap),
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
