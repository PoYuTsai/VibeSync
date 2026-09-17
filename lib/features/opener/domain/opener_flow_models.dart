// 開場救星兩段式（先分析、再補充、按生成才第二段）的明確資料型別，
// 對應 Edge opener_stage.ts／opener_flow_payload.ts 的合約（附件 §10）。
// 不再靠多層任意 Map 猜資料；所有 fromJson 都是防禦式的（壞欄位丟掉、不炸）。

import '../data/services/opener_service.dart';
import 'opener_access.dart';

abstract final class OpenerFlowContract {
  /// 兩段流程版本（與 openerContractVersion 分開，不合併成同一個版本號）。
  static const int flowVersion = 1;

  /// 一局共三組＝首次＋兩次主動生成。
  static const int includedGenerationCount = 3;

  /// 首次成功生成的一般費用；零扣費由伺服器客觀判定後在 analysis 回報。
  static const int firstGenerationCost = 3;

  /// 補充最多 300 個字（grapheme cluster，與伺服器 Intl.Segmenter 一致）。
  static const int freeTextMaxGraphemes = 300;
}

/// 伺服器錯誤碼（附件 §11.7）。App 只認碼，不比對訊息文字。
abstract final class OpenerFlowErrorCode {
  static const sessionExpired = 'OPENER_SESSION_EXPIRED';
  static const sessionInvalid = 'OPENER_SESSION_INVALID';
  static const inputMismatch = 'OPENER_OPERATION_INPUT_MISMATCH';
  static const contributionInvalid = 'OPENER_CONTRIBUTION_INVALID';
  static const generationPending = 'OPENER_GENERATION_PENDING';
  static const analysisPending = 'OPENER_ANALYSIS_PENDING';
  static const generationLimitReached = 'OPENER_GENERATION_LIMIT_REACHED';
  static const modelRateLimited = 'MODEL_RATE_LIMITED';
  static const settlementPending = 'OPENER_SETTLEMENT_PENDING';
  static const flowUnavailable = 'OPENER_FLOW_UNAVAILABLE';
  static const wrongSurface = 'OPENER_WRONG_SURFACE';

  /// App 端合成：舊 Edge 不認識兩段式 mode（400 卻沒有 code）。
  static const flowUnsupported = 'OPENER_FLOW_UNSUPPORTED';
}

class OpenerFlowException implements Exception {
  const OpenerFlowException({
    required this.code,
    required this.message,
    required this.status,
    this.retryable = false,
    this.retryAfterMs,
    this.surface,
  });

  final String code;
  final String message;
  final int status;
  final bool retryable;
  final int? retryAfterMs;

  /// OPENER_WRONG_SURFACE 的 surface（chat_conversation／unrelated）。
  final String? surface;

  bool get isExpired => code == OpenerFlowErrorCode.sessionExpired;
  bool get isSessionInvalid => code == OpenerFlowErrorCode.sessionInvalid;
  bool get isUnsupported => code == OpenerFlowErrorCode.flowUnsupported;
  bool get isUnavailable => code == OpenerFlowErrorCode.flowUnavailable;
  bool get isRateLimited => code == OpenerFlowErrorCode.modelRateLimited;
  bool get isLimitReached => code == OpenerFlowErrorCode.generationLimitReached;
  bool get isPending =>
      code == OpenerFlowErrorCode.generationPending ||
      code == OpenerFlowErrorCode.analysisPending ||
      code == OpenerFlowErrorCode.settlementPending;

  @override
  String toString() => message;
}

class OpenerCueEvidence {
  const OpenerCueEvidence({this.field, this.quote, this.imageIndex, this.visible});

  final String? field;
  final String? quote;
  final int? imageIndex;
  final String? visible;

  static const _fieldLabels = {
    'name': '對方名字',
    'bio': '自我介紹',
    'interests': '興趣',
    'meetingContext': '認識場景',
  };

  /// 判斷依據的白話說明：對回第幾張圖或哪個欄位。
  String describe() {
    if (imageIndex != null) {
      final what = visible?.trim();
      return what == null || what.isEmpty ? '第 $imageIndex 張截圖' : '第 $imageIndex 張截圖：$what';
    }
    final label = _fieldLabels[field] ?? field ?? '對方資料';
    final text = quote?.trim();
    return text == null || text.isEmpty ? label : '$label：「$text」';
  }

