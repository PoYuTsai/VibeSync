import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../entities/keyboard_context_snapshot.dart';

@immutable
class KeyboardContextPartnerSource {
  KeyboardContextPartnerSource({
    required this.partnerId,
    required this.ownerUserId,
    required this.displayName,
    required List<String> confirmedAliases,
    required this.userAuthoredNote,
    required this.outcomeStats,
    required this.effectiveVoice,
    required this.sourceUpdatedAt,
    this.isAllowlisted = false,
    this.isPinned = false,
    this.hasDataQualityConflict = false,
  }) : confirmedAliases = List.unmodifiable(confirmedAliases);

  final String partnerId;
  final String ownerUserId;
  final String displayName;
  final List<String> confirmedAliases;
  final String? userAuthoredNote;
  final KeyboardOutcomeStats? outcomeStats;
  final KeyboardContextVoice effectiveVoice;
  final DateTime sourceUpdatedAt;
  final bool isAllowlisted;
  final bool isPinned;
  final bool hasDataQualityConflict;
}

class KeyboardContextSnapshotBuilder {
  KeyboardContextSnapshotBuilder({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const schemaVersion = 1;
  static const ttl = Duration(hours: 24);
  static const maxPartners = 20;
  static const maxAliasesPerPartner = 5;
  static const maxDisplayNameGraphemes = 100;
  static const maxUserNoteGraphemes = 300;
  static const maxPlaintextBytes = 64 * 1024;

  final DateTime Function() _now;

  KeyboardContextSnapshot build({
    required String ownerUserId,
    required KeyboardContextConsent consent,
    required KeyboardContextVoice globalVoice,
    required Iterable<KeyboardContextPartnerSource> partners,
  }) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(
          ownerUserId, 'ownerUserId', 'must not be empty');
    }
    final generatedAt = _now().toUtc();
    _validateConsent(consent, generatedAt);

    final eligible = consent.partnerContextSharingEnabled
        ? partners
            .where(
              (source) =>
                  source.isAllowlisted &&
                  source.ownerUserId.trim() == owner &&
                  source.partnerId.trim().isNotEmpty &&
                  source.displayName.trim().isNotEmpty,
            )
            .toList(growable: false)
        : <KeyboardContextPartnerSource>[];
    final partnerIds = <String>{};
    for (final source in eligible) {
      final partnerId = source.partnerId.trim();
      if (!partnerIds.add(partnerId)) {
        throw ArgumentError.value(
          partnerId,
          'partners',
          'duplicate keyboard context partner id',
        );
      }
    }
    eligible.sort(_compareSources);

    var entries =
        eligible.take(maxPartners).map(_buildPartner).toList(growable: true);
    var snapshot = _assemble(
      owner: owner,
      generatedAt: generatedAt,
      consent: consent,
      globalVoice: globalVoice,
      partners: entries,
    );
    while (utf8.encode(snapshot.canonicalJson).length > maxPlaintextBytes &&
        entries.isNotEmpty) {
      entries = entries.sublist(0, entries.length - 1);
      snapshot = _assemble(
        owner: owner,
        generatedAt: generatedAt,
        consent: consent,
        globalVoice: globalVoice,
        partners: entries,
      );
    }
    if (utf8.encode(snapshot.canonicalJson).length > maxPlaintextBytes) {
      throw StateError('keyboard context envelope exceeds 64 KiB');
    }
    return snapshot;
  }

  void _validateConsent(
    KeyboardContextConsent consent,
    DateTime generatedAt,
  ) {
    if (consent.version != KeyboardContextConsent.currentVersion) {
      throw ArgumentError.value(
        consent.version,
        'consent.version',
        'unsupported keyboard consent version',
      );
    }
    if (!consent.latestScreenshotDetectionEnabled) {
      throw ArgumentError(
        'latest screenshot detection must be enabled before publishing context',
      );
    }
    if (consent.acceptedAt.toUtc().isAfter(
          generatedAt.add(const Duration(minutes: 5)),
        )) {
      throw ArgumentError('keyboard consent timestamp is in the future');
    }
  }

