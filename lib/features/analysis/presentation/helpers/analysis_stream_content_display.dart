/// AnalyzeChat 串流事件 → 顯示內容的映射（presentation-owned）。
///
/// wire decode（NDJSON 行 → event map）留在 data 的
/// [AnalyzeStreamClient]；這裡負責事件分型、中文標題／內文、schema-leak
/// 顯示清洗。經 data-owned 的 [AnalysisStreamDisplayMapper] seam 注入，
/// production 與測試都走同一條路。
library;

import 'dart:convert';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/enthusiasm_level.dart';
import '../../data/services/analyze_stream_client.dart'
    show
        AnalysisStreamContent,
        AnalysisStreamContentKind,
        AnalysisStreamDisplayMapper;

class AnalysisStreamContentDisplayMapper
    implements AnalysisStreamDisplayMapper {
  const AnalysisStreamContentDisplayMapper();

  @override
  AnalysisStreamContent? contentFromEvent(Map<String, dynamic> event) {
    final type = _stringField(event['type']);
    switch (type) {
      case 'analysis.decision':
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.decision,
          title: _stringField(event['nextStepTitle']) ?? '下一步策略',
          body: _joinNonEmpty([
            _stringField(event['nextStepBody']) ??
                _stringField(event['nextStep']),
            _prefix('建議', _stringField(event['doThis'])),
            _prefix('避免', _stringField(event['avoidThis'])),
          ]),
          rawEvent: event,
        );
      case 'analysis.reply_option':
        final style = _stringField(event['style']) ??
            _stringField(event['selectedStyle']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.replyOption,
          title: '回覆選項：${_styleLabel(style)}',
          body: _joinNonEmpty([
            _stringField(event['message']),
            _prefix(
              '思路',
              _stringField(event['reason']) ?? _stringField(event['approach']),
            ),
            _prefix(
              '對應',
              _stringField(event['quotedContext']) ??
                  _stringField(event['sourceMessage']),
            ),
          ]),
          tag: style,
          rawEvent: event,
        );
      case 'analysis.metrics':
        final score = _numberField(
          event['heat'] ?? event['enthusiasmScore'] ?? event['score'],
        );
        final topicDepth = _recordField(event['topicDepth']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.metrics,
          title: '互動指標',
          body: _joinNonEmpty([
            // 串流 heat 是 raw（0–100）：先套與 server finalize 相同的
            // × 0.9 校準，可見分母固定 90，避免與最終分數尺度打架。
            score == null
                ? null
                : '本次投入：${calibrateVisibleInvestment(score)}'
                    '/${AppConstants.investmentVisibleMax}',
            _prefix(
              '話題深度',
              _stringField(topicDepth?['suggestion']) ??
                  _stringField(topicDepth?['current']),
            ),
          ]),
          rawEvent: event,
        );
      case 'analysis.coach_hint':
        final hint = event['coachActionHint'];
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.coachHint,
          title: '教練提示',
          body: _stringify(hint) ??
              _joinNonEmpty([
                _stringField(event['title']),
                _stringField(event['message']),
                _stringField(event['body']),
              ]),
          rawEvent: event,
        );
      case 'analysis.report_section':
        final section = _stringField(event['section']);
        final body = _reportSectionBody(section, event);
        if (body == null) return null;
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.reportSection,
          title: _sectionLabel(section),
          body: body,
          tag: section,
          rawEvent: event,
        );
      default:
        return null;
    }
  }

  static String _styleLabel(String? style) {
    switch (style) {
      case 'extend':
        return '延伸話題';
      case 'resonate':
        return '共鳴回應';
      case 'tease':
        return '輕鬆挑逗';
      case 'humor':
        return '幽默回覆';
      case 'coldRead':
        return '冷讀觀察';
      default:
        return '可用回覆';
    }
  }

  static String _sectionLabel(String? section) {
    switch (section) {
      case 'strategy':
        return '深度策略';
      case 'warnings':
        return '注意事項';
      case 'psychology':
        return '心理訊號';
      case 'topicDepth':
        return '話題深度';
      case 'gameStage':
        return '關係階段';
      case 'status':
      case 'gameStage.status':
        return '關係狀態';
      default:
        return '完整分析段落';
    }
  }

  static String? _prefix(String label, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return '$label：${value.trim()}';
  }

  static String _joinNonEmpty(Iterable<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  static String? _stringField(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String? displayText(dynamic value) {
    final raw = _stringField(value);
    if (raw == null) return null;
    final sanitized = _sanitizeSchemaLeakText(raw).trim();
    return sanitized.isEmpty ? null : sanitized;
  }

  static int? _numberField(dynamic value) {
    if (value is num && value.isFinite) return value.round();
    return null;
  }

  static Map<String, dynamic>? _recordField(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String? _stringify(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = _stringField(value);
      if (trimmed == null) return null;
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          final formatted = _stringify(decoded);
          if (formatted != null && formatted.trim().isNotEmpty) {
            return formatted;
          }
        } on FormatException {
          // Fall through to the original text.
        }
      }
      return trimmed;
    }
    if (value is List) {
      final joined = value
          .map(_stringify)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .join('\n');
      return joined.isEmpty ? null : joined;
    }
    if (value is Map) {
      final direct = _joinNonEmpty([
        _stringField(value['title']),
        _stringField(value['message']),
        _stringField(value['body']),
        _stringField(value['summary']),
        _stringField(value['suggestion']),
      ]);
      if (direct.isNotEmpty) return direct;
      final structured = _formatStructuredMap(value);
      if (structured != null) return structured;
      return null;
    }
    return value.toString();
  }

  static String? _formatStructuredMap(Map value) {
    final lines = <String>[];
    final usedKeys = <String>{};

    void add(String key, String label) {
      if (!value.containsKey(key)) return;
      final formatted = _formatStructuredValueForKey(key, value[key]);
      if (formatted == null || formatted.isEmpty) return;
      usedKeys.add(key);
      lines.add('$label：$formatted');
    }

    add('subtext', '她話裡的意思');
    add('qualificationSignal', '主動投入訊號');
    add('current', '目前狀態');
    add('status', '狀態');
    add('suggestion', '建議');
    add('nextStep', '下一步');
    add('catchablePoint', '可接的球');
    add('read', '判讀');
    add('microMove', '微行動');
    add('avoid', '先避免');
    add('confidence', '信心');
    add('interests', '她的興趣/偏好');
    add('traits', '她的特質');
    add('notes', '補充觀察');

    value.forEach((key, rawValue) {
      final keyText = key.toString();
      if (usedKeys.contains(keyText)) return;
      final formatted = _formatStructuredValue(rawValue);
      if (formatted == null || formatted.isEmpty) return;
      lines.add(formatted);
    });

    final joined = lines.join('\n');
    return joined.trim().isEmpty ? null : joined;
  }

  static String? _reportSectionBody(
    String? section,
    Map<String, dynamic> event,
  ) {
    final rawValue = event.containsKey('payload')
        ? event['payload']
        : event.containsKey('content')
            ? event['content']
            : event['message'];
    final formatted = _stringify(rawValue);
    if (formatted == null || formatted.trim().isEmpty) return null;
    return _formatReportSectionScalar(section, formatted);
  }

  static String? _formatReportSectionScalar(String? section, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final sectionKey = section?.trim();
    final statusLabel = _schemaStatusLabel(trimmed);
    if (statusLabel != null) {
      switch (sectionKey) {
        case 'status':
        case 'gameStage.status':
          return statusLabel;
        case 'gameStage':
          return '狀態：$statusLabel';
        default:
          return null;
      }
    }

    final currentLabel = _schemaCurrentLabel(trimmed);
    if (currentLabel != null) {
      switch (sectionKey) {
        case 'gameStage':
        case 'gameStage.current':
          return '目前狀態：$currentLabel';
        case 'topicDepth':
        case 'topicDepth.current':
          return '目前層次：$currentLabel';
        default:
          return null;
      }
    }

    return _sanitizeSchemaLeakText(trimmed);
  }

  static String? _formatStructuredValueForKey(String key, dynamic value) {
    switch (key) {
      case 'interests':
      case 'traits':
      case 'notes':
        if (value is List) {
          final joined = value
              .map(_stringify)
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .join('、');
          return joined.isEmpty ? null : joined;
        }
        break;
    }

    final formatted = _formatStructuredValue(value);
    if (formatted == null || formatted.isEmpty) return null;
    switch (key) {
      case 'status':
        return _schemaStatusLabel(formatted) ?? formatted;
      case 'current':
        return _schemaCurrentLabel(formatted) ?? formatted;
      default:
        return formatted;
    }
  }

  static String _sanitizeSchemaLeakText(String value) {
    var text = value.trim();
    if (text.isEmpty) return text;

    text = text.replaceAllMapped(
      RegExp(r'\bpersonal\s*階段', caseSensitive: false),
      (_) => '個人層階段',
    );
    text = text.replaceAllMapped(
      RegExp(r'(^|[^A-Za-z])normal(?=([^A-Za-z]|$))', caseSensitive: false),
      (match) => '${match.group(1) ?? ''}維持節奏',
    );

    return _replaceSchemaListFields(text);
  }

  static String _replaceSchemaListFields(String text) {
    final schemaLabels = <String, String>{
      'interests': '她的興趣/偏好',
      'traits': '她的特質',
      'notes': '補充觀察',
    };
    final schemaFieldPattern = RegExp(
      r'''["']?(interests|traits|notes)["']?\s*[:：]\s*(\[[^\]]*\]|[^,\n]+)\s*,?''',
      caseSensitive: false,
    );
    final matches = schemaFieldPattern.allMatches(text).toList();
    if (matches.isEmpty) return text;

    final leftover = text
        .replaceAll(schemaFieldPattern, '')
        .replaceAll(RegExp(r'[\s,，{}]+'), '');
    if (matches.length > 1 && leftover.isEmpty) {
      return matches.map((match) {
        final key = match.group(1)!.toLowerCase();
        final rawValue = match.group(2) ?? '';
        return '${schemaLabels[key]}：${_humanizeSchemaList(rawValue)}';
      }).join('\n');
    }

    return text.replaceAllMapped(schemaFieldPattern, (match) {
      final key = match.group(1)!.toLowerCase();
      final rawValue = match.group(2) ?? '';
      return '${schemaLabels[key]}：${_humanizeSchemaList(rawValue)}';
    });
  }

  static String _humanizeSchemaList(String value) {
    var text = value.trim();
    if (text.endsWith(',')) {
      text = text.substring(0, text.length - 1).trim();
    }
    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1);
    }

    final items = text
        .split(RegExp(r'[,，]'))
        .map((item) => item.replaceAll(RegExp(r'''["']'''), '').trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    return items.isEmpty ? value.trim() : items.join('、');
  }

  static String? _formatStructuredValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? '有' : '沒有';
    if (value is num && value.isFinite) return value.toString();
    if (value is String) return _stringify(value);
    if (value is List || value is Map) return _stringify(value);
    return value.toString();
  }

  static String? _schemaStatusLabel(String value) {
    switch (value.trim()) {
      case 'normal':
        return '維持節奏';
      case 'stuckFriend':
        return '互動偏平';
      case 'canAdvance':
        return '可以推進';
      case 'shouldRetreat':
        return '放慢一點';
      default:
        return null;
    }
  }

  static String? _schemaCurrentLabel(String value) {
    switch (value.trim()) {
      case 'opening':
        return '破冰階段';
      case 'premise':
        return '建立男女感';
      case 'qualification':
        return '互相評估';
      case 'narrative':
        return '展現個人魅力';
      case 'close':
        return '準備邀約';
      case 'facts':
      case 'event':
        return '事件層';
      case 'personal':
        return '個人層';
      case 'intimate':
        return '曖昧層';
      default:
        return null;
    }
  }
}