  Map<String, dynamic> toJson() => {
        if (field != null) 'field': field,
        if (quote != null) 'quote': quote,
        if (imageIndex != null) 'imageIndex': imageIndex,
        if (visible != null) 'visible': visible,
      };

  static OpenerCueEvidence? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final field = raw['field'];
    final quote = raw['quote'];
    final imageIndex = raw['imageIndex'];
    final visible = raw['visible'];
    if (field is! String && imageIndex is! num) return null;
    return OpenerCueEvidence(
      field: field is String ? field : null,
      quote: quote is String && quote.trim().isNotEmpty ? quote.trim() : null,
      imageIndex: imageIndex is num ? imageIndex.round() : null,
      visible: visible is String && visible.trim().isNotEmpty ? visible.trim() : null,
    );
  }
}

class OpenerCue {
  const OpenerCue({required this.id, required this.label, required this.source, this.evidence});

  final String id;
  final String label;
  final String source;
  final OpenerCueEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'source': source,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };

  static OpenerCue? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.isEmpty || label is! String || label.trim().isEmpty) {
      return null;
    }
    return OpenerCue(
      id: id,
      label: label.trim(),
      source: raw['source'] is String ? raw['source'] as String : 'profile_text',
      evidence: OpenerCueEvidence.tryParse(raw['evidence']),
    );
  }
}

class OpenerQuestionOption {
  const OpenerQuestionOption({
    required this.id,
    required this.label,
    required this.meaning,
    this.statement,
    this.cueId,
  });

  final String id;
  final String label;

  /// 受控語意（pick_cue／assert_sender_fact／curious_without_experience／
  /// exclude_cue／change_direction／no_preference）。
  final String meaning;
  final String? statement;
  final String? cueId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'meaning': meaning,
        if (statement != null) 'statement': statement,
        if (cueId != null) 'cueId': cueId,
      };

  static OpenerQuestionOption? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    final meaning = raw['meaning'];
    if (id is! String || id.isEmpty || label is! String || label.trim().isEmpty || meaning is! String) {
      return null;
    }
    return OpenerQuestionOption(
      id: id,
      label: label.trim(),
      meaning: meaning,
      statement: raw['statement'] is String ? raw['statement'] as String : null,
      cueId: raw['cueId'] is String ? raw['cueId'] as String : null,
    );
  }
}

class OpenerQuestion {
  const OpenerQuestion({
    required this.id,
    required this.affects,
    required this.text,
    required this.options,
  });

  final String id;
  final String affects;
  final String text;
  final List<OpenerQuestionOption> options;

  OpenerQuestionOption? optionById(String? id) {
    if (id == null) return null;
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'affects': affects,
        'text': text,
        'options': options.map((o) => o.toJson()).toList(),
      };

  static OpenerQuestion? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    final rawOptions = raw['options'];
    if (id is! String || id.isEmpty || text is! String || text.trim().isEmpty || rawOptions is! List) {
      return null;
    }
    final options = rawOptions.map(OpenerQuestionOption.tryParse).whereType<OpenerQuestionOption>().toList(growable: false);
    if (options.length < 2) return null;
    return OpenerQuestion(
      id: id,
      affects: raw['affects'] is String ? raw['affects'] as String : 'material',
      text: text.trim(),
      options: options,
    );
  }
}

class OpenerApproach {
  const OpenerApproach({required this.mode, required this.summary, required this.avoid});

  final String mode;
  final String summary;
  final List<String> avoid;

  Map<String, dynamic> toJson() => {'mode': mode, 'summary': summary, 'avoid': avoid};

  static OpenerApproach? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final summary = raw['summary'];
    if (summary is! String || summary.trim().isEmpty) return null;
    final avoid = raw['avoid'];
    return OpenerApproach(
      mode: raw['mode'] is String ? raw['mode'] as String : 'low_info',
      summary: summary.trim(),
      avoid: avoid is List ? avoid.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).take(2).toList(growable: false) : const [],
    );
  }
}

