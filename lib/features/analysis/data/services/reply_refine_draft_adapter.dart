/// data 端 adapter：以既有 ReplyRefineDraftStore 實作 application 的
/// ReplyRefineDraftPort（TTL／加密／digest 規則全在 store）。
library;

import '../../application/ports/reply_refine_draft_port.dart';
import 'reply_refine_draft_store.dart';

class ReplyRefineDraftAdapter implements ReplyRefineDraftPort {
  ReplyRefineDraftAdapter({required ReplyRefineDraftStore store})
      : _store = store;

  final ReplyRefineDraftStore _store;

  @override
  Future<ReplyRefineDraftSnapshot?> loadFor({
    required String ownerUserId,
    required String originText,
  }) async {
    final draft = await _store.loadFor(
      ownerUserId: ownerUserId,
      originText: originText,
    );
    if (draft == null) return null;
    return ReplyRefineDraftSnapshot(
      refinedText: draft.refinedText,
      requestId: draft.requestId,
    );
  }

  @override
  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
  }) {
    return _store.save(
      ownerUserId: ownerUserId,
      originText: originText,
      refinedText: refinedText,
      requestId: requestId,
    );
  }
}
