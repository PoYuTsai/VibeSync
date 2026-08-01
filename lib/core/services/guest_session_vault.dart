import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 訪客額度綁裝置（2026-08-01 Eric 拍板，ADR #33）：把匿名帳號的 refresh
/// token 鏡存 iOS Keychain（flutter_secure_storage 預設 accessibility 會在
/// 刪 app 重裝後存活）。重裝後點「先逛逛」先復活舊訪客 session——同帳號＝
/// 同剩餘額度＝同 server 紀錄，堵掉「刪 app 重裝重領 30 則」。
///
/// 規則：
/// - 匿名 session 每次建立/換發 token 都要 [save]（rotation 後舊 token 失效）。
/// - 出現非匿名 session（註冊 linking 完成、登入既有帳號）即 [clear]。
/// - 訪客「登出」不動 vault，但 signOut 會 revoke token，vault 內 token 必死
///   ——登出後重進訪客會拿到新帳號（重領額度）是 ADR #33 已接受的風險；
///   vault 只堵「刪 app 重裝」主路徑。後人別試圖在登出路徑「補救」綁定。
/// - Android 的 secure storage 不跨重裝存活，此綁定實質只保 iOS（現階段
///   產品目標機）。
class GuestSessionVault {
  GuestSessionVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'guest_refresh_token_v1';

  final FlutterSecureStorage _storage;

  /// 記憶體去重：auth state 事件很頻繁，同 token 不重複寫 Keychain。
  String? _lastSaved;

  /// 寫入串行化（審修 F1）：save/clear 依呼叫順序排隊執行，杜絕「舊 token
  /// 的 write 較晚完成、覆蓋新 token」的 async 交錯。op 內全吞例外，鏈不斷。
  Future<void> _serial = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _serial.then((_) => op());
    _serial = next;
    return next;
  }

  Future<void> save(String refreshToken) => _enqueue(() async {
        if (refreshToken.isEmpty || refreshToken == _lastSaved) return;
        try {
          await _storage.write(key: _key, value: refreshToken);
          _lastSaved = refreshToken;
        } catch (e) {
          // Best-effort：vault 壞掉最多退化成「重裝重領」，不影響功能。
          debugPrint('[GuestSessionVault] save failed (ignored): $e');
        }
      });

  Future<String?> read() async {
    await _serial; // 排在 in-flight 寫入之後，讀到的必是最新狀態。
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      debugPrint('[GuestSessionVault] read failed (ignored): $e');
      return null;
    }
  }

  Future<void> clear() => _enqueue(() async {
        // 先清去重快取（審修 F4）：即使 delete 失敗，下一次 save 也要真的重寫。
        _lastSaved = null;
        try {
          await _storage.delete(key: _key);
        } catch (e) {
          debugPrint('[GuestSessionVault] clear failed (ignored): $e');
        }
      });

  /// auth 狀態同步入口：匿名 session → 跟寫最新 token；非匿名 session →
  /// 清 vault。無 session（登出）由呼叫端直接不呼叫（vault 不動）。
  Future<void> syncAuthSession({
    required bool isAnonymous,
    required String? refreshToken,
  }) {
    if (isAnonymous) {
      if (refreshToken == null || refreshToken.isEmpty) {
        return Future<void>.value();
      }
      return save(refreshToken);
    }
    return clear();
  }
}

/// 「先逛逛」入口流程（審修 F2/F5：抽出純邏輯供單元測試）：
/// 先試復活 vault 內舊訪客 session，復活失敗或復活到非匿名帳號
/// （vault 清理失敗的殘留）才退回開新匿名帳號。
class GuestSignInFlow {
  GuestSignInFlow({
    required this.vault,
    required this.restoreSession,
    required this.freshSignIn,
    required this.discardSession,
  });

  final GuestSessionVault vault;

  /// `client.auth.setSession(refreshToken)`。
  final Future<AuthResponse> Function(String refreshToken) restoreSession;

  /// `client.auth.signInAnonymously()`。
  final Future<AuthResponse> Function() freshSignIn;

  /// 復活到非匿名帳號時的退出（`client.auth.signOut()`）。
  final Future<void> Function() discardSession;

  Future<AuthResponse> signIn() async {
    final stored = await vault.read();
    if (stored != null && stored.isNotEmpty) {
      try {
        final restored = await restoreSession(stored);
        final user = restored.user;
        if (restored.session != null && user != null && user.isAnonymous) {
          return restored;
        }
        if (user != null) {
          // 復活到正式帳（理論上 vault 已清；此為 clear 失敗殘留的防衛）：
          // 「先逛逛」絕不悄悄登入正式帳號，退出後照訪客流程走。
          try {
            await discardSession();
          } catch (e) {
            debugPrint('[GuestSignInFlow] discard non-guest session: $e');
          }
        }
      } on AuthException catch (e) {
        // 審修（GLM P1）：只有「token 真死」（4xx）才棄舊帳開新帳；
        // 網路瞬斷/伺服器錯誤要保住 vault 讓使用者重試，否則綁定會被
        // 一次斷線永久擊穿。
        if (e is AuthRetryableFetchException) rethrow;
        final status = int.tryParse(e.statusCode ?? '');
        if (status != null && status >= 500) rethrow;
        debugPrint('[GuestSignInFlow] stored guest token rejected '
            '(${e.statusCode}), falling back to fresh anonymous sign-in');
      }
      // 走到這裡＝token 已死或帳號非匿名，清掉避免每次都白試一輪。
      // （非 Auth 例外——如純網路層錯誤——已在上面 rethrow，不會清。）
      await vault.clear();
    }
    return freshSignIn();
  }
}