/// 第一段回應（伺服器快照的 App 投影）。App 只保存它給 UI 與草稿用；
/// 第二段不回傳這些內容給伺服器（伺服器只信自己的快照）。
class OpenerAnalysis {
  const OpenerAnalysis({
    required this.sessionId,
    required this.analysisRevision,
    required this.expiresAt,
    required this.approach,
    required this.cues,
    required this.question,
    required this.firstGenerationCost,
    required this.includedGenerationCount,
    required this.generationsUsed,
    required this.quotaCharged,
    this.replayed = false,
  });

  final String sessionId;
  final int analysisRevision;
  final DateTime expiresAt;
  final OpenerApproach approach;
  final List<OpenerCue> cues;
  final OpenerQuestion? question;
  final int firstGenerationCost;
  final int includedGenerationCount;
  final int generationsUsed;
  final bool quotaCharged;
  final bool replayed;

  int get generationsRemaining => (includedGenerationCount - generationsUsed).clamp(0, includedGenerationCount);

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  OpenerAnalysis copyWith({int? generationsUsed, bool? quotaCharged}) {
    return OpenerAnalysis(
      sessionId: sessionId,
      analysisRevision: analysisRevision,
      expiresAt: expiresAt,
      approach: approach,
      cues: cues,
      question: question,
      firstGenerationCost: firstGenerationCost,
      includedGenerationCount: includedGenerationCount,
      generationsUsed: generationsUsed ?? this.generationsUsed,
      quotaCharged: quotaCharged ?? this.quotaCharged,
      replayed: replayed,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'analysisRevision': analysisRevision,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'approach': approach.toJson(),
        'cues': cues.map((c) => c.toJson()).toList(),
        'question': question?.toJson(),
        'usage': {
          'firstGenerationCost': firstGenerationCost,
          'includedGenerationCount': includedGenerationCount,
          'generationsUsed': generationsUsed,
          'quotaCharged': quotaCharged,
        },
      };

  static OpenerAnalysis? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final sessionId = raw['sessionId'];
    final expiresAtRaw = raw['expiresAt'];
    final approach = OpenerApproach.tryParse(raw['approach']);
    if (sessionId is! String || sessionId.isEmpty || expiresAtRaw is! String || approach == null) {
      return null;
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) return null;
    final rawCues = raw['cues'];
    final usage = raw['usage'] is Map ? raw['usage'] as Map : const {};
    return OpenerAnalysis(
      sessionId: sessionId,
      analysisRevision: (raw['analysisRevision'] as num?)?.round() ?? 1,
      expiresAt: expiresAt,
      approach: approach,
      cues: rawCues is List ? rawCues.map(OpenerCue.tryParse).whereType<OpenerCue>().toList(growable: false) : const [],
      question: OpenerQuestion.tryParse(raw['question']),
      firstGenerationCost: (usage['firstGenerationCost'] as num?)?.round() ?? OpenerFlowContract.firstGenerationCost,
      includedGenerationCount: (usage['includedGenerationCount'] as num?)?.round() ?? OpenerFlowContract.includedGenerationCount,
      generationsUsed: (usage['generationsUsed'] as num?)?.round() ?? 0,
      quotaCharged: usage['quotaCharged'] == true,
      replayed: raw['replayed'] == true,
    );
  }
}

enum OpenerContributionState { answered, skipped, noAnswer }

/// 第二段送出的回答（附件 §10.4）。freeText 是目前完整版本，取代先前草稿。
class OpenerContribution {
  const OpenerContribution({
    required this.state,
    this.questionId,
    this.selectedOptionId,
    this.freeText,
  });

  final OpenerContributionState state;
  final String? questionId;
  final String? selectedOptionId;
  final String? freeText;

  String get stateWire => switch (state) {
        OpenerContributionState.answered => 'answered',
        OpenerContributionState.skipped => 'skipped',
        OpenerContributionState.noAnswer => 'no_answer',
      };

  Map<String, dynamic> toJson() => {
        'state': stateWire,
        if (questionId != null) 'questionId': questionId,
        if (selectedOptionId != null) 'selectedOptionId': selectedOptionId,
        if (freeText != null) 'freeText': freeText,
      };

