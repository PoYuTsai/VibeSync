import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/scroll_card_ticks.dart';
import '../../domain/entities/analysis_models.dart';
import '../widgets/reply_style_card.dart';
import '../widgets/swipe_hint_nudge.dart';

/// 回覆區的動作介面：複製/微調/升級/刷新全由 screen 實作（剪貼簿、
/// 觸覺、outcome 記錄、paywall route、計費流程都是副作用）。
abstract interface class ReplyZoneActions {
  void copyRecommendationText(String text, String label);
  void copyStyleReply(String type, String text, String snackBarMessage);
  void refineReply(String text, String originCardKey);
  void openPaywall();
  void refreshPremiumReplies();
}

/// 回覆區尾端提示的種類（顯示條件與訂閱狀態判讀由 screen 決定）。
enum ReplyZoneNoticeKind {
  /// Free 用戶：升級解鎖完整 5 種風格。
  freeUpgrade,

  /// 已升級但目前看的是免費版結果：提供重新產生完整分析。
  refreshStale,

  /// 付費 fallback 說明：AI 判斷此情境最適合延展。
  premiumDefault,
}

/// 單一風格卡的展示規格。
@immutable
class ReplyStyleCardSpec {
  const ReplyStyleCardSpec({
    required this.type,
    required this.content,
    required this.option,
    required this.isRecommended,
  });

  final String type;
  final String content;
  final ReplyOption? option;
  final bool isRecommended;
}

/// canonical 回覆卡集合：顯示卡組、stagger/張數與 outcome bar 對映
/// 全部由這一份有序集合推導（單一真相源，張數與卡序不可能分岔）。
///
/// 規則（沿用既有行為）：
/// - 推薦卡存在條件＝recommendation.content 非空白，恆為第一張。
/// - 風格卡照 [styleOrder] 固定順序；推薦 pick 型別若已有非空回覆，
///   併入推薦卡不重複成卡（僅在推薦卡存在時去重）。
/// - 沒有推薦卡時，pick 型別的風格卡標記 isRecommended。
@immutable
class ReplyZoneCards {
  ReplyZoneCards({
    required this.recommendation,
    required Map<String, String>? replies,
    required Map<String, ReplyOption>? replyOptions,
  })  : presentStyleTypes = List.unmodifiable(
          styleOrder.where((type) => replies?.containsKey(type) ?? false),
        ),
        styleCards = List.unmodifiable(
          styleOrder
              .where((type) => replies?.containsKey(type) ?? false)
              .where(
                (type) => !(_recommendationShown(recommendation) &&
                    _isRecommendedType(recommendation, replies, type)),
              )
              .map(
                (type) => ReplyStyleCardSpec(
                  type: type,
                  content: replies![type]!,
                  option: replyOptions?[type],
                  isRecommended:
                      _isRecommendedType(recommendation, replies, type),
                ),
              ),
        );

  static const styleOrder = [
    'extend',
    'resonate',
    'tease',
    'humor',
    'coldRead',
  ];

  final FinalRecommendation? recommendation;

  /// 顯示的風格卡（有序、已依推薦卡去重）。
  final List<ReplyStyleCardSpec> styleCards;

  /// 結果中出現的風格型別（有序、不去重）；outcome bar 對映用。
  final List<String> presentStyleTypes;

  static bool _recommendationShown(FinalRecommendation? recommendation) =>
      recommendation != null && recommendation.content.trim().isNotEmpty;

  static bool _isRecommendedType(
    FinalRecommendation? recommendation,
    Map<String, String>? replies,
    String type,
  ) {
    final pick = recommendation?.pick.trim();
    return pick == type && (replies?[type]?.trim().isNotEmpty ?? false);
  }

  bool get showRecommended => _recommendationShown(recommendation);

  int get cardCount => styleCards.length + (showRecommended ? 1 : 0);

  /// 由 canonical 卡組推導（Codex r1-P2）：只有推薦卡或至少一張五風格卡
  /// 才算有內容；原始 replies map 含未知鍵不再撐開空回覆區。
  bool get hasContent => showRecommended || styleCards.isNotEmpty;
}