  KeyboardContextPartner _buildPartner(KeyboardContextPartnerSource source) {
    final aliases = <String>[];
    for (final raw in source.confirmedAliases) {
      final alias = _cap(raw.trim(), maxDisplayNameGraphemes);
      if (alias.isEmpty || aliases.contains(alias)) continue;
      aliases.add(alias);
      if (aliases.length == maxAliasesPerPartner) break;
    }

    final status = source.hasDataQualityConflict
        ? KeyboardPartnerContextStatus.dataQualityFlagged
        : KeyboardPartnerContextStatus.available;
    final facts = <KeyboardContextFact>[];
    final note = _cap(
      source.userAuthoredNote?.trim() ?? '',
      maxUserNoteGraphemes,
    );
    if (!source.hasDataQualityConflict && note.isNotEmpty) {
      facts.add(
        KeyboardContextFact(
          kind: KeyboardContextFactKind.userNote,
          text: note,
          updatedAt: source.sourceUpdatedAt,
        ),
      );
    }
    final outcomeStats =
        !source.hasDataQualityConflict && source.outcomeStats?.isValid == true
            ? source.outcomeStats
            : null;
    final effectiveVoice =
        source.hasDataQualityConflict ? null : source.effectiveVoice;

    final revisionPayload = <String, Object?>{
      'partnerId': source.partnerId.trim(),
      'displayName': _cap(
        source.displayName.trim(),
        maxDisplayNameGraphemes,
      ),
      'confirmedAliases': aliases,
      'contextStatus': status.wireValue,
      'facts': facts.map((fact) => fact.toJson()).toList(growable: false),
      'outcomeStats': outcomeStats?.toJson(),
      'effectiveVoice': effectiveVoice?.toPartnerJson(),
      'sourceUpdatedAt': source.sourceUpdatedAt.toUtc().toIso8601String(),
    };
    final contextRevision = sha256
        .convert(utf8.encode(canonicalJsonEncode(revisionPayload)))
        .toString();

    return KeyboardContextPartner(
      partnerId: source.partnerId.trim(),
      displayName: revisionPayload['displayName']! as String,
      confirmedAliases: aliases,
      contextStatus: status,
      facts: facts,
      outcomeStats: outcomeStats,
      effectiveVoice: effectiveVoice,
      contextRevision: contextRevision,
      sourceUpdatedAt: source.sourceUpdatedAt,
    );
  }

  KeyboardContextSnapshot _assemble({
    required String owner,
    required DateTime generatedAt,
    required KeyboardContextConsent consent,
    required KeyboardContextVoice globalVoice,
    required List<KeyboardContextPartner> partners,
  }) {
    final expiresAt = generatedAt.add(ttl);
    final revisionPayload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'ownerUserId': owner,
      'generatedAt': generatedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'consent': consent.toJson(),
      'globalVoice': globalVoice.toJson(),
      'partners':
          partners.map((partner) => partner.toJson()).toList(growable: false),
    };
    final revision = sha256
        .convert(utf8.encode(canonicalJsonEncode(revisionPayload)))
        .toString();
    return KeyboardContextSnapshot(
      schemaVersion: schemaVersion,
      ownerUserId: owner,
      revision: revision,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      consent: consent,
      globalVoice: globalVoice,
      partners: partners,
    );
  }

  static int _compareSources(
    KeyboardContextPartnerSource left,
    KeyboardContextPartnerSource right,
  ) {
    if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
    final updated = right.sourceUpdatedAt.compareTo(left.sourceUpdatedAt);
    if (updated != 0) return updated;
    return left.partnerId.compareTo(right.partnerId);
  }

  static String _cap(String value, int maxGraphemes) {
    final characters = value.characters;
    if (characters.length <= maxGraphemes) return value;
    return characters.take(maxGraphemes).toString();
  }
}
