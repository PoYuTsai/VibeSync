// lib/features/analysis/presentation/widgets/reply_refine_sheet.dart
//
// 「再調一下」面板。使用者拿到一則 AI 回覆後，就地用快捷或自由指令調語氣長短，
// 可以連續迭代：上一輪的結果直接變成下一輪要調的原句。
//
// 這個 widget 只負責呈現與互動，**不自己打網路、不自己扣費**。實際請求由呼叫端
// 透過 [onRefine] 提供，因為 exactly-once 帳本（requestId／replay）與額度都必須
// 留在 analysis_screen 那條唯一路徑上；面板若自己再開一條，就等於多一個可以重複
// 扣費的入口。

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 與 server `MAX_REFINE_INSTRUCTION_LENGTH` 對齊。輸入框先擋一次，server 仍會
/// 再驗一次（超長是 400、0 扣費）。
const int kMaxRefineInstructionLength = 80;

/// 與 server `REFINE_FREE_DAILY_LIMIT` 對齊；真相源在 server，實際剩餘次數一律
/// 以回應帶回來的數字為準，這裡只在還沒問過 server 時用來寫文案。
const int kRefineFreeDailyLimit = 10;

/// 快捷指令刻意只留「收斂」方向。
///
/// 不放「更直接一點」：容易被讀成改變承諾／邀約／界線的方向，與 prompt 的安全
/// 條款正面衝突。也不放「更撩一點」這種升溫捷徑——技巧感漏出來是壞案例最主要的
/// 成因之一。
const kRefineQuickInstructions = <String>[
  '太油了，自然一點',
  '短一點',
  '白話一點',
  '語氣溫和一點',
  '換個說法',
];

/// 一次成功微調的結果。`freeRemaining` / `chargedQuota` 由 server 回應決定，
/// client 不自己推算，否則面板顯示的免費次數會和真正扣費的那一本帳分岔。
class ReplyRefineOutcome {
  const ReplyRefineOutcome({
    required this.refinedText,
    this.requestId,
    this.freeRemaining,
    this.freeDailyLimit,
    this.chargedQuota = false,
  });

  final String refinedText;
  final String? requestId;
  final int? freeRemaining;
  final int? freeDailyLimit;
  final bool chargedQuota;
}

/// 呼叫端要送出的一次微調。丟出例外代表這次失敗（面板顯示訊息、版本堆疊不動）；
/// 回 null 代表呼叫端自己決定不送（例如同意條款被拒絕），同樣不算一個版本。
typedef ReplyRefineRequest = Future<ReplyRefineOutcome?> Function({
  required String currentText,
  required String instruction,
});

/// 使用者關掉面板時帶走的東西。[isRefined] 為 false 代表他最後選的還是原句。
class ReplyRefineSheetResult {
  const ReplyRefineSheetResult({
    required this.adoptedText,
    required this.isRefined,
    this.requestId,
  });

  final String adoptedText;
  final bool isRefined;

  /// 產生 [adoptedText] 那一次微調的 requestId；選回原句時為 null。
  final String? requestId;
}

Future<ReplyRefineSheetResult?> showReplyRefineSheet(
  BuildContext context, {
  required String originalText,
  required ReplyRefineRequest onRefine,
  int? freeRemaining,
  int freeDailyLimit = kRefineFreeDailyLimit,
  String? restoredText,
  String? restoredRequestId,
}) {
  return showModalBottomSheet<ReplyRefineSheetResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ReplyRefineSheet(
      originalText: originalText,
      onRefine: onRefine,
      freeRemaining: freeRemaining,
      freeDailyLimit: freeDailyLimit,
      restoredText: restoredText,
      restoredRequestId: restoredRequestId,
    ),
  );
}

class ReplyRefineSheet extends StatefulWidget {
  const ReplyRefineSheet({
    super.key,
    required this.originalText,
    required this.onRefine,
    this.freeRemaining,
    this.freeDailyLimit = kRefineFreeDailyLimit,
    this.restoredText,
    this.restoredRequestId,
  });

  final String originalText;
  final ReplyRefineRequest onRefine;

  /// 已知的今日剩餘免費次數；null 代表今天還沒問過 server。
  final int? freeRemaining;
  final int freeDailyLimit;

  /// 24 小時內對同一則回覆調過的最後一版。有的話直接接著調，不用重來。
  final String? restoredText;
  final String? restoredRequestId;

  @override
  State<ReplyRefineSheet> createState() => _ReplyRefineSheetState();
}

class _RefineVersion {
  const _RefineVersion({
    required this.label,
    required this.text,
    this.requestId,
  });

  final String label;
  final String text;
  final String? requestId;
}

class _ReplyRefineSheetState extends State<ReplyRefineSheet> {
  static const _submitDebounce = Duration(milliseconds: 600);

  final TextEditingController _instructionController = TextEditingController();
  late final List<_RefineVersion> _versions = [
    _RefineVersion(label: '原句', text: widget.originalText.trim()),
  ];

  int _selectedIndex = 0;
  bool _inFlight = false;
  String? _errorText;
  int? _freeRemaining;
  late int _freeDailyLimit = widget.freeDailyLimit;
  DateTime? _lastSubmitAt;

  /// 上一次送出失敗過，因此 [_freeRemaining] 不再可信。
  ///
  /// server 有一條真實路徑會先授權免費額度、之後結算才失敗（額度表沒有退款
  /// 函式，這是已知取捨）。此時畫面上的「今天還有 N 次免費」已經是舊的，繼續
  /// 顯示它等於在扣費前給出錯誤的揭露：使用者以為下一次免費，實際會扣 1 則。
  bool _freeRemainingStale = false;

