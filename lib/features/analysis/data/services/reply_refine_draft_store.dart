import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';

/// 微調結果只是「還沒送出的草稿」，留一天就夠：使用者離開畫面再回來時還能接著
/// 用，但不會變成一份長期堆在裝置上的聊天內容備份。
const Duration kReplyRefineDraftTtl = Duration(hours: 24);

/// 一則回覆最後一個成功的微調版本。
///
/// 版本堆疊本身是面板的 UI state，不進 `AnalysisRecord`（片段快照依
/// `AnalysisFragmentPolicy` 不可變）；這裡只留最後一版，避免「調了三輪、關掉
/// 畫面全沒了」。
class ReplyRefineDraft {
  const ReplyRefineDraft({
    required this.ownerUserId,
    required this.originDigest,
    required this.refinedText,
    required this.savedAt,
    this.requestId,
  });

  final String ownerUserId;
  final String originDigest;
  final String refinedText;
  final DateTime savedAt;
  final String? requestId;

  Map<String, dynamic> toJson() => {
        'ownerUserId': ownerUserId,
        'originDigest': originDigest,
        'refinedText': refinedText,
        'savedAt': savedAt.toUtc().toIso8601String(),
        if (requestId != null) 'requestId': requestId,
      };

  static ReplyRefineDraft? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final ownerUserId = json['ownerUserId'];
    final originDigest = json['originDigest'];
    final refinedText = json['refinedText'];
    final savedAt = DateTime.tryParse(json['savedAt']?.toString() ?? '');
    final requestId = json['requestId'];
    if (ownerUserId is! String ||
        ownerUserId.trim().isEmpty ||
        originDigest is! String ||
        originDigest.isEmpty ||
        refinedText is! String ||
        refinedText.trim().isEmpty ||
        savedAt == null) {
      return null;
    }
    return ReplyRefineDraft(
      ownerUserId: ownerUserId,
      originDigest: originDigest,
      refinedText: refinedText,
      savedAt: savedAt.toUtc(),
      requestId: requestId is String && requestId.isNotEmpty ? requestId : null,
    );
  }
}

abstract class ReplyRefineDraftStore {
  Future<ReplyRefineDraft?> loadFor({
    required String ownerUserId,
    required String originText,
  });

  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
  });
}

String replyRefineOriginDigest(String originText) =>
    sha256.convert(utf8.encode(originText.trim())).toString();

class InMemoryReplyRefineDraftStore implements ReplyRefineDraftStore {
  InMemoryReplyRefineDraftStore({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, ReplyRefineDraft> _drafts = {};

  static String _key(String ownerUserId, String originDigest) =>
      '${ownerUserId.trim()}::$originDigest';

  @override
  Future<ReplyRefineDraft?> loadFor({
    required String ownerUserId,
    required String originText,
  }) async {
    final draft =
        _drafts[_key(ownerUserId, replyRefineOriginDigest(originText))];
    if (draft == null) return null;
    if (_now().toUtc().difference(draft.savedAt) >= kReplyRefineDraftTtl) {
      return null;
    }
    return draft;
  }

  @override
  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
  }) async {
    final originDigest = replyRefineOriginDigest(originText);
    _drafts[_key(ownerUserId, originDigest)] = ReplyRefineDraft(
      ownerUserId: ownerUserId.trim(),
      originDigest: originDigest,
      refinedText: refinedText,
      savedAt: _now().toUtc(),
      requestId: requestId,
    );
  }
}

/// 存在既有的 AES-256 加密 settings box；登出／刪除帳號走
/// `StorageService.clearAll()` 時一併清掉。
class HiveReplyRefineDraftStore implements ReplyRefineDraftStore {
  HiveReplyRefineDraftStore(this._openBox, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Box Function() _openBox;
  final DateTime Function() _now;

  static const storageKeyPrefix = 'reply_refine_draft:v1:';

  static String _storageKey(String ownerUserId, String originDigest) {
    final encodedOwner =
        base64Url.encode(utf8.encode(ownerUserId.trim())).replaceAll('=', '');
    return '$storageKeyPrefix$encodedOwner:$originDigest';
  }

  @override
  Future<ReplyRefineDraft?> loadFor({
    required String ownerUserId,
    required String originText,
  }) async {
    final box = _openBox();
    final originDigest = replyRefineOriginDigest(originText);
    final key = _storageKey(ownerUserId, originDigest);
    final draft = _decode(box.get(key));
    // 這裡和 optimize pending identity 的處理刻意不同：那一份讀不出來會 throw，
    // 因為它代表可能已扣過費的身分，刪掉就可能重複扣。這裡只是方便用的草稿快取，
    // 讀不出來就當作沒有並清掉，不能為了它把畫面擋住。
    if (draft == null ||
        draft.ownerUserId != ownerUserId.trim() ||
        draft.originDigest != originDigest ||
        _now().toUtc().difference(draft.savedAt) >= kReplyRefineDraftTtl) {
      if (box.containsKey(key)) await box.delete(key);
      return null;
    }
    return draft;
  }

  @override
  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
  }) async {
    final box = _openBox();
    final originDigest = replyRefineOriginDigest(originText);
    final draft = ReplyRefineDraft(
      ownerUserId: ownerUserId.trim(),
      originDigest: originDigest,
      refinedText: refinedText,
      savedAt: _now().toUtc(),
      requestId: requestId,
    );
    await box.put(
      _storageKey(draft.ownerUserId, originDigest),
      jsonEncode(draft.toJson()),
    );
    await _purgeExpired(box);
  }

  /// 每次存檔順手掃掉過期的舊草稿，免得每調一則新回覆就永久多一把鑰匙。
  Future<void> _purgeExpired(Box box) async {
    final now = _now().toUtc();
    final expiredKeys = <dynamic>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith(storageKeyPrefix)) continue;
      final draft = _decode(box.get(key));
      if (draft == null || now.difference(draft.savedAt) >= kReplyRefineDraftTtl) {
        expiredKeys.add(key);
      }
    }
    for (final key in expiredKeys) {
      await box.delete(key);
    }
  }

  static ReplyRefineDraft? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      return ReplyRefineDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