  static OpenerContribution? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'answered' => OpenerContributionState.answered,
      'skipped' => OpenerContributionState.skipped,
      'no_answer' => OpenerContributionState.noAnswer,
      _ => null,
    };
    if (state == null) return null;
    return OpenerContribution(
      state: state,
      questionId: raw['questionId'] is String ? raw['questionId'] as String : null,
      selectedOptionId: raw['selectedOptionId'] is String ? raw['selectedOptionId'] as String : null,
      freeText: raw['freeText'] is String ? raw['freeText'] as String : null,
    );
  }
}

/// 回答區的可編輯草稿：一個選項（不預選）＋一段自由文字。
class OpenerContributionDraft {
  const OpenerContributionDraft({this.selectedOptionId, this.freeText = '', this.skipped = false});

  final String? selectedOptionId;
  final String freeText;

  /// 用戶明確按「略過，直接生成」。清空答案與略過是不同狀態。
  final bool skipped;

  bool get hasContent => selectedOptionId != null || freeText.trim().isNotEmpty;

  OpenerContributionDraft copyWith({
    String? selectedOptionId,
    bool clearOption = false,
    String? freeText,
    bool? skipped,
  }) {
    return OpenerContributionDraft(
      selectedOptionId: clearOption ? null : (selectedOptionId ?? this.selectedOptionId),
      freeText: freeText ?? this.freeText,
      skipped: skipped ?? this.skipped,
    );
  }

  /// 轉成正式回答：有內容＝answered；按略過＝skipped；什麼都沒做＝no_answer
  /// （有題目但沒回答，按生成視為未補充繼續，不彈強迫填寫）。
  OpenerContribution toContribution(OpenerQuestion? question) {
    final text = freeText.trim();
    final option = question?.optionById(selectedOptionId);
    if (option != null || text.isNotEmpty) {
      return OpenerContribution(
        state: OpenerContributionState.answered,
        questionId: option == null ? null : question!.id,
        selectedOptionId: option?.id,
        freeText: text.isEmpty ? null : text,
      );
    }
    return OpenerContribution(
      state: skipped ? OpenerContributionState.skipped : OpenerContributionState.noAnswer,
    );
  }

  Map<String, dynamic> toJson() => {
        if (selectedOptionId != null) 'selectedOptionId': selectedOptionId,
        'freeText': freeText,
        'skipped': skipped,
      };

  static OpenerContributionDraft fromJson(dynamic raw) {
    if (raw is! Map) return const OpenerContributionDraft();
    return OpenerContributionDraft(
      selectedOptionId: raw['selectedOptionId'] is String ? raw['selectedOptionId'] as String : null,
      freeText: raw['freeText'] is String ? raw['freeText'] as String : '',
      skipped: raw['skipped'] == true,
    );
  }
}

/// 生成前的一行摘要（附件 §4.4）：只組合已選選項與用戶原文，不打模型。
abstract final class OpenerContributionSummary {
  static String? compose({
    required OpenerQuestion? question,
    required OpenerContributionDraft draft,
    required List<OpenerCue> cues,
  }) {
    final option = question?.optionById(draft.selectedOptionId);
    final text = draft.freeText.trim();
    final parts = <String>[];
    if (option != null) {
      final cueLabel = cues.where((c) => c.id == option.cueId).map((c) => c.label).firstOrNull;
      parts.add(switch (option.meaning) {
        'pick_cue' => cueLabel == null ? '這次從「${option.label}」聊起' : '這次從她的「$cueLabel」聊起',
        'assert_sender_fact' => option.statement == null ? '這次用「${option.label}」當你的事實' : '你自己「${option.statement}」，可以當共同點',
        'curious_without_experience' => cueLabel == null ? '你只是好奇，不寫成你也有經驗' : '從「$cueLabel」聊起；你只是好奇，不寫成你也有',
        'exclude_cue' => cueLabel == null ? '先不聊「${option.label}」' : '先不聊她的「$cueLabel」',
        'change_direction' => '這些線索都先不接，另開話題',
        'no_preference' => '沒有特別偏好，走低壓方向',
        _ => option.label,
      });
    }
    if (text.isNotEmpty) parts.add('你補充：「$text」');
    if (parts.isEmpty) {
      return draft.skipped ? '略過補充，用她的資料直接生成' : null;
    }
    return parts.join('；');
  }
}

