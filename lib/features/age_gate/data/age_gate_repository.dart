// lib/features/age_gate/data/age_gate_repository.dart
//
// 年齡確認的紀錄：送到伺服器（sync-subscription `record_age_gate`），伺服器回的
// 紀錄才算數；路由（resolveAppRedirect）同步讀 [AgeGateService]，只看 session。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/age_gate.dart';

/// 路由每次導頁同步讀這裡：只看 session 裡帳號的 app_metadata（登入、換 token 時
/// 伺服器給的權威紀錄）。不另外記在記憶體：那份會蓋過別台裝置或客服之後改的紀錄
/// （主審第 1 輪 P2）。寫入成功但換 token 失敗時，畫面請他再按一次。
class AgeGateService {
  static AgeGateResult? resultFor(User? user) =>
      user == null ? null : ageGateResultFromAppMetadata(user.appMetadata);

  static bool isAdultConfirmed(User? user) =>
      resultFor(user) == AgeGateResult.adult;
}

/// 沒寫成功（連不上、逾時、伺服器錯誤、回應形狀不對）：畫面請他再按一次，不放行。
class AgeGateRecordException implements Exception {
  const AgeGateRecordException(this.reason);

  final String reason;

  @override
  String toString() => 'AgeGateRecordException($reason)';
}

/// 伺服器記下的結果；[sessionUpdated]＝之後換 token 成功、session 已經帶著這筆紀錄
/// （路由只看 session，沒換成功就還不能放行）。
typedef AgeGateRecordOutcome = ({AgeGateResult result, bool sessionUpdated});

typedef AgeGateInvoker = Future<FunctionResponse> Function(
  String functionName, {
  Map<String, dynamic>? body,
});

class AgeGateRepository {
  AgeGateRepository({
    AgeGateInvoker? invoke,
    Future<void> Function()? refreshSession,
    String? Function()? currentUserId,
  })  : _invoke = invoke ?? _defaultInvoke,
        _refreshSession = refreshSession ?? _defaultRefreshSession,
        _currentUserId =
            currentUserId ?? (() => SupabaseService.currentUser?.id);

  final AgeGateInvoker _invoke;
  final Future<void> Function() _refreshSession;
  final String? Function() _currentUserId;

  static Future<FunctionResponse> _defaultInvoke(
    String functionName, {
    Map<String, dynamic>? body,
  }) =>
      SupabaseService.invokeFunction(
        functionName,
        body: body,
        timeout: const Duration(seconds: 20),
      );

  static Future<void> _defaultRefreshSession() async {
    await SupabaseService.client.auth.refreshSession();
  }

  /// 送出這次算出的結果，回伺服器記下的紀錄：未成年鎖住時（409）伺服器回的是
  /// 原本的未成年紀錄，照它走。寫成功後換一次 token，讓 session 裡的 app_metadata
  /// 跟上；有沒有換成功放在 [AgeGateRecordOutcome.sessionUpdated]。
  Future<AgeGateRecordOutcome> record(AgeGateResult result) async {
    final userId = _currentUserId();
    if (userId == null) throw const AgeGateRecordException('not_signed_in');

    int status;
    Object? data;
    try {
      final response = await _invoke(
        'sync-subscription',
        body: {
          'mode': 'record_age_gate',
          'result': result.name,
          'policy': kAgeGatePolicyVersion,
        },
      );
      status = response.status;
      data = response.data;
    } on FunctionException catch (error) {
      // functions_client 對非 2xx 直接丟例外：409（鎖住）也走這裡。
      status = error.status;
      data = error.details;
    } catch (error) {
      throw AgeGateRecordException('request_failed: $error');
    }

    final recorded = (status == 200 || status == 409) && data is Map
        ? ageGateResultFromRecord(data['ageGate'])
        : null;
    if (recorded == null) throw AgeGateRecordException('status_$status');

    var sessionUpdated = true;
    try {
      await _refreshSession().timeout(const Duration(seconds: 10));
    } catch (error) {
      sessionUpdated = false;
      debugPrint('Age gate session refresh failed: $error');
    }
    return (result: recorded, sessionUpdated: sessionUpdated);
  }
}

final ageGateRepositoryProvider = Provider<AgeGateRepository>(
  (ref) => AgeGateRepository(),
);
