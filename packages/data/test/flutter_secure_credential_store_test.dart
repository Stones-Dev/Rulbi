import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';

/// S4 · Ola 2 (Formulario Xtream, P5): primera implementación real de
/// `SecureCredentialStore` (el puerto vive en `core` desde S1, sin
/// implementación hasta ahora). No se toca el almacén real del SO: se
/// sustituye `FlutterSecureStoragePlatform.instance` por un doble en
/// memoria — mismo patrón que usan los tests del propio paquete
/// `flutter_secure_storage` (extender la interfaz de plataforma, no
/// mockear el `MethodChannel` a mano).
void main() {
  late _FakeSecureStoragePlatform platform;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  test('save + read: devuelve el secreto guardado', () async {
    final store = FlutterSecureCredentialStore();

    await store.save('source-1', 's3cr3t');

    expect(await store.read('source-1'), 's3cr3t');
  });

  test('read de un sourceId nunca guardado: null', () async {
    final store = FlutterSecureCredentialStore();

    expect(await store.read('nunca-guardado'), isNull);
  });

  test('delete: el siguiente read vuelve a devolver null', () async {
    final store = FlutterSecureCredentialStore();
    await store.save('source-1', 's3cr3t');

    await store.delete('source-1');

    expect(await store.read('source-1'), isNull);
  });

  test('delete de una clave inexistente no lanza', () async {
    final store = FlutterSecureCredentialStore();

    await expectLater(store.delete('nunca-existió'), completes);
  });

  test('la clave persistida está namespaced por sourceId, no es el sourceId a pelo', () async {
    final store = FlutterSecureCredentialStore();

    await store.save('mi-fuente', 's3cr3t');

    expect(platform.written.keys, isNot(contains('mi-fuente')));
    expect(
      platform.written.keys.single,
      allOf(contains('mi-fuente'), isNot(equals('mi-fuente'))),
    );
  });

  test('dos sourceId distintos no colisionan', () async {
    final store = FlutterSecureCredentialStore();

    await store.save('source-a', 'secreto-a');
    await store.save('source-b', 'secreto-b');

    expect(await store.read('source-a'), 'secreto-a');
    expect(await store.read('source-b'), 'secreto-b');
  });
}

/// Doble en memoria de `FlutterSecureStoragePlatform`, indexado por la
/// clave completa que envía el paquete (namespace incluido) — permite al
/// test "namespaced" comprobar la forma real de la clave sin acoplarse al
/// formato exacto salvo por lo que expone `written`.
final class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> written = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    written[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return written[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return written.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    written.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(written);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    written.clear();
  }
}