  @override
  void initState() {
    super.initState();
    _freeRemaining = widget.freeRemaining;
    final restored = widget.restoredText?.trim();
    if (restored != null &&
        restored.isNotEmpty &&
        restored != _versions.first.text) {
      _versions.add(
        _RefineVersion(
          label: '上次調過的',
          text: restored,
          requestId: widget.restoredRequestId,
        ),
      );
      _selectedIndex = _versions.length - 1;
    }
  }

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  _RefineVersion get _selected => _versions[_selectedIndex];

  String get _quotaLine {
    if (_freeRemainingStale) {
      return '免費次數待確認，下一次微調可能會使用 1 則。';
    }
    final remaining = _freeRemaining;
    if (remaining == null) {
      return '今天前 $_freeDailyLimit 次微調免費。';
    }
    if (remaining > 0) {
      return '今天還有 $remaining 次免費微調。';
    }
    return '今天的免費次數用完了，接下來每次微調使用 1 則。';
  }

  /// 連點的源頭在這裡掐掉：`_inFlight` 同步先設起來，時間窗再擋住送出成功後
  /// 立刻補上的第二下。不靠 server 節流兜底——那會變成使用者已經被扣了才擋。
  bool get _canSubmit {
    if (_inFlight) return false;
    final last = _lastSubmitAt;
    if (last != null && DateTime.now().difference(last) < _submitDebounce) {
      return false;
    }
    return true;
  }

  Future<void> _refine(String instruction) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty || !_canSubmit) return;

    setState(() {
      _inFlight = true;
      _errorText = null;
      _lastSubmitAt = DateTime.now();
    });

    try {
      final outcome = await widget.onRefine(
        currentText: _selected.text,
        instruction: trimmed,
      );
      if (!mounted) return;
      if (outcome == null) {
        setState(() => _inFlight = false);
        return;
      }
      final refined = outcome.refinedText.trim();
      setState(() {
        _inFlight = false;
        if (refined.isNotEmpty) {
          _versions.add(
            _RefineVersion(
              label: '第 ${_versions.length} 版',
              text: refined,
              requestId: outcome.requestId,
            ),
          );
          _selectedIndex = _versions.length - 1;
          _instructionController.clear();
        }
        if (outcome.freeRemaining != null) {
          _freeRemaining = outcome.freeRemaining;
          _freeRemainingStale = false;
        }
        if (outcome.freeDailyLimit != null) {
          _freeDailyLimit = outcome.freeDailyLimit!;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inFlight = false;
        _errorText = _messageFor(error);
        // 失敗不代表沒扣到免費額度：server 可能已授權、結算才失敗。餘額改標
        // 成待確認，下一次的權威回應會覆蓋它。
        _freeRemainingStale = true;
      });
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    const prefix = 'AnalysisException: ';
    if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    return '這次沒有調成功，請再試一次。';
  }

  void _adopt() {
    Navigator.of(context).pop(
      ReplyRefineSheetResult(
        adoptedText: _selected.text,
        isRefined: _selectedIndex > 0,
        requestId: _selected.requestId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.86,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BrandPageBackground(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '再調一下',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _quotaLine,
                    key: const ValueKey('reply-refine-quota-line'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('reply-refine-body'),
                      padding: EdgeInsets.zero,
                      children: [
                        _CurrentVersionCard(
                          label: _selected.label,
                          text: _selected.text,
                        ),
                        if (_versions.length > 1) ...[
                          const SizedBox(height: 16),
                          Text(
                            '版本',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (var i = 0; i < _versions.length; i++)
                            _VersionTile(
                              key: ValueKey('reply-refine-version-$i'),
                              version: _versions[i],
                              selected: i == _selectedIndex,
                              onTap: _inFlight
                                  ? null
                                  : () => setState(() => _selectedIndex = i),
                            ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final instruction in kRefineQuickInstructions)
                              ActionChip(
                                key: ValueKey('reply-refine-quick-$instruction'),
                                label: Text(instruction),
                                onPressed: _inFlight
                                    ? null
                                    : () => _refine(instruction),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('reply-refine-instruction'),
                          controller: _instructionController,
                          enabled: !_inFlight,
                          maxLength: kMaxRefineInstructionLength,
                          maxLines: 2,
                          minLines: 1,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: '想怎麼調？例如「別提星期六」',
                            hintStyle: AppTypography.bodyMedium.copyWith(
                              color: AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.6),
                            ),
                            filled: true,
                            fillColor:
                                AppColors.brandInk.withValues(alpha: 0.4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          textInputAction: TextInputAction.send,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _inFlight ? null : _refine,
                        ),
                        if (_errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _errorText!,
                              key: const ValueKey('reply-refine-error'),
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: const ValueKey('reply-refine-submit'),
                            onPressed: _inFlight ||
                                    _instructionController.text.trim().isEmpty
                                ? null
                                : () => _refine(_instructionController.text),
                            icon: _inFlight
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.tune_rounded),
                            label: Text(_inFlight ? '調整中…' : '照這個指令調'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('reply-refine-adopt'),
                      onPressed: _inFlight ? null : _adopt,
                      child: const Text('用這個版本'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentVersionCard extends StatelessWidget {
  const _CurrentVersionCard({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            key: const ValueKey('reply-refine-current-text'),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    super.key,
    required this.version,
    required this.selected,
    required this.onTap,
  });

  final _RefineVersion version;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.ctaStart.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.ctaStart.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                version.label,
                style: AppTypography.caption.copyWith(
                  color: selected
                      ? AppColors.ctaStart
                      : AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  version.text,
                  // 選中的版本展開全文（2026-08-16 Eric：橘色那列字被切掉），
                  // 未選中維持單行省略，清單才不會爆長。
                  maxLines: selected ? null : 1,
                  overflow: selected ? null : TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
