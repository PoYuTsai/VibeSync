import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../conversation/data/repositories/conversation_archive_store.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../domain/entities/analysis_record.dart';

enum AnalysisRecordSaveStatus {
  createdCurrent,
  advancedCurrent,
  replacedCurrent,
  replayed,
  rejected,
}

class AnalysisRecordSaveResult {
  const AnalysisRecordSaveResult._({
    required this.status,
    this.record,
    this.archivedPrevious,
    this.rejectionReason,
  });

  const AnalysisRecordSaveResult.rejected(String reason)
      : this._(
          status: AnalysisRecordSaveStatus.rejected,
          rejectionReason: reason,
        );

  final AnalysisRecordSaveStatus status;
  final AnalysisRecord? record;

  /// Non-null only when a newly appended fragment advanced the current
  /// pointer and made the previous current record visible in the archive.
  final AnalysisRecord? archivedPrevious;
  final String? rejectionReason;

  bool get accepted => status != AnalysisRecordSaveStatus.rejected;
  bool get didWrite => switch (status) {
        AnalysisRecordSaveStatus.createdCurrent ||
        AnalysisRecordSaveStatus.advancedCurrent ||
        AnalysisRecordSaveStatus.replacedCurrent =>
          true,
        AnalysisRecordSaveStatus.replayed ||
        AnalysisRecordSaveStatus.rejected =>
          false,
      };
}

/// Owner-scoped durable storage for independent analyze-chat records.
///
/// Each record and each conversation's current pointer are separate entries
/// in the existing AES-encrypted settings box. There is intentionally no FIFO
/// or automatic pruning: archived records leave only through explicit delete,
/// conversation cleanup, or account-wide storage cleanup.
abstract class AnalysisRecordStore {
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  });

  AnalysisRecord? recordById({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  });

  /// Lists archived records for the supplied live conversations. A current
  /// record is included only after [archiveCurrentRecord] closes its fragment.
  /// Results are newest first.
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  });

  /// Makes the current successful record visible in the archive without
  /// changing the immutable conversation snapshot it came from.
  ///
  /// This closes the one-fragment lifecycle. It is deliberately separate
  /// from [saveSuccessfulAnalysis] so legacy multi-fragment conversations can
  /// keep using the current pointer as their boundary authority.
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  });

  /// [allowArchivedRefresh] is reserved for an explicit paid refresh of the
  /// exact same message boundary. It never permits appending messages,
  /// changing the analyzed revision, or reviving a deleted record.
  Future<AnalysisRecordSaveResult> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
    DateTime? completedAt,
  });

  Future<bool> deleteRecord({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  });

  /// Removes the conversation state, all valid records, and source metadata.
  /// Returns the number of record entries removed.
  Future<int> removeConversation({
    required String ownerUserId,
    required String conversationId,
  });

  /// Writes a durable intent before the live conversation is removed. If a
  /// later cascade fails, [recoverPendingConversationRemovals] can finish it.
  Future<bool> prepareConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  });

  Future<bool> cancelConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  });

  bool hasPendingConversationRemovals({required String ownerUserId});

  /// Finishes committed removals and cancels markers whose conversation still
  /// exists. Returns the number of absent conversations reconciled.
  Future<int> recoverPendingConversationRemovals({
    required String ownerUserId,
    required Iterable<String> liveConversationIds,
  });

  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  });

  Future<bool> setConversationSource({
    required String ownerUserId,
    required String conversationId,
    required String? sourcePlatform,
    bool relabelCurrent = false,
  });

  String? partnerMetVia({
    required String ownerUserId,
    required String partnerId,
  });

  Future<bool> setPartnerMetVia({
    required String ownerUserId,
    required String partnerId,
    required String? sourcePlatform,
  });

  Future<bool> removePartnerMetadata({
    required String ownerUserId,
    required String partnerId,
  });

  /// An existing target value wins; otherwise the source value is carried
  /// forward. The source key is removed after the target write succeeds.
  Future<bool> mergePartnerMetadata({
    required String ownerUserId,
    required String fromPartnerId,
    required String toPartnerId,
  });
}

class HiveAnalysisRecordStore implements AnalysisRecordStore {
  HiveAnalysisRecordStore(this._openBox);