/// 明確矛盾（附件 §4.4／§5.4）：選了某個線索，又在文字裡寫「不想聊／不要聊」
/// 那個線索，或明確寫「改聊…」「其實想聊別的」→ 介面移除被明確否定／覆蓋的
/// 選擇。只處理無法同時執行的輸入，不追問；不明確的就保留內容。
abstract final class OpenerContributionConflict {
  static const _overrides = ['改聊', '改成聊', '改問', '換聊', '改成想聊', '其實想聊', '想聊別的', '不接這個'];
  static const _negations = ['不想聊', '不要聊', '不聊', '不想提', '不要提', '別提', '別聊', '不想講', '不要講'];

  static bool optionNegatedByText({
    required OpenerQuestionOption? option,
    required List<OpenerCue> cues,
    required String freeText,
  }) {
    if (option == null) return false;
    if (option.meaning != 'pick_cue' && option.meaning != 'assert_sender_fact' && option.meaning != 'curious_without_experience') {
      return false;
    }
    final text = freeText.trim();
    if (text.isEmpty) return false;
    if (_overrides.any(text.contains)) return true;
    final label = cues.where((c) => c.id == option.cueId).map((c) => c.label).firstOrNull;
    if (label == null || label.isEmpty) return false;
    for (final negation in _negations) {
      final index = text.indexOf(negation);
      if (index < 0) continue;
      final after = text.substring(index + negation.length);
      if (after.contains(label)) return true;
    }
    return false;
  }
}

class OpenerMaterialReference {
  const OpenerMaterialReference({required this.style, required this.materialId, required this.outputSpan});

  final String style;
  final String materialId;
  final String outputSpan;

  Map<String, dynamic> toJson() => {'style': style, 'materialId': materialId, 'outputSpan': outputSpan};

  static OpenerMaterialReference? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final style = raw['style'];
    final materialId = raw['materialId'];
    final span = raw['outputSpan'];
    if (style is! String || materialId is! String || span is! String) return null;
    return OpenerMaterialReference(style: style, materialId: materialId, outputSpan: span);
  }
}

/// 來源核對狀態（附件 §10.7）：matched 只代表來源紀錄對得上，不代表語意已通過。
class OpenerMaterialUse {
  const OpenerMaterialUse({
    required this.inputState,
    required this.references,
    required this.traceStatus,
    this.displayNote,
  });

  final String inputState;
  final List<OpenerMaterialReference> references;
  final String traceStatus;
  final String? displayNote;

  bool get matched => traceStatus == 'matched';

  bool styleReferenced(String style) => references.any((r) => r.style == style);

  Map<String, dynamic> toJson() => {
        'inputState': inputState,
        'references': references.map((r) => r.toJson()).toList(),
        'traceStatus': traceStatus,
        if (displayNote != null) 'displayNote': displayNote,
      };

  static OpenerMaterialUse? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final refs = raw['references'];
    final note = raw['displayNote'];
    return OpenerMaterialUse(
      inputState: raw['inputState'] is String ? raw['inputState'] as String : 'no_answer',
      references: refs is List ? refs.map(OpenerMaterialReference.tryParse).whereType<OpenerMaterialReference>().toList(growable: false) : const [],
      traceStatus: raw['traceStatus'] is String ? raw['traceStatus'] as String : 'uncertain',
      displayNote: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }
}

class OpenerGenerationUsage {
  const OpenerGenerationUsage({
    required this.chargedNow,
    required this.sessionChargedTotal,
    required this.generationsUsed,
    required this.generationsRemaining,
    required this.replayed,
  });

  final int chargedNow;
  final int sessionChargedTotal;
  final int generationsUsed;
  final int generationsRemaining;
  final bool replayed;

  Map<String, dynamic> toJson() => {
        'chargedNow': chargedNow,
        'sessionChargedTotal': sessionChargedTotal,
        'generationsUsed': generationsUsed,
        'generationsRemaining': generationsRemaining,
        'replayed': replayed,
      };

  static OpenerGenerationUsage fromJson(dynamic raw) {
    final map = raw is Map ? raw : const {};
    return OpenerGenerationUsage(
      chargedNow: (map['chargedNow'] as num?)?.round() ?? 0,
      sessionChargedTotal: (map['sessionChargedTotal'] as num?)?.round() ?? 0,
      generationsUsed: (map['generationsUsed'] as num?)?.round() ?? 0,
      generationsRemaining: (map['generationsRemaining'] as num?)?.round() ?? 0,
      replayed: map['replayed'] == true,
    );
  }
}

