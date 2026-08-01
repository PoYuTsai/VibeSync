import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vibesync/core/services/guest_session_vault.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockStorage storage;
  late GuestSessionVault vault;

  setUp(() {
    storage = _MockStorage();
    vault = GuestSessionVault(storage: storage);
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'tok-1');
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  group('GuestSessionVault（訪客額度綁裝置）', () {
    test('save 寫入 Keychain；同 token 重複 save 只寫一次（記憶體去重）', () async {
      await vault.save('tok-1');
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(1);

      await vault.save('tok-2');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-2'))
          .called(1);
    });

    test('save 空字串直接略過', () async {
      await vault.save('');
      verifyNever(
          () => storage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('clear 之後同 token 可再次 save（去重快取歸零）', () async {
      await vault.save('tok-1');
      await vault.clear();
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(2);
    });

    test('read 回傳儲存值', () async {
      expect(await vault.read(), 'tok-1');
    });

    test('storage 全炸時 save/read/clear 都吞例外不外拋（best-effort）', () async {
      when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'))).thenThrow(Exception('keychain down'));
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('keychain down'));
      when(() => storage.delete(key: any(named: 'key')))
          .thenThrow(Exception('keychain down'));

      await vault.save('tok-1');
      expect(await vault.read(), isNull);
      await vault.clear();
    });

    test('save 失敗不落去重快取，下次同 token 會重試', () async {
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenThrow(Exception('keychain down'));
      await vault.save('tok-1');

      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(2);
    });
  });
}