/// 回覆區（分析完成的 payoff 區塊）：標題列＋橫滑卡組（推薦卡＋風格卡，
/// 帶 stagger 進場）＋outcome bar 插槽＋尾端提示。
///
/// 進場 [entrance] 的 AnimationController 與播放時機由 screen 持有；
/// 本 section 只消費 Animation 並依 [entranceTotalMs] 時間軸切 Interval。
class ReplyZoneSection extends StatelessWidget {
  const ReplyZoneSection({
    super.key,
    required this.cards,
    required this.entrance,
    required this.anchorKey,
    required this.actions,
    required this.noticeKind,
    required this.noticeBusy,
    required this.outcomeBars,
  });

  /// 回覆區進場（payoff 時刻）：區塊 fade+slide 320ms，卡組每張 stagger
  /// 50ms。總長 = celebrate(320) + 5×50 = 570ms。一次性：新一輪分析
  /// （內容歸零後再出現）才重播。
  static const cardStaggerMs = 50;
  static const entranceTotalMs = 570;

  final ReplyZoneCards cards;
  final Animation<double> entrance;

  /// 分析完成一次性自動捲動的錨（screen 持有的 GlobalKey）。
  final Key anchorKey;
  final ReplyZoneActions actions;

  /// null＝不顯示尾端提示。
  final ReplyZoneNoticeKind? noticeKind;

  /// refreshStale 提示的刷新按鈕忙碌態（分析中/刷新中停用並轉圈）。
  final bool noticeBusy;

