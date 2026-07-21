import 'package:flutter/foundation.dart';

import 'unified_coach_result.dart';

/// Phase E 教練統一的 scope 值物件：conversation（分析頁 1:1）與
/// partner（對象頁跟進）雙 scope 共用同一條 coach 流程時，用它取代
/// 散落的裸 conversationId 字串。
///
/// [type] 一律引用 [CoachScopeType] 常數（Hive 持久化值，絕不可改），
/// 值相等性以 (type, id) 定義，可直接當 Riverpod family key。
@immutable
class CoachScope {
  final String type;
  final String id;

  const CoachScope.conversation(this.id) : type = CoachScopeType.conversation;

  const CoachScope.partner(this.id) : type = CoachScopeType.partner;

  bool get isConversation => type == CoachScopeType.conversation;

  /// 本機索引/family key 用的複合鍵，如 `conversation:c1`／`partner:p1`。
  String get key => '$type:$id';

  /// 舊 wire 欄位 `conversationId` 的相容映射：conversation scope 送原 id；
  /// partner scope 送 `partner:<id>` 合成 id（server 端 Phase C 已認得）。
  String get wireConversationId => isConversation ? id : 'partner:$id';

  /// 新 wire 的結構化 scope 物件。
  Map<String, dynamic> toWireJson() => isConversation
      ? {'type': 'conversation', 'conversationId': id}
      : {'type': 'partner', 'partnerId': id};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachScope && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'CoachScope($type:$id)';
}
