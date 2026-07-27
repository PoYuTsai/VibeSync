import 'dart:convert';

import 'package:flutter/foundation.dart';

enum KeyboardVoice { steady, direct, humorous, gentle, playful }

enum KeyboardPartnerContextStatus { available, dataQualityFlagged }

extension KeyboardPartnerContextStatusWire on KeyboardPartnerContextStatus {
  String get wireValue => switch (this) {
        KeyboardPartnerContextStatus.available => 'available',
        KeyboardPartnerContextStatus.dataQualityFlagged =>
          'data_quality_flagged',
      };
}

enum KeyboardContextFactKind { userNote }

String _enumName(Enum value) => value.name;

DateTime canonicalUtcDateTime(DateTime value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value.toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );
}

String canonicalUtcTimestamp(DateTime value) {
  return canonicalUtcDateTime(value).toIso8601String();
}

String canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      for (final entry in entries) entry.key: _canonicalize(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

@immutable
class KeyboardContextConsent {
  const KeyboardContextConsent({
    required this.version,
    required this.acceptedAt,
    required this.latestScreenshotDetectionEnabled,
    required this.partnerContextSharingEnabled,
  });

  static const currentVersion = 'keyboard_screenshot_ai_202607_v1';

  final String version;
  final DateTime acceptedAt;
  final bool latestScreenshotDetectionEnabled;
  final bool partnerContextSharingEnabled;

  Map<String, Object?> toJson() => {
        'version': version,
        'acceptedAt': canonicalUtcTimestamp(acceptedAt),
        'latestScreenshotDetectionEnabled': latestScreenshotDetectionEnabled,
        'partnerContextSharingEnabled': partnerContextSharingEnabled,
      };
}

@immutable
class KeyboardContextVoice {
  const KeyboardContextVoice({
    required this.primary,
    required this.secondary,
    required this.sourceUpdatedAt,
  });

  final KeyboardVoice? primary;
  final KeyboardVoice? secondary;
  final DateTime sourceUpdatedAt;

  Map<String, Object?> toJson() => {
        'primary': primary == null ? null : _enumName(primary!),
        'secondary': secondary == null ? null : _enumName(secondary!),
        'sourceUpdatedAt': canonicalUtcTimestamp(sourceUpdatedAt),
      };

  Map<String, Object?> toPartnerJson() => {
        'primary': primary == null ? null : _enumName(primary!),
        'secondary': secondary == null ? null : _enumName(secondary!),
      };
}

@immutable
class KeyboardContextFact {
  const KeyboardContextFact({
    required this.kind,
    required this.text,
    required this.updatedAt,
  });

  final KeyboardContextFactKind kind;
  final String text;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'kind': switch (kind) {
          KeyboardContextFactKind.userNote => 'user_note',
        },
        'text': text,
        'updatedAt': canonicalUtcTimestamp(updatedAt),
      };
}

@immutable
class KeyboardOutcomeStats {
  const KeyboardOutcomeStats({
    required this.sampleSize,
    required this.engaged,
    required this.cold,
    required this.noReply,
    required this.negative,
  });

  final int sampleSize;
  final int engaged;
  final int cold;
  final int noReply;
  final int negative;

  static const minimumSampleSize = 3;

  Map<String, Object?> toJson() => {
        'sampleSize': sampleSize,
        'engaged': engaged,
        'cold': cold,
        'noReply': noReply,
        'negative': negative,
      };

  bool get isValid {
    if ([sampleSize, engaged, cold, noReply, negative]
        .any((value) => value < 0)) {
      return false;
    }
    return sampleSize >= minimumSampleSize &&
        engaged + cold + noReply + negative <= sampleSize;
  }
}

@immutable
class KeyboardContextPartner {
  KeyboardContextPartner({
    required this.partnerId,
    required this.displayName,
    required List<String> confirmedAliases,
    required this.contextStatus,
    required List<KeyboardContextFact> facts,
    required this.outcomeStats,
    required this.effectiveVoice,
    required this.contextRevision,
    required this.sourceUpdatedAt,
  })  : confirmedAliases = List.unmodifiable(confirmedAliases),
        facts = List.unmodifiable(facts);

  final String partnerId;
  final String displayName;
  final List<String> confirmedAliases;
  final KeyboardPartnerContextStatus contextStatus;
  final List<KeyboardContextFact> facts;
  final KeyboardOutcomeStats? outcomeStats;
  final KeyboardContextVoice? effectiveVoice;
  final String contextRevision;
  final DateTime sourceUpdatedAt;

  Map<String, Object?> toJson() => {
        'partnerId': partnerId,
        'displayName': displayName,
        'confirmedAliases': confirmedAliases,
        'contextStatus': contextStatus.wireValue,
        'facts': facts.map((fact) => fact.toJson()).toList(growable: false),
        'outcomeStats': outcomeStats?.toJson(),
        'effectiveVoice': effectiveVoice?.toPartnerJson(),
        'contextRevision': contextRevision,
        'sourceUpdatedAt': canonicalUtcTimestamp(sourceUpdatedAt),
      };
}

@immutable
class KeyboardContextSnapshot {
  KeyboardContextSnapshot({
    required this.schemaVersion,
    required this.ownerUserId,
    required this.revision,
    required this.generatedAt,
    required this.expiresAt,
    required this.consent,
    required this.globalVoice,
    required List<KeyboardContextPartner> partners,
  }) : partners = List.unmodifiable(partners);

  final int schemaVersion;
  final String ownerUserId;
  final String revision;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final KeyboardContextConsent consent;
  final KeyboardContextVoice globalVoice;
  final List<KeyboardContextPartner> partners;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'ownerUserId': ownerUserId,
        'revision': revision,
        'generatedAt': canonicalUtcTimestamp(generatedAt),
        'expiresAt': canonicalUtcTimestamp(expiresAt),
        'consent': consent.toJson(),
        'globalVoice': globalVoice.toJson(),
        'partners':
            partners.map((partner) => partner.toJson()).toList(growable: false),
      };

  String get canonicalJson => canonicalJsonEncode(toJson());
}