  /// 複製後才浮出的成效回報列；依 provider 狀態渲染，由 screen 組好插入。
  final List<Widget> outcomeBars;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分析完成的一次性自動捲動錨在這裡（回覆區頂、不錨上方的
        // 「下一步」卡）。
        KeyedSubtree(
          key: anchorKey,
          child: _entranceFade(
            child: Row(
              children: [
                Text('回覆建議',
                    style: AppTypography.titleLarge
                        .copyWith(color: AppColors.onBackgroundPrimary)),
                const Spacer(),
                if (cards.cardCount > 1)
                  const SwipeHintNudge(
                    child: SwipeHintChip(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 高度自適應（2026-08-09 拍板）：拆掉固定 400 高，每張卡各自照
        // 內容長高、頂端對齊——推薦卡長是它自己的事，其他風格卡不跟著
        // 拉伸。卡最多 6 張，放棄 ListView 的懶載無感。
        _entranceFade(
          child: ScrollCardTicks(
            axis: Axis.horizontal,
            focusFraction: 0.3,
            child: SingleChildScrollView(
              key: const ValueKey('analysis-reply-zone'),
              scrollDirection: Axis.horizontal,
              child: _cardRow(),
            ),
          ),
        ),
        ...outcomeBars,
        if (noticeKind != null) ...[
          const SizedBox(height: 12),
          _notice(noticeKind!),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  /// 回覆區塊層進場（標題與卡組共用）：opacity 0→1＋往上 4% 落定，
  /// 佔總時間軸的前 320ms。
  Widget _entranceFade({required Widget child}) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: Interval(
        0,
        AppMotion.celebrate.inMilliseconds / entranceTotalMs,
        curve: AppMotion.easeOut,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  /// 第 [index] 張卡的 stagger 進場：延遲 index×50ms，fade（easeOut，
  /// 避免 easeOutBack 超過 1 的 opacity）＋scale 0.96→1（celebrateCurve，
  /// 全 app 唯一允許彈感的檔位）。純裝飾，不擋互動。
  Widget _staggeredCard(int index, Widget child) {
    final startMs = index * cardStaggerMs;
    final start = (startMs / entranceTotalMs).clamp(0.0, 1.0).toDouble();
    final end = ((startMs + AppMotion.celebrate.inMilliseconds) /
            entranceTotalMs)
        .clamp(0.0, 1.0)
        .toDouble();
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: entrance,
        curve: Interval(start, end, curve: AppMotion.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(
            parent: entrance,
            curve: Interval(start, end, curve: AppMotion.celebrateCurve),
          ),
        ),
        child: child,
      ),
    );
  }

  /// 回覆卡組（推薦卡＋風格卡）帶 stagger 進場的橫列。
  Widget _cardRow() {
    final children = <Widget>[
      if (cards.showRecommended)
        _RecommendedReplyCard(
          recommendation: cards.recommendation!,
          actions: actions,
        ),
      for (final spec in cards.styleCards)
        ReplyStyleCard(
          type: spec.type,
          content: spec.content,
          option: spec.option,
          isRecommended: spec.isRecommended,
          onCopy: (text, message) =>
              actions.copyStyleReply(spec.type, text, message),
          onRefine: (text) => actions.refineReply(text, spec.type),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++)
          // CardTickTarget：橫掃跨卡打一下輕觸覺（與開場白/新話題同語彙）。
          CardTickTarget(index: i, child: _staggeredCard(i, children[i])),
      ],
    );
  }

  /// 回覆區尾端提示：Free 升級入口／已升級但看舊 Free 結果的重新分析
  /// ／付費 fallback 說明。
  Widget _notice(ReplyZoneNoticeKind kind) {
    switch (kind) {
      case ReplyZoneNoticeKind.freeUpgrade:
        return GestureDetector(
          onTap: actions.openPaywall,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: AppColors.ctaStart),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '你已可比較延展、調情；升級解鎖共鳴、幽默、冷讀等完整 5 種風格',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.ctaStart),
              ],
            ),
          ),
        );
      case ReplyZoneNoticeKind.refreshStale:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ctaStart.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.ctaStart.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.ctaStart),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '你已升級，這份分析仍是免費版結果。',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.ctaStart,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '重新分析一次，就能拿到完整分析結果。',
                style:
                    AppTypography.caption.copyWith(color: AppColors.ctaStart),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: noticeBusy ? null : actions.refreshPremiumReplies,
                  icon: noticeBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    noticeBusy ? '正在刷新完整分析…' : '重新產生完整分析',
                  ),
                ),
              ),
            ],
          ),
        );
      case ReplyZoneNoticeKind.premiumDefault:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: AppColors.onBackgroundSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 判斷此情境最適合使用延展回覆',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// 回覆區第一張：AI 推薦回覆。比風格卡寬一號、卡高照內容自然長。
class _RecommendedReplyCard extends StatelessWidget {
  const _RecommendedReplyCard({
    required this.recommendation,
    required this.actions,
  });

  final FinalRecommendation recommendation;
  final ReplyZoneActions actions;

