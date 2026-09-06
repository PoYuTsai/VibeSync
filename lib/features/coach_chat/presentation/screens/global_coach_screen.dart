import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/coach_head_avatar.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../learning/domain/dating_knowledge_links.dart';
import '../../../learning/presentation/screens/ebook_detail_screen.dart'
    show ebookChapterRoute;
import '../../../learning/presentation/widgets/knowledge_library_link_row.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/mindmap/mind_map_builder.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../data/services/coach_chat_api_service.dart'
    show CoachChatAnalysisSnapshot;
import '../../data/providers/coach_chat_providers.dart';
import '../../domain/entities/coach_scope.dart';
import '../widgets/coach_surface.dart';
import '../widgets/sydney_welcome_portrait.dart';

/// 問教練 Sydney 獨立聊天視窗（2026-08-15 拍板：三入口共用同一個視窗）。
///
/// 三種進場：
/// - 首頁「問教練 Sydney」→ `/coach`：頂部「問誰」chips（有對象卡才渲染），
///   預設「一般」；切到對象＝整個畫面換成該對象版（開場泡泡＋情境問句）。
/// - 對象頁／作戰板 CTA → `/coach?partnerId=X`：鎖定該對象，不渲染 chips，
///   標題帶對象名。對象已刪除時退回一般模式。
/// - 分析頁 CTA → `/coach?conversationId=Y`（extra 帶分析快照）：鎖定該段
///   對話的 conversation scope（沿用分析頁 1:1 的同一條串），快照隨 ask
///   附送。標題帶該段對話的對象名（查無對象時只顯示 Sydney）。
///
/// 引導問句跟著 scope 走，不是跟著入口走：一般＝三句「怎麼做」問句；
/// 對象＝三句「情境」chips（種入 lifecyclePhase＋prefill）。點擊只「預填」
/// 進輸入框（prefill＋focus token 遞增），絕不自動送出——送出永遠是用戶
/// 按鈕行為（quota 安全）。
///
/// 開場泡泡吃記憶素材（優先序，只引用已存在的資料、絕不腦補）：
/// 上次教練串問句 → 最近分析的下一步 → 關係階段 → 通用 fallback。
class GlobalCoachScreen extends ConsumerStatefulWidget {
  const GlobalCoachScreen({
    super.key,
    this.lockedPartnerId,
    this.lockedConversationId,
    this.analysisSnapshot,
  });

  /// 非 null＝對象頁／作戰板 CTA 進場：鎖定該對象 scope、不渲染「問誰」。
  final String? lockedPartnerId;

  /// 非 null＝分析頁 CTA 進場：鎖定 conversation scope（優先於
  /// [lockedPartnerId]）、不渲染「問誰」。
  final String? lockedConversationId;

  /// 分析頁 CTA 隨行的分析快照（僅 conversation 模式）：CoachSurface 隨
  /// ask 附送，開場泡泡也拿它的 nextStep 當記憶素材。push extra 傳遞，
  /// 冷啟 deep-link 拿不到時為 null——教練照常運作，只少快照脈絡。
  final CoachChatAnalysisSnapshot? analysisSnapshot;

  /// 一般 scope 引導問句（計畫拍板三句；widget 測試字面對齊）。
  static const guideQuestions = <String>[
    '不知道怎麼開啟話題，給我一點方向？',
    '對方回得很短，我該怎麼判斷？',
    '怎麼把聊天推進到約出來？',
  ];

  /// 對象 scope 情境問句（沿用對象頁「教練跟進」三情境；phase 字串隨
  /// wire lifecyclePhase 原樣送）。
  static const scenarioChips = <({String phase, String label, String prefill})>[
    (phase: 'chatStalled', label: '聊天卡住了', prefill: '我們聊天卡住了，接下來該怎麼辦？'),
    (phase: 'prepareInvite', label: '想約她出來', prefill: '我想約她出來，該怎麼開口比較自然？'),
    (phase: 'postDate', label: '約完會之後', prefill: '剛約完會，接下來要怎麼經營比較好？'),
  ];

