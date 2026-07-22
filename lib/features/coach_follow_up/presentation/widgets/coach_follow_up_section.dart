// Phase E Task 6 — CoachFollowUpSection：對象頁教練區薄 wrapper。
//
// Spec 5 的罐頭卡 engine（chip → input sheet 表單 → controller.generate →
// result card）整段退場，改掛統一教練介面 CoachSurface（partner scope，
// 串流/多輪/釐清/forceAnswer/outcome 全能力）。本 widget 只剩：
//   標題＋三情境 chip＋caption＋openCoach entry＋CoachSurface。
//
// chip 點擊「只種入」CoachSurface 的 lifecyclePhase＋prefill＋focus token
// （focusRequestToken 遞增觸發 didUpdateWidget 的 prefill/focus 機制）——
// 送出永遠是用戶按鈕行為，絕無 auto-send（quota 安全硬規則）。consent
// gate 也隨之收斂進 CoachSurface 的 _ask/_forceAnswer，本層不再自彈。
//
// Phase F 已刪除舊 engine 死叢集（providers/api/hint builder/resolver/
// input sheet/chip row/result card）。保留的只有：result entity（Hive 模型）、
// repository read-bridge（Phase D）、phase enum（wire format）與本薄 wrapper；
// telemetry 契約由檔尾 sealed 家族的 deep-link 意圖事件沿用。

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../coach_chat/domain/entities/coach_scope.dart';
import '../../../coach_chat/presentation/widgets/coach_surface.dart';

// ── 三情境 chip（Task 6 拍板；phase 字串隨 wire lifecyclePhase 原樣送）──

typedef _CoachEntryChip = ({String phase, String label, String prefill});

const _chips = <_CoachEntryChip>[
  (phase: 'chatStalled', label: '聊天卡住了', prefill: '我們聊天卡住了，接下來該怎麼辦？'),
  (phase: 'prepareInvite', label: '想約她出來', prefill: '我想約她出來，該怎麼開口比較自然？'),
  (phase: 'postDate', label: '約完會之後', prefill: '剛約完會，接下來要怎麼經營比較好？'),
];

// ── Section widget ────────────────────────────────────────────────────────

class CoachFollowUpSection extends StatefulWidget {
  final String partnerId;

  /// 凍結參數：薄 wrapper 不再產生舊 telemetry 事件（chip 不再觸發生成）。
  /// 保留只為掛載介面相容；deep-link 意圖事件由 orchestrator 直接走 stub
  /// sink，不經此參數（Phase F 退場）。
  final ValueChanged<CoachFollowUpTelemetryEvent>? onTelemetry;
  final Future<void> Function()? onQuotaExceeded;
  final Key? openCoachEntryAnchorKey;
  final bool openCoachInputRequested;
  final bool compactPracticePresentation;

  const CoachFollowUpSection({
    super.key,
    required this.partnerId,
    this.onTelemetry,
    this.onQuotaExceeded,
    this.openCoachEntryAnchorKey,
    this.openCoachInputRequested = false,
    this.compactPracticePresentation = false,
  });

  @override
  State<CoachFollowUpSection> createState() => _CoachFollowUpSectionState();
}

