import 'package:characters/characters.dart';

import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/extensions/partner_aggregates.dart';

/// 新話題專用的對象作戰板脈絡（2026-07-24 計畫 §9）。
///
/// 刻意不重用 `PartnerSummaryBuilder.build()`：那份輸出綁著 analyze 的
/// 「當前對話優先」語意與「尚無紀錄」header，直接搬會讓 server 把
/// placeholder 誤判成實質素材。這裡沒有 actionable signal 時 promptText
/// 一律 null，材料 readiness 由呼叫端以 [hasActionableSignals] 判斷。
class NewTopicPartnerContext {
  const NewTopicPartnerContext({
    required this.promptText,
    required this.hasActionableSignals,
    required this.hasHeatSignal,
    required this.hasInterestSignals,
    required this.hasTraitSignals,
    required this.hasNoteSignals,
  });

  static const empty = NewTopicPartnerContext(
    promptText: null,
    hasActionableSignals: false,
    hasHeatSignal: false,
    hasInterestSignals: false,
    hasTraitSignals: false,
    hasNoteSignals: false,
  );

  final String? promptText;
  final bool hasActionableSignals;
  final bool hasHeatSignal;
  final bool hasInterestSignals;
  final bool hasTraitSignals;
  final bool hasNoteSignals;
}

class NewTopicPartnerContextBuilder {
  static const int kHardCharCap = 1500;
  static const int kServerCodeUnitCap = 2000;
  static const int kTopNotes = 5;
  static const String _truncationMarker = '... [truncated]';

  NewTopicPartnerContext build({
    required Partner partner,
    required List<Conversation> conversations,
  }) {
    // Owner mismatch＝資料層防線破口，一律 blocked/empty，不送任何內容。
    if (_hasOwnerMismatch(partner, conversations)) {
      return NewTopicPartnerContext.empty;
    }

    final aggregate = partner.aggregateOver(conversations);
    final customNote = partner.customNote?.trim();
    final hasCustomNote = customNote != null && customNote.isNotEmpty;
    final aggregateNotes =
        hasCustomNote ? const <String>[] : _topNNotes(aggregate.unionNotes);

    final hasHeatSignal = aggregate.latestHeat != null;
    final hasInterestSignals = aggregate.unionInterests.isNotEmpty;
    final hasTraitSignals = aggregate.unionTraits.isNotEmpty;
    final hasNoteSignals = hasCustomNote || aggregateNotes.isNotEmpty;
    final hasActionableSignals = hasHeatSignal ||
        hasInterestSignals ||
        hasTraitSignals ||
        hasNoteSignals;

    // 只有名稱、對話數、日期或 placeholder 不算實質素材：promptText 回
    // null，不得輸出「尚無紀錄」header 讓 server 誤判 material readiness。
    if (!hasActionableSignals) {
      return NewTopicPartnerContext.empty;
    }

    final buffer = StringBuffer()..writeln('[對象作戰板：${_partnerName(partner)}]');
    if (conversations.isNotEmpty) {
      buffer.writeln(
        '- 累計對話：${conversations.length} 段，'
        '最後互動 ${_formatDate(aggregate.lastInteraction)}',
      );
    }
    if (hasHeatSignal) {
      buffer.writeln('- 最近熱度：${aggregate.latestHeat}');
    }
    if (hasInterestSignals) {
      buffer.writeln('- 興趣：${aggregate.unionInterests.join('、')}');
    }
    if (hasTraitSignals) {
      buffer.writeln('- 性格：${aggregate.unionTraits.join('、')}');
    }
    if (hasCustomNote) {
      buffer.writeln('- 你的備註：$customNote');
    } else if (aggregateNotes.isNotEmpty) {
      buffer.writeln('- 過往備註：${aggregateNotes.join('；')}');
    }
    buffer.writeln('- 只可使用以上明確紀錄，不得猜補對方興趣');

    return NewTopicPartnerContext(
      promptText: _capWithGraphemeSafeTruncation(buffer.toString()),
      hasActionableSignals: true,
      hasHeatSignal: hasHeatSignal,
      hasInterestSignals: hasInterestSignals,
      hasTraitSignals: hasTraitSignals,
      hasNoteSignals: hasNoteSignals,
    );
  }

  bool _hasOwnerMismatch(Partner partner, List<Conversation> conversations) {
    final partnerOwner = partner.ownerUserId;
    if (partnerOwner == null) return false;
    return conversations.any(
      (c) => c.ownerUserId != null && c.ownerUserId != partnerOwner,
    );
  }

  String _partnerName(Partner partner) {
    final name = partner.name.trim();
    if (name.isNotEmpty) return name;
    final tail = partner.id.length >= 4
        ? partner.id.substring(partner.id.length - 4)
        : partner.id;
    return '對象 #$tail';
  }

  List<String> _topNNotes(String? unionNotes) {
    if (unionNotes == null) return const [];
    final lines = unionNotes.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.length <= kTopNotes) return lines;
    return lines.sublist(lines.length - kTopNotes);
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '未知';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Grapheme-safe 雙 cap（同 PartnerSummaryBuilder：1500 graphemes、
  /// 2000 UTF-16 code units 鏡射 server sanitizer）。
  String _capWithGraphemeSafeTruncation(String s) {
    final charCapped = _capByGraphemeCount(s, kHardCharCap);
    if (charCapped.length <= kServerCodeUnitCap) return charCapped;
    return _capByCodeUnits(charCapped, kServerCodeUnitCap);
  }

  String _capByGraphemeCount(String s, int cap) {
    final cs = s.characters;
    if (cs.length <= cap) return s;
    final keep = cap - _truncationMarker.characters.length;
    if (keep <= 0) {
      return _truncationMarker.characters.take(cap).toString();
    }
    return '${cs.take(keep)}$_truncationMarker';
  }

  String _capByCodeUnits(String s, int cap) {
    if (s.length <= cap) return s;

    const marker = _truncationMarker;
    final keepLimit = cap - marker.length;
    if (keepLimit <= 0) {
      return marker.characters
          .takeWhile((cluster) => cluster.length <= cap)
          .join();
    }

    final buffer = StringBuffer();
    var used = 0;
    for (final cluster in s.characters) {
      final next = used + cluster.length;
      if (next > keepLimit) break;
      buffer.write(cluster);
      used = next;
    }
    return '${buffer.toString()}$marker';
  }
}
