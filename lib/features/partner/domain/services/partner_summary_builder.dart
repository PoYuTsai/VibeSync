import 'package:characters/characters.dart';

import '../../../conversation/domain/entities/conversation.dart';
import '../entities/partner.dart';
import '../extensions/partner_aggregates.dart';

/// Composes a compact partner-context summary that the AI prompt prepends
/// before each `analyze-chat` call. Output is grapheme-safe truncated to
/// `kHardCharCap` so we never overrun the AI prompt budget mid-emoji.
///
/// The builder is stateless — `analyze-chat` rebuilds it on every call so
/// the partner aggregate stays fresh with the latest conversation snapshot.
class PartnerSummaryBuilder {
  static const int kHardCharCap = 1500;
  static const int kServerCodeUnitCap = 2000;
  static const int kTopNotes = 5;
  static const String _truncationMarker = '... [truncated]';

  String build({
    required Partner partner,
    required List<Conversation> conversations,
  }) {
    if (_hasOwnerMismatch(partner, conversations)) return '';

    if (conversations.isEmpty) {
      return _renderHeader(partner, '（尚無對話記錄）');
    }

    final aggregate = partner.aggregateOver(conversations);
    final hasParsedSnapshot = aggregate.unionInterests.isNotEmpty ||
        aggregate.unionTraits.isNotEmpty ||
        aggregate.unionNotes != null;

    if (!hasParsedSnapshot) {
      if (conversations.length == 1) {
        return _renderHeader(partner, '這是你跟此對象的第一次對話');
      }
      return _renderHeader(partner, '（過往對話尚未分析）');
    }

    final buffer = StringBuffer()
      ..writeln('[對象背景：${_partnerName(partner)}]')
      ..writeln(
        '- 累計對話：${conversations.length} 段，'
        '${aggregate.totalMessages} 則訊息，'
        '最後互動 ${_formatDate(aggregate.lastInteraction)}',
      );

    if (aggregate.latestHeat != null) {
      buffer.writeln('- 最近熱度：${aggregate.latestHeat}');
    }
    if (aggregate.unionInterests.isNotEmpty) {
      buffer.writeln('- 興趣：${aggregate.unionInterests.join('、')}');
    }
    if (aggregate.unionTraits.isNotEmpty) {
      buffer.writeln('- 性格：${aggregate.unionTraits.join('、')}');
    }

    final customNote = partner.customNote?.trim();
    if (customNote != null && customNote.isNotEmpty) {
      buffer.writeln('- 你的備註：$customNote');
    } else if (aggregate.unionNotes != null) {
      final pastNotes = _topNNotes(aggregate.unionNotes!);
      if (pastNotes.isNotEmpty) {
        buffer.writeln('- 過往備註：${pastNotes.join('；')}');
      }
    }

    buffer.writeln('- 注意：以上是整體背景，當前對話內容仍以本次訊息為主');

    return _capWithGraphemeSafeTruncation(buffer.toString());
  }

  bool _hasOwnerMismatch(Partner partner, List<Conversation> conversations) {
    final partnerOwner = partner.ownerUserId;
    if (partnerOwner == null) return false;
    return conversations.any(
      (c) => c.ownerUserId != null && c.ownerUserId != partnerOwner,
    );
  }

  String _renderHeader(Partner partner, String body) {
    return _capWithGraphemeSafeTruncation(
      '[對象背景：${_partnerName(partner)}]\n$body',
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

  /// `aggregate.unionNotes` is the chronological-oldest-first newline-joined
  /// dump from `PartnerAggregates`. Take the most recent N (last N lines).
  List<String> _topNNotes(String unionNotes) {
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

  /// Truncate at grapheme-cluster boundaries — never on raw UTF-16 code
  /// units. The second code-unit cap mirrors the Edge Function sanitizer,
  /// so emoji-heavy summaries cannot pass the client cap but fail server-side.
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

    final marker = _truncationMarker;
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