// KeepAlive：section 掛在 partner 詳情頁的 lazy ListView 深處，滑出
// viewport + cacheExtent 會被回收。使用者可見狀態（CoachSurface 輸入
// 草稿與 controller、chip 選中高亮、_lastAskedQuestion）都活在這棵子樹
// 的本地 State，回收即丟失；initState 的 auto-focus 排程也會在重新
// mount 時重跑。保活整個 section 一併保住 CoachSurface。
class _CoachFollowUpSectionState extends State<CoachFollowUpSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _pendingPhase;
  String? _prefill;
  int _focusToken = 0;
  bool _openingQuotaPaywall = false;
  bool _didAutoFocusCoachInput = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoFocusIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CoachFollowUpSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.partnerId != oldWidget.partnerId) {
      // 原地切換對象 → auto-focus 閂鎖歸零，讓新對象的請求能再發一次
      // （第三層防禦；parent/orchestrator 已各自守衛，此處保持一致性）。
      // 注意：flag 未收回的 carry-over（true→true）不重發——parent/
      // orchestrator 負責逐對象收回 flag。
      _didAutoFocusCoachInput = false;
    }
    if (widget.openCoachInputRequested &&
        !oldWidget.openCoachInputRequested) {
      _scheduleAutoFocusIfNeeded();
    }
  }

  /// 舊行為＝自動開 input sheet；新行為＝收到 openCoachInputRequested
  /// （首幀即帶入、或中途 false→true transition）後 bump focus token，
  /// 讓 CoachSurface 輸入框取得焦點（無 phase、無 prefill）。
  void _scheduleAutoFocusIfNeeded() {
    if (!widget.openCoachInputRequested || _didAutoFocusCoachInput) return;
    _didAutoFocusCoachInput = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onOpenCoachTap();
    });
  }

  void _onChipTap(_CoachEntryChip chip) {
    setState(() {
      _pendingPhase = chip.phase;
      _prefill = chip.prefill;
      _focusToken += 1;
    });
  }

  void _onOpenCoachTap() {
    setState(() {
      _pendingPhase = null;
      _prefill = null;
      _focusToken += 1;
    });
  }

  /// paywall 只開一次的防抖（沿用舊 section 行為）；CoachSurface 的
  /// ref.listen 在 quota 錯誤時同步呼叫，這裡排到 post-frame 再 push。
  void _handleQuotaExceeded() {
    if (_openingQuotaPaywall) return;
    _openingQuotaPaywall = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _openingQuotaPaywall = false;
        return;
      }
      try {
        await widget.onQuotaExceeded?.call();
      } finally {
        if (mounted) {
          _openingQuotaPaywall = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 契約要求。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.compactPracticePresentation)
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: AppColors.ctaStart,
              ),
              const SizedBox(width: 8),
              Text(
                '還沒有素材？先練習一下',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        else
          Text(
            '教練跟進',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _chips.map((chip) {
            return ChoiceChip(
              label: Text(chip.label),
              selected: _pendingPhase == chip.phase,
              // showCheckmark: false avoids the dark-bg ghost-checkmark
              // artifact that bit ProfileChipSection (memory ref).
              showCheckmark: false,
              onSelected: (_) => _onChipTap(chip),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 6),
        Text(
          '釐清免費，正式建議才扣 1 則',
          style: AppTypography.caption.copyWith(
            color: AppColors.glassTextSecondary,
          ),
        ),
        if (!widget.compactPracticePresentation) ...[
          const SizedBox(height: 12),
          _OpenCoachEntry(
            key: widget.openCoachEntryAnchorKey,
            onTap: _onOpenCoachTap,
          ),
        ],
        const SizedBox(height: 12),
        CoachSurface(
          scope: CoachScope.partner(widget.partnerId),
          onQuotaExceeded:
              widget.onQuotaExceeded == null ? null : _handleQuotaExceeded,
          focusRequestToken: _focusToken,
          prefillText: _prefill,
          lifecyclePhase: _pendingPhase,
        ),
      ],
    );
  }
}

class _OpenCoachEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenCoachEntry({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: AppColors.glassTextSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '或直接問教練一個問題…',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Telemetry 契約（sealed 家族，deep-link 意圖事件在用）─────────────────

sealed class CoachFollowUpTelemetryEvent {
  const CoachFollowUpTelemetryEvent();
}

/// deep-link focusAction=openCoachInput 意圖時點記錄（orchestrator 定位完成
/// 後、翻 parent flag 前發出）。無欄位：phase 恆為 openCoach；用戶自由文字
/// 只存在於 CoachSurface 輸入框內、絕不隨 telemetry 外流。
class CoachOpenCoachIntentEvent extends CoachFollowUpTelemetryEvent {
  const CoachOpenCoachIntentEvent();
}