  @override
  Widget build(BuildContext context) {
    // 對標示意稿（2026-08-14）：拆掉外層漸層框卡，內容平鋪在頁面底上；
    // 標題換圓形靶心徽章＋白字，理由收進帶 icon 座的說明卡。
    return Container(
      key: const ValueKey('analysis-recommended-reply-card'),
      width: 340,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ctaStart.withValues(alpha: 0.16),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  size: 19,
                  color: AppColors.ctaStart,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'AI 推薦回覆',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._recommendationContent(),
          const SizedBox(height: 12),
          _recommendationNote(),
        ],
      ),
    );
  }

  /// 每一顆「再調一下」都只綁一則回覆——整組合併後的文字不給微調。
  Widget _refineButton(String replyText) {
    final text = replyText.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        height: 34,
        child: TextButton.icon(
          key: ValueKey('refine-reply-${text.hashCode}'),
          onPressed: () => actions.refineReply(text, 'final'),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Text('再調一下', style: AppTypography.labelMedium),
        ),
      ),
    );
  }

  List<String> _extractSegments(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final matches = RegExp(r'[①②③④⑤💡]').allMatches(normalized).toList();
    if (matches.isEmpty) {
      return [normalized];
    }

    final segments = <String>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : normalized.length;
      final segment = normalized.substring(start, end).trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    return segments;
  }

  String? _extractSegmentReplyText(String segment) {
    final normalized = segment.replaceAll('\r\n', '\n').trim();
    final match =
        RegExp(r'^[①②③④⑤]\s*[^→\n]{0,80}\s*→\s*').firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final replyText = normalized
        .substring(match.end)
        .trim()
        .replaceAll(RegExp(r'^[「『"“]+|[」』"”]+$'), '');
    return replyText.isEmpty ? null : replyText;
  }

  /// 優先呈現結構化分段回覆；舊版 ①② 格式只保留相容。
  List<Widget> _recommendationContent() {
    final content = recommendation.content.trim();
    final structuredSegments = recommendation.replySegments
        .where((segment) => segment.reply.trim().isNotEmpty)
        .toList();
    if (structuredSegments.isNotEmpty) {
      return _structuredSegments(structuredSegments);
    }

    final segments = _extractSegments(content);
    if (segments.length <= 1) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(content, style: AppTypography.bodyLarge),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: AppHaptics.onPress(() {
              actions.copyRecommendationText(content, '已複製到剪貼簿');
            }),
            icon: const Icon(Icons.copy),
            label: const Text('複製推薦回覆'),
          ),
        ),
        _refineButton(content),
      ];
    }

    final widgets = <Widget>[];
    for (final segment in segments) {
      final trimmed = segment.trim();
      final isHint = trimmed.startsWith('💡');
      final replyText = isHint ? null : _extractSegmentReplyText(trimmed);

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHint
                ? AppColors.info.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: isHint
                ? Border.all(color: AppColors.info.withValues(alpha: 0.2))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trimmed,
                style: AppTypography.bodyMedium.copyWith(
                  color:
                      isHint ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
              if (!isHint && replyText != null && replyText.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      actions.copyRecommendationText(replyText, '已複製這句');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('複製這句', style: TextStyle(fontSize: 13)),
                  ),
                ),
                _refineButton(replyText),
              ],
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  List<Widget> _structuredSegments(List<ReplySegment> segments) {
    final widgets = <Widget>[
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(
          segments.length == 1
              ? '這是推薦訊息素材；下方保留引用，方便你確認 AI 接的是哪顆球。'
              : '建議拆成 ${segments.length} 則短訊息。每段都引用她的原句，也能單獨複製。',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundPrimary.withValues(alpha: 0.88),
            height: 1.45,
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final source = segment.sourceMessage.trim();
      final reply = segment.reply.trim();
      final reason = segment.reason.trim();
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    size: 16,
                    color: AppColors.ctaStart,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      segment.displayLabel,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ctaStart,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (source.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: AppColors.ctaStart.withValues(alpha: 0.45),
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    source,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                reply,
                style: AppTypography.bodyLarge.copyWith(height: 1.45),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton.icon(
                  onPressed: () {
                    actions.copyRecommendationText(reply, '已複製第 ${i + 1} 句');
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    foregroundColor: AppColors.onBackgroundPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                    color: AppColors.coachAccent,
                  ),
                  label: Text(
                    segments.length == 1 ? '複製這句' : '複製第 ${i + 1} 句',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _refineButton(reply),
            ],
          ),
        ),
      );
    }

    final allContent = recommendation.content.trim();
    if (segments.length > 1 && allContent.isNotEmpty) {
      widgets.add(
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: AppHaptics.onPress(() {
              actions.copyRecommendationText(allContent, '已複製整組訊息');
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(
              '複製整組訊息',
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// 推薦理由說明卡：icon 座＋灰字，取代舊 📝/🧠 emoji 前綴行。
  Widget _recommendationNote() {
    final reason = recommendation.reason.trim();
    final psychology = recommendation.psychology.trim();
    if (reason.isEmpty && psychology.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.22),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 16,
              color: AppColors.coachAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reason.isNotEmpty)
                  Text(
                    reason,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                if (psychology.isNotEmpty && psychology != reason) ...[
                  if (reason.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    psychology,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