  static const recordKeyPrefix = 'analysis_record_v2';
  static const stateKeyPrefix = 'analysis_record_state_v1';
  static const partnerMetViaKeyPrefix = 'analysis_partner_met_via_v1';
  static const conversationSourceKeyPrefix = 'analysis_conversation_source_v1';
  static const cleanupKeyPrefix = 'analysis_record_cleanup_v1';
  static const tombstoneKeyPrefix = 'analysis_record_deleted_v1';
  static const recordTombstoneKeyPrefix = 'analysis_record_item_deleted_v1';

  /// Lazy getter keeps widget/headless tests that never initialize Hive from
  /// failing merely by constructing the provider or building a screen.
  final Box<dynamic> Function() _openBox;

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return null;
    try {
      final box = _openBox();
      if (box.containsKey(_tombstoneKey(owner, conversation))) return null;
      final state = _stateFromRaw(box.get(_stateKey(owner, conversation)));
      if (state == null || state.currentDeleted) return null;
      final record = _recordFromBox(
        box,
        owner: owner,
        recordId: state.currentRecordId,
        conversationId: conversation,
      );
      if (record == null ||
          record.id != state.currentRecordId ||
          record.ownerUserId != owner ||
          record.conversationId != conversation ||
          record.completionKey != state.lastCompletionKey ||
          record.segmentStart != state.currentStart ||
          record.segmentEnd != state.currentEnd) {
        return null;
      }
      return record;
    } catch (_) {
      return null;
    }
  }

  @override
  AnalysisRecord? recordById({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    final id = _normalized(recordId);
    if (owner == null || conversation == null || id == null) return null;
    try {
      final box = _openBox();
      if (box.containsKey(_tombstoneKey(owner, conversation))) return null;
      final state = _stateFromRaw(box.get(_stateKey(owner, conversation)));
      if (state?.currentRecordId == id && state?.currentDeleted == true) {
        return null;
      }
      return _recordFromBox(
        box,
        owner: owner,
        recordId: id,
        conversationId: conversation,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  }) {
    final owner = _normalized(ownerUserId);
    if (owner == null) return const [];
    final conversations =
        conversationIds.map(_normalized).whereType<String>().toSet();
    if (conversations.isEmpty) return const [];

    try {
      final box = _openBox();
      final currentIds = <String>{};
      final conversationsWithState = <String>{};
      for (final conversationId in conversations) {
        if (box.containsKey(_tombstoneKey(owner, conversationId))) continue;
        final state = _stateFromRaw(
          box.get(_stateKey(owner, conversationId)),
        );
        if (state != null) {
          conversationsWithState.add(conversationId);
          if (!state.currentArchived || state.currentDeleted) {
            currentIds.add(state.currentRecordId);
          }
        }
      }

      final recordPrefix = '$recordKeyPrefix:$owner:';
      final records = <AnalysisRecord>[];
      for (final key in box.keys) {
        if (key is! String || !key.startsWith(recordPrefix)) continue;
        final record = AnalysisRecord.tryDecode(box.get(key));
        if (record == null ||
            key != _recordKey(owner, record.conversationId, record.id) ||
            box.containsKey(
              _recordTombstoneKey(owner, record.conversationId, record.id),
            ) ||
            record.ownerUserId != owner ||
            !conversations.contains(record.conversationId) ||
            !conversationsWithState.contains(record.conversationId) ||
            currentIds.contains(record.id)) {
          continue;
        }
        records.add(record);
      }
      records.sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      return List.unmodifiable(records);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return false;

    final box = _openBox();
    if (box.containsKey(_tombstoneKey(owner, conversation))) return false;
    final state = _stateFromRaw(box.get(_stateKey(owner, conversation)));
    if (state == null) return false;
    if (state.currentDeleted) return true;

    final currentRecordTombstoned = box.containsKey(
      _recordTombstoneKey(owner, conversation, state.currentRecordId),
    );
    if (currentRecordTombstoned) {
      // The item tombstone is the first durable write during manual deletion.
      // If the app stopped before the state write, treat the deletion as
      // complete and heal the state when its immutable identity is available.
      final rawCurrent = _recordFromBox(
        box,
        owner: owner,
        recordId: state.currentRecordId,
        conversationId: conversation,
        ignoreRecordTombstone: true,
      );
      final revision =
          state.currentRevision ?? rawCurrent?.analyzedContentRevision;
      final snapshotDigest = state.currentSnapshotDigest ??
          (rawCurrent == null
              ? null
              : _snapshotDigest(rawCurrent.analysisSnapshotJson));
      if (revision != null && snapshotDigest != null) {
        await box.put(
          _stateKey(owner, conversation),
          state
              .copyWith(
                currentArchived: true,
                currentDeleted: true,
                currentRevision: revision,
                currentSnapshotDigest: snapshotDigest,
              )
              .encode(),
        );
      }
      return true;
    }

    final current = _recordFromBox(
      box,
      owner: owner,
      recordId: state.currentRecordId,
      conversationId: conversation,
    );
    if (current == null ||
        current.completionKey != state.lastCompletionKey ||
        current.segmentStart != state.currentStart ||
        current.segmentEnd != state.currentEnd) {
      return false;
    }
    if (state.currentArchived &&
        state.currentRevision == current.analyzedContentRevision &&
        state.currentSnapshotDigest ==
            _snapshotDigest(current.analysisSnapshotJson)) {
      return true;
    }

    await box.put(
      _stateKey(owner, conversation),
      state
          .copyWith(
            currentArchived: true,
            currentDeleted: false,
            currentRevision: current.analyzedContentRevision,
            currentSnapshotDigest:
                _snapshotDigest(current.analysisSnapshotJson),
          )
          .encode(),
    );
    return true;
  }

  @override
  Future<AnalysisRecordSaveResult> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
    DateTime? completedAt,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversationId = _normalized(conversation.id);
    final conversationOwner = _normalized(conversation.ownerUserId);
    final completion = _normalized(completionKey);
    final revision = _normalized(analyzedContentRevision);
    if (owner == null) {
      return const AnalysisRecordSaveResult.rejected('owner_is_blank');
    }
    if (conversationId == null || conversationOwner != owner) {
      return const AnalysisRecordSaveResult.rejected(
        'conversation_owner_mismatch',
      );
    }
    if (completion == null) {
      return const AnalysisRecordSaveResult.rejected(
        'completion_key_is_blank',
      );
    }
    if (runStartPreviousCount < 0 ||
        analyzedMessageCount <= 0 ||
        analyzedMessageCount > conversation.messages.length) {
      return const AnalysisRecordSaveResult.rejected(
        'invalid_message_boundary',
      );
    }
    if (revision == null ||
        revision !=
            conversationContentRevision(
              conversation,
              messageCount: analyzedMessageCount,
            )) {
      return const AnalysisRecordSaveResult.rejected(
        'stale_content_revision',
      );
    }
    if (analysisSnapshotJson.trim().isEmpty) {
      return const AnalysisRecordSaveResult.rejected(
        'analysis_snapshot_is_blank',
      );
    }
    final snapshotDigest = _snapshotDigest(analysisSnapshotJson);

    // Reads are intentionally fail-safe. The actual write below is not
    // swallowed: an unavailable/encryption-failed box is a persistence error
    // the caller may surface or retry.
    final box = _openBox();
    if (box.containsKey(_tombstoneKey(owner, conversationId))) {
      return const AnalysisRecordSaveResult.rejected(
        'conversation_deleted',
      );
    }
    final state = _stateFromRaw(box.get(_stateKey(owner, conversationId)));
    final rawCurrentCandidate = state == null
        ? null
        : _recordFromBox(
            box,
            owner: owner,
            recordId: state.currentRecordId,
            conversationId: conversationId,
            ignoreRecordTombstone: true,
          );
    final currentRecordTombstoned = state != null &&
        box.containsKey(
          _recordTombstoneKey(
            owner,
            conversationId,
            state.currentRecordId,
          ),
        );
    final currentWasDeleted =
        state != null && (state.currentDeleted || currentRecordTombstoned);
    final currentCandidate = currentWasDeleted ? null : rawCurrentCandidate;
    final current = state != null &&
            currentCandidate != null &&
            currentCandidate.completionKey == state.lastCompletionKey &&
            currentCandidate.segmentStart == state.currentStart &&
            currentCandidate.segmentEnd == state.currentEnd
        ? currentCandidate
        : null;
    final currentMatchesSnapshot = current != null &&
        current.analyzedContentRevision == revision &&
        current.segmentEnd == analyzedMessageCount &&
        _snapshotDigest(current.analysisSnapshotJson) == snapshotDigest;
    if (currentMatchesSnapshot) {
      return AnalysisRecordSaveResult._(
        status: AnalysisRecordSaveStatus.replayed,
        record: current,
      );
    }

    final durableDeletedRevision =
        state?.currentRevision ?? rawCurrentCandidate?.analyzedContentRevision;
    final durableDeletedSnapshotDigest = state?.currentSnapshotDigest ??
        (rawCurrentCandidate == null
            ? null
            : _snapshotDigest(rawCurrentCandidate.analysisSnapshotJson));
    final deletedCurrentMatchesSnapshot = currentWasDeleted &&
        state.currentEnd == analyzedMessageCount &&
        durableDeletedRevision == revision &&
        durableDeletedSnapshotDigest == snapshotDigest;
    if (deletedCurrentMatchesSnapshot) {
      // A cold hydration repair may use a different synthetic completion key
      // from the original stream. Revision + snapshot digest are the durable
      // identity here; accepting without rewriting preserves manual deletion.
      return const AnalysisRecordSaveResult._(
        status: AnalysisRecordSaveStatus.replayed,
      );
    }

    if (currentWasDeleted && analyzedMessageCount <= state.currentEnd) {
      return const AnalysisRecordSaveResult.rejected(
        'deleted_fragment_closed',
      );
    }
    final isExplicitArchivedRefresh = allowArchivedRefresh &&
        state?.currentArchived == true &&
        current != null &&
        analyzedMessageCount == current.segmentEnd &&
        revision == current.analyzedContentRevision;
    if (state?.currentArchived == true &&
        current != null &&
        analyzedMessageCount <= current.segmentEnd &&
        !isExplicitArchivedRefresh) {
      return const AnalysisRecordSaveResult.rejected(
        'archived_fragment_closed',
      );
    }

    final boundaryEnd =
        current?.segmentEnd ?? (currentWasDeleted ? state.currentEnd : null);
    final boundaryRevision = current?.analyzedContentRevision ??
        (currentWasDeleted ? durableDeletedRevision : null);
    if (boundaryEnd != null && analyzedMessageCount > boundaryEnd) {
      final prefixRevision = conversationContentRevision(
        conversation,
        messageCount: boundaryEnd,
      );
      if (boundaryRevision == null || prefixRevision != boundaryRevision) {
        return const AnalysisRecordSaveResult.rejected(
          'fragment_prefix_changed',
        );
      }
    }

    final deletedBoundary = currentWasDeleted ? state : null;
    final advancesCurrent = current != null
        ? analyzedMessageCount > current.segmentEnd
        : deletedBoundary != null &&
            analyzedMessageCount > deletedBoundary.currentEnd;
    final segmentStart = advancesCurrent
        // A validated current pointer is the durable boundary authority. The
        // caller baseline can be stale after cold repair or a missed write;
        // using it here could overlap or skip private message fragments.
        ? (current?.segmentEnd ?? deletedBoundary!.currentEnd)
        : current == null && deletedBoundary == null
            // Legacy/same-count hydration without a state must still create a
            // usable first current record from the full analyzed input.
            ? 0
            : (current?.segmentStart ?? deletedBoundary!.currentStart) <
                    analyzedMessageCount
                ? (current?.segmentStart ?? deletedBoundary!.currentStart)
                : 0;
    if (segmentStart < 0 || segmentStart >= analyzedMessageCount) {
      return const AnalysisRecordSaveResult.rejected(
        'invalid_message_fragment',
      );
    }

    final recordId = advancesCurrent || current == null
        ? _newRecordId(
            owner,
            conversationId,
            completion,
            revision,
            segmentStart,
            analyzedMessageCount,
          )
        : current.id;
    final sourceKey = _conversationSourceKey(owner, conversationId);
    final hasStoredSource = box.containsKey(sourceKey);
    final selectedSource = _normalized(sourcePlatform) ??
        (hasStoredSource
            ? _conversationSourceFromBox(box, owner, conversationId)
            : advancesCurrent
                ? null
                : current?.sourcePlatform);
    final record = AnalysisRecord(
      id: recordId,
      ownerUserId: owner,
      conversationId: conversationId,
      partnerId: _normalized(conversation.partnerId),
      subjectName: conversation.name,
      segmentStart: segmentStart,
      segmentEnd: analyzedMessageCount,
      createdAt: advancesCurrent || current == null
          ? (completedAt ?? DateTime.now())
          : current.createdAt,
      messages: List.unmodifiable(
        conversation.messages
            .sublist(segmentStart, analyzedMessageCount)
            .map(AnalysisRecordMessage.fromMessage),
      ),
      analysisSnapshotJson: analysisSnapshotJson,
      analyzedContentRevision: revision,
      completionKey: completion,
      sourcePlatform: selectedSource,
      enthusiasmScore: enthusiasmScore.clamp(0, 100),
      gameStageLabel: gameStageLabel,
    );
    final nextState = _AnalysisRecordState(
      currentRecordId: record.id,
      lastCompletionKey: completion,
      currentStart: segmentStart,
      currentEnd: analyzedMessageCount,
      currentArchived: false,
      currentDeleted: false,
      currentRevision: revision,
      currentSnapshotDigest: snapshotDigest,
    );
    if (deletedBoundary != null) {
      // The per-record tombstone already hides this item. Remove any residual
      // payload before advancing the pointer so an interrupted prior delete
      // can never reappear as an older archive after state replacement.
      await box.delete(
        _recordKey(owner, conversationId, deletedBoundary.currentRecordId),
      );
    }
    await box.putAll(<String, Object?>{
      _recordKey(owner, conversationId, record.id): record.encode(),
      _stateKey(owner, conversationId): nextState.encode(),
    });

    return AnalysisRecordSaveResult._(
      status: current == null && deletedBoundary == null
          ? AnalysisRecordSaveStatus.createdCurrent
          : advancesCurrent
              ? AnalysisRecordSaveStatus.advancedCurrent
              : AnalysisRecordSaveStatus.replacedCurrent,
      record: record,
      archivedPrevious: advancesCurrent ? current : null,
    );
  }

  @override
  Future<bool> deleteRecord({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    final id = _normalized(recordId);
    if (owner == null || conversation == null || id == null) return false;
    final box = _openBox();
    if (box.containsKey(_tombstoneKey(owner, conversation))) return false;
    final record = AnalysisRecord.tryDecode(
      box.get(_recordKey(owner, conversation, id)),
    );
    if (record == null ||
        record.id != id ||
        record.ownerUserId != owner ||
        record.conversationId != conversation) {
      return false;
    }

    final stateKey = _stateKey(owner, record.conversationId);
    final state = _stateFromRaw(box.get(stateKey));
    if (state?.currentRecordId == id && !state!.currentArchived) {
      return false;
    }
    await box.put(
      _recordTombstoneKey(owner, record.conversationId, id),
      true,
    );
    if (state?.currentRecordId == id) {
      final currentState = state!;
      // A live current record still belongs to the analysis screen. Once the
      // fragment is closed, retain its boundary/digest as a durable deletion
      // tombstone so cold snapshot repair cannot recreate the user's record.
      await box.put(
        stateKey,
        currentState
            .copyWith(
              currentArchived: true,
              currentDeleted: true,
              currentRevision: record.analyzedContentRevision,
              currentSnapshotDigest:
                  _snapshotDigest(record.analysisSnapshotJson),
            )
            .encode(),
      );
      await box.delete(_recordKey(owner, conversation, id));
      return true;
    }
    await box.delete(_recordKey(owner, conversation, id));
    return true;
  }

  @override
  Future<int> removeConversation({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return 0;
    final box = _openBox();
    await box.put(_cleanupKey(owner, conversation), conversation);
    return _removeConversationFromBox(
      box,
      owner: owner,
      conversationId: conversation,
    );
  }

  @override
  Future<bool> prepareConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return false;
    final box = _openBox();
    if (box.containsKey(_tombstoneKey(owner, conversation))) return false;
    await box.put(_cleanupKey(owner, conversation), conversation);
    return true;
  }

  @override
  Future<bool> cancelConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return false;
    await _openBox().deleteAll(<String>[
      _cleanupKey(owner, conversation),
      _tombstoneKey(owner, conversation),
    ]);
    return true;
  }

  @override
  bool hasPendingConversationRemovals({required String ownerUserId}) {
    final owner = _normalized(ownerUserId);
    if (owner == null) return false;
    try {
      final prefix = '$cleanupKeyPrefix:$owner:';
      return _openBox()
          .keys
          .whereType<String>()
          .any((key) => key.startsWith(prefix));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> recoverPendingConversationRemovals({
    required String ownerUserId,
    required Iterable<String> liveConversationIds,
  }) async {
    final owner = _normalized(ownerUserId);
    if (owner == null) return 0;
    final liveIds =
        liveConversationIds.map(_normalized).whereType<String>().toSet();
    final box = _openBox();
    final prefix = '$cleanupKeyPrefix:$owner:';
    final markerKeys = box.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    var recovered = 0;
    for (final markerKey in markerKeys) {
      final conversation = _normalized(box.get(markerKey)) ??
          _normalized(markerKey.substring(prefix.length));
      if (conversation == null) continue;
      if (liveIds.contains(conversation)) {
        await box.deleteAll(<String>[
          markerKey,
          _tombstoneKey(owner, conversation),
        ]);
        continue;
      }
      await _removeConversationFromBox(
        box,
        owner: owner,
        conversationId: conversation,
      );
      recovered++;
    }
    return recovered;
  }

  static Future<int> _removeConversationFromBox(
    Box<dynamic> box, {
    required String owner,
    required String conversationId,
  }) async {
    await box.put(_tombstoneKey(owner, conversationId), true);
    final keys = <String>{
      _stateKey(owner, conversationId),
      _conversationSourceKey(owner, conversationId),
    };
    final recordKeys = <String>{};
    final recordTombstoneKeys = <String>{};
    final state = _stateFromRaw(box.get(_stateKey(owner, conversationId)));
    if (state != null) {
      final currentKey =
          _recordKey(owner, conversationId, state.currentRecordId);
      final current = AnalysisRecord.tryDecode(box.get(currentKey));
      if (current != null &&
          current.ownerUserId == owner &&
          current.conversationId == conversationId) {
        recordKeys.add(currentKey);
      }
    }

    final recordPrefix = '$recordKeyPrefix:$owner:$conversationId:';
    final recordTombstonePrefix =
        '$recordTombstoneKeyPrefix:$owner:$conversationId:';
    for (final key in box.keys) {
      if (key is! String) continue;
      if (key.startsWith(recordPrefix)) {
        recordKeys.add(key);
      } else if (key.startsWith(recordTombstonePrefix)) {
        recordTombstoneKeys.add(key);
      }
    }
    keys.addAll(recordKeys);
    keys.addAll(recordTombstoneKeys);
    await box.deleteAll(keys);
    // The marker is removed last. If any prior cleanup throws, recovery can
    // retry while the tombstone blocks every stale post-delete writer.
    await box.delete(_cleanupKey(owner, conversationId));
    return recordKeys.length;
  }

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return null;
    try {
      final box = _openBox();
      if (box.containsKey(_tombstoneKey(owner, conversation))) return null;
      return _conversationSourceFromBox(box, owner, conversation);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setConversationSource({
    required String ownerUserId,
    required String conversationId,
    required String? sourcePlatform,
    bool relabelCurrent = false,
  }) async {
    final owner = _normalized(ownerUserId);
    final conversation = _normalized(conversationId);
    if (owner == null || conversation == null) return false;
    final box = _openBox();
    if (box.containsKey(_tombstoneKey(owner, conversation))) return false;
    if (!relabelCurrent) {
      // Preserve an explicit clear as an empty sentinel. This lets a later
      // same-count repair distinguish 「user cleared source」 from legacy rows
      // that never had source metadata and should retain their record label.
      await box.put(
        _conversationSourceKey(owner, conversation),
        _normalized(sourcePlatform) ?? '',
      );
      return true;
    }

    final state = _stateFromRaw(box.get(_stateKey(owner, conversation)));
    if (state == null) return false;
    final current = _recordFromBox(
      box,
      owner: owner,
      recordId: state.currentRecordId,
      conversationId: conversation,
    );
    if (current == null ||
        current.completionKey != state.lastCompletionKey ||
        current.segmentStart != state.currentStart ||
        current.segmentEnd != state.currentEnd) {
      return false;
    }

    final normalizedSource = _normalized(sourcePlatform);
    final relabelled = _copyWithSource(current, normalizedSource);
    // Keep the visible source pill and the current record in the same Hive
    // batch. Empty string is the atomic representation of 「未分類」 here;
    // all metadata reads normalize it back to null.
    await box.putAll(<String, Object?>{
      _conversationSourceKey(owner, conversation): normalizedSource ?? '',
      _recordKey(owner, conversation, current.id): relabelled.encode(),
    });
    return true;
  }

  static AnalysisRecord _copyWithSource(
    AnalysisRecord record,
    String? sourcePlatform,
  ) {
    return AnalysisRecord(
      id: record.id,
      ownerUserId: record.ownerUserId,
      conversationId: record.conversationId,
      partnerId: record.partnerId,
      subjectName: record.subjectName,
      segmentStart: record.segmentStart,
      segmentEnd: record.segmentEnd,
      createdAt: record.createdAt,
      messages: record.messages,
      analysisSnapshotJson: record.analysisSnapshotJson,
      analyzedContentRevision: record.analyzedContentRevision,
      completionKey: record.completionKey,
      sourcePlatform: sourcePlatform,
      enthusiasmScore: record.enthusiasmScore,
      gameStageLabel: record.gameStageLabel,
    );
  }

  @override
  String? partnerMetVia({
    required String ownerUserId,
    required String partnerId,
  }) {
    final owner = _normalized(ownerUserId);
    final partner = _normalized(partnerId);
    if (owner == null || partner == null) return null;
    try {
      return _normalized(_openBox().get(_partnerMetViaKey(owner, partner)));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setPartnerMetVia({
    required String ownerUserId,
    required String partnerId,
    required String? sourcePlatform,
  }) {
    return _writeMetadata(
      ownerUserId: ownerUserId,
      scopeId: partnerId,
      value: sourcePlatform,
      keyBuilder: _partnerMetViaKey,
    );
  }

  @override
  Future<bool> removePartnerMetadata({
    required String ownerUserId,
    required String partnerId,
  }) async {
    final owner = _normalized(ownerUserId);
    final partner = _normalized(partnerId);
    if (owner == null || partner == null) return false;
    final box = _openBox();
    final key = _partnerMetViaKey(owner, partner);
    final existed = box.containsKey(key);
    await box.delete(key);
    return existed;
  }

  @override
  Future<bool> mergePartnerMetadata({
    required String ownerUserId,
    required String fromPartnerId,
    required String toPartnerId,
  }) async {
    final owner = _normalized(ownerUserId);
    final from = _normalized(fromPartnerId);
    final to = _normalized(toPartnerId);
    if (owner == null || from == null || to == null || from == to) {
      return false;
    }
    final box = _openBox();
    final fromKey = _partnerMetViaKey(owner, from);
    final toKey = _partnerMetViaKey(owner, to);
    final source = _normalized(box.get(fromKey));
    final target = _normalized(box.get(toKey));
    if (source != null && target == null) {
      // Put first so an interrupted merge may duplicate metadata but never
      // loses the only reachable value.
      await box.put(toKey, source);
    }
    final existed = box.containsKey(fromKey);
    await box.delete(fromKey);
    return existed;
  }

  Future<bool> _writeMetadata({
    required String ownerUserId,
    required String scopeId,
    required String? value,
    required String Function(String owner, String scope) keyBuilder,
  }) async {
    final owner = _normalized(ownerUserId);
    final scope = _normalized(scopeId);
    if (owner == null || scope == null) return false;
    final box = _openBox();
    final normalizedValue = _normalized(value);
    final key = keyBuilder(owner, scope);
    if (normalizedValue == null) {
      await box.delete(key);
    } else {
      await box.put(key, normalizedValue);
    }
    return true;
  }

  static AnalysisRecord? _recordFromBox(
    Box<dynamic> box, {
    required String owner,
    required String recordId,
    required String conversationId,
    bool ignoreRecordTombstone = false,
  }) {
    if (!ignoreRecordTombstone &&
        box.containsKey(
          _recordTombstoneKey(owner, conversationId, recordId),
        )) {
      return null;
    }
    final record = AnalysisRecord.tryDecode(
      box.get(_recordKey(owner, conversationId, recordId)),
    );
    if (record == null ||
        record.id != recordId ||
        record.ownerUserId != owner ||
        record.conversationId != conversationId) {
      return null;
    }
    return record;
  }

  static String? _conversationSourceFromBox(
    Box<dynamic> box,
    String owner,
    String conversationId,
  ) {
    return _normalized(
      box.get(_conversationSourceKey(owner, conversationId)),
    );
  }

  static String _newRecordId(
    String owner,
    String conversationId,
    String completionKey,
    String contentRevision,
    int segmentStart,
    int segmentEnd,
  ) {
    return sha256
        .convert(
          utf8.encode(
            '$owner\u0000$conversationId\u0000$completionKey\u0000'
            '$contentRevision\u0000$segmentStart\u0000$segmentEnd',
          ),
        )
        .toString();
  }

  static String _snapshotDigest(String snapshotJson) =>
      sha256.convert(utf8.encode(snapshotJson)).toString();

  static String _recordKey(
    String owner,
    String conversationId,
    String recordId,
  ) =>
      '$recordKeyPrefix:$owner:$conversationId:$recordId';
  static String _stateKey(String owner, String conversationId) =>
      '$stateKeyPrefix:$owner:$conversationId';
  static String _partnerMetViaKey(String owner, String partnerId) =>
      '$partnerMetViaKeyPrefix:$owner:$partnerId';
  static String _conversationSourceKey(String owner, String conversationId) =>
      '$conversationSourceKeyPrefix:$owner:$conversationId';
  static String _cleanupKey(String owner, String conversationId) =>
      '$cleanupKeyPrefix:$owner:$conversationId';
  static String _tombstoneKey(String owner, String conversationId) =>
      '$tombstoneKeyPrefix:$owner:$conversationId';
  static String _recordTombstoneKey(
    String owner,
    String conversationId,
    String recordId,
  ) =>
      '$recordTombstoneKeyPrefix:$owner:$conversationId:$recordId';

  static String? _normalized(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static _AnalysisRecordState? _stateFromRaw(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final currentRecordId = _normalized(json['currentRecordId']);
      final lastCompletionKey = _normalized(json['lastCompletionKey']);
      final currentStart = json['currentStart'];
      final currentEnd = json['currentEnd'];
      final schemaVersion = json['schemaVersion'];
      final currentArchived =
          schemaVersion == 2 ? json['currentArchived'] : false;
      final currentDeleted =
          schemaVersion == 2 ? json['currentDeleted'] : false;
      final currentRevision =
          schemaVersion == 2 ? _normalized(json['currentRevision']) : null;
      final currentSnapshotDigest = schemaVersion == 2
          ? _normalized(json['currentSnapshotDigest'])
          : null;
      if ((schemaVersion != 1 && schemaVersion != 2) ||
          currentRecordId == null ||
          lastCompletionKey == null ||
          currentStart is! int ||
          currentEnd is! int ||
          currentArchived is! bool ||
          currentDeleted is! bool ||
          currentStart < 0 ||
          currentEnd <= currentStart ||
          (currentDeleted &&
              (currentRevision == null || currentSnapshotDigest == null))) {
        return null;
      }
      return _AnalysisRecordState(
        currentRecordId: currentRecordId,
        lastCompletionKey: lastCompletionKey,
        currentStart: currentStart,
        currentEnd: currentEnd,
        currentArchived: currentArchived,
        currentDeleted: currentDeleted,
        currentRevision: currentRevision,
        currentSnapshotDigest: currentSnapshotDigest,
      );
    } catch (_) {
      return null;
    }
  }
}

class _AnalysisRecordState {
  const _AnalysisRecordState({
    required this.currentRecordId,
    required this.lastCompletionKey,
    required this.currentStart,
    required this.currentEnd,
    required this.currentArchived,
    required this.currentDeleted,
    required this.currentRevision,
    required this.currentSnapshotDigest,
  });

  final String currentRecordId;
  final String lastCompletionKey;
  final int currentStart;
  final int currentEnd;
  final bool currentArchived;
  final bool currentDeleted;
  final String? currentRevision;
  final String? currentSnapshotDigest;

  _AnalysisRecordState copyWith({
    bool? currentArchived,
    bool? currentDeleted,
    String? currentRevision,
    String? currentSnapshotDigest,
  }) =>
      _AnalysisRecordState(
        currentRecordId: currentRecordId,
        lastCompletionKey: lastCompletionKey,
        currentStart: currentStart,
        currentEnd: currentEnd,
        currentArchived: currentArchived ?? this.currentArchived,
        currentDeleted: currentDeleted ?? this.currentDeleted,
        currentRevision: currentRevision ?? this.currentRevision,
        currentSnapshotDigest:
            currentSnapshotDigest ?? this.currentSnapshotDigest,
      );

  String encode() => jsonEncode(<String, Object>{
        'schemaVersion': 2,
        'currentRecordId': currentRecordId,
        'lastCompletionKey': lastCompletionKey,
        'currentStart': currentStart,
        'currentEnd': currentEnd,
        'currentArchived': currentArchived,
        'currentDeleted': currentDeleted,
        if (currentRevision != null) 'currentRevision': currentRevision!,
        if (currentSnapshotDigest != null)
          'currentSnapshotDigest': currentSnapshotDigest!,
      });
}