/// 第二段回應：既有 [OpenerResult]（卡片、推薦、access）＋來源核對＋本局用量。
class OpenerGeneration {
  const OpenerGeneration({
    required this.sessionId,
    required this.generationId,
    required this.result,
    required this.cardReasons,
    required this.materialUse,
    required this.usage,
    required this.expiresAt,
    required this.contribution,
  });

  final String sessionId;
  final String generationId;

  /// requestId＝generationId：回報 ID 走既有 `opener:<requestId>:<type>`。
  final OpenerResult result;
  final Map<String, String> cardReasons;
  final OpenerMaterialUse materialUse;
  final OpenerGenerationUsage usage;
  final DateTime expiresAt;

  /// 這組結果對應的回答（調整想法時帶回原回答區）。
  final OpenerContribution contribution;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'generationId': generationId,
        'result': result.toJson(),
        'cardReasons': cardReasons,
        'materialUse': materialUse.toJson(),
        'usage': usage.toJson(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'contribution': contribution.toJson(),
      };

  static OpenerGeneration? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final sessionId = raw['sessionId'];
    final generationId = raw['generationId'];
    final resultRaw = raw['result'];
    final expiresAtRaw = raw['expiresAt'];
    final materialUse = OpenerMaterialUse.tryParse(raw['materialUse']);
    final contribution = OpenerContribution.tryParse(raw['contribution']);
    if (sessionId is! String || generationId is! String || resultRaw is! Map || expiresAtRaw is! String || materialUse == null || contribution == null) {
      return null;
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) return null;
    final reasons = raw['cardReasons'];
    return OpenerGeneration(
      sessionId: sessionId,
      generationId: generationId,
      result: OpenerResult.fromJson(resultRaw.map((k, v) => MapEntry(k.toString(), v))),
      cardReasons: reasons is Map ? reasons.map((k, v) => MapEntry(k.toString(), v.toString())) : const {},
      materialUse: materialUse,
      usage: OpenerGenerationUsage.fromJson(raw['usage']),
      expiresAt: expiresAt,
      contribution: contribution,
    );
  }

  /// 從伺服器第二段回應建立（伺服器 body 是攤平的 result＋usage）。
  static OpenerGeneration? fromServerBody(Map<String, dynamic> body, {required OpenerContribution contribution}) {
    final sessionId = body['sessionId'];
    final generationId = body['generationId'];
    final expiresAtRaw = body['expiresAt'];
    if (sessionId is! String || generationId is! String || expiresAtRaw is! String) return null;
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) return null;
    final openers = OpenerResult.fromJson({'openers': body['openers']}).openers;
    if (openers.isEmpty) return null;
    final recommendation = body['recommendation'];
    final usage = OpenerGenerationUsage.fromJson(body['usage']);
    final reasons = body['cardReasons'];
    final pioneer = body['pioneerPlan'];
    final profileAnalysis = body['profileAnalysis'];
    final result = OpenerResult(
      profileAnalysis: profileAnalysis is Map ? profileAnalysis.map((k, v) => MapEntry(k.toString(), v)) : null,
      openers: openers,
      pioneerPlan: pioneer is Map ? pioneer.map((k, v) => MapEntry(k.toString(), v.toString())) : null,
      recommendedPick: recommendation is Map && recommendation['pick'] is String ? recommendation['pick'] as String : null,
      recommendedReason: recommendation is Map && recommendation['reason'] is String ? recommendation['reason'] as String : null,
      costUsed: usage.chargedNow,
      requestId: generationId,
      access: OpenerAccess.tryParse(body['access']),
    );
    final materialUse = OpenerMaterialUse.tryParse(body['materialUse']) ??
        const OpenerMaterialUse(inputState: 'no_answer', references: [], traceStatus: 'uncertain');
    return OpenerGeneration(
      sessionId: sessionId,
      generationId: generationId,
      result: result,
      cardReasons: reasons is Map ? reasons.map((k, v) => MapEntry(k.toString(), v.toString())) : const {},
      materialUse: materialUse,
      usage: usage,
      expiresAt: expiresAt,
      contribution: contribution,
    );
  }
}