  @override
  ConsumerState<GlobalCoachScreen> createState() => _GlobalCoachScreenState();
}

class _GlobalCoachScreenState extends ConsumerState<GlobalCoachScreen> {
  bool _engaged = false;
  String? _prefill;
  int _focusToken = 0;
  String? _pendingPhase;
  late CoachScope _scope = widget.lockedConversationId != null
      ? CoachScope.conversation(widget.lockedConversationId!)
      : widget.lockedPartnerId != null
          ? CoachScope.partner(widget.lockedPartnerId!)
          : const CoachScope.global();

  @override
  void initState() {
    super.initState();
    // 鎖定的對象進場前就被合併/刪除 → 退回一般模式（deep link 防呆）。
    // 開著視窗期間被刪的情況由 build 裡的 ref.listen 接手。
    final partnerId = widget.lockedPartnerId;
    if (widget.lockedConversationId == null &&
        partnerId != null &&
        ref.read(partnerByIdProvider(partnerId)) == null) {
      _scope = const CoachScope.global();
    }
  }

  void _onGuideTap(String question, {String? phase}) {
    setState(() {
      _prefill = question;
      _pendingPhase = phase;
      _focusToken += 1;
    });
  }

  void _onScopeTap(CoachScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _engaged = false;
      // 情境是跟著對象串的：換人（或回一般）就歸零，避免 A 的 phase
      // 黏到 B 的下一次 ask。輸入框草稿刻意不清（設計拍板：切換保留）。
      _pendingPhase = null;
    });
  }

  /// 「問誰」chips：沒有任何對象卡就整排不渲染（新用戶畫面同現狀，
  /// 不出現只有「一般」的孤兒選項）。
  Widget _buildScopeChips(List<Partner> partners) {
    if (partners.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '問誰',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
          _scopeChip(
            key: const Key('coach_scope_general'),
            label: '一般',
            selected: _scope.isGlobal,
            onTap: () => _onScopeTap(const CoachScope.global()),
          ),
          for (final partner in partners)
            _scopeChip(
              key: Key('coach_scope_partner_${partner.id}'),
              label: partner.name,
              selected: _scope == CoachScope.partner(partner.id),
              onTap: () => _onScopeTap(CoachScope.partner(partner.id)),
            ),
        ],
      ),
    );
  }

  Widget _scopeChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: key,
        label: Text(label),
        selected: selected,
        // 勾勾的淡入淡出會在快速切換時留殘影＋寬度跳動（2026-08-10
        // Eric 真機回報；同 CoachFollowUpSection 的既有修法）。
        showCheckmark: false,
        onSelected: (_) {
          AppHaptics.light();
          onTap();
        },
      ),
    );
  }

  /// 引用素材超過這個長度就截斷加省略號——開場泡泡是一句話，不是轉貼全文。
  static String _clip(String value, [int max = 20]) {
    final trimmed = value.trim();
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max)}…';
  }

  /// 開場泡泡文案。非一般 scope 按優先序取材；素材只引用已存在的資料，
  /// 一句話＋一個問句收尾，絕不腦補沒發生的事。
  String _openingLine(Partner? contextPartner) {
    if (_scope.isGlobal) return '隨時問我，聊天卡住我來接。';

    final history = ref.watch(coachChatHistoryProvider(_scope));
    if (history.isNotEmpty) {
      final latest = history.reduce(
        (a, b) => a.generatedAt.isAfter(b.generatedAt) ? a : b,
      );
      final question = latest.question.trim();
      if (question.isNotEmpty) {
        return '上次你問我「${_clip(question)}」，後來有下文嗎？';
      }
    }

    if (_scope.isConversation) {
      // 分析頁 CTA 隨行快照：本段分析的下一步。
      final nextStep = widget.analysisSnapshot?.nextStep?.trim();
      if (nextStep != null && nextStep.isNotEmpty) {
        return '上次分析完的下一步是「${_clip(nextStep)}」，試了嗎？';
      }
    } else if (contextPartner != null) {
      // 作戰板同一套快照衍生（零 AI 邊際成本）：下一步 → 關係信號。
      final map = buildPartnerMindMap(
        partnerName: contextPartner.name,
        aggregate: ref.watch(partnerAggregateProvider(contextPartner.id)),
        conversations: ref.watch(
          conversationsByPartnerProvider(contextPartner.id),
        ),
        analysisRecords: ref.watch(
          partnerAnalysisRecordsProvider(contextPartner.id),
        ),
        partnerCustomNote: contextPartner.customNote,
      );
      final nextStep = map.fullNextStep?.trim();
      if (nextStep != null && nextStep.isNotEmpty) {
        return '上次分析完的下一步是「${_clip(nextStep)}」，試了嗎？';
      }
      final signal = map.relationshipSignal?.trim();
      if (signal != null && signal.isNotEmpty) {
        return '你們目前的狀態：${_clip(signal)}。想從哪裡推進？';
      }
    }

    final name = contextPartner?.name;
    if (name == null) return '想聊哪一段？卡住的地方直接丟給我。';
    return '想聊$name的什麼？卡住的地方直接丟給我。';
  }

  Widget _buildOpeningBubble(Partner? scopePartner) {
    final baseHeight = (MediaQuery.sizeOf(context).height * 0.26).clamp(
      144.0,
      240.0,
    );
    // 大字體時先把人物縮小，讓開場文字保有寬度，不裁字或降低文字倍率。
    final textScale =
        (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 2.5);
    final height = (baseHeight / textScale).clamp(88.0, 240.0);
    return Column(
      key: const Key('coach-welcome'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final portraitWidth = (height * 9 / 16).clamp(
              0.0,
              constraints.maxWidth * 0.46 / textScale,
            );
            return Row(
              children: [
                Expanded(
                  child: Text(
                    _openingLine(scopePartner),
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  key: const Key('coach-welcome-portrait'),
                  width: portraitWidth,
                  height: portraitWidth * 16 / 9,
                  child: const SydneyWelcomePortrait(),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '幫教練釐清最多 3 次；正式建議扣 1 則，額度用完會提醒升級。',
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Batch B1「教練會參考」：partner scope 下教練會自動帶入該對象最近
  /// 一段有效對話。刻意用未來式——這行與 controller 下一次 ask 讀同一個
  /// provider，描述的是「接下來提問會用的來源」；過去某次回答用了哪段，
  /// 不在這行的語意裡（R1 主審 P2：live watch 不得宣稱歷史請求的來源）。
  /// 沒有有效對話時不渲染（教練會先釐清）。
  Widget _buildPartnerContextReference() {
    if (!_scope.isPartner) return const SizedBox.shrink();
    final source = ref.watch(coachPartnerSourceConversationProvider(_scope.id));
    if (source == null) return const SizedBox.shrink();
    final at = lastNonEmptyMessageAt(source);
    final when = at == null ? '最近' : '${at.month}/${at.day}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '教練會參考：你們 $when 的對話紀錄',
        key: const Key('coach_partner_context_reference'),
        style: AppTypography.caption.copyWith(
          color: AppColors.onBackgroundSecondary,
          height: 1.35,
        ),
      ),
    );
  }

  /// 引導問句泡泡：跟著 scope 走——一般＝「怎麼做」問句；對象／分析段＝
  /// 情境 chips（種入 lifecyclePhase）。點擊只預填，可改再送。
  Widget _buildGuideBubbles() {
    final bubbles = _scope.isGlobal
        ? [
            for (final question in GlobalCoachScreen.guideQuestions)
              _guideBubble(label: question, onTap: () => _onGuideTap(question)),
          ]
        : [
            for (final chip in GlobalCoachScreen.scenarioChips)
              _guideBubble(
                label: chip.label,
                selected: _pendingPhase == chip.phase,
                onTap: () => _onGuideTap(chip.prefill, phase: chip.phase),
              ),
          ];
    return Wrap(spacing: 8, runSpacing: 8, children: bubbles);
  }

  Widget _guideBubble({
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: selected ? 0.12 : 0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: AppHaptics.onPress(onTap),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.ctaStart.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  /// 目前選中情境對應的 Dating Knowledge Library 章節；沒選或查無對應
  /// 時不渲染（沿用對象頁「教練跟進」的既有決策：寧可不給入口，也不連
  /// 一章不相干的內容）。
  Widget _buildKnowledgeLink() {
    final target = DatingKnowledgeLinks.forFollowUpPhase(_pendingPhase);
    if (target == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KnowledgeLibraryLinkRow(
        key: const Key('coach_window_knowledge_link'),
        label: '看這一段的完整原理',
        onTap: () => context.push(
          ebookChapterRoute(
            target.bookId,
            target.chapterId,
            entryId: target.entryId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partners = ref.watch(partnerListProvider);
    final conversationMode = widget.lockedConversationId != null;

    // 鎖定對象／該段對話的對象；對象已被合併/刪除時為 null。
    Partner? contextPartner;
    if (conversationMode) {
      final conversation = ref.watch(
        conversationProvider(widget.lockedConversationId!),
      );
      final partnerId = conversation?.partnerId;
      contextPartner =
          partnerId == null ? null : ref.watch(partnerByIdProvider(partnerId));
    } else if (widget.lockedPartnerId != null) {
      // 開著視窗期間對象被合併/刪除 → 退回一般模式。listener 在 build 外
      // 觸發，setState 安全（進場前已刪的情況由 initState 處理）。
      ref.listen(partnerByIdProvider(widget.lockedPartnerId!), (_, next) {
        if (next == null && !_scope.isGlobal) {
          setState(() => _scope = const CoachScope.global());
        }
      });
      contextPartner = ref.watch(partnerByIdProvider(widget.lockedPartnerId!));
    } else if (!_scope.isGlobal) {
      contextPartner = partners
          .where((partner) => _scope == CoachScope.partner(partner.id))
          .firstOrNull;
    }

    // 鎖定與否只看進場參數（含防呆後仍有效），不看 free 模式下的 chip 選擇。
    final locked = conversationMode ||
        (widget.lockedPartnerId != null && contextPartner != null);

    final title = locked && contextPartner != null
        ? '問教練 Sydney・${contextPartner.name}'
        : '問教練 Sydney';
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onBackgroundPrimary,
          elevation: 0,
          centerTitle: false,
          title: Row(
            children: [
              if (_engaged) ...[
                const CoachHeadAvatar(
                  key: Key('coach-compact-avatar'),
                  size: 32,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  // 同 brandAppBar 的標題字（19／w800），跟其他頁一致。
                  style: AppTypography.appBarTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            if (_engaged && !locked && partners.isNotEmpty)
              PopupMenuButton<CoachScope>(
                key: const Key('coach_scope_menu'),
                tooltip: '問誰',
                onSelected: _onScopeTap,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    key: Key('coach_scope_general'),
                    value: CoachScope.global(),
                    child: Text('一般'),
                  ),
                  for (final partner in partners)
                    PopupMenuItem(
                      key: Key('coach_scope_partner_${partner.id}'),
                      value: CoachScope.partner(partner.id),
                      child: Text(partner.name),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: Text(
                          _scope.isGlobal ? '一般' : contextPartner?.name ?? '對象',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!locked && !_engaged) ...[
                const SizedBox(height: 8),
                _buildScopeChips(partners),
              ],
              Expanded(
                child: CoachSurface(
                  scope: _scope,
                  onEngagementChanged: (engaged) {
                    if (mounted && _engaged != engaged) {
                      setState(() => _engaged = engaged);
                    }
                  },
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOpeningBubble(contextPartner),
                      const SizedBox(height: 16),
                      _buildGuideBubbles(),
                      const SizedBox(height: 16),
                    ],
                  ),
                  contextHeader: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPartnerContextReference(),
                      if (!_scope.isGlobal) _buildKnowledgeLink(),
                    ],
                  ),
                  analysisSnapshot:
                      conversationMode ? widget.analysisSnapshot : null,
                  focusRequestToken: _focusToken,
                  prefillText: _prefill,
                  lifecyclePhase: _pendingPhase,
                  onQuotaExceeded: () => context.push('/paywall'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
