// lib/features/learning/presentation/widgets/ebook_entry_list.dart
//
// 條目庫：一行一條（標題＋摘要），點開才展開內文。
//
// 為什麼需要它（2026-07-27）：教材有一半篇幅是「查的」不是「讀的」——開場
// 範例 8 型、對話拆解 13 案例、疑難情境 8 條、FAQ 12 條。攤成長捲會出現數千
// 字沒有落點的牆；做成列表，讀者先看得到全部有哪些，再決定點開哪一條。
//
// 無障礙與韌性約束：
//   - 每一條是 InkWell，Semantics 帶 expanded 狀態與「點兩下展開／收合」。
//   - 展開狀態除了箭頭方向，標題本身也換成強調色，不只靠圖示。
//   - 展開／收合狀態刻意不持久化：這是當下查閱行為，不是閱讀進度。
//   - 動畫用 AnimatedCrossFade，reduced motion 時直接切換。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';

class EbookEntryListView extends StatefulWidget {
  const EbookEntryListView({
    super.key,
    required this.block,
    required this.entryBlockBuilder,
    this.anchorEntryId,
    this.onAnchorConsumed,
  });

  final EbookEntryListBlock block;

  /// 由呼叫端負責渲染條目內的巢狀 block（才能把 quiz／checklist 的
  /// callback 一路傳下去）。
  final Widget Function(EbookBlock block) entryBlockBuilder;

  /// 從別章的交叉指涉跳過來時，要自動展開並捲到的那一條。
  final String? anchorEntryId;

  /// 展開並捲到定位之後回呼一次。
  final VoidCallback? onAnchorConsumed;

  @override
  State<EbookEntryListView> createState() => _EbookEntryListViewState();
}

class _EbookEntryListViewState extends State<EbookEntryListView> {
  final Set<String> _expanded = <String>{};
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _applyAnchor();
  }

  @override
  void didUpdateWidget(covariant EbookEntryListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchorEntryId != oldWidget.anchorEntryId) _applyAnchor();
  }

  /// 目標條目在這個庫裡才處理。條目 id 全域唯一（catalog 載入時驗證），
  /// 所以同一章的其他庫不會被誤觸。
  void _applyAnchor() {
    final anchor = widget.anchorEntryId;
    if (anchor == null) return;
    if (!widget.block.entries.any((entry) => entry.id == anchor)) return;
    _expanded.add(anchor);
    // 展開之後才有得捲：等這一幀 build 完再 ensureVisible。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _tileKeys[anchor]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
              ? Duration.zero
              : AppMotion.scroll,
          curve: AppMotion.easeOut,
          alignment: 0.1,
        );
      }
      widget.onAnchorConsumed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.block.title != null) ...[
          Text(
            widget.block.title!,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (widget.block.caption != null) ...[
          Text(
            widget.block.caption!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '共 ${widget.block.entries.length} 條，點開你需要的那一條',
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in widget.block.entries)
          Padding(
            key: _tileKeys.putIfAbsent(entry.id, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: 8),
            child: _EntryTile(
              entry: entry,
              isExpanded: _expanded.contains(entry.id),
              onToggle: () => setState(() {
                if (!_expanded.remove(entry.id)) _expanded.add(entry.id);
              }),
              entryBlockBuilder: widget.entryBlockBuilder,
            ),
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.isExpanded,
    required this.onToggle,
    required this.entryBlockBuilder,
  });

  final EbookEntry entry;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget Function(EbookBlock block) entryBlockBuilder;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final accent =
        isExpanded ? AppColors.ctaStart : AppColors.onBackgroundPrimary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isExpanded ? 0.06 : 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpanded
              ? AppColors.ctaStart.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: isExpanded,
            label:
                isExpanded ? '${entry.title}。點兩下收合。' : '${entry.title}。點兩下展開。',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style: AppTypography.bodyMedium.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                            if (entry.summary != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                entry.summary!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.onBackgroundSecondary
                                      .withValues(alpha: 0.8),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: isExpanded
                            ? AppColors.ctaStart
                            : AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 收合時完全不建子樹：一個庫有十幾條，全部預建等於沒有收合，
          // 也會讓「看不到內文」這件事只是視覺假象。
          AnimatedSize(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !isExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.10),
                          margin: const EdgeInsets.only(bottom: 16),
                        ),
                        for (final block in entry.blocks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: entryBlockBuilder(block),
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
