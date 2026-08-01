import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 訪客額度綁裝置（2026-08-01 Eric 拍板）：把匿名帳號的 refresh token 鏡存
/// iOS Keychain（flutter_secure_storage 預設 accessibility 會在刪 app 重裝後
/// 存活）。重裝後點「先逛逛」先復活舊訪客 session——同帳號＝同剩餘額度＝
/// 同 server 紀錄，堵掉「刪 app 重領 30 則」。
///
/// 規則：
/// - 匿名 session 每次建立/換發 token 都要 [save]（rotation 後舊 token 失效）。
/// - 出現非匿名 session（註冊 linking 完成、登入既有帳號）即 [clear]。
/// - 訪客「登出」不清 vault——綁裝置的重點就是登出重進不重領額度。
/// - Android 的 secure storage 不跨重裝存活，此綁定實質只保 iOS（現階段
///   產品目標機）。
class GuestSessionVault {
  GuestSessionVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'guest_refresh_token_v1';

  final FlutterSecureStorage _storage;

  /// 記憶體去重：auth state 事件很頻繁，同 token 不重複寫 Keychain。
  String? _lastSaved;

  Future<void> save(String refreshToken) async {
    if (refreshToken.isEmpty || refreshToken == _lastSaved) return;
    try {
      await _storage.write(key: _key, value: refreshToken);
      _lastSaved = refreshToken;
    } catch (e) {
      // Best-effort：vault 壞掉最多退化成「重裝重領」，不影響功能。
      debugPrint('[GuestSessionVault] save failed (ignored): $e');
    }
  }

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      debugPrint('[GuestSessionVault] read failed (ignored): $e');
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
      _lastSaved = null;
    } catch (e) {
      debugPrint('[GuestSessionVault] clear failed (ignored): $e');
    }
  }
}
