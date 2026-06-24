import 'package:supabase_flutter/supabase_flutter.dart';

/// 一則送進 practice-chat 的對話 turn。
class PracticeTurnDto {
  final String role; // 'user' | 'ai'
  final String text;
  const PracticeTurnDto({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

/// chat 模式成功回應。
class PracticeChatReply {
  final String reply;
  final int aiTurnCount;
  final bool sessionComplete;
  final int costDeducted;
  final int? monthlyRemaining;
  final int? dailyRemaining;

  const PracticeChatReply({
    required this.reply,
    required this.aiTurnCount,
    required this.sessionComplete,
    required this.costDeducted,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
}

/// debrief 模式成功回應（教練拆解卡）。
class PracticeDebrief {
  final String summary;
  final List<String> strengths;
  final List<String> watchouts;
  final String suggestedLine;
  final String vibe;
  final int? monthlyRemaining;
  final int? dailyRemaining;

  const PracticeDebrief({
    required this.summary,
    required this.strengths,
    required this.watchouts,
    required this.suggestedLine,
    required this.vibe,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
}

typedef PracticeChatInvoker = Future<PracticeInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

class PracticeInvokeResponse {
  final int status;
  final dynamic data;
  const PracticeInvokeResponse({required this.status, this.data});
}

class PracticeApiException implements Exception {
  final String message;
  final int? status;
  PracticeApiException(this.message, {this.status});
  @override
  String toString() => 'PracticeApiException($status): $message';
}

class PracticeQuotaExceededException implements Exception {
  final String message;
  final int? used;
  final int? limit;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  PracticeQuotaExceededException(
    this.message, {
    this.used,
    this.limit,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
  @override
  String toString() => 'PracticeQuotaExceededException: $message';
}

class PracticeGenerationFailedException implements Exception {
  final String message;
  PracticeGenerationFailedException(this.message);
  @override
  String toString() => 'PracticeGenerationFailedException: $message';
}

/// 練習已滿 10 則 AI 回覆（伺服器回 409）。前端應引導去拆解卡。
class PracticeSessionCompleteException implements Exception {
  PracticeSessionCompleteException();
  @override
  String toString() => 'PracticeSessionCompleteException';
}

class PracticeChatApiService {
  PracticeChatApiService({PracticeChatInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  final PracticeChatInvoker _invoke;

  static const _functionName = 'practice-chat';

  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required List<PracticeTurnDto> turns,
  }) async {
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'chat',
        'sessionId': sessionId,
        'turns': turns.map((t) => t.toJson()).toList(),
      },
    );
    final data = _guardStatus(response);
    return PracticeChatReply(
      reply: _asString(data['reply']),
      aiTurnCount: _asInt(data['aiTurnCount']) ?? 0,
      sessionComplete: data['sessionComplete'] == true,
      costDeducted: _asInt(data['costDeducted']) ?? 0,
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
    );
  }

  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required List<PracticeTurnDto> turns,
  }) async {
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'debrief',
        'sessionId': sessionId,
        'turns': turns.map((t) => t.toJson()).toList(),
      },
    );
    final data = _guardStatus(response);
    final card = data['card'];
    if (card is! Map) {
      throw PracticeGenerationFailedException('malformed_debrief');
    }
    return PracticeDebrief(
      summary: _asString(card['summary']),
      strengths: _asStringList(card['strengths']),
      watchouts: _asStringList(card['watchouts']),
      suggestedLine: _asString(card['suggestedLine']),
      vibe: _asString(card['vibe']).isEmpty ? '中性' : _asString(card['vibe']),
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
    );
  }

  /// 把 HTTP 狀態映射成例外；200 回傳 data map。
  Map<String, dynamic> _guardStatus(PracticeInvokeResponse response) {
    switch (response.status) {
      case 200:
        final data = response.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        throw PracticeGenerationFailedException('malformed_response');
      case 429:
        final data = response.data is Map ? response.data as Map : const {};
        throw PracticeQuotaExceededException(
          (data['message'] as String?) ?? '額度已用完',
          used: _asInt(data['used']),
          limit: _asInt(data['limit']),
          monthlyRemaining: _asInt(data['monthlyRemaining']),
          dailyRemaining: _asInt(data['dailyRemaining']),
        );
      case 409:
        throw PracticeSessionCompleteException();
      default:
        if (response.status >= 500) {
          throw PracticeGenerationFailedException(
            'practice_generation_failed_${response.status}',
          );
        }
        final data = response.data is Map ? response.data as Map : const {};
        throw PracticeApiException(
          (data['error'] as String?) ?? 'practice_api_error',
          status: response.status,
        );
    }
  }

  static String _asString(dynamic v) => v is String ? v : '';

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.whereType<String>().toList();
    }
    return const [];
  }
}

Future<PracticeInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return PracticeInvokeResponse(status: res.status, data: res.data);
}
